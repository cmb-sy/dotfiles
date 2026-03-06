#!/bin/bash
# Claude Code利用統計コレクター呼び出しスクリプト
# VIBE_COLLECTOR 環境変数でcollector.pyのパスを指定する
# 未設定またはファイルが存在しない場合はスキップ

if [ -z "$VIBE_COLLECTOR" ]; then
    exit 0
fi

if [ -f "$VIBE_COLLECTOR" ]; then
    python3 "$VIBE_COLLECTOR"
fi
