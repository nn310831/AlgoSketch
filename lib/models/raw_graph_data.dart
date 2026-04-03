import 'package:equatable/equatable.dart';
import 'node.dart';
import 'edge.dart';

class RawLine extends Equatable {
  final double x1;
  final double y1;
  final double x2;
  final double y2;

  const RawLine({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
  });

  @override
  List<Object?> get props => [x1, y1, x2, y2];
}

class RawGraphData extends Equatable {
  final List<Node> nodes;
  final List<Edge> edges;
  final List<RawLine> rawLines; // 新增：用來存放尚未匹配成 Edge 的純線段圖形資料

  const RawGraphData({
    required this.nodes,
    required this.edges,
    this.rawLines = const [],
  });

  @override
  List<Object?> get props => [nodes, edges, rawLines];
}
