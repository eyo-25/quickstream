# 퀵스트림 릴리스

릴리스는 노트북이 아니라 GitHub Actions 가 빌드합니다. `release.sh` 가 메인테이너의 Mac 에서 전체를 이끕니다: 버전 태그를 달고, Release 워크플로가 zip 을 빌드·증명할 때까지 기다리고, 결과를 검증해 공개한 뒤, Homebrew cask 를 새 버전으로 바꿉니다.

## 시작 전에

- GitHub CLI(`gh`)가 `eyo-25/quickstream` 과 `eyo-25/homebrew-tap` 에 push 권한이 있는 계정으로 로그인되어 있어야 합니다.
- `main` 브랜치에서 커밋하지 않은 변경이 없고, `main` 이 `origin/main` 과 같아야 합니다.
- `CHANGELOG.md` 에 새 버전의 `## X.Y.Z` 섹션이 커밋·푸시되어 있어야 합니다. 이 내용이 릴리스 노트가 되며, 없으면 `release.sh` 와 워크플로가 멈춥니다.
- tap 저장소에 `Casks/quickstream.rb` 가 있어야 합니다(첫 릴리스 전에 이 저장소의 `Casks/quickstream.rb` 템플릿을 복사해 넣으세요. `version`/`sha256` 은 `release.sh` 가 채웁니다).
- 저장소·cask 이름은 `Info.plist` 의 `QSGitHubRepo`, `QSBrewCask` 가 단일 출처입니다. `release.sh` 가 이 값에서 tap 저장소(`<owner>/homebrew-<tap>`)와 cask 토큰을 계산합니다.

아무것도 바꾸지 않고 리허설하려면 `main` 을 푸시한 뒤 `./release.sh --check X.Y.Z` 를 실행하세요. 검사와 테스트를 돌리고 태그·GitHub 릴리스·cask 의 현재 상태를 보여 줍니다.

## 배포

```sh
./release.sh X.Y.Z
```

| # | 단계 | 하는 일 | 다시 실행하면 |
|---|---|---|---|
| 1 | 사전 점검 | 브랜치, 깨끗한 작업 트리, `origin/main`, `gh auth status`, 두 저장소의 push 권한, CHANGELOG 섹션, X.Y.Z 가 `Info.plist` 의 버전보다 큰지(`sort -V`. 단 `v*` 태그가 하나도 없는 첫 릴리스는 X.Y.Z 와 같아도 통과), 배포할 커밋의 CI 통과(진행 중이면 기다림) | 반복 |
| 2 | 테스트 | `tests/swift/run.sh` | 태그가 이미 있거나 버전 커밋에서 이어갈 때는 건너뜀 |
| 3 | 버전 올리기·태그 | `plutil -replace` 로 `Info.plist` 의 `CFBundleShortVersionString`·`CFBundleVersion` 변경, 커밋 `Release X.Y.Z`, 주석 태그 `vX.Y.Z`. 첫 릴리스는 `Info.plist` 가 이미 X.Y.Z 이므로 커밋 없이 HEAD 에 태그만 답니다 | `vX.Y.Z` 가 HEAD 에 있으면 건너뜀. 다른 곳을 가리키면 멈춤 |
| 4 | 푸시 | `git push --atomic origin main vX.Y.Z` | 이미 푸시됐으면 변화 없음 |
| 5 | 빌드 | 태그가 `.github/workflows/release.yml` 을 `macos-15` 러너에서 시작: 테스트, `./build.sh`, `.github/verify-app.sh`(버전, arm64 + x86_64, 최소 macOS 14.0, hardened runtime 서명), `ditto` zip, 빌드 출처 증명, CHANGELOG 섹션·Swift 버전·러너 이미지가 담긴 **draft** 릴리스. `release.sh` 는 `gh run watch` 로 따라감 | draft 에 zip 이 있으면 건너뜀 |
| 6 | 검증 | draft 의 zip 을 내려받아 `gh attestation verify`(`refs/tags/vX.Y.Z` 의 `release.yml` 에서 나왔는지), 압축 해제 후 `verify-app.sh`, sha256 계산 | 반복 |
| 7 | 공개 | `gh release edit vX.Y.Z --draft=false --latest=false`: zip 은 받을 수 있지만 앱의 업데이트 확인이 읽는 `releases/latest` 는 아직 이전 버전 | 이미 공개됐으면 건너뜀 |
| 8 | 공개 다운로드 | 공개 URL 을 `curl` 로 받아 sha256 비교 | 반복 |
| 9 | cask | tap 의 `Casks/quickstream.rb` 의 `version`·`sha256` 변경, 두 줄이 정확히 바뀌었는지 확인, Homebrew 가 있으면 `brew style`, 커밋 `quickstream X.Y.Z` 후 푸시 | cask 가 이미 같으면 건너뜀 |
| 10 | latest | `gh release edit vX.Y.Z --latest`: 이 순간부터 앱의 업데이트 확인이 X.Y.Z 를 안내 | 반복 |

순서가 중요합니다. 앱은 Homebrew 가 설치할 수 있게 된 뒤(9단계)에야 업데이트를 안내하고(10단계), cask 는 zip 이 공개되어 검증된 뒤(6~8단계)에야 바뀝니다.

