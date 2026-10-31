#!/bin/bash
# 빌드된 QuickStream.app 을 검사한다: .github/verify-app.sh build/QuickStream.app [X.Y.Z]
# CI, 릴리스 워크플로, release.sh, build.sh 가 같은 검사를 쓴다. QS_ARCHS 로 기대 아키텍처를 줄일 수 있다(기본: arm64 x86_64).
set -euo pipefail
app=${1:?사용: verify-app.sh path/to/QuickStream.app [version]}
want_version=${2:-}
archs_expected=${QS_ARCHS:-"arm64 x86_64"}
bin=$app/Contents/MacOS/QuickStream
plist=$app/Contents/Info.plist
fail() { echo "verify-app: $*" >&2; exit 1; }
key() { /usr/bin/plutil -extract "$1" raw -o - "$plist" 2>/dev/null || true; }

[[ -x $bin ]] || fail "실행 파일이 없습니다: $bin"
[[ -f $plist ]] || fail "Contents/Info.plist 가 없습니다"
[[ -f $app/Contents/Resources/AppIcon.icns ]] || fail "Contents/Resources/AppIcon.icns 가 없습니다"

expect() { [[ $(key "$1") == "$2" ]] || fail "$1 이(가) '$(key "$1")' 입니다(기대: $2)"; }
expect CFBundleIdentifier io.github.eyo-25.quickstream
expect CFBundleExecutable QuickStream
expect CFBundleName QuickStream
expect CFBundlePackageType APPL
expect CFBundleIconFile AppIcon
expect LSMinimumSystemVersion 14.0
expect LSUIElement true
expect QSGitHubRepo eyo-25/quickstream
expect QSBrewCask eyo-25/tap/quickstream
version=$(key CFBundleShortVersionString)
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "CFBundleShortVersionString '$version' 은(는) X.Y.Z 형식이 아닙니다"
[[ -z $want_version || $version == "$want_version" ]] || fail "버전이 $version 입니다(기대: $want_version)"
[[ -n $(key CFBundleVersion) ]] || fail "CFBundleVersion 이 비어 있습니다"

archs=$(/usr/bin/lipo -archs "$bin")
for arch in $archs_expected; do
  [[ " $archs " == *" $arch "* ]] || fail "$arch 슬라이스가 없습니다(있는 것: $archs)"
  minos=$(/usr/bin/vtool -arch "$arch" -show-build "$bin" | /usr/bin/awk '$1 == "minos" {print $2}')
  [[ $minos == 14.0 ]] || fail "$arch 의 minos 가 '$minos' 입니다(기대: 14.0)"
done

/usr/bin/codesign --verify --strict --deep "$app" || fail "codesign 검증 실패"
signature=$(/usr/bin/codesign -d --verbose=2 "$app" 2>&1)
[[ $signature =~ flags=0x[0-9a-f]+\(([a-z-]+,)*runtime[,\)] ]] || fail "hardened runtime 플래그가 없습니다"
echo "verify-app: OK $app ($version, $archs, minos 14.0, hardened runtime 서명)"
