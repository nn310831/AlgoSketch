import 'dart:math';
import 'package:flutter/material.dart';
import '../models/algorithm_state.dart';
import '../models/graph.dart';
import '../models/node.dart';
import '../models/edge.dart';

class GraphVisualizer extends StatelessWidget {
  final Graph? graph;
  final AlgorithmState? state;

  const GraphVisualizer({
    Key? key,
    this.graph,
    this.state,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (graph == null) {
      return const Center(child: Text('無圖形資料'));
    }

    // 新增：使用 InteractiveViewer 包裹畫布，一秒實現拖移與縮放功能
    return InteractiveViewer(
      boundaryMargin: const EdgeInsets.all(double.infinity), // 允許無邊界的拖移
      minScale: 0.1, // 最小可縮放到 0.1 倍
      maxScale: 5.0, // 最大可放大到 5 倍
      panEnabled: true, // 開啟平移拖曳
      scaleEnabled: true, // 開啟雙指縮放
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: GraphPainter(
            graph: graph!,
            state: state ?? const AlgorithmState(),
          ),
        ),
      ),
    );
  }
}

class GraphPainter extends CustomPainter {
  final Graph graph;
  final AlgorithmState state;

  GraphPainter({required this.graph, required this.state});

  // 定義顏色與樣式常數
  static const Color standardNodeColor = Colors.white;
  static const Color visitedNodeColor = Colors.green;
  static const Color queuedNodeColor = Colors.orange;
  static const Color activeNodeColor = Colors.redAccent;
  static const Color shortestPathNodeColor = Colors.yellowAccent;
  
  static const Color standardEdgeColor = Colors.grey;
  static const Color activeEdgeColor = Colors.redAccent;
  static const Color shortestPathEdgeColor = Colors.yellowAccent;

  @override
  void paint(Canvas canvas, Size size) {
    _drawEdges(canvas);
    _drawNodes(canvas);
  }

  void _drawEdges(Canvas canvas) {
    final Paint edgePaint = Paint()
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;

    final TextPainter textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    for (final nodeEntry in graph.adjacencyList.entries) {
      final List<Edge> edges = nodeEntry.value;
      for (final edge in edges) {
        final Node? source = graph.nodes[edge.sourceNodeId];
        final Node? target = graph.nodes[edge.targetNodeId];

        if (source == null || target == null) continue;

        // 判斷這條邊是否正在被演算法處理中
        final bool isActiveEdge = state.activeEdgeId != null && 
           state.activeEdgeId == '${edge.sourceNodeId}-${edge.targetNodeId}';
        
        // 判斷是否為最短路徑的一部份
        final bool isShortestPathEdge = state.shortestPathEdgeIds != null && 
           state.shortestPathEdgeIds!.contains('${edge.sourceNodeId}-${edge.targetNodeId}');

        if (isActiveEdge) {
          edgePaint.color = activeEdgeColor;
          edgePaint.strokeWidth = 5.0;
        } else if (isShortestPathEdge) {
          edgePaint.color = shortestPathEdgeColor;
          edgePaint.strokeWidth = 6.0;
        } else {
          edgePaint.color = standardEdgeColor;
          edgePaint.strokeWidth = 3.0;
        }

        final Offset startOffset = Offset(source.centerX, source.centerY);
        final Offset endOffset = Offset(target.centerX, target.centerY);

        // 為了不讓線條畫進節點內部，可根據半徑做微調長度
        final Offset direction = endOffset - startOffset;
        final double distance = direction.distance;
        if (distance == 0) continue; // 避免除以零

        final Offset unitVector = direction / distance;
        final Offset adjustedStart = startOffset + unitVector * source.radius;
        final Offset adjustedEnd = endOffset - unitVector * target.radius;

        // 畫線
        canvas.drawLine(adjustedStart, adjustedEnd, edgePaint);

        // 如果邊有權重，畫在線段中點
        if (edge.weight != null) {
          final Offset midPoint = (startOffset + endOffset) / 2;
          
          textPainter.text = TextSpan(
            text: edge.weight.toString(),
            style: const TextStyle(
              color: Colors.blueAccent, 
              fontSize: 18, 
              fontWeight: FontWeight.bold,
              backgroundColor: Colors.white70, // 背景略白，增加易讀性
            ),
          );
          
          textPainter.layout();
          textPainter.paint(
            canvas,
            Offset(
              midPoint.dx - (textPainter.width / 2),
              midPoint.dy - (textPainter.height / 2),
            ),
          );
        }
      }
    }
  }

  void _drawNodes(Canvas canvas) {
    final Paint nodePaint = Paint()..style = PaintingStyle.fill;
    final Paint borderPaint = Paint()
      ..color = Colors.black87
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final TextPainter textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );

    for (final node in graph.nodes.values) {
      final Offset center = Offset(node.centerX, node.centerY);

      // 決定節點當前狀態顏色
      Color fillColor = standardNodeColor;
      if (state.activeNodeId == node.id) {
        fillColor = activeNodeColor;
      } else if (state.shortestPathNodeIds != null && state.shortestPathNodeIds!.contains(node.id)) {
        fillColor = shortestPathNodeColor;
      } else if (state.visitedNodeIds.contains(node.id)) {
        fillColor = visitedNodeColor;
      } else if (state.queuedNodeIds.contains(node.id)) {
        fillColor = queuedNodeColor;
      }

      nodePaint.color = fillColor;

      canvas.drawCircle(center, node.radius, nodePaint);
      canvas.drawCircle(center, node.radius, borderPaint);

      // 在節點上方繪製 node.id
      textPainter.text = TextSpan(
        text: '${node.id}',
        style: const TextStyle(
          color: Colors.black87,
          fontSize: 16,
          fontWeight: FontWeight.bold,
          backgroundColor: Colors.white70, // 加點背景比較清楚
        ),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(
          center.dx - (textPainter.width / 2),
          center.dy + node.radius + textPainter.height - 45 , // 放在圓圈的正上方
        ),
      );

      // 若有辨識出的值則繪製在節點中央
      if (node.value != null && node.value!.isNotEmpty) {
        textPainter.text = TextSpan(
          text: node.value,
          style: const TextStyle(
            color: Colors.black,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        );
        
        textPainter.layout();
        textPainter.paint(
          canvas,
          Offset(
            center.dx - (textPainter.width / 2),
            center.dy - (textPainter.height / 2),
          ),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant GraphPainter oldDelegate) {
    // 當 graph 結構變更，或 state（演算法狀態）更新時觸發重繪
    return oldDelegate.graph != graph || oldDelegate.state != state;
  }
}
