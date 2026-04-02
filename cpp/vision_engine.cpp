#include <iostream>

extern "C" {

    // 定義用來傳遞資料的結構
    struct ResultData {
        float* nodeCoordinates; // 存放 x, y, radius 的陣列
        int nodeCount;
        
        // TODO: 未來可加入 Edge 的座標陣列
        // float* edgeCoordinates;
        // int edgeCount;
    };

    // 1. 執行運算並「分配 (malloc / new)」記憶體
    // 注意：此方法利用 C++ 動態配置記憶體並回傳指標，這些資源 Dart GC 管不到。
    __attribute__((visibility("default"))) __attribute__((used))
    ResultData* process_image_c(const char* imagePath) {
        
        // 在這裡，影像引擎會讀取 imagePath，呼叫 OpenCV 分析...
        // ... (模擬分析圖檔，耗時運算) ...

        ResultData* result = new ResultData();
        
        // 假設找到了 2 個節點 (圓形)，並動態分配記憶體給陣列
        // 每個 Node 需要 3 個 float (x, y, radius)
        result->nodeCount = 2;
        result->nodeCoordinates = new float[result->nodeCount * 3]; 
        
        // 寫入模擬的第一個節點
        result->nodeCoordinates[0] = 100.0f; // centerX
        result->nodeCoordinates[1] = 150.0f; // centerY
        result->nodeCoordinates[2] = 30.0f;  // radius
        
        // 寫入模擬的第二個節點
        result->nodeCoordinates[3] = 400.0f; // centerX
        result->nodeCoordinates[4] = 200.0f; // centerY
        result->nodeCoordinates[5] = 35.0f;  // radius
        
        // 把指標傳給 Dart
        return result; 
    }

    // 2. 【合約核心】專門用來「釋放 (delete)」記憶體的函數
    __attribute__((visibility("default"))) __attribute__((used))
    void free_result_data_c(ResultData* data) {
        if (data != nullptr) {
            if (data->nodeCoordinates != nullptr) {
                delete[] data->nodeCoordinates; // 釋放內部陣列
            }
            delete data; // 釋放結構本身
        }
    }

}
