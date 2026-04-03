import 'package:equatable/equatable.dart';

class AlgorithmState extends Equatable {
  final String? activeNodeId;
  final Set<String> visitedNodeIds;
  final List<String> queuedNodeIds;
  final String? activeEdgeId;
  final String description;
  final Map<String, double>? distances;           // 新增：紀錄所有節點目前的距離
  final List<String>? shortestPathNodeIds;        // 新增：最短路徑節點 (黃色)
  final List<String>? shortestPathEdgeIds;        // 新增：最短路徑邊 (黃色)

  const AlgorithmState({
    this.activeNodeId,
    this.visitedNodeIds = const {},
    this.queuedNodeIds = const [],
    this.activeEdgeId,
    this.description = '',
    this.distances,
    this.shortestPathNodeIds,
    this.shortestPathEdgeIds,
  });

  AlgorithmState copyWith({
    String? activeNodeId,
    Set<String>? visitedNodeIds,
    List<String>? queuedNodeIds,
    String? activeEdgeId,
    String? description,
    Map<String, double>? distances,
    List<String>? shortestPathNodeIds,
    List<String>? shortestPathEdgeIds,
  }) {
    return AlgorithmState(
      activeNodeId: activeNodeId ?? this.activeNodeId,
      visitedNodeIds: visitedNodeIds ?? this.visitedNodeIds,
      queuedNodeIds: queuedNodeIds ?? this.queuedNodeIds,
      activeEdgeId: activeEdgeId ?? this.activeEdgeId,
      description: description ?? this.description,
      distances: distances ?? this.distances,
      shortestPathNodeIds: shortestPathNodeIds ?? this.shortestPathNodeIds,
      shortestPathEdgeIds: shortestPathEdgeIds ?? this.shortestPathEdgeIds,
    );
  }

  @override
  List<Object?> get props => [
        activeNodeId,
        visitedNodeIds,
        queuedNodeIds,
        activeEdgeId,
        description,
        distances,
        shortestPathNodeIds,
        shortestPathEdgeIds,
      ];
}
