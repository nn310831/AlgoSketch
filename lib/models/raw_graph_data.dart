import 'package:equatable/equatable.dart';
import 'node.dart';
import 'edge.dart';

class RawGraphData extends Equatable {
  final List<Node> nodes;
  final List<Edge> edges;

  const RawGraphData({
    required this.nodes,
    required this.edges,
  });

  @override
  List<Object?> get props => [nodes, edges];
}
