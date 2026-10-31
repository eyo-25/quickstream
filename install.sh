#!/bin/bash
# 이 체크아웃을 빌드해 ~/Applications/QuickStream.app 에 설치한다(소스 설치).
#   ./install.sh               설치, 또는 git pull 뒤 업데이트
#   ./install.sh --uninstall   앱 삭제(설정 ~/Library/Application Support/QuickStream 은 남김)
#   둘 다 --dry-run 을 붙이면 바꾸지 않고 할 일만 출력한다.
# 로그인 시 자동 시작은 LaunchAgent 가 아니라 앱의 설정 창("로그인 시 자동 시작")이 맡는다.
set -euo pipefail
project_dir=$(cd "$(dirname "$0")" && pwd)
app=$HOME/Applications/QuickStream.app
binary=$app/Contents/MacOS/QuickStream
mode=install
dry_run=0
for arg in "$@"; do
  case $arg in
    --uninstall) mode=uninstall ;;
    --dry-run) dry_run=1 ;;
    *) echo "사용법: ./install.sh [--uninstall] [--dry-run]" >&2; exit 1 ;;
  esac
done
die() { echo "$*" >&2; exit 1; }
run() { if (( dry_run )); then printf 'would run:'; printf ' %q' "$@"; echo; else "$@"; fi; }

# Homebrew 로 설치된 cask 가 있으면 같은 앱이 두 벌이 되므로 소스 설치를 막는다
cask_dir=
caskrooms=(/opt/homebrew/Caskroom /usr/local/Caskroom)
if command -v brew >/dev/null 2>&1; then
  brew_room=$(brew --caskroom 2>/dev/null || true)
  [[ -n $brew_room ]] && caskrooms=("$brew_room" "${caskrooms[@]}")
fi
for room in "${caskrooms[@]}"; do
  [[ -d $room/quickstream ]] && { cask_dir=$room/quickstream; break; }
done

# 이 경로에서 실행 중인 복사본만 정확한 명령줄 일치로 종료한다(홈 경로의 공백도 안전)
stop_running() {
  local line pid pids=() deadline=$((SECONDS + 5))
  while IFS= read -r line; do
    line=${line#"${line%%[![:space:]]*}"}
    [[ ${line#* } == "$binary" ]] && pids+=("${line%% *}")
  done < <(/bin/ps -axww -o pid=,command=)
  (( ${#pids[@]} )) || return 0
  run /bin/kill "${pids[@]}" 2>/dev/null || true
  (( dry_run )) && return 0
  for pid in "${pids[@]}"; do
    while /bin/kill -0 "$pid" 2>/dev/null && (( SECONDS < deadline )); do /bin/sleep 0.1; done
    /bin/kill -9 "$pid" 2>/dev/null || true  # 5초 뒤에도 남아 있으면 강제 종료
  done
}

if [[ $mode == uninstall ]]; then
  stop_running
  if [[ -d $app && -n $cask_dir && ! -e $app/Contents/Resources/source-install ]]; then
    echo "$app 은(는) Homebrew 로 설치한 복사본일 수 있어 남겨 둡니다. 삭제하려면: brew uninstall --cask quickstream"
    exit 0
  fi
  [[ -d $app ]] && run /bin/rm -rf "$app"
  (( dry_run )) && exit 0
  echo "퀵스트림 소스 설치본을 삭제했습니다."
  echo "설정과 로그(~/Library/Application Support/QuickStream)는 남겨 두었습니다. 지우려면 그 폴더를 삭제하세요."
  exit 0
fi

[[ -z $cask_dir ]] || die "퀵스트림이 Homebrew 로 설치되어 있습니다($cask_dir).
소스 설치와 겹치면 같은 앱이 두 벌이 되고 업데이트가 엉뚱한 쪽으로 갑니다.
먼저 Homebrew 복사본을 지우세요: brew uninstall --cask quickstream"
/usr/bin/xcrun --find swiftc >/dev/null 2>&1 || die "빌드에 swiftc 가 필요합니다. Xcode Command Line Tools 를 설치하세요: xcode-select --install
설치한 뒤 ./install.sh 를 다시 실행하세요."

# 소스 설치 표식(Resources/source-install)은 서명 전에 넣어야 하므로 build.sh 가 만든다. --uninstall 이 Homebrew 복사본을 지우지 않게 하는 용도
run env QS_SOURCE_INSTALL=1 "$project_dir/build.sh"
run /bin/mkdir -p "$HOME/Applications"
stop_running
run /bin/rm -rf "$app"
run /usr/bin/ditto "$project_dir/build/QuickStream.app" "$app"
run /usr/bin/codesign --verify --deep --strict "$app"
run /usr/bin/open "$app"
(( dry_run )) || echo "설치했습니다: $app"
