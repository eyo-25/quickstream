#!/bin/bash
# 앱 아이콘(icns)을 CoreGraphics 로 만든다: ./make-icon.sh [출력 경로, 기본 assets/AppIcon.icns]
set -euo pipefail
project_dir=$(cd "$(dirname "$0")" && pwd)
out=${1:-$project_dir/assets/AppIcon.icns}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
/usr/bin/swiftc -swift-version 5 -O "$project_dir/assets/make-icon.swift" -o "$work/make-icon"
"$work/make-icon" "$work/AppIcon.iconset"
/usr/bin/iconutil -c icns "$work/AppIcon.iconset" -o "$out"
echo "$out"
