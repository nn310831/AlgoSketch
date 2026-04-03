import '../models/graph.dart';
import '../models/algorithm_state.dart';
import 'algorithm_service.dart';

class AlgorithmServiceImpl implements AlgorithmService {
  
  // 為了配合你的介面，我們將 Iterable 轉成 Stream
  // 但實務上因為我們要支援「上一步」，UI 層會把它轉成 List (時間軸) 儲存
  @override
  Stream<AlgorithmState> runBFSAlgorithm(Graph graph, String startNodeId) {
    return Stream.fromIterable(_bfsGenerator(graph, startNodeId));
  }

  @override
  Stream<AlgorithmState> runDFSAlgorithm(Graph graph, String startNodeId) {
    return Stream.fromIterable(_dfsGenerator(graph, startNodeId));
  }

  @override
  Stream<AlgorithmState> runDijkstraAlgorithm(Graph graph, String startNodeId) {
    return Stream.fromIterable(_dijkstraGenerator(graph, startNodeId));
  }

  /// 核心魔法：使用 sync* 與 yield 實作「步進式 BFS」
  Iterable<AlgorithmState> _bfsGenerator(Graph graph, String startNodeId) sync* {
    // 防呆：如果起點不存在於圖中，直接結束
    if (!graph.nodes.containsKey(startNodeId)) return;

    // 1. 初始化 BFS 所需的資料結構
    final Set<String> visited = {};
    final List<String> queue = [];

    // 2. 初始狀態快照
    queue.add(startNodeId);
    visited.add(startNodeId);
    
    yield AlgorithmState(
      activeNodeId: startNodeId,
      visitedNodeIds: Set.from(visited), // 必須複製 Set，確保 Immutable (不可變性)
      queuedNodeIds: List.from(queue),
      description: '初始化 BFS，將起點 $startNodeId 加入佇列',
    );

    // 3. 傳統 BFS 迴圈
    while (queue.isNotEmpty) {
      // 從佇列取出第一個節點
      final currentNodeId = queue.removeAt(0);

      // ★ 快照：正在處理當前節點
      yield AlgorithmState(
        activeNodeId: currentNodeId,
        visitedNodeIds: Set.from(visited),
        queuedNodeIds: List.from(queue),
        description: '從佇列取出節點 $currentNodeId 進行探索',
      );

      // 找出這個節點的所有鄰居 (透過鄰接表)
      final neighbors = graph.adjacencyList[currentNodeId] ?? [];

      for (var edge in neighbors) {
        final targetId = edge.targetNodeId;

        // ★ 快照：正在看這條連線
        yield AlgorithmState(
          activeNodeId: currentNodeId,
          activeEdgeId: '${edge.sourceNodeId}_${edge.targetNodeId}', // 標示發光的邊
          visitedNodeIds: Set.from(visited),
          queuedNodeIds: List.from(queue),
          description: '檢查 $currentNodeId 的鄰居 $targetId...',
        );

        // 如果鄰居還沒被訪問過
        if (!visited.contains(targetId)) {
          visited.add(targetId);
          queue.add(targetId);

          // ★ 快照：發現新節點，加入佇列
          yield AlgorithmState(
            activeNodeId: currentNodeId,
            activeEdgeId: '${edge.sourceNodeId}_${edge.targetNodeId}',
            visitedNodeIds: Set.from(visited),
            queuedNodeIds: List.from(queue), // 佇列內容更新了！
            description: '發現新節點 $targetId，標記為已訪問並加入佇列等待探索',
          );
        } else {
          // ★ 快照：鄰居已經去過了
          yield AlgorithmState(
            activeNodeId: currentNodeId,
            activeEdgeId: '${edge.sourceNodeId}_${edge.targetNodeId}',
            visitedNodeIds: Set.from(visited),
            queuedNodeIds: List.from(queue),
            description: '節點 $targetId 已經訪問過了，跳過。',
          );
        }
      }
    }

    // ★ 結束快照
    yield AlgorithmState(
      visitedNodeIds: Set.from(visited),
      queuedNodeIds: const [],
      description: 'BFS 走訪完成！',
    );
  }

