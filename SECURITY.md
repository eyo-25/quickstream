# 보안 정책

## 지원 버전

최신 릴리스에만 수정이 배포됩니다. Homebrew 설치본은 `brew upgrade --cask eyo-25/tap/quickstream`, 소스 설치본은 `git pull` 뒤 `./install.sh` 를 다시 실행해 업데이트하세요.

## 취약점 신고

취약점은 공개 이슈가 아니라 비공개로 신고해 주세요. 저장소의 **Security** 탭에서 **Report a vulnerability** 를 선택합니다
(<https://github.com/eyo-25/quickstream/security/advisories/new>). 버튼이 보이지 않으면 자세한 내용 없이 비공개 연락처만 요청하는 이슈를 열어 주세요.

퀵스트림 버전, macOS 버전, 공격자가 할 수 있는 일, 재현 방법을 적어 주세요. 한 사람이 관리하는 프로젝트라 신고는 가능한 범위에서 처리하며, advisory 에서 답변드리고 수정은 새 릴리스로 배포합니다(원하지 않으시면 공개 감사 표기는 생략합니다).

범위에 해당하는 예: 설정 파일로 임의 셸·스크립트가 실행되는 경우, 매크로/URL 검증 우회, 업데이트 경로, `install.sh`, 릴리스 워크플로, Homebrew cask.

## 서명·격리 속성·다운로드 검증

퀵스트림은 ad-hoc 서명이며 Apple 공증을 받지 않았습니다. Homebrew cask 는 설치 뒤 `com.apple.quarantine` 속성을 제거해 Gatekeeper 경고 없이 열리게 합니다. 즉 macOS 가 앱을 대신 검사해 주지 않으므로, 이 저장소와 [eyo-25/homebrew-tap](https://github.com/eyo-25/homebrew-tap) 의 cask 를 신뢰한다는 뜻입니다.

릴리스 zip 은 태그된 커밋에서 GitHub Actions 가 빌드하며, 각 zip 에는 서명된 빌드 출처 증명(attestation)이 있습니다. 직접 확인하려면(GitHub CLI 필요):

```sh
gh release download v0.1.0 -R eyo-25/quickstream -p 'QuickStream-*.zip'
gh attestation verify QuickStream-0.1.0.zip -R eyo-25/quickstream \
  --signer-workflow eyo-25/quickstream/.github/workflows/release.yml --source-ref refs/tags/v0.1.0
shasum -a 256 QuickStream-0.1.0.zip   # tap 의 Casks/quickstream.rb 의 sha256 과 비교
```

`--signer-workflow` 와 `--source-ref` 를 주면 이 저장소의 릴리스 워크플로가 그 버전의 태그에서 빌드한 것과 바이트 단위로 같은 zip 일 때만 검증이 성공합니다.
