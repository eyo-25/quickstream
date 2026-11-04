#!/bin/bash
# Swift 단위 검사. Sources/*.swift(앱 진입점 main.swift 제외) + tests/swift/*.swift 를 한 번에 빌드해 실행한다.
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT="$(mktemp -d)/qs-tests"
SOURCES=$(ls Sources/*.swift | grep -v '/main.swift$')
# AppController 가 Sparkle 을 쓰므로 같은 프레임워크(tools/sparkle.sh)에 링크하고, 실행 파일이 그 폴더에서 찾게 한다
SPARKLE=$(tools/sparkle.sh)
swiftc -swift-version 5 -target "$(uname -m)-apple-macos14.0" -F "$SPARKLE" -framework Sparkle -Xlinker -rpath -Xlinker "$SPARKLE" \
  -o "$OUT" $SOURCES tests/swift/*.swift
"$OUT"