  /// 使用 Stack 與 yield 實作「步進式 DFS」
  Iterable<AlgorithmState> _dfsGenerator(Graph graph, String startNodeId) sync* {
    if (!graph.nodes.containsKey(startNodeId)) return;

    final Set<String> visited = {};
    
    // 這裡我們把命名改成 stack，但本質上一樣是 Dart 的 List
    final List<String> stack = []; 

    stack.add(startNodeId);
    
    yield AlgorithmState(
      activeNodeId: startNodeId,
      visitedNodeIds: Set.from(visited),
      queuedNodeIds: List.from(stack),
      description: '初始化 DFS，將起點 $startNodeId 推入堆疊 (Stack)',
    );

    while (stack.isNotEmpty) {
      // 🌟 核心關鍵改變 1：從 List 的「尾端」拿出資料 (後進先出 LIFO)
      // 在 BFS 中，這裡是 queue.removeAt(0);
      final currentNodeId = stack.removeLast(); 

      // 🌟 核心關鍵改變 2：DFS 通常在「拿出堆疊」時才標記為已訪問
      if (!visited.contains(currentNodeId)) {
        visited.add(currentNodeId);

        yield AlgorithmState(
          activeNodeId: currentNodeId,
          visitedNodeIds: Set.from(visited),
          queuedNodeIds: List.from(stack),
          description: '一路向下鑽！正在探索節點 $currentNodeId',
        );

        final neighbors = graph.adjacencyList[currentNodeId] ?? [];

        // 小技巧：為了讓視覺上符合人類習慣（從左邊的鄰居開始鑽）
        // 因為 Stack 是後進先出，所以我們把鄰居「反向」推入堆疊
        for (var edge in neighbors.reversed) {
          final targetId = edge.targetNodeId;

          yield AlgorithmState(
            activeNodeId: currentNodeId,
            activeEdgeId: '${edge.sourceNodeId}_${edge.targetNodeId}',
            visitedNodeIds: Set.from(visited),
            queuedNodeIds: List.from(stack),
            description: '檢查 $currentNodeId 的鄰居 $targetId...',
          );

          // 如果還沒去過，推入堆疊頂端！
          if (!visited.contains(targetId)) {
            stack.add(targetId);

            yield AlgorithmState(
              activeNodeId: currentNodeId,
              activeEdgeId: '${edge.sourceNodeId}_${edge.targetNodeId}',
              visitedNodeIds: Set.from(visited),
              queuedNodeIds: List.from(stack), 
              description: '發現新節點 $targetId，推入堆疊頂端準備下次優先探索！',
            );
          }
        }
      }
    }

    yield AlgorithmState(
      visitedNodeIds: Set.from(visited),
      queuedNodeIds: const [],
      description: 'DFS 深度走訪完成！',
    );
  }

  /// 使用優先佇列 (或 List 排序) 與 yield 實作「步進式 Dijkstra」
  Iterable<AlgorithmState> _dijkstraGenerator(Graph graph, String startNodeId) sync* {
    if (!graph.nodes.containsKey(startNodeId)) return;

    // 記錄起點到每個節點的最短距離
    final Map<String, double> distances = {startNodeId: 0.0};
    
    // 已確定最短距離的節點集合 (Settled)
    final Set<String> settledNodes = {};
    
    // 待處理的優先佇列 (這裡用 List 模擬，並在每次取出前排序)
    final List<String> priorityQueue = [startNodeId];

    yield AlgorithmState(
      activeNodeId: startNodeId,
      visitedNodeIds: Set.from(settledNodes),
      queuedNodeIds: List.from(priorityQueue),
      description: '初始化 Dijkstra，起點 $startNodeId 距離設為 0，加入優先佇列',
    );

    while (priorityQueue.isNotEmpty) {
      // 根據目前已知最短距離排序，確保取出的是距離最小的節點 (Min-Heap 概念)
      priorityQueue.sort((a, b) => (distances[a] ?? double.infinity)
          .compareTo(distances[b] ?? double.infinity));
      
      final currentNodeId = priorityQueue.removeAt(0);

      // 如果這個節點已經確定了，就跳過
      if (settledNodes.contains(currentNodeId)) continue;

      yield AlgorithmState(
        activeNodeId: currentNodeId,
        visitedNodeIds: Set.from(settledNodes),
        queuedNodeIds: List.from(priorityQueue),
        description: '從佇列取出目前距離最短的節點 $currentNodeId，確定其最短路徑！',
      );

      // 當我們從優先佇列取出節點，代表該節點的最短路徑已確定
      settledNodes.add(currentNodeId);

      final neighbors = graph.adjacencyList[currentNodeId] ?? [];

      for (var edge in neighbors) {
        final targetId = edge.targetNodeId;
        
        if (settledNodes.contains(targetId)) continue; // 已確定的不回頭看

        // 如果圖論中的邊沒有權重，我們預設為 1.0 (或可以讀取 edge 內的權重)
        final weight = edge.weight ?? 1.0;
        final currentDist = distances[currentNodeId] ?? double.infinity;
        final newDist = currentDist + weight;

        yield AlgorithmState(
          activeNodeId: currentNodeId,
          activeEdgeId: '${edge.sourceNodeId}_${edge.targetNodeId}',
          visitedNodeIds: Set.from(settledNodes),
          queuedNodeIds: List.from(priorityQueue),
          description: '檢查 $currentNodeId 的鄰居 $targetId (路徑權重: $weight)...',
        );

        final targetOldDist = distances[targetId] ?? double.infinity;

        if (newDist < targetOldDist) {
          distances[targetId] = newDist;
          
          if (!priorityQueue.contains(targetId)) {
            priorityQueue.add(targetId);
            yield AlgorithmState(
              activeNodeId: currentNodeId,
              activeEdgeId: '${edge.sourceNodeId}_${edge.targetNodeId}',
              visitedNodeIds: Set.from(settledNodes),
              queuedNodeIds: List.from(priorityQueue),
              description: '更新 $targetId 距離為 $newDist，加入優先佇列！',
            );
          } else {
            yield AlgorithmState(
              activeNodeId: currentNodeId,
              activeEdgeId: '${edge.sourceNodeId}_${edge.targetNodeId}',
              visitedNodeIds: Set.from(settledNodes),
              queuedNodeIds: List.from(priorityQueue),
              description: '發現更短路徑！更新 $targetId 距離為 $newDist (佇列將重新排序)',
            );
          }
        }
      }
    }

    yield AlgorithmState(
      visitedNodeIds: Set.from(settledNodes),
      queuedNodeIds: const [],
      description: 'Dijkstra 演算法執行完成！',
    );
  }
}
