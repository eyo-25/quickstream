#!/bin/bash
# Sparkle 프레임워크를 처음 한 번 받아 sha256 을 확인하고 풀어 둔 뒤, 그 폴더 경로를 출력한다.
#   sparkle=$(tools/sparkle.sh)       # $sparkle/Sparkle.framework, $sparkle/bin/{generate_keys,sign_update,generate_appcast}
# build.sh, tests/swift/run.sh, tools/make-screenshots.sh, release.sh, CI 가 같은 사본을 쓴다.
# 버전을 올릴 때는 아래 두 값을 함께 바꾼다. sha256 은 새로 받은 파일을 직접 계산하고, GitHub 릴리스 에셋의 digest 와도 맞는지 확인한다:
#   gh release view <버전> -R sparkle-project/Sparkle --json assets --jq '.assets[] | select(.name | endswith(".tar.xz")) | .digest'
set -euo pipefail
version=2.10.1
sha256=1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27

root=$(cd "$(dirname "$0")/.." && pwd)
dir=$root/.cache/sparkle-$version
if [[ ! -d $dir/Sparkle.framework ]]; then
  tmp=$(/usr/bin/mktemp -d)
  trap '/bin/rm -rf "$tmp"' EXIT
  /usr/bin/curl -fsSL --retry 5 --retry-delay 5 --retry-all-errors -o "$tmp/sparkle.tar.xz" \
    "https://github.com/sparkle-project/Sparkle/releases/download/$version/Sparkle-$version.tar.xz" >&2
  actual=$(/usr/bin/shasum -a 256 "$tmp/sparkle.tar.xz" | /usr/bin/awk '{print $1}')
  [[ $actual == "$sha256" ]] || { echo "tools/sparkle.sh: Sparkle $version 의 sha256 이 $actual 입니다(기대: $sha256)" >&2; exit 1; }
  /bin/mkdir -p "$tmp/unpacked"
  /usr/bin/tar -xf "$tmp/sparkle.tar.xz" -C "$tmp/unpacked"
  [[ -d $tmp/unpacked/Sparkle.framework && -x $tmp/unpacked/bin/sign_update ]] || { echo "tools/sparkle.sh: 압축 안에 Sparkle.framework 또는 bin/sign_update 가 없습니다" >&2; exit 1; }
  /bin/mkdir -p "$root/.cache"
  /bin/rm -rf "$dir"
  /bin/mv "$tmp/unpacked" "$dir"
fi
echo "$dir"
