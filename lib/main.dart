import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'services/vision_service_impl.dart';
import 'services/graph_builder_service_impl.dart';
import 'services/algorithm_service_impl.dart';
import 'providers/algorithm_playback_provider.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => AlgorithmPlaybackProvider(AlgorithmServiceImpl()),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FFI Test',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal)),
      home: const TestScreen(),
    );
  }
}

class TestScreen extends StatefulWidget {
  const TestScreen({super.key});

  @override
  State<TestScreen> createState() => _TestScreenState();
}

class _TestScreenState extends State<TestScreen> {
  final VisionServiceImpl _visionService = VisionServiceImpl();
  final GraphBuilderServiceImpl _graphBuilder = GraphBuilderServiceImpl();
  
  String _statusText = "請點擊右下角按鈕，選取一張白板測試照片";
  bool _isLoading = false;

  Future<void> _runPipelineTest() async {
    final picker = ImagePicker();
    // 1. 從相簿選取照片
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    
    if (image == null) return;

    setState(() {
      _isLoading = true;
      _statusText = "正在透過 FFI 呼叫 C++ OpenCV 處理影像...";
    });

    try {
      // ==========================================
      // 測試點 1：FFI 與 OpenCV 處理
      // ==========================================
      final rawData = await _visionService.processImage(image.path);
      
      print("========== [階段二測試結果] ==========");
      print("✅ 成功從 C++ 拿回資料！");
      print("🎯 找到 ${rawData.nodes.length} 個節點 (圓圈)");
      print("📏 找到 ${rawData.rawLines.length} 條原始線段");
      
      for (var node in rawData.nodes) {
        print("  - 節點 ID: ${node.id}, 座標: (${node.centerX.toStringAsFixed(1)}, ${node.centerY.toStringAsFixed(1)}), OCR: ${node.value}");
      }

      setState(() => _statusText = "影像處理完成！正在建構 Graph...");

      // ==========================================
      // 測試點 2：Dart 演算法與 Graph 建構
      // ==========================================
      final graph = _graphBuilder.buildGraph(rawData);

      print("\n========== [階段三測試結果] ==========");
      print("✅ 成功建構 Graph 鄰接表！");
      
      int totalEdges = 0;
      graph.adjacencyList.forEach((nodeId, edges) {
        print("  - 節點 $nodeId 連接了 ${edges.length} 條邊");
        for (var edge in edges) {
           print("    -> 連向: ${edge.targetNodeId}");
        }
        totalEdges += edges.length;
      });

      setState(() {
        _statusText = "✅ 測試成功！\n"
                      "偵測到 ${rawData.nodes.length} 個節點\n"
                      "成功定義 ${totalEdges ~/ 2} 條有效連線 (無向圖)";
        _isLoading = false;
      });

      // ==========================================
      // 測試點 3：觸發演算法與時間軸
      // ==========================================
      if (graph.nodes.isNotEmpty) {
        final playback = context.read<AlgorithmPlaybackProvider>();
        
        // 我們隨機取第一個節點當作演算法的起點
        String startNodeId = graph.nodes.keys.first;
        
        // 載入 BFS 演算法 (也可以在此改成 'DFS' 或 'DIJKSTRA' 測試)
        await playback.loadAlgorithm(graph, startNodeId, algorithmType: 'BFS');
      }

    } catch (e, stackTrace) {
      print("❌ 測試失敗: $e");
      print(stackTrace);
      setState(() {
        _statusText = "發生錯誤：$e";
        _isLoading = false;
      });
    }
  }

  Widget _buildPlaybackControls(AlgorithmPlaybackProvider playback) {
    final state = playback.currentState;

    if (state == null) return const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. 顯示演算法目前的思維邏輯 (人類可讀的描述)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          color: Colors.black87,
          child: Text(
            state.description,
            style: const TextStyle(color: Colors.greenAccent, fontSize: 16),
            textAlign: TextAlign.center,
          ),
        ),
        
        // 2. 播放控制器 (上一步 / 下一步)
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.skip_previous),
              onPressed: playback.canGoPrev ? playback.stepBackward : null,
            ),
            Text('${playback.currentIndex + 1} / ${playback.timeline.length}'),
            IconButton(
              icon: const Icon(Icons.skip_next),
              onPressed: playback.canGoNext ? playback.stepForward : null,
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: playback.hasData ? playback.reset : null,
            ),
          ],
        ),
        
        // 3. 觀察底層資料結構 (用文字先確認狀態機是否正確)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('💡 目前活躍點: ${state.activeNodeId ?? "無"}', style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('⚡ 正在檢查邊: ${state.activeEdgeId ?? "無"}'),
              const SizedBox(height: 8),
              Text('📦 佇列狀態: [ ${state.queuedNodeIds.join(" -> ")} ]', style: const TextStyle(color: Colors.blueAccent)),
              const SizedBox(height: 4),
              Text('✅ 拜訪紀錄: { ${state.visitedNodeIds.join(", ")} }', style: const TextStyle(color: Colors.deepOrange)),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // 讓 UI 可以監聽時間軸進度並重新渲染
    final playback = context.watch<AlgorithmPlaybackProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('C++ FFI 與狀態機整合測試')),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: _isLoading 
                    ? const CircularProgressIndicator()
                    : Text(_statusText, style: const TextStyle(fontSize: 18), textAlign: TextAlign.center),
              ),
            ),
          ),
          
          // 若有演算法播放資料，則顯示影片控制器
          if (playback.hasData) ...[
            const Divider(height: 2, thickness: 2),
            _buildPlaybackControls(playback),
          ],
          
          // 預留位置給右下角的按鈕，避免字被擋到
          const SizedBox(height: 80), 
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _isLoading ? null : _runPipelineTest,
        child: const Icon(Icons.image_search),
      ),
    );
  }
}