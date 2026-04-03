#include <iostream>
#include <opencv2/opencv.hpp>

// ==========================================
// 1. 純 C++ 區塊 (內部邏輯)
// 移出 extern "C"，這裡可以自由使用所有的 C++ 特性與 OpenCV 物件
// ==========================================
cv::Mat preprocessWhiteboardImage(const cv::Mat& src) {
    if (src.empty()) {
        std::cerr << "[C++ Error] Input image is empty." << std::endl;
        return cv::Mat(); 
    }

    cv::Mat gray, blurred, thresholded, edges;

    try {
        cv::cvtColor(src, gray, cv::COLOR_BGR2GRAY);
        cv::GaussianBlur(gray, blurred, cv::Size(5, 5), 0);
        cv::adaptiveThreshold(blurred, thresholded, 255, 
                              cv::ADAPTIVE_THRESH_GAUSSIAN_C, 
                              cv::THRESH_BINARY_INV, 
                              11, 2);
        cv::Canny(thresholded, edges, 50, 150);
    } catch (const cv::Exception& e) {
        std::cerr << "[C++ OpenCV Exception] " << e.what() << std::endl;
        return cv::Mat();
    }

    return edges;
}

// ==========================================
// 2. C 介面區塊 (FFI 橋接)
// 這裡面的函數必須嚴格遵守 C 語言規範，只使用指標與基本型別
// ==========================================
extern "C" {

    // 定義用來傳遞資料的結構 (這是純 C 結構，完全合法)
    struct ResultData {
        float* nodeCoordinates; 
        int nodeCount;
    };

    // 開放給 Dart 呼叫的主函數
    __attribute__((visibility("default"))) __attribute__((used))
    ResultData* process_image_c(const char* imagePath) {
        
        // 💡 你可以在這裡面安心地呼叫外面的純 C++ 函數！
        // cv::Mat src = cv::imread(imagePath);
        // cv::Mat processedEdges = preprocessWhiteboardImage(src);
        
        // ... (執行霍夫轉換等後續 OpenCV 分析) ...

        ResultData* result = new ResultData();
        
        // 模擬寫入資料
        result->nodeCount = 2;
        result->nodeCoordinates = new float[result->nodeCount * 3]; 
        
        result->nodeCoordinates[0] = 100.0f; // centerX
        result->nodeCoordinates[1] = 150.0f; // centerY
        result->nodeCoordinates[2] = 30.0f;  // radius
        
        result->nodeCoordinates[3] = 400.0f; // centerX
        result->nodeCoordinates[4] = 200.0f; // centerY
        result->nodeCoordinates[5] = 35.0f;  // radius
        
        return result; 
    }

    // 專門用來釋放記憶體的函數
    __attribute__((visibility("default"))) __attribute__((used))
    void free_result_data_c(ResultData* data) {
        if (data != nullptr) {
            if (data->nodeCoordinates != nullptr) {
                delete[] data->nodeCoordinates; 
            }
            delete data; 
        }
    }

}