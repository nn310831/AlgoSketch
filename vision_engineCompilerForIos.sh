#!/bin/bash

# 這是自動化編譯cpp的腳本 若有增加其他C++程式，可照此範例編寫腳本

set -e

echo "開始自動化編譯流程..."

echo "[1/3] 正在刪除舊的 ios/Runner/vision_engine.cpp..."
rm -f ios/Runner/vision_engine.cpp

echo "[2/3] 正在將最新的 C++ 引擎複製到 iOS 專案中..."

if [ ! -f "cpp/vision_engine.cpp" ]; then
    echo "錯誤：找不到 cpp/vision_engine.cpp！"
    exit 1
fi

cp cpp/vision_engine.cpp ios/Runner/

echo "[3/3] 開始編譯 Flutter iOS 模擬器版本..."
flutter build ios --simulator
flutter run -d FB666244-BC84-4043-8B78-50DA6B940AE3

echo "全自動編譯流程執行完畢"