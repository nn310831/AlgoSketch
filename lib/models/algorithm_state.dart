import 'package:equatable/equatable.dart';

class AlgorithmState extends Equatable {
  final String? activeNodeId;
  final Set<String> visitedNodeIds;
  final List<String> queuedNodeIds;
  final String? activeEdgeId;
  final String description;

  const AlgorithmState({
    this.activeNodeId,
    this.visitedNodeIds = const {},
    this.queuedNodeIds = const [],
    this.activeEdgeId,
    this.description = '',
  });

  AlgorithmState copyWith({
    String? activeNodeId,
    Set<String>? visitedNodeIds,
    List<String>? queuedNodeIds,
    String? activeEdgeId,
    String? description,
  }) {
    return AlgorithmState(
      activeNodeId: activeNodeId ?? this.activeNodeId,
      visitedNodeIds: visitedNodeIds ?? this.visitedNodeIds,
      queuedNodeIds: queuedNodeIds ?? this.queuedNodeIds,
      activeEdgeId: activeEdgeId ?? this.activeEdgeId,
      description: description ?? this.description,
    );
  }

  @override
  List<Object?> get props => [
        activeNodeId,
        visitedNodeIds,
        queuedNodeIds,
        activeEdgeId,
        description,
      ];
}
