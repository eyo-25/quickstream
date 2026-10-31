#!/bin/bash
# Swift 단위 검사. Sources/*.swift(앱 진입점 main.swift 제외) + tests/swift/*.swift 를 한 번에 빌드해 실행한다.
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT="$(mktemp -d)/qs-tests"
SOURCES=$(ls Sources/*.swift | grep -v '/main.swift$')
swiftc -swift-version 5 -target "$(uname -m)-apple-macos14.0" -o "$OUT" $SOURCES tests/swift/*.swift
"$OUT"
