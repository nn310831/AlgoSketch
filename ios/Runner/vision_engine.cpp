#include <iostream>
#include <vector>
#include <cstdlib>
#include <opencv2/opencv.hpp>

// ==========================================
// 1. 純 C++ 區塊 (內部邏輯)
// ==========================================

// 定義一個結構來包裝我們找到的所有幾何特徵
struct ExtractedFeatures {
    std::vector<cv::Vec3f> circles; // [x, y, radius]
    std::vector<cv::Vec4i> lines;   // [x1, y1, x2, y2]
};

// 核心視覺管線
ExtractedFeatures extractWhiteboardFeatures(const cv::Mat& src) {
    ExtractedFeatures features;

    // 防禦性檢查
    if (src.empty() || src.cols <= 0 || src.rows <= 0) {
        std::cerr << "[C++ Error] Invalid image." << std::endl;
        return features; 
    }

    cv::Mat gray, blurred, thresholded, edges;

    // --- 階段一：前處理 ---
    cv::cvtColor(src, gray, cv::COLOR_BGR2GRAY);
    cv::GaussianBlur(gray, blurred, cv::Size(5, 5), 0);
    cv::adaptiveThreshold(blurred, thresholded, 255, 
                          cv::ADAPTIVE_THRESH_GAUSSIAN_C, cv::THRESH_BINARY_INV, 11, 2);
    cv::Canny(thresholded, edges, 50, 150);

    // --- 階段二：特徵擷取 ---
    
    // 1. 找圓圈 (注意：吃的是 blurred，不是 edges！)
    // minDist 設為圖片高度的 1/8，避免同一個圓被重複標記
    double minDist = blurred.rows / 8.0; 
    cv::HoughCircles(blurred, features.circles, cv::HOUGH_GRADIENT, 1, 
                     minDist, 
                     100,  // param1: 內部 Canny 閾值
                     35,   // param2: 圓形完美度閾值 (調低變敏感，調高變嚴格)
                     10,   // minRadius
                     150); // maxRadius

    // 2. 找線段 (注意：吃的是 edges)
    // 參數：(輸入, 輸出, rho解析度, theta解析度, 投票閾值, 最小線長, 最大斷裂間隙)
    cv::HoughLinesP(edges, features.lines, 1, CV_PI / 180, 
                    50,  // threshold: 至少要有 50 個像素在同一條直線上
                    40,  // minLineLength: 線段至少要 40 像素長
                    10); // maxLineGap: 允許線段中間斷裂不超過 10 像素

    return features;
}

// ==========================================
// 2. C 介面區塊 (FFI 橋接)
// ==========================================
extern "C" {
    // 1. 定義平坦的純 C 結構 (Plain Old Data)
    struct NodeData {
        float x;
        float y;
        float radius;
    };

    struct EdgeData {
        int x1;
        int y1;
        int x2;
        int y2;
    };

    // 總打包結構 (要傳給 Dart 的大包裹)
    struct VisionResult {
        NodeData* nodes;   // 指向節點陣列的指標
        int nodeCount;     // 節點數量
        
        EdgeData* edges;   // 指向連線陣列的指標
        int edgeCount;     // 連線數量
    };

    // 2. 核心影像處理與匯出函數 (Dart 呼叫的進入點)
    __attribute__((visibility("default"))) __attribute__((used))
    VisionResult* process_whiteboard_image(const char* imagePath) {
        // 讀取圖片
        cv::Mat src = cv::imread(imagePath);
        
        // 執行視覺管線
        ExtractedFeatures features = extractWhiteboardFeatures(src);

        std::vector<cv::Vec3f>& circles = features.circles;
        std::vector<cv::Vec4i>& lines = features.lines;

        // 【關鍵 A】：在 Heap 分配最外層 VisionResult 結構的記憶體
        VisionResult* result = (VisionResult*)malloc(sizeof(VisionResult));
        
        // 【關鍵 B】：封裝圓形資料 (陣列分配)
        result->nodeCount = circles.size();
        if (result->nodeCount > 0) {
            result->nodes = (NodeData*)malloc(sizeof(NodeData) * result->nodeCount);
            for (int i = 0; i < result->nodeCount; ++i) {
                result->nodes[i].x = circles[i][0];
                result->nodes[i].y = circles[i][1];
                result->nodes[i].radius = circles[i][2];
            }
        } else {
            result->nodes = nullptr;
        }

        // 【關鍵 C】：封裝線段資料 (陣列分配)
        result->edgeCount = lines.size();
        if (result->edgeCount > 0) {
            result->edges = (EdgeData*)malloc(sizeof(EdgeData) * result->edgeCount);
            for (int i = 0; i < result->edgeCount; ++i) {
                result->edges[i].x1 = lines[i][0];
                result->edges[i].y1 = lines[i][1];
                result->edges[i].x2 = lines[i][2];
                result->edges[i].y2 = lines[i][3];
            }
        } else {
            result->edges = nullptr;
        }
        
        // 將這塊永遠不會自動消失的記憶體指標，交給 Dart
        return result; 
    }

    // 3. 記憶體釋放函數 (Dart 讀完資料後「必須」呼叫這個，否則會 Memory Leak)
    __attribute__((visibility("default"))) __attribute__((used))
    void free_vision_result(VisionResult* result) {
        if (result != nullptr) {
            // 順序很重要：先釋放裡面的陣列，再釋放外殼
            if (result->nodes != nullptr) free(result->nodes);
            if (result->edges != nullptr) free(result->edges);
            free(result);
        }
    }
}