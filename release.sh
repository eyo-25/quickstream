#!/bin/bash
# 버전을 배포한다: ./release.sh X.Y.Z    (./release.sh --check X.Y.Z 는 검사와 테스트만 하고 아무것도 바꾸지 않는다)
# 모든 단계는 다시 실행해도 안전하다: 실패하면 원인을 고치고 같은 명령을 다시 실행한다.
# 1. 사전 점검, 테스트, Info.plist 버전 올리기, 커밋, vX.Y.Z 태그, 푸시(태그가 HEAD 에 있으면 건너뜀)
# 2. Release 워크플로가 빌드·증명하고 QuickStream-X.Y.Z.zip 을 draft 릴리스에 올린다
# 3. draft 의 zip 을 검증하고, latest 표시 없이 공개하고, Homebrew cask 를 새 버전으로 바꾼 뒤, 마지막에 latest 로 표시한다
#    (latest 가 되어야 앱의 업데이트 확인이 이 버전을 안내하기 시작한다)
# docs/RELEASING.md 참고. 두 저장소(앱·tap) 모두 push 권한이 있는 gh 로그인이 필요하다.
set -euo pipefail
project_dir=$(cd "$(dirname "$0")" && pwd)
cd "$project_dir"

# 저장소·cask 이름의 단일 출처는 Info.plist
repo=$(/usr/libexec/PlistBuddy -c 'Print :QSGitHubRepo' Info.plist)
cask_full=$(/usr/libexec/PlistBuddy -c 'Print :QSBrewCask' Info.plist)   # owner/tap/token
tap_owner=${cask_full%%/*}
tap_name=${cask_full#*/}; tap_name=${tap_name%%/*}
cask_token=${cask_full##*/}
tap_repo=$tap_owner/homebrew-$tap_name

check_only=0
[[ ${1:-} == --check ]] && { check_only=1; shift; }
version=${1:-}
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "사용법: ./release.sh [--check] X.Y.Z" >&2; exit 1; }
tag=v$version
zip_name=QuickStream-$version.zip

