# AlgoSketch 🎨🤖

**AlgoSketch** 是一個結合「電腦視覺 (Computer Vision)」、「深度學習邊緣運算 (Edge AI)」與「圖論演算法 (Graph Algorithms)」的創新 Flutter 行動應用。

使用者只需透過相機拍攝在白板或紙上的**手繪圖形草稿**（包含節點、連線、權重數值及起終點標記），AlgoSketch 就能立刻將實體手繪圖無縫轉換為 App 內的數位資料結構，並且讓使用者可以直接在畫面上執行並觀察圖論演算法（如 BFS、DFS、Dijkstra 等）的**視覺化動畫解析**，提供極具互動性的虛實整合學習體驗。

---

## ✨ 核心特色 (Features)

*   📷 **手繪草圖影像辨識 (OpenCV & FFI)**
    使用底層 C++ OpenCV 進行高斯模糊、自適應二值化、邊緣檢測，並應用霍夫轉換 (Hough Transform) 精準偵測畫面中的節點與連線。透過 **Dart FFI** Zero-copy 技術與 Flutter 進行極低延遲的記憶體資料交互。
*   🧠 **邊緣運算 OCR 模型 (TFLite & Python CNN)**
    內建輕量化的卷積神經網路 (CNN) 模型，針對手繪的數字 (0-9) 以及特殊符號（`S`: 起點, `T`: 終點, `∞`: 無限大距）進行精準的光學字元辨識。模型經過量化壓縮（Float32 $\rightarrow$ Int8），適合完全在手機端進行離線推論。
*   🕸 **空間幾何轉譯與圖論架構重建**
    自動化進行邏輯合併，將雜亂的像素座標及線段，透過空間距離運算轉換實體化為正規的圖結構「鄰接表 (Adjacency List)」，並具備優異的容錯與雜訊過濾機制。
*   🔄 **演算法視覺化狀態機 (State Machine)**
    利用 Dart 的 `sync*` 與 `yield` 產生器概念改寫傳統圖論演算法，提煉出每一個步驟的「狀態快照 (State Snapshot)」。配合狀態管理 (Provider)，實作如影片播放器般的「下一步/上一步」時光倒流控制邏輯。
*   📱 **流暢的 60FPS UI 渲染動畫**
    採用底層的 `CustomPainter` 在畫布上精準著色，結合 `AnimationController` 的線性插值 (Lerp)，實現平滑的節點移動、光球特效與顏色漸變；並藉由 `RepaintBoundary` 分層渲染，保障嚴苛性能要求下的最佳體驗。

---

## 📂 系統架構與目錄說明 (Directory Structure)

本專案主要切分為兩個領域環境：前端 Flutter 工作目錄 (`alsk_project/`) 與 後端模型訓練腳本 (`CNN/`)。

```text
AlgoSketch/
├── alsk_project/          # Flutter 跨平台前端 App (Dart / C++)
│   ├── android/, ios/     # 雙平台原生設定檔目錄
│   ├── cpp/               # C++ 電腦視覺核心模組 (vision_engine.cpp)
│   ├── lib/               # Flutter UI 與核心邏輯實作
│   │   ├── models/        # 嚴格定義的 Immutable 資料模型 (Node, Edge 等)
│   │   ├── providers/     # App 狀態管理與圖形演算法播放器控制器
│   │   ├── services/      # 核心服務 (控制 TFLite 推論引擎、呼叫 C++ FFI)
│   │   └── widgets/       # 共用 UI 元件與動畫實作 (CustomPainter 繪圖元件)
│   ├── assets/            # 存放轉檔好的 model.tflite 模型檔與靜態資源
│   └── pubspec.yaml       # Dart 套件依賴清單 (tflite_flutter, ffi 等等)
│
└── CNN/                   # 自定義手寫符號辨識 OCR 神經網路訓練環境 (Python)
    ├── raw_dataset/       # 我們自行採集的原始白板手繪符號資料集
    ├── processed_dataset/ # 預處理與資料增強後的訓練集圖片
    ├── preprocess_data.py # 圖片前處理及影像增強腳本
    ├── train_model.py     # 模型訓練、評估與 .tflite 輕量化導出腳本
    ├── inference.py       # 用於驗證 TFLite 模型準確度的推論腳本
    ├── class_mapping.json # 標籤與神經元對應的 Mapping (確保訓練/推論順序一致)
    └── requirements.txt   # Python 環境依賴清單 (TensorFlow, OpenCV 等)
```

---

## 🚀 環境需求與執行方式 (Getting Started)

### 1. CNN 神經網路模組 (選用)
如果您想要自行調整資料集或重新訓練手寫辨識 OCR 模型：
1. 系統需安裝 **Python 3.8+**。
2. 進入 `CNN/` 目錄，安裝相關機器學習相依套件：
   ```bash
   cd CNN
   # 建議使用虛擬環境 (Virtual Environment)
   pip install -r requirements.txt
   ```
3. 執行圖片預處理與資料增強：
   ```bash
   python preprocess_data.py
   ```
4. 進行模型訓練（結果會導出為 `.tflite` 及對應的標籤配置）：
   ```bash
   python train_model.py
   ```
5. 完成後，可利用獨立腳本測試模型辨識結果：
   ```bash
   python inference.py
   ```
> 💡 **小提醒**: 產生的 `model.tflite` 模型必須手動覆寫/複製到 `../alsk_project/assets/` 資料夾內，App 才能載入最新模型。

### 2. Flutter App 前端專案
1. 確保開發環境已安裝 **Flutter SDK (^3.10.4)**。
2. 進入 Flutter 工作目錄：
   ```bash
   cd alsk_project
   ```
3. 下載並安裝 Dart/Flutter 相依套件：
   ```bash
   flutter pub get
   ```
4. 由於本專案包含 C++ FFI 及 OpenCV，執行前確定已配置好相關 C++ 編譯器 (如 Android NDK 或是 macOS/iOS Xcode Command Line Tools)。
5. 啟動模擬器或連上實機，然後執行編譯：
   ```bash
   flutter run
   ```

---

## 🏗 開發規範與防護機制
*   **強型別與 Immutability**: App 內部嚴格規範狀態更新一律不可變（Immutable），確保時光倒流等歷史狀態提取絕無 Side Effect。
*   **效能防雷隔離**: 電腦視覺與複雜的矩陣建構、OCR 批次推論涉及大量運算，均已使用 Dart **Isolate** 進行隔離，確保 UI 主執行緒徹底流暢無閃退疑慮。
*   **記憶體管理**: 在越界操作（如 Dart 請求 OpenCV C++ 函式）的 FFI (Foreign Function Interface) 操作時，明確定義記憶體 Pointers 釋放與 Zero-copy 技術，免除 Memory Leak 風險。