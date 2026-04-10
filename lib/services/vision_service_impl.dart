import 'dart:isolate';
import 'dart:ffi';
import 'dart:typed_data'; // 新增
import 'package:ffi/ffi.dart'; // 提供 utf8 與指標相關的擴充工具
import 'package:flutter/services.dart'; // 引入 RootIsolateToken 需要的套件

import '../models/raw_graph_data.dart';
import '../models/node.dart';
// import '../models/edge.dart';  // 未來用到時開啟
import 'vision_service.dart';
import 'ocr_service.dart';


// CNN模型建立好之後
// 記得去 102行 跟 166行 跟 191行 取消註解 , 並註解 169、192 行
// 才會真的運行到模型
//模擬CNN模型隨機數用 有模型就可以把 ramdom 刪掉了

// ============================================
// 【1. FFI 資料結構對齊】
// 用於銜接 C++ struct VisionResult
// ============================================
// 1. 鏡射 C++ 的 NodeData
final class NativeNode extends Struct {
  @Float()
  external double x;

  @Float()
  external double y;

  @Float()
  external double radius;

  external Pointer<Float> pixels; // 新增：C++ 傳來的 784 維 Tensor
}

// 2. 鏡射 C++ 的 EdgeData
final class NativeEdge extends Struct {
  @Int32()
  external int x1;

  @Int32()
  external int y1;

  @Int32()
  external int x2;

  @Int32()
  external int y2;

  @Bool()
  external bool hasWeight; // 是否有找到文字墨水

  external Pointer<Float> pixels; // 指向 28x28 權重影像的指標
}

// 3. 鏡射 C++ 的大包裹 VisionResult
final class NativeVisionResult extends Struct {
  external Pointer<NativeNode> nodes; // 指向 Node 陣列的指標
  @Int32()
  external int nodeCount;

  external Pointer<NativeEdge> edges; // 指向 Edge 陣列的指標
  @Int32()
  external int edgeCount;
}

// ============================================
// 【2. 定義 FFI 函數型式】
// ============================================
typedef ProcessImageC =
    Pointer<NativeVisionResult> Function(Pointer<Utf8> imagePath);
typedef ProcessImageDart =
    Pointer<NativeVisionResult> Function(Pointer<Utf8> imagePath);

typedef FreeResultDataC = Void Function(Pointer<NativeVisionResult> data);
typedef FreeResultDataDart = void Function(Pointer<NativeVisionResult> data);

// ============================================
// 【3. 實作 VisionService，主打安全與效能】
// ============================================
class VisionServiceImpl implements VisionService {
  @override
  Future<RawGraphData> processImage(String imagePath) async {
    // 獲取主執行緒的 Token，準備傳給背景 Isolate
    RootIsolateToken rootToken = RootIsolateToken.instance!;

    // 主執行緒先讀取模型
    final modelData = await rootBundle.load('assets/model.tflite');
    final modelBytes = modelData.buffer.asUint8List();

    // 1. 將繁重工作丟進背景 Isolate
    // UI 執行緒到這裡就不會被卡住，繼續維持 60fps 順暢運作
    final rawData = await Isolate.run(() async {
      // --- 以下程式碼全部在「背景 CPU 核心」中獨立執行 ---

      // 初始化背景 Isolate 的 Flutter 引擎綁定 (這是讀取 assets 的關鍵！)
      BackgroundIsolateBinaryMessenger.ensureInitialized(rootToken);

      // 載入 OCR 模型
      final ocrService = OcrService();

      //訓練好模型後開啟，並傳入 bytes
      ocrService.loadModelFromBuffer(modelBytes);


      final DynamicLibrary nativeLib = DynamicLibrary.process();
      // 綁定 C++ 的處理函式
      final ProcessImageDart nativeProcessImage = nativeLib
          .lookup<NativeFunction<ProcessImageC>>('process_whiteboard_image')
          .asFunction<ProcessImageDart>();

      // 將 Dart 的字串轉成 C++ 看得懂的 utf8 指標
      final pathPointer = imagePath.toNativeUtf8();

      try {
        // 2. 透過 FFI 呼叫底層 C++ OpenCV 引擎
        final pointerResult = nativeProcessImage(pathPointer);

        // 3. 解析指標資料轉換為 Dart 模型，並交由 finally 處理跨語言記憶體回收
        return _parseAndFree(pointerResult, nativeLib, ocrService);
      } finally {
        // 釋放 Dart 傳給 C++ 的字串記憶體 (也是 gc 管不到的地方)
        calloc.free(pathPointer);
        ocrService.dispose(); // 記得關閉 TFLite 解釋器
      }

      // --- 至此 Isolate 工作結束，將乾淨的 Data Model 傳回給主執行緒 ---
    });

    return rawData;
  }

