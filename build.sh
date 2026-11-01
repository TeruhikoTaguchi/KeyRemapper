#!/bin/bash

echo "Ctrl キーリマッピングツール のビルド"
echo "========================================"
echo ""

# Swiftコンパイラの確認
if ! command -v swiftc &> /dev/null; then
    echo "❌ Swiftコンパイラが見つかりません"
    echo "Xcodeまたは Command Line Tools をインストールしてください:"
    echo "  xcode-select --install"
    exit 1
fi

echo "✅ Swiftコンパイラを検出"
echo ""

# コンパイル
echo "📦 コンパイル中..."
swiftc KeyRemapper.swift -o KeyRemapper

if [ $? -eq 0 ]; then
    echo "✅ コンパイル成功！"
    echo ""
    echo "実行方法:"
    echo "  ./KeyRemapper"
    echo ""
    echo "注意: 初回実行時にアクセシビリティ権限の許可が必要です"
else
    echo "❌ コンパイル失敗"
    exit 1
fi
