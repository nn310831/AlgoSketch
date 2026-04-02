import 'package:equatable/equatable.dart';
import 'node.dart';
import 'edge.dart';

class Graph extends Equatable {
  // 將節點儲存為 Map，方便透過 ID 快速尋找
  final Map<String, Node> nodes;
  // 透過鄰接表 (Adjacency List) 記錄節點間的連線關係
  final Map<String, List<Edge>> adjacencyList;

  const Graph({
    required this.nodes,
    required this.adjacencyList,
  });

  @override
  List<Object?> get props => [nodes, adjacencyList];
}