## 첫 릴리스 (0.1.0)

`release.sh` 는 원격 저장소·CI·tap 이 이미 있다고 가정합니다. 아래 순서를 지켜야 합니다.

1. GitHub 에 앱 저장소(`eyo-25/quickstream`)와 tap 저장소(`eyo-25/homebrew-tap`)를 만듭니다. tap 에는 이 저장소의 `Casks/quickstream.rb` 를 `Casks/quickstream.rb` 로 복사해 넣고 푸시합니다.
2. 앱 저장소에서 `main` 브랜치로 첫 커밋을 만들고(`CHANGELOG.md` 의 `## 0.1.0` 섹션 포함, 작업 트리가 깨끗해야 함) `git remote add origin ...` 후 `git push -u origin main` 합니다. 커밋이 없거나 `origin` 이 없으면 `release.sh` 는 사전 점검에서 멈춥니다.
3. 푸시한 커밋의 `ci.yml` 이 끝나 통과할 때까지 기다립니다. `release.sh` 는 그 CI 실행이 없으면 멈춥니다.
4. `./release.sh --check 0.1.0` 으로 리허설합니다.
5. `./release.sh 0.1.0` 을 실행합니다. 아직 `v*` 태그가 없고 `Info.plist` 가 이미 `0.1.0` 이면 첫 릴리스로 보아 버전 올리기 커밋을 만들지 않고 HEAD 에 `v0.1.0` 을 달아 푸시합니다. `Info.plist` 보다 낮은 버전은 첫 릴리스에서도 거부합니다.

## 실패 뒤 이어서 하기

`release.sh` 는 멈춘 단계를 출력합니다. 원인을 고치고 같은 `./release.sh X.Y.Z` 를 다시 실행하면 끝난 단계는 건너뜁니다.

- **Release 워크플로가 일시적 이유로 실패**(러너·네트워크): `gh run rerun <run id> -R eyo-25/quickstream --failed` 후 `release.sh` 를 다시 실행합니다. 재실행하면 draft 의 zip 이 교체됩니다.
- **태그의 코드가 깨져서 실패**: 태그는 이미 공개이니 옮기지 마세요. draft 를 지우고(`gh release delete vX.Y.Z -R eyo-25/quickstream --yes`, 태그는 남음) `main` 에서 고친 뒤 다음 패치 버전의 CHANGELOG 섹션을 추가해 그 버전을 배포합니다.
- **푸시 실패**(main+태그 또는 tap): `release.sh` 를 다시 실행합니다. 그 사이 `origin/main` 이 움직여 atomic push 가 거절되면 로컬 릴리스 커밋과 태그를 버리고(`git tag -d vX.Y.Z && git reset --hard origin/main`) pull 한 뒤 처음부터 합니다.
- **버전 커밋은 됐는데 태그가 안 달림**: `release.sh` 를 다시 실행하면 `origin/main` 위의 `Release X.Y.Z` 커밋을 알아보고 태그를 답니다.

## 잘못된 릴리스 되돌리기

공개된 릴리스의 zip 은 교체하지 않습니다. 문제 있는 릴리스는 더 새로운 릴리스로 대체하고 릴리스 노트에 경고만 덧붙입니다(저장소에서 immutable releases 를 켜 두면 GitHub 가 asset·태그 변경을 거부하며, 이미 받은 사람도 있습니다).

1. cask 커밋을 되돌려 Homebrew 가 이전 버전을 가리키게 합니다.

   ```sh
   gh repo clone eyo-25/homebrew-tap /tmp/homebrew-tap && cd /tmp/homebrew-tap
   git log --oneline -3 -- Casks/quickstream.rb    # "quickstream X.Y.Z" 커밋 찾기
   git revert --no-edit <commit>
   git push
   ```

   Homebrew 는 설치된 버전과 cask 버전이 다르면 outdated 로 보므로, `brew upgrade --cask quickstream` 이 X.Y.Z 사용자를 이전 버전으로 돌려보내고 새 설치는 이전 버전을 받습니다.

2. 앱의 업데이트 확인이 X.Y.Z 를 더 안내하지 않게 합니다: `gh release edit vPREV -R eyo-25/quickstream --latest`.
3. X.Y.Z 릴리스 노트 맨 위에 수정 버전을 가리키는 경고를 덧붙입니다.
4. `main` 에서 고치고 다음 패치 버전을 평소처럼 배포합니다. `release.sh` 가 cask 와 latest 를 다시 앞으로 옮깁니다.

## 관련 검사

- `.github/workflows/ci.yml` 은 모든 푸시·PR 마다 macOS 14, 15, 26 과 Intel 러너에서 셸 문법, Swift 테스트, 빌드, 번들 검사, 실행 확인을 합니다.
- 누구든 `gh attestation verify QuickStream-X.Y.Z.zip -R eyo-25/quickstream --signer-workflow eyo-25/quickstream/.github/workflows/release.yml --source-ref refs/tags/vX.Y.Z` 로 릴리스 zip 을 확인할 수 있습니다([SECURITY.md](../SECURITY.md)).
