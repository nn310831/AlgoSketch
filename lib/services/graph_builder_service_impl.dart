import 'dart:math';

import '../models/raw_graph_data.dart';
import '../models/graph.dart';
import '../models/node.dart';
import '../models/edge.dart';

import 'graph_builder_service.dart';

class GraphBuilderServiceImpl implements GraphBuilderService {
  // 容錯門檻 (Epsilon): 允許線段端點距離圓形邊緣多遠 (單位：邏輯像素)
  // 如果白板筆跡比較粗或畫得比較隨意，可以調大這個值
  static const double toleranceBuffer = 20.0;

  @override
  Graph buildGraph(RawGraphData rawData) {
    // 1. 建立 Node Map，方便 O(1) 尋找
    final Map<String, Node> nodeMap = {
      for (var node in rawData.nodes) node.id: node
    };

    // 2. 初始化空的鄰接表
    final Map<String, List<Edge>> adjacencyList = {
      for (var node in rawData.nodes) node.id: []
    };

    // 暫存已經建立的連線，用於「多重連線合併」防呆機制
    final Set<String> establishedConnections = {};

    // 3. 核心迴圈：自動吸附與交集判定
    for (var line in rawData.rawLines) {
      // 錯誤校正一：過短邊過濾 (Short Edge Removal)
      // 如果線段長度小於 15 像素，通常是雜訊，直接捨棄
      if (_calculateDistance(line.x1, line.y1, line.x2, line.y2) < 15.0) {
        continue;
      }

      Node? startNode = _findSnappingNode(line.x1, line.y1, rawData.nodes);
      Node? endNode = _findSnappingNode(line.x2, line.y2, rawData.nodes);

      // 判定有效連線：必須成功連接兩個「不同」的節點
      if (startNode != null && endNode != null && startNode.id != endNode.id) {
        
        // 為了處理無向圖 (Undirected Graph)，我們將 ID 排序組合成唯一鍵值
        // 例如：連接 A 和 B，鍵值固定為 "A_B"
        final List<String> sortedIds = [startNode.id, endNode.id]..sort();
        final connectionKey = '${sortedIds[0]}_${sortedIds[1]}';

        // 錯誤校正二：多重連線合併 (Duplicate Edge Merging)
        // 如果使用者重複畫了兩條線連接 A 和 B，我們只記錄一條
        if (!establishedConnections.contains(connectionKey)) {
          establishedConnections.add(connectionKey);

          // 由於手繪白板通常是無向圖 (除非有辨識箭頭)，
          // 我們需要在鄰接表中建立「雙向」的 Edge。
          adjacencyList[startNode.id]!.add(
            Edge(sourceNodeId: startNode.id, targetNodeId: endNode.id, weight: line.weight),
          );
          adjacencyList[endNode.id]!.add(
            Edge(sourceNodeId: endNode.id, targetNodeId: startNode.id, weight: line.weight),
          );
        }
      } else {
        // 錯誤校正三：孤立線段捨棄
        // 如果這條線一端或兩端懸空 (找不到吸附的節點)，則判定為雜訊，不做任何事。
      }
    }

    return Graph(nodes: nodeMap, adjacencyList: adjacencyList);
  }

  // ==========================================
  // 私有輔助數學函數
  // ==========================================

  /// 尋找座標點是否能「吸附」到某個節點上
  Node? _findSnappingNode(double targetX, double targetY, List<Node> nodes) {
    for (var node in nodes) {
      // 計算端點與圓心的歐幾里得距離
      double d = _calculateDistance(targetX, targetY, node.centerX, node.centerY);
      
      // 數學判定公式： d <= r_j + epsilon
      // 只要距離小於等於「圓的半徑 + 容錯門檻」，就算作連接上了
      if (d <= node.radius + toleranceBuffer) {
        return node;
      }
    }
    return null; // 該端點懸空
  }

  /// 計算兩點間的歐幾里得距離 (Euclidean Distance)
  double _calculateDistance(double x1, double y1, double x2, double y2) {
    return sqrt(pow(x2 - x1, 2) + pow(y2 - y1, 2));
  }
}