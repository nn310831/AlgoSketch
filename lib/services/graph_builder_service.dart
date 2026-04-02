import '../models/raw_graph_data.dart';
import '../models/graph.dart';

abstract class GraphBuilderService {
  /// 將離散的節點與邊，透過空間交集演算法轉化為程式可理解的圖論 Graph 結構。
  /// 此過程為同步操作。
  Graph buildGraph(RawGraphData rawData);
}