step=preflight
work=$(/usr/bin/mktemp -d)
on_exit() {
  local exit_status=$?
  /bin/rm -rf "$work"
  (( exit_status == 0 )) || echo "
release.sh 가 '$step' 단계에서 멈췄습니다.
원인을 고치고 ./release.sh $( ((check_only)) && echo '--check ' )$version 을 다시 실행하세요. 끝난 단계는 건너뜁니다." >&2
}
trap on_exit EXIT
say() { step=$1; echo "==> $1"; }
die() { echo "error: $*" >&2; exit 1; }
version_gt() { [[ $1 != "$2" && $(printf '%s\n' "$1" "$2" | /usr/bin/sort -V | /usr/bin/tail -1) == "$1" ]]; }
require_ci() {  # 이 커밋에 대해 CI(모든 macOS 버전·Intel)가 통과해야 한다
  local sha=$1 run id result
  run=$(gh run list -R "$repo" --workflow ci.yml --commit "$sha" --limit 1 \
    --json databaseId,status,conclusion --jq '.[0] // empty | "\(.databaseId) \(.status) \(.conclusion)"')
  [[ -n $run ]] || die "${sha:0:12} 의 CI 실행이 없습니다. main 을 푸시하고 CI 가 끝나길 기다리세요."
  id=${run%% *} result=${run#* }
  if [[ $result != completed* ]]; then
    echo "CI 대기 중: https://github.com/$repo/actions/runs/$id"
    gh run watch "$id" -R "$repo" --exit-status --compact --interval 30 >/dev/null \
      || die "${sha:0:12} 의 CI 가 실패했습니다: https://github.com/$repo/actions/runs/$id"
  elif [[ $result != "completed success" ]]; then
    die "${sha:0:12} 의 CI 가 통과하지 못했습니다(${result#completed }): https://github.com/$repo/actions/runs/$id"
  fi
}
release_state() {  # "none", 또는 "draft"/"published" + " with zip"/" without zip"
  local query="(if .isDraft then \"draft\" else \"published\" end) + (if any(.assets[]; .name == \"$zip_name\") then \" with zip\" else \" without zip\" end)"
  gh release view "$tag" -R "$repo" --json isDraft,assets --jq "$query" 2>/dev/null || echo none
}

say "사전 점검"
command -v gh >/dev/null || die "GitHub CLI(gh)를 설치하세요."
[[ $(git branch --show-current) == main ]] || die "main 브랜치에서 배포하세요."
[[ -z $(git status --porcelain) ]] || die "변경 사항을 커밋하거나 stash 하세요."
gh auth status --active --hostname github.com >/dev/null 2>&1 || die "먼저 GitHub CLI 에 로그인하세요: gh auth login"
for r in "$repo" "$tap_repo"; do
  [[ $(gh api "repos/$r" --jq .permissions.push) == true ]] || die "gh 계정에 $r 의 push 권한이 없습니다."
done
section=$(/usr/bin/awk -v v="$version" '$1 == "##" && $2 == v {f = 1; next} f && /^## / {exit} f' CHANGELOG.md)
[[ $section == *[^[:space:]]* ]] || die "CHANGELOG.md 에 '## $version' 섹션이 없습니다. 릴리스 노트로 쓰입니다."
git fetch -q --tags origin main
head=$(git rev-parse HEAD)
current=$(/usr/bin/plutil -extract CFBundleShortVersionString raw Info.plist)
if tag_commit=$(git rev-parse -q --verify "refs/tags/$tag^{commit}"); then
  [[ $tag_commit == "$head" ]] || die "태그 $tag 가 HEAD(${head:0:12})가 아닌 ${tag_commit:0:12} 에 있습니다."
  git merge-base --is-ancestor origin/main HEAD || die "origin/main 에 HEAD 에 없는 커밋이 있습니다. 먼저 해결하세요."
  [[ $current == "$version" ]] || die "태그 $tag 가 HEAD 에 있는데 Info.plist 는 $current 입니다."
  # 버전 올리기 커밋이 있으면 CI 는 그 직전 커밋 기준이고, 첫 릴리스처럼 올리기 커밋이 없으면 HEAD 기준이다
  if [[ $(git log -1 --format=%s) == "Release $version" ]]; then require_ci "$(git rev-parse HEAD~1)"; else require_ci "$head"; fi
  tagged=1
elif [[ $(git log -1 --format=%s) == "Release $version" && $(git rev-parse HEAD~1) == $(git rev-parse origin/main) \
        && $current == "$version" ]]; then
  # 이전 실행이 버전 커밋까지 만들고 태그 전에 멈춘 경우
  require_ci "$(git rev-parse HEAD~1)"
  if (( ! check_only )); then
    say "릴리스 커밋에 $tag 태그"
    git tag -a "$tag" -m "QuickStream $version"
  fi
  tagged=1
else
  [[ $head == "$(git rev-parse origin/main)" ]] || die "main 이 origin/main 과 다릅니다. pull 또는 push 하세요."
  # 아직 v* 태그가 하나도 없는 첫 릴리스는 Info.plist 가 이미 요청 버전이어도 된다(올리기 커밋 없이 HEAD 에 태그). 낮은 버전은 여전히 거부한다.
  if [[ -z $(git tag -l 'v*') && $current == "$version" ]]; then
    first_release=1
  else
    first_release=0
    version_gt "$version" "$current" || die "$version 은(는) 현재 버전 $current 보다 크지 않습니다."
  fi
  require_ci "$head"
  tagged=0
  say "테스트 실행"
  tests/swift/run.sh
fi

if (( check_only )); then
  if (( tagged )); then
    echo "태그 $tag 가 HEAD 에 있습니다: 배포 실행은 버전 올리기를 건너뛰고 푸시부터 이어갑니다."
  elif (( first_release )); then
    echo "첫 릴리스입니다: Info.plist 는 이미 $version 이므로 올리기 커밋 없이 HEAD 에 $tag 태그를 달고 main 과 함께 푸시합니다."
  else
    echo "배포 실행은 Info.plist 를 $current → $version 로 올리고 커밋, $tag 태그, main 푸시를 합니다."
  fi
  echo "GitHub 릴리스 $tag: $(release_state)"
  echo "tap 의 cask 현재 값: $(gh api -H 'Accept: application/vnd.github.raw' "repos/$tap_repo/contents/Casks/$cask_token.rb" \
    | /usr/bin/awk '$1 == "version" || $1 == "sha256" {printf "%s %s  ", $1, $2}')"
  echo "검사를 통과했습니다. 아무것도 바꾸지 않았습니다."
  exit 0
fi

if (( ! tagged )); then
  if (( first_release )); then
    say "첫 릴리스: HEAD 에 $tag 태그"
    git tag -a "$tag" -m "QuickStream $version"
  else
    say "Info.plist 를 $version 로 올리고 커밋, $tag 태그"
    /usr/bin/plutil -replace CFBundleShortVersionString -string "$version" Info.plist
    /usr/bin/plutil -replace CFBundleVersion -string "$version" Info.plist
    [[ $(/usr/bin/plutil -extract CFBundleShortVersionString raw Info.plist) == "$version" ]] || die "Info.plist 를 바꾸지 못했습니다."
    git commit -q -m "Release $version" Info.plist
    git tag -a "$tag" -m "QuickStream $version"
  fi
fi
say "main 과 $tag 푸시"
git push -q --atomic origin main "$tag"

say "Release 워크플로가 draft 에 $zip_name 을 올릴 때까지 대기"
state=$(release_state)
if [[ $state != *" with zip" ]]; then
  run_id=
  for _ in $(seq 30); do
    run_id=$(gh run list -R "$repo" --workflow release.yml --branch "$tag" --limit 1 --json databaseId --jq '.[0].databaseId // empty' 2>/dev/null) || true
    [[ -n $run_id ]] && break
    sleep 5
  done
  [[ -n $run_id ]] || die "$tag 의 Release 워크플로 실행이 아직 없습니다: https://github.com/$repo/actions/workflows/release.yml"
  gh run watch "$run_id" -R "$repo" --exit-status --compact --interval 15 \
    || die "Release 워크플로가 실패했습니다: https://github.com/$repo/actions/runs/$run_id
  일시적 실패: gh run rerun $run_id -R $repo --failed 후 release.sh 를 다시 실행하세요.
  태그의 코드가 깨진 경우: main 에서 고치고 다음 버전을 배포하세요."
  state=$(release_state)
  [[ $state == *" with zip" ]] || die "워크플로는 끝났지만 릴리스 $tag 의 상태가 '$state' 입니다."
fi

say "$zip_name 다운로드·검증"
gh release download "$tag" -R "$repo" --pattern "$zip_name" --dir "$work" --clobber
gh attestation verify "$work/$zip_name" -R "$repo" --signer-workflow "$repo/.github/workflows/release.yml" \
  --source-ref "refs/tags/$tag" --deny-self-hosted-runners
/usr/bin/ditto -x -k "$work/$zip_name" "$work/unzipped"
.github/verify-app.sh "$work/unzipped/QuickStream.app" "$version"
sha=$(/usr/bin/shasum -a 256 "$work/$zip_name" | /usr/bin/awk '{print $1}')
echo "sha256 $sha"

if [[ $state == draft* ]]; then
  say "latest 표시 없이 $tag 공개"
  gh release edit "$tag" -R "$repo" --draft=false --latest=false >/dev/null
fi

say "공개 다운로드 확인"
/usr/bin/curl -fsSL --retry 5 --retry-delay 5 --retry-all-errors -o "$work/public.zip" \
  "https://github.com/$repo/releases/download/$tag/$zip_name"
public_sha=$(/usr/bin/shasum -a 256 "$work/public.zip" | /usr/bin/awk '{print $1}')
[[ $public_sha == "$sha" ]] || die "공개 다운로드의 sha256 이 $public_sha 입니다(기대: $sha)."

say "Homebrew cask 를 $version 으로 변경"
gh repo clone "$tap_repo" "$work/tap" -- -q
cask="$work/tap/Casks/$cask_token.rb"
/usr/bin/sed -i '' -E -e "s/^  version \"[^\"]*\"$/  version \"$version\"/" \
  -e "s/^  sha256 \"[0-9a-f]*\"$/  sha256 \"$sha\"/" "$cask"
/usr/bin/grep -qx "  version \"$version\"" "$cask" && /usr/bin/grep -qx "  sha256 \"$sha\"" "$cask" \
  || die "Casks/$cask_token.rb 의 version, sha256 을 바꾸지 못했습니다."
if git -C "$work/tap" diff --quiet; then
  echo "cask 가 이미 $version 을 가리킵니다."
else
  if command -v brew >/dev/null; then HOMEBREW_NO_AUTO_UPDATE=1 brew style "$cask"; fi
  git -C "$work/tap" commit -q -am "$cask_token $version"
  git -C "$work/tap" push -q
fi

say "$tag 를 latest 로 표시"
gh release edit "$tag" -R "$repo" --latest >/dev/null
echo "퀵스트림 $version 을 배포했습니다(sha256 $sha)"
