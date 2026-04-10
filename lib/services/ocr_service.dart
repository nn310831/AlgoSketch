import 'dart:typed_data';
import 'package:tflite_flutter/tflite_flutter.dart';

class OcrService {
  Interpreter? _interpreter;

  // 標籤對應表 (根據文件階段零 0.2 所定義的 13 個類別)
  final List<String> _labels = [
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9',
    'S', 'T', '∞'
  ];

  /// 載入模型 (在 Isolate 中呼叫)
  Future<void> loadModel() async {
    // 載入量化過的 tflite 模型
    _interpreter = await Interpreter.fromAsset('assets/model.tflite');
  }

  /// 從 bytes 載入模型 (解決 Isolate 內無法讀取 Asset 的問題)
  void loadModelFromBuffer(Uint8List modelBytes) {
    _interpreter = Interpreter.fromBuffer(modelBytes);
  }

  /// 執行單次/批次推論
  String recognizeCharacter(Float32List tensor784) {
    if (_interpreter == null) throw Exception("模型尚未載入");

    // 1. 準備輸入資料
    // tflite_flutter 中 Float32List 的 reshape 寫法為：
    // var input = tensor784.reshape([1, 28, 28, 1]);
    var input = tensor784.reshape([1, 28, 28, 1]);

    // 2. 準備輸出容器
    // 預期輸出是[1, 13] 的機率陣列
    var output = List.generate(1, (i) => List.filled(13, 0.0)).reshape([1, 13]);

    // 3. 執行推論 (TFLite 引擎運算)
    _interpreter!.run(input, output);

    // 4. 解析結果 (Argmax 與 信心度過濾)
    List<double> probabilities = (output[0] as List).cast<double>();
    return _decodeArgmax(probabilities);
  }

  /// 結果解碼與信心度過濾 (Confidence Thresholding)
  String _decodeArgmax(List<double> probabilities) {
    double maxProb = 0.0;
    int maxIndex = -1;

    for (int i = 0; i < probabilities.length; i++) {
      if (probabilities[i] > maxProb) {
        maxProb = probabilities[i];
        maxIndex = i;
      }
    }

    // 文件強調的 Best Practice：信心度過濾
    // 如果機率低於 80% (0.8)，回傳 "?"，讓 UI 提示使用者手動校正，避免演算法崩潰
    if (maxProb < 0.60) {
      return "?";
    }

    return _labels[maxIndex];
  }

  /// 釋放記憶體
  void dispose() {
    _interpreter?.close();
  }
}
