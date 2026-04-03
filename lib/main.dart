import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'services/vision_service_impl.dart';
import 'services/graph_builder_service_impl.dart';
import 'services/algorithm_service_impl.dart';
import 'providers/algorithm_playback_provider.dart';
import 'models/graph.dart';
import 'widgets/graph_visualizer.dart';

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

  String _selectedAlgorithm = 'BFS';
  final List<String> _algorithms = ['BFS', 'DFS', 'DIJKSTRA'];
  Graph? _currentGraph;
  String? _selectedStartNodeId;
  String? _selectedEndNodeId;

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
      _currentGraph = graph;

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
        
        setState(() {
          _selectedStartNodeId = graph.nodes.keys.first;
          // 將第二個點或最後一個點設為預設終點（如果超過一個點）
          _selectedEndNodeId = graph.nodes.length > 1 ? graph.nodes.keys.last : null;
        });
        
        // 載入選擇的演算法
        await playback.loadAlgorithm(graph, _selectedStartNodeId!, endNodeId: _selectedEndNodeId, algorithmType: _selectedAlgorithm);
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

  Widget _buildAlgorithmSelector(AlgorithmPlaybackProvider playback) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('選擇演算法：', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(width: 10),
        DropdownButton<String>(
          value: _selectedAlgorithm,
          items: _algorithms.map((String algo) {
            return DropdownMenuItem<String>(
              value: algo,
              child: Text(algo),
            );
          }).toList(),
          onChanged: (String? newValue) {
            if (newValue != null) {
              setState(() {
                _selectedAlgorithm = newValue;
              });
              
              // 如果已經有圖片解析出的圖資料，直接切換演算法而不用重新選圖
              if (_currentGraph != null && _selectedStartNodeId != null) {
                playback.loadAlgorithm(_currentGraph!, _selectedStartNodeId!, endNodeId: _selectedEndNodeId, algorithmType: _selectedAlgorithm);
              }
            }
          },
        ),
      ],
    );
  }

  Widget _buildNodeSelectors(AlgorithmPlaybackProvider playback) {
    if (_currentGraph == null || _currentGraph!.nodes.isEmpty) return const SizedBox.shrink();

    final nodeIds = _currentGraph!.nodes.keys.toList();

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('起點：', style: TextStyle(fontWeight: FontWeight.bold)),
        DropdownButton<String>(
          value: _selectedStartNodeId,
          items: nodeIds.map((id) => DropdownMenuItem(value: id, child: Text(id))).toList(),
          onChanged: (val) {
            if (val != null) {
              setState(() => _selectedStartNodeId = val);
              playback.loadAlgorithm(_currentGraph!, _selectedStartNodeId!, endNodeId: _selectedEndNodeId, algorithmType: _selectedAlgorithm);
            }
          },
        ),
        if (_selectedAlgorithm == 'DIJKSTRA') ...[
          const SizedBox(width: 20),
          const Text('終點：', style: TextStyle(fontWeight: FontWeight.bold)),
          DropdownButton<String?>(
            value: _selectedEndNodeId,
            items: [
              const DropdownMenuItem(value: null, child: Text('無')),
              ...nodeIds.map((id) => DropdownMenuItem(value: id, child: Text(id)))
            ],
            onChanged: (val) {
              setState(() => _selectedEndNodeId = val);
              if (_selectedStartNodeId != null) {
                playback.loadAlgorithm(_currentGraph!, _selectedStartNodeId!, endNodeId: _selectedEndNodeId, algorithmType: _selectedAlgorithm);
              }
            },
          ),
        ],
      ],
    );
  }

  List<Widget> _buildPlaybackControls(AlgorithmPlaybackProvider playback) {
    final state = playback.currentState;

    if (state == null) return const [SizedBox.shrink()];

    return [
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
        
        // 3. 觀察底層資料結構 (用表格呈現)
        Container(
          height: 190, // 固定高度
          margin: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade400),
            borderRadius: BorderRadius.circular(8.0),
          ),
          child: SingleChildScrollView(
            child: Table(
              border: TableBorder(
                horizontalInside: BorderSide(color: Colors.grey.shade300, width: 1),
                verticalInside: BorderSide(color: Colors.grey.shade300, width: 1),
              ),
              columnWidths: const {
                0: IntrinsicColumnWidth(), // 第一個欄位寬度自動根據文字內容決定
                1: FlexColumnWidth(),      // 第二個欄位佔滿剩餘空間
              },
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
              TableRow(
                children: [
                  const Padding(padding: EdgeInsets.all(6.0), child: Text('💡 目前活躍點', style: TextStyle(fontWeight: FontWeight.bold))),
                  Padding(padding: const EdgeInsets.all(6.0), child: Text(state.activeNodeId ?? "無")),
                ]
              ),
              TableRow(
                children: [
                  const Padding(padding: EdgeInsets.all(6.0), child: Text('⚡ 正在檢查邊', style: TextStyle(fontWeight: FontWeight.bold))),
                  Padding(padding: const EdgeInsets.all(6.0), child: Text(state.activeEdgeId ?? "無")),
                ]
              ),
              if (state.distances != null)
                TableRow(
                  children: [
                    const Padding(padding: EdgeInsets.all(6.0), child: Text('📍 各節點目前距離', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.purpleAccent))),
                    Padding(padding: const EdgeInsets.all(6.0), child: Text('{ ${state.distances!.entries.map((e) => '${e.key}: ${e.value}').join('｜ ')} }', style: const TextStyle(color: Colors.purpleAccent))),
                  ]
                ),
              if (state.distances != null)
                TableRow(
                  children: [
                    const Padding(padding: EdgeInsets.all(6.0), child: Text('💯 已確認最短節點', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.pinkAccent))),
                    Padding(padding: const EdgeInsets.all(6.0), child: Text('{ ${state.visitedNodeIds.join("｜ ")} }', style: const TextStyle(color: Colors.pinkAccent))),
                  ]
                ),
              TableRow(
                children: [
                  const Padding(padding: EdgeInsets.all(6.0), child: Text('📦 佇列狀態', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent))),
                  Padding(padding: const EdgeInsets.all(6.0), child: Text('[ ${state.queuedNodeIds.join(" -> ")} ]', style: const TextStyle(color: Colors.blueAccent))),
                ]
              ),
              if (state.distances == null) 
                TableRow(
                  children: [
                    const Padding(padding: EdgeInsets.all(6.0), child: Text('✅ 拜訪紀錄', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.deepOrange))),
                    Padding(padding: const EdgeInsets.all(6.0), child: Text('{ ${state.visitedNodeIds.join("｜ ")} }', style: const TextStyle(color: Colors.deepOrange))),
                  ]
                ),
              if (state.shortestPathNodeIds != null && state.shortestPathNodeIds!.isNotEmpty)
                TableRow(
                  children: [
                    const Padding(padding: EdgeInsets.all(6.0), child: Text('🌟 最短路徑', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange))),
                    Padding(padding: const EdgeInsets.all(6.0), child: Text('[ ${state.shortestPathNodeIds!.join(" -> ")} ]', style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 15))),
                  ]
                ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 80), 
    ];
  }

  @override
  Widget build(BuildContext context) {
    // 讓 UI 可以監聽時間軸進度並重新渲染
    final playback = context.watch<AlgorithmPlaybackProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('AlgoSketch')),
      body: Column(
        children: [
          // 新增：演算法選擇器
          Padding(
            padding: const EdgeInsets.only(top: 8.0, left: 8.0, right: 8.0),
            child: _buildAlgorithmSelector(playback),
          ),
          
          // 新增：起點與終點選擇器 (圖解析完成才會顯示)
          _buildNodeSelectors(playback),

          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: _isLoading 
                    ? const CircularProgressIndicator()
                    : (_currentGraph == null)
                        ? Text(_statusText, style: const TextStyle(fontSize: 18), textAlign: TextAlign.center)
                        : GraphVisualizer(
                            graph: _currentGraph,
                            state: playback.currentState,
                          ),
              ),
            ),
          ),
          
          // 若有演算法播放資料，則顯示影片控制器
          if (playback.hasData) ...[
            const Divider(height: 2, thickness: 2),
            ..._buildPlaybackControls(playback),
          ],
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _isLoading ? null : _runPipelineTest,
        child: const Icon(Icons.image_search),
      ),
    );
  }
}