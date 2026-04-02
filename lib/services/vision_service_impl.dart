import 'dart:isolate';
import 'dart:ffi';
import 'package:ffi/ffi.dart'; // 提供 utf8 與指標相關的擴充工具

import '../models/raw_graph_data.dart';
import '../models/node.dart';
// import '../models/edge.dart';  // 未來用到時開啟
import 'vision_service.dart';

// ============================================
// 【1. FFI 資料結構對齊】 
// 用於銜接 C++ struct ResultData 
// ============================================
final class ResultData extends Struct {
  external Pointer<Float> nodeCoordinates;

  @Int32()
  external int nodeCount;
}

// ============================================
// 【2. 定義 FFI 函數型式】
// ============================================
typedef ProcessImageC = Pointer<ResultData> Function(Pointer<Utf8> imagePath);
typedef ProcessImageDart = Pointer<ResultData> Function(Pointer<Utf8> imagePath);

typedef FreeResultDataC = Void Function(Pointer<ResultData> data);
typedef FreeResultDataDart = void Function(Pointer<ResultData> data);

// ============================================
// 【3. 實作 VisionService，主打安全與效能】
// ============================================
class VisionServiceImpl implements VisionService {
  @override
  Future<RawGraphData> processImage(String imagePath) async {
    // 1. 將繁重工作丟進背景 Isolate
    // UI 執行緒到這裡就不會被卡住，繼續維持 60fps 順暢運作
    final rawData = await Isolate.run(() {
      
      // --- 以下程式碼全部在「背景 CPU 核心」中獨立執行 ---

      // 載入動態套件 (這裡以 process 表示靜態綁定，實際會是 .so 或 framework 等)
      final DynamicLibrary nativeLib = DynamicLibrary.process();

      // 綁定 C++ 的處理函式
      final ProcessImageDart nativeProcessImage = nativeLib
          .lookup<NativeFunction<ProcessImageC>>('process_image_c')
          .asFunction<ProcessImageDart>();

      // 將 Dart 的字串轉成 C++ 看得懂的 utf8 指標
      final pathPointer = imagePath.toNativeUtf8();
      
      try {
        // 2. 透過 FFI 呼叫底層 C++ OpenCV 引擎
        final pointerResult = nativeProcessImage(pathPointer);
        
        // 3. 解析指標資料轉換為 Dart 模型，並交由 finally 處理跨語言記憶體回收
        return _parseAndFree(pointerResult, nativeLib);
      } finally {
        // 釋放 Dart 傳給 C++ 的字串記憶體 (也是 gc 管不到的地方)
        calloc.free(pathPointer);
      }

      // --- 至此 Isolate 工作結束，將乾淨的 Data Model 傳回給主執行緒 ---
    });

    return rawData;
  }

  /// 負責解析 C++ 指標資料，這也是【跨語言記憶體管理：防禦地雷區】的核心。
  static RawGraphData _parseAndFree(Pointer<ResultData> resultPtr, DynamicLibrary nativeLib) {
    // 動態綁定 C++ 端的釋放記憶體函數
    //('free_result_data_c') 一定要與 C++ function name 相同
    final FreeResultDataDart nativeFreeResultData = nativeLib
        .lookup<NativeFunction<FreeResultDataC>>('free_result_data_c')
        .asFunction<FreeResultDataDart>();

    try {
      if (resultPtr == nullptr) {
        return const RawGraphData(nodes: [], edges: []);
      }

      // 將 C++ 的 Pointer 實體化讀取
      final data = resultPtr.ref;
      final Set<Node> nodes = {}; // 確保同一節點不會因為不完美的預測生成重複資料

      // 解析 Node，陣列排列為 [x1, y1, r1, x2, y2, r2, ...]
      for (int i = 0; i < data.nodeCount; i++) {
        // 每次位移 3 格來讀取中心座標與半徑
        final x = data.nodeCoordinates[i * 3 + 0];
        final y = data.nodeCoordinates[i * 3 + 1];
        final r = data.nodeCoordinates[i * 3 + 2];

        nodes.add(Node(
          id: 'v_node_$i', // 給定臨時唯一 ID，日後可能是 OCR 辨識結果
          centerX: x,
          centerY: y,
          radius: r,
        ));
      }

      // 此處可擴充解析 Edge 的邏輯 ...

      return RawGraphData(nodes: nodes.toList(), edges: []);
    } finally {
      // 4. 【防護網：生命週期合約】
      // 不管 try 區塊內轉型成不成功、有沒有發生範圍溢界例外 (Exception)
      // finally 一定會執行，強制呼叫 C++ 端的釋放函數，清空記憶體！
      if (resultPtr != nullptr) {
        nativeFreeResultData(resultPtr);
      }
    }
  }
}
