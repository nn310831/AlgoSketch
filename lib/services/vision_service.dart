import '../models/raw_graph_data.dart';

abstract class VisionService {
  /// 傳入影像路徑，回傳辨識出的離散節點與線段。
  /// 影像處理涉及龐大的矩陣運算與跨語言呼叫，這是一個高耗時操作，必須在背景 Isolate 中執行避免卡頓 UI。
  Future<RawGraphData> processImage(String imagePath);
}
