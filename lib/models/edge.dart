import 'package:equatable/equatable.dart';

class Edge extends Equatable {
  final String sourceNodeId;
  final String targetNodeId;
  final double? weight;

  const Edge({
    required this.sourceNodeId,
    required this.targetNodeId,
    this.weight,
  });

  Edge copyWith({
    String? sourceNodeId,
    String? targetNodeId,
    double? weight,
  }) {
    return Edge(
      sourceNodeId: sourceNodeId ?? this.sourceNodeId,
      targetNodeId: targetNodeId ?? this.targetNodeId,
      weight: weight ?? this.weight,
    );
  }

  @override
  List<Object?> get props => [sourceNodeId, targetNodeId, weight];
}
