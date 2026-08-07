#!/bin/zsh
set -e

PROJECT_DIR="${0:A:h}"
GODOT_BIN="/Applications/Godot.app/Contents/MacOS/Godot"

if [[ ! -x "$GODOT_BIN" ]]; then
  osascript -e 'display alert "无法启动《断环》" message "未找到 /Applications/Godot.app。请先安装 Godot 4.7.x 标准版。" as critical'
  exit 1
fi

exec "$GODOT_BIN" --path "$PROJECT_DIR"
