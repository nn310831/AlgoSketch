# alsk_project

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## 配置OpenCV
從 OpenCV 官網下載 iOS 版本的 SDK，解壓縮後你會得到一個 opencv2.framework 資料夾。

在你的 Flutter 專案的 ios 目錄下，建立一個名為 Frameworks 的資料夾。

將 opencv2.framework 整個拖曳放進 ios/Frameworks/ 目錄中

## 模型訓練前，會先模擬所有OCR結果都是 6
### 模型訓練後
名為：model.tflite 並放入 /assets  

lib/services/vision_service_impl.dart 內要更改  

pubspec.yaml 也要更改.  
