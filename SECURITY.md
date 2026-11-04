# 보안 정책

## 지원 버전

최신 릴리스에만 수정이 배포됩니다. 0.1.3 이상은 앱 메뉴의 **업데이트 확인…** 으로 업데이트하고(아래 '업데이트 서명' 참고), Homebrew 설치본은 `brew upgrade --cask eyo-25/tap/quickstream` 으로도 됩니다. 소스 설치본은 `git pull` 뒤 `./install.sh` 를 다시 실행하세요. 0.1.2 이하는 0.1.3 으로 한 번 직접 설치해야 합니다.

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

## 업데이트 서명

앱 안의 업데이트는 [Sparkle](https://sparkle-project.org) 이 합니다. 업데이트 피드(`appcast.xml`)는 GitHub 릴리스 에셋이고, 릴리스 zip 에는 **EdDSA(Ed25519) 서명**이 붙습니다. 앱은 번들 `Info.plist` 의 `SUPublicEDKey` 공개키로 받은 zip 의 서명을 확인하고, 맞지 않으면 설치하지 않습니다. ad-hoc 서명 앱에는 Apple 서명 신원이 없으므로 이 EdDSA 서명이 업데이트의 유일한 신뢰 근거입니다.

- 개인키는 메인테이너의 로그인 키체인에만 있고 CI 에는 없습니다. `release.sh` 가 CI 가 만든 zip 의 출처 증명(attestation)을 확인한 뒤 로컬에서 서명하고 `appcast.xml` 을 올립니다. 개인키가 유출되거나 의심되면 신고해 주세요: 키를 바꾸려면 새 공개키가 든 앱을 사용자가 직접 설치해야 하므로 공지와 함께 새 릴리스로 대응합니다.
- 앱의 hardened runtime 은 `disable-library-validation` 예외를 둡니다. 번들에 든 Sparkle 프레임워크가 ad-hoc 서명(Team ID 없음)이라 이 예외가 없으면 로드되지 않습니다. 이 예외는 앱 번들이 변조되지 않았다는 전제에서만 안전하므로(번들을 바꿀 수 있는 공격자는 어차피 앱을 바꿀 수 있습니다), 앱을 쓰기 권한이 있는 사용자 폴더나 관리자 소유 폴더에 두세요.
- 업데이트 확인은 시스템 정보를 보내지 않습니다(`SUSendProfileInfo` 끔). 자세한 내용은 README 의 '개인정보와 권한' 을 보세요.