  /// 負責解析 C++ 指標資料，這也是【跨語言記憶體管理：防禦地雷區】的核心。
  static RawGraphData _parseAndFree(
    Pointer<NativeVisionResult> resultPtr,
    DynamicLibrary nativeLib,
    OcrService ocrService,
  ) {
    // 動態綁定 C++ 端的釋放記憶體函數
    //('free_vision_result') 一定要與 C++ function name 相同
    final FreeResultDataDart nativeFreeResultData = nativeLib
        .lookup<NativeFunction<FreeResultDataC>>('free_vision_result')
        .asFunction<FreeResultDataDart>();

    try {
      if (resultPtr == nullptr) {
        return const RawGraphData(nodes: [], edges: [], rawLines: []);
      }

      // 解開第一層指標，看到裡面的結構
      final data = resultPtr.ref;
      final Set<Node> nodes = {};
      final List<RawLine> rawLines = [];

      // 3. 零拷貝讀取 Nodes
      for (int i = 0; i < data.nodeCount; i++) {
        // 我們沒有複製陣列，而是直接把視線 (View) 移到 C++ 的記憶體位址上
        final node = data.nodes[i];

        // ★ 核心魔法：FFI 零拷貝讀取 ★
        // 這行不會產生新的記憶體分配，而是直接建立一個透視 C++ 記憶體的「視窗」
        Float32List tensorView = node.pixels.asTypedList(784);

        // ★★★ 真正呼叫 CNN 模型辨識數字 ★★★ //訓練好模型後開啟
        String recognizedChar = ocrService.recognizeCharacter(tensorView);

        //先模擬判斷出來的數字為隨機數
        // String recognizedChar = (random.nextInt(10)).toString(); 

        nodes.add(
          Node(
            id: 'ID:${i}',
            value: recognizedChar, // 正確將 OCR 辨識結果存入
            centerX: node.x,
            centerY: node.y,
            radius: node.radius,
          ),
        );
      }

      // 4. 零拷貝讀取 Edges
      for (int i = 0; i < data.edgeCount; i++) {
        final edge = data.edges[i];
        double? weightValue;

        if (edge.hasWeight && edge.pixels != nullptr) {
          Float32List edgeTensor = edge.pixels.asTypedList(784);
          
          // 使用同一個 interpreter 進行 CNN 推論
          String recognizedChar = ocrService.recognizeCharacter(edgeTensor);
          // String recognizedChar = (random.nextInt(10)).toString(); // MOCK，先假設抓出來的權重都是 5
          
          weightValue = double.tryParse(recognizedChar); 
        }

        rawLines.add(
          RawLine(
            x1: edge.x1.toDouble(),
            y1: edge.y1.toDouble(),
            x2: edge.x2.toDouble(),
            y2: edge.y2.toDouble(),
            weight: weightValue,
          ),
        );
      }

      return RawGraphData(nodes: nodes.toList(), edges: [], rawLines: rawLines);
    } finally {
      // 5. ☢️ 極度重要：立刻通知 C++ 銷毀記憶體！
      // 不管 try 區塊內轉型成不成功、有沒有發生範圍溢界例外 (Exception)
      // finally 一定會執行，強制呼叫 C++ 端的釋放函數，清空記憶體！
      if (resultPtr != nullptr) {
        nativeFreeResultData(resultPtr);
      }
    }
  }
}
