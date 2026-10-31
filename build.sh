#!/bin/bash
# build/QuickStream.app 을 만든다(유니버설 arm64+x86_64, ad-hoc 서명 + hardened runtime).
#   ./build.sh
#   VERSION=0.2.0 ./build.sh        Info.plist 의 버전을 이 빌드에만 덮어쓴다(저장소 파일은 그대로)
#   QS_ARCHS=arm64 ./build.sh       한 아키텍처만 빠르게 빌드(검사는 그 아키텍처만)
#   QS_SOURCE_INSTALL=1 ./build.sh  소스 설치 표식 파일 포함(install.sh 가 사용)
#   QS_SOURCES="a.swift b.swift" ./build.sh   소스 목록을 덮어쓴다(기본: Sources/*.swift)
set -euo pipefail
project_dir=$(cd "$(dirname "$0")" && pwd)
cd "$project_dir"
app=$project_dir/build/QuickStream.app
archs=${QS_ARCHS:-"arm64 x86_64"}
minos=$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' Info.plist)
if [[ -n ${QS_SOURCES:-} ]]; then read -r -a sources <<<"$QS_SOURCES"; else sources=(Sources/*.swift); fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
# Swift 5 언어 모드 고정: macOS 14 러너(Xcode 15)에는 Swift 6 모드가 없다.
slices=()
for arch in $archs; do
  /usr/bin/swiftc -O -swift-version 5 -module-name QuickStream -target "$arch-apple-macos$minos" \
    "${sources[@]}" -o "$work/QuickStream-$arch"
  slices+=("$work/QuickStream-$arch")
done

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
if (( ${#slices[@]} == 1 )); then cp "${slices[0]}" "$app/Contents/MacOS/QuickStream"
else /usr/bin/lipo -create "${slices[@]}" -output "$app/Contents/MacOS/QuickStream"; fi
cp Info.plist "$app/Contents/Info.plist"
cp assets/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
if [[ -n ${VERSION:-} ]]; then
  /usr/bin/plutil -replace CFBundleShortVersionString -string "$VERSION" "$app/Contents/Info.plist"
  /usr/bin/plutil -replace CFBundleVersion -string "$VERSION" "$app/Contents/Info.plist"
fi
# 소스 설치 표식: 서명 전에 넣어야 번들 봉인이 깨지지 않는다(install.sh 가 설정)
if [[ ${QS_SOURCE_INSTALL:-} == 1 ]]; then : > "$app/Contents/Resources/source-install"; fi
/usr/bin/xattr -cr "$app"
/usr/bin/codesign --force --sign - --options runtime "$app" >/dev/null
QS_ARCHS="$archs" .github/verify-app.sh "$app" "${VERSION:-}"
echo "$app"
