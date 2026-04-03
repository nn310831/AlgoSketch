import '../models/graph.dart';
import '../models/algorithm_state.dart';

abstract class AlgorithmService {
  /// 執行圖論演算法，並持續吐出當前的演算法狀態快照 (AlgorithmState)。
  /// 以 Stream 的形式回傳，以便 UI 端 (透過 StreamBuilder、Bloc 或 Provider) 監聽狀態改變並分步播放動畫。
  Stream<AlgorithmState> runBFSAlgorithm(Graph graph, String startNodeId);
  Stream<AlgorithmState> runDFSAlgorithm(Graph graph, String startNodeId);
  Stream<AlgorithmState> runDijkstraAlgorithm(Graph graph, String startNodeId);
}
