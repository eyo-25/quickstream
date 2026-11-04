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
# 업데이트 피드·공개키: 저장소 Info.plist 와 같아야 한다(업데이트 시험용 빌드는 QS_SU_FEED_URL·QS_SU_PUBLIC_KEY 로 덮어쓴 값과 같아야 한다)
repo_plist=$(cd "$(dirname "$0")/.." && pwd)/Info.plist
repo_key() { /usr/bin/plutil -extract "$1" raw -o - "$repo_plist"; }
expect SUFeedURL "${QS_SU_FEED_URL:-$(repo_key SUFeedURL)}"
expect SUPublicEDKey "${QS_SU_PUBLIC_KEY:-$(repo_key SUPublicEDKey)}"
[[ ${QS_E2E_HTTP:-} == 1 || $(key SUFeedURL) == https://* ]] || fail "SUFeedURL 이 https 가 아닙니다(업데이트 시험 빌드만 QS_E2E_HTTP=1 로 예외)"
[[ $(key SUPublicEDKey) =~ ^[A-Za-z0-9+/]{43}=$ ]] || fail "SUPublicEDKey 가 base64 32바이트 키 형식이 아닙니다"
expect SUEnableAutomaticChecks true
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

# Sparkle: 번들에 들어 있고, 앱이 rpath 로 찾고, 앱의 엔타이틀먼트가 ad-hoc 서명된 프레임워크 로드를 허용해야 한다(없으면 실행하자마자 죽는다)
framework=$app/Contents/Frameworks/Sparkle.framework
[[ -x $framework/Versions/B/Sparkle && -x $framework/Versions/B/Autoupdate && -d $framework/Versions/B/Updater.app ]] || fail "Sparkle.framework 가 번들에 없거나 불완전합니다"
[[ ! -e $framework/XPCServices && ! -e $framework/Versions/B/XPCServices ]] || fail "Sparkle XPC 서비스는 번들에 넣지 않습니다(샌드박스 앱이 아니다)"
# 출력을 변수에 받은 뒤 검사한다(grep -q 가 먼저 끝나 파이프가 끊기면 pipefail 로 실패하기 때문)
linked=$(/usr/bin/otool -L "$bin")
[[ $linked == *"@rpath/Sparkle.framework/Versions/B/Sparkle"* ]] || fail "실행 파일이 Sparkle 에 링크되어 있지 않습니다"
load_commands=$(/usr/bin/otool -l "$bin")
[[ $load_commands == *"@executable_path/../Frameworks"* ]] || fail "실행 파일에 Frameworks rpath 가 없습니다"
entitlements=$(/usr/bin/codesign -d --entitlements - "$app" 2>/dev/null || true)
[[ $entitlements == *"com.apple.security.cs.disable-library-validation"* ]] || fail "disable-library-validation 엔타이틀먼트가 없습니다"
echo "verify-app: OK $app ($version, $archs, minos 14.0, hardened runtime 서명)"
