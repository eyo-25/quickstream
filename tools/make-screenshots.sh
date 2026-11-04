#!/bin/bash
# README 용 스크린샷을 만든다. 화면·창을 캡처하지 않고 앱의 SwiftUI 뷰를 오프스크린으로 그려 PNG 로 쓴다.
#   tools/make-screenshots.sh [출력 폴더]        기본: docs/images (같은 이름이 있으면 덮어쓴다)
#   tools/make-screenshots.sh out hero-orbit.png  이름을 더 주면 그 이미지만 만든다
# 앱을 실행하지 않는다: Sources/*.swift(main.swift 제외)와 렌더러를 한 실행 파일로 빌드해 돌릴 뿐이다.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
out=${1:-$root/docs/images}
shift || true

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# 앱 진입점(main.swift)은 NSApp.run 을 하므로 빼고, 렌더러의 main.swift 를 대신 넣는다
sources=()
for file in "$root"/Sources/*.swift; do
  [[ $(basename "$file") == main.swift ]] || sources+=("$file")
done

sparkle=$("$root/tools/sparkle.sh")  # AppController 가 Sparkle 을 쓰므로 같은 프레임워크에 링크한다
/usr/bin/swiftc -swift-version 5 -module-name QSShots -target "$(uname -m)-apple-macos14.0" \
  -F "$sparkle" -framework Sparkle -Xlinker -rpath -Xlinker "$sparkle" \
  "${sources[@]}" "$root/tools/screenshots/main.swift" -o "$work/qs-shots"

mkdir -p "$out"
"$work/qs-shots" "$out" "$root/Info.plist" "$@"
