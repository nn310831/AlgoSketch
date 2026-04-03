import 'package:flutter/material.dart';
import '../models/algorithm_state.dart';
import '../models/graph.dart';
import '../services/algorithm_service.dart';

class AlgorithmPlaybackProvider extends ChangeNotifier {
  final AlgorithmService _algorithmService;

  AlgorithmPlaybackProvider(this._algorithmService);

  // 我們的「時間軸 (Timeline)」：儲存演算法的所有快照
  List<AlgorithmState> _timeline = [];
  
  // 目前播放到第幾步
  int _currentIndex = 0;

  // 供 UI 讀取的 Getter
  List<AlgorithmState> get timeline => _timeline;
  int get currentIndex => _currentIndex;
  bool get hasData => _timeline.isNotEmpty;

  // 取得「當下這瞬間」的狀態快照
  AlgorithmState? get currentState => 
      _timeline.isNotEmpty ? _timeline[_currentIndex] : null;

  bool get canGoNext => _currentIndex < _timeline.length - 1;
  bool get canGoPrev => _currentIndex > 0;

  /// 載入演算法並生成時間軸
  Future<void> loadAlgorithm(Graph graph, String startNodeId, {String algorithmType = 'BFS'}) async {
    Stream<AlgorithmState> stream;
    
    switch (algorithmType.toUpperCase()) {
      case 'DFS':
        stream = _algorithmService.runDFSAlgorithm(graph, startNodeId);
        break;
      case 'DIJKSTRA':
        stream = _algorithmService.runDijkstraAlgorithm(graph, startNodeId);
        break;
      case 'BFS':
      default:
        stream = _algorithmService.runBFSAlgorithm(graph, startNodeId);
        break;
    }
    
    // 呼叫 Service，並將 Stream 轉換為完整的 List (時間軸)
    _timeline = await stream.toList();
    _currentIndex = 0;
    
    notifyListeners(); // 通知 UI 更新畫面
  }

  /// 下一步
  void stepForward() {
    if (canGoNext) {
      _currentIndex++;
      notifyListeners();
    }
  }

  /// 上一步 (時光倒流魔法！)
  void stepBackward() {
    if (canGoPrev) {
      _currentIndex--;
      notifyListeners();
    }
  }

  /// 重置回到初始狀態
  void reset() {
    _currentIndex = 0;
    notifyListeners();
  }
}