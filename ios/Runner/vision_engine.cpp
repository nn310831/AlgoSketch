#include <iostream>
#include <vector>
#include <cstdlib>
#include <opencv2/opencv.hpp>

//這裡要新增功能，掃描判斷邊上權重位置，並傳送給CNN判斷 weight

// ==========================================
// 1. 純 C++ 區塊 (內部邏輯)
// ==========================================

// 定義一個結構來包裝我們找到的所有幾何特徵
struct ExtractedFeatures {
    std::vector<cv::Vec3f> circles; // [x, y, radius]
    std::vector<cv::Vec4i> lines;   // [x1, y1, x2, y2]
};

// 內部輔助函數：執行自動裁切、等比例縮放至 20x20，並置中處理以供 CNN 推論 (符合 Python 端的前處理)
cv::Mat preprocess_roi_for_tflite(const cv::Mat& gray_roi) {
    cv::Mat thresh_img;
    // 1. 預先二值化與反轉 (找輪廓 Bounding Box)
    cv::adaptiveThreshold(gray_roi, thresh_img, 255, 
                          cv::ADAPTIVE_THRESH_GAUSSIAN_C, cv::THRESH_BINARY_INV, 21, 10);

    // 2. 獲取文字的最小邊界框
    std::vector<cv::Point> nonZeroPoints;
    cv::findNonZero(thresh_img, nonZeroPoints);
    
    cv::Mat cropped_tight;
    if (!nonZeroPoints.empty()) {
        cv::Rect bbox = cv::boundingRect(nonZeroPoints);
        cropped_tight = gray_roi(bbox);
    } else {
        cropped_tight = gray_roi;
    }

    // 3. 等比例縮放至 20x20 內部大小
    int h = cropped_tight.rows;
    int w = cropped_tight.cols;
    int inner_size = 20;
    
    cv::Mat resized_img;
    if (std::max(h, w) > 0) {
        double scale = static_cast<double>(inner_size) / std::max(h, w);
        int new_w = static_cast<int>(w * scale);
        int new_h = static_cast<int>(h * scale);
        cv::resize(cropped_tight, resized_img, cv::Size(new_w, new_h), 0, 0, cv::INTER_AREA);
    } else {
        resized_img = cv::Mat(inner_size, inner_size, CV_8UC1, cv::Scalar(255));
    }

    // 4. 準備 28x28 的白色背景
    int target_size = 28;
    cv::Mat canvas(target_size, target_size, CV_8UC1, cv::Scalar(255));
    
    int x_offset = (target_size - resized_img.cols) / 2;
    int y_offset = (target_size - resized_img.rows) / 2;
    
    cv::Rect dst_roi(x_offset, y_offset, resized_img.cols, resized_img.rows);
    resized_img.copyTo(canvas(dst_roi));

    // 5. 正式二值化與反轉 (針對縮放好且置中的圖)
    cv::Mat final_processed;
    cv::adaptiveThreshold(canvas, final_processed, 255, 
                          cv::ADAPTIVE_THRESH_GAUSSIAN_C, cv::THRESH_BINARY, 11, 2);
    // 反轉讓背景為黑 (0)，字跡為白 (255) 以符合 CNN 需求
    cv::bitwise_not(final_processed, final_processed);

    return final_processed;
}

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

    // 【修改 1】：把 Canny 輸入改成 blurred (具有平滑灰階)，而不是 thresholded (鋸齒二值圖)
    // 同時調低閾值 (30, 90) 以更容易捕捉白板筆或淡色墨跡的邊界
    cv::Canny(blurred, edges, 30, 90);

    // 【新增】：膨脹邊緣！把微小的斷線、彎曲的虛線強行變粗連成一氣，再送給找直線的函數
    cv::Mat kernel = cv::getStructuringElement(cv::MORPH_ELLIPSE, cv::Size(7, 7));
    cv::dilate(edges, edges, kernel);

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
                    35,   // threshold: 調回 35，門檻放寬
                    40,   // minLineLength: 線段至少要 40 像素長
                    250); // maxLineGap: 提高到 250 像素（約 2~3 公分的斷裂都能被當成同一條線）

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
        float* pixels; // 新增：指向 28x28 = 784 個 float 的記憶體區塊
    };

    struct EdgeData {
        int x1;
        int y1;
        int x2;
        int y2;
        bool hasWeight; // 是否有找到文字墨水
        float* pixels;  // 指向 28x28 權重影像的指標 (如果沒有文字則為 nullptr)
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
        
        // 為了取得乾淨的 ROI，我們需要在這裡再做一次二值化
        // (在實際專案中，你可以把 extractWhiteboardFeatures 改為回傳處理好的二值圖)
        cv::Mat gray, thresholded;
        cv::cvtColor(src, gray, cv::COLOR_BGR2GRAY);
        // 使用 ADAPTIVE_THRESH_GAUSSIAN_C，且 INV 讓背景為黑(0)，筆跡為白(255) -> 符合 CNN 需求
        cv::adaptiveThreshold(gray, thresholded, 255, 
                              cv::ADAPTIVE_THRESH_GAUSSIAN_C, cv::THRESH_BINARY_INV, 11, 2);
        
        //debug 用,release 時可註解掉
        // // =============== ▼ 輸出二值化偵錯圖片 ▼ ===============
        std::string originalPath(imagePath);
        size_t dotPos = originalPath.find_last_of(".");
        std::string debugPath;
        if(dotPos != std::string::npos) {
            debugPath = originalPath.substr(0, dotPos) + "_debug_binary.jpg";
        } else {
            debugPath = originalPath + "_debug_binary.jpg";
        }

        // 把處理完的黑底白字二值圖存到手機中
        cv::imwrite(debugPath, thresholded);
        std::cout << "[VisionEngine] Debug image saved to: " << debugPath << std::endl;
        // =============== ▲ 輸出二值化偵錯圖片 ▲ ===============

        // 執行視覺管線
        ExtractedFeatures features = extractWhiteboardFeatures(src);

        std::vector<cv::Vec3f>& circles = features.circles;
        std::vector<cv::Vec4i>& lines = features.lines;

        // 【關鍵 A】：在 Heap 分配最外層 VisionResult 結構的記憶體
        VisionResult* result = (VisionResult*)malloc(sizeof(VisionResult));
        
        // 【關鍵 B】：封裝圓形資料 (陣列分配) 與 ROI 裁切
        result->nodeCount = circles.size();
        if (result->nodeCount > 0) {
            result->nodes = (NodeData*)malloc(sizeof(NodeData) * result->nodeCount);
            for (int i = 0; i < result->nodeCount; ++i) {
                float x = circles[i][0];
                float y = circles[i][1];
                float r = circles[i][2];

                result->nodes[i].x = x;
                result->nodes[i].y = y;
                result->nodes[i].radius = r;
                
                // --- 新增：ROI 裁切、過濾外框與標準化 ---
                // 1. 計算矩形範圍，並加上安全防禦 (避免超出圖片邊界導致 C++ 閃退)
                cv::Rect roi(x - r, y - r, 2 * r, 2 * r);
                roi &= cv::Rect(0, 0, thresholded.cols, thresholded.rows); 

                // 分配 784 個浮點數記憶體
                result->nodes[i].pixels = (float*)malloc(28 * 28 * sizeof(float));

                if (roi.area() > 0) {
                    // == 這裡新增：去除外圍圓框，只留下內部數字 ==
                    cv::Mat roi_gray = gray(roi).clone(); // 取出灰階 ROI (深色筆跡)
                    
                    // 建立一個與 ROI 大小相同的遮罩，全黑 (0) 代表不要的區域
                    cv::Mat mask(roi_gray.size(), CV_8UC1, cv::Scalar(0));
                    
                    // 畫一個填滿的白色圓形 (255代表保留內部)，半徑設為 r * 0.75 (避免切到稍微偏內的圓框自己)
                    // 位置是正方形的中心點
                    cv::Point center(roi.width / 2, roi.height / 2);
                    int inner_radius = static_cast<int>(r * 0.75); // 縮小 25% 避開粗圓框
                    cv::circle(mask, center, inner_radius, cv::Scalar(255), -1);
                    
                    // 將「不是白色遮罩」(也就是全黑背景、圓以外的部分) 的像素，直接刷成白板顏色 (255)
                    // 這樣圓的外框雜訊就不見了，只留下內部的數字！
                    roi_gray.setTo(cv::Scalar(255), mask == 0);
                    // ===========================================

                    // 2. 自動裁切並縮放為 28x28 (新增 CNN 最佳化步驟，傳入已經被清掉圓框的圖)
                    cv::Mat processed = preprocess_roi_for_tflite(roi_gray);
                    
                    // 3. 歸一化 (0~255 轉為 0.0~1.0 的 float32)
                    cv::Mat floatMat;
                    processed.convertTo(floatMat, CV_32FC1, 1.0 / 255.0);
                    
                    // 4. 將 OpenCV 的矩陣資料 Copy 到我們要回傳的指標中
                    std::memcpy(result->nodes[i].pixels, floatMat.data, 28 * 28 * sizeof(float));

                    // // 查看node C++處理後圖片用
                    // // ===============================================
                    // // 新增：把要送給 CNN (已經是 float32 相對應的圖) 這個 28x28 圖片存下來
                    // // ===============================================
                    // std::string basePath(imagePath);
                    // size_t p = basePath.find_last_of(".");
                    // std::string roiDebugPath;
                    
                    // // 結尾加上 _node_0.jpg, _node_1.jpg 等可以辨識是哪一個圓圈
                    // if (p != std::string::npos) {
                    //     roiDebugPath = basePath.substr(0, p) + "_node_" + std::to_string(i) + ".jpg";
                    // } else {
                    //     roiDebugPath = basePath + "_node_" + std::to_string(i) + ".jpg";
                    // }

                    // // 注意：因為 processed 經過 preprocess_roi_for_tflite 後，是 0 與 255 的 CV_8UC1 矩陣
                    // cv::imwrite(roiDebugPath, processed);
                    // // ===============================================
                    
                } else {
                    // 防呆：如果意外裁切失敗，填入全黑
                    std::memset(result->nodes[i].pixels, 0, 28 * 28 * sizeof(float));
                }
            }
        } else {
            result->nodes = nullptr;
        }

        // 【關鍵 C】：封裝線段資料 (陣列分配) 與權重 ROI 裁切
        result->edgeCount = lines.size();
        if (result->edgeCount > 0) {
            result->edges = (EdgeData*)malloc(sizeof(EdgeData) * result->edgeCount);
            for (int i = 0; i < result->edgeCount; ++i) {
                int x1 = lines[i][0];
                int y1 = lines[i][1];
                int x2 = lines[i][2];
                int y2 = lines[i][3];
                
                result->edges[i].x1 = x1;
                result->edges[i].y1 = y1;
                result->edges[i].x2 = x2;
                result->edges[i].y2 = y2;
                
                // 1. 計算線段中點
                int mx = (x1 + x2) / 2;
                int my = (y1 + y2) / 2;

                // 【新增機制】：防禦 HoughLinesP 亂拉圓形邊緣的假線
                // 如果這個中點離任何一個圓心太近 (小於半徑的 1.2 倍)，
                // 代表這條線根本就是沿著圓的外框畫的假線，直接放棄。
                bool isFakeLineOnCircle = false;
                for (const auto& circle : circles) {
                    float cx = circle[0];
                    float cy = circle[1];
                    float cr = circle[2];
                    
                    float distSq = (mx - cx) * (mx - cx) + (my - cy) * (my - cy);
                    if (distSq < (cr * 1.2f) * (cr * 1.2f)) {
                        isFakeLineOnCircle = true;
                        break;
                    }
                }

                if (isFakeLineOnCircle) {
                    result->edges[i].hasWeight = false;
                    result->edges[i].pixels = nullptr;
                    continue; // 提早結束這條線的處理，不要浪費時間抓錯的 ROI
                }
                
                // 2. 在中點周圍圈出 40x40 的矩形 ROI
                int roiSize = 40; 
                cv::Rect roi(mx - roiSize / 2, my - roiSize / 2, roiSize, roiSize);
                
                // 防禦邊界溢位
                roi &= cv::Rect(0, 0, thresholded.cols, thresholded.rows);

                // 3. 判斷該區域有沒有文字 (白色的墨水)
                cv::Mat thresholded_cropped = thresholded(roi).clone();
                
                // 【新增抗噪】：使用形態學開運算(Opening)移除小白點雜訊
                // 用一個 3x3 的矩陣削掉孤立的小雜訊
                cv::Mat noise_kernel = cv::getStructuringElement(cv::MORPH_RECT, cv::Size(3, 3));
                cv::morphologyEx(thresholded_cropped, thresholded_cropped, cv::MORPH_OPEN, noise_kernel);

                int nonZeroPixels = cv::countNonZero(thresholded_cropped);

                // 假設超過 100 個像素是白的，才判定有寫字 (原本 15 在高畫素下太容易被雜訊觸發)
                // 且因為我們前面已經把散落的小雜訊削掉了，剩下的幾乎肯定是筆跡
                if (roi.area() > 0 && nonZeroPixels > 100) {
                    result->edges[i].hasWeight = true;
                    result->edges[i].pixels = (float*)malloc(28 * 28 * sizeof(float));
                    
                    // 自動裁切並縮放為 28x28 (新增 CNN 最佳化步驟)
                    cv::Mat processed = preprocess_roi_for_tflite(gray(roi));
                    cv::Mat floatMat;
                    processed.convertTo(floatMat, CV_32FC1, 1.0 / 255.0);
                    std::memcpy(result->edges[i].pixels, floatMat.data, 28 * 28 * sizeof(float));

                    // 查看node C++處理後圖片用
                    // ===============================================
                    // 新增：把要送給 CNN (已經是 float32 相對應的圖) 這個 28x28 圖片存下來
                    // ===============================================
                    std::string basePath(imagePath);
                    size_t p = basePath.find_last_of(".");
                    std::string roiDebugPath;
                    
                    if (p != std::string::npos) {
                        roiDebugPath = basePath.substr(0, p) + "_edgeW_" + std::to_string(i) + ".jpg";
                    } else {
                        roiDebugPath = basePath + "_edgeW_" + std::to_string(i) + ".jpg";
                    }

                    // 注意：因為 processed 經過 preprocess_roi_for_tflite 後，是 0 與 255 的 CV_8UC1 矩陣
                    cv::imwrite(roiDebugPath, processed);
                    // ===============================================
                    
                } else {
                    result->edges[i].hasWeight = false;
                    result->edges[i].pixels = nullptr; // 沒有文字，不分配記憶體
                }
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
            if (result->nodes != nullptr) {
                // 新增：必須先釋放每一個節點的 pixels，否則會發生嚴重的 Memory Leak
                for (int i = 0; i < result->nodeCount; ++i) {
                    if (result->nodes[i].pixels != nullptr) {
                        free(result->nodes[i].pixels);
                    }
                }
                free(result->nodes);
            }
            // 🌟 釋放邊緣權重的影像記憶體
            if (result->edges != nullptr) {
                for (int i = 0; i < result->edgeCount; ++i) {
                    if (result->edges[i].pixels != nullptr) {
                        free(result->edges[i].pixels);
                    }
                }
                free(result->edges);
            }
            free(result);
        }
    }
}