# tap 저장소(eyo-25/homebrew-tap)의 Casks/quickstream.rb 에 들어갈 템플릿.
# version 과 sha256 은 release.sh 가 릴리스마다 갱신한다(두 줄의 들여쓰기·따옴표 형식을 바꾸지 말 것).
cask "quickstream" do
  version "0.1.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/eyo-25/quickstream/releases/download/v#{version}/QuickStream-#{version}.zip"
  name "QuickStream"
  desc "Circular 8-slot app launcher for the menu bar"
  homepage "https://github.com/eyo-25/quickstream"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sonoma

  app "QuickStream.app"

  # 앱은 ad-hoc 서명이고 공증되지 않았다. 설치 직후 Gatekeeper 경고 없이 열리도록 격리 속성을 제거한다.
  postflight_steps do
    run "/usr/bin/xattr",
        args:         ["-dr", "com.apple.quarantine", "{{appdir}}/QuickStream.app"],
        must_succeed: false
  end

  # 이전 Electron 판이 쓰던 설정 폴더(퀵스트림·퀘스트림)는 SettingsMigration 이 읽어 가져온다
  zap trash: [
    "~/Library/Application Support/QuickStream",
    "~/Library/Application Support/퀘스트림",
    "~/Library/Application Support/퀵스트림",
    "~/Library/Caches/io.github.eyo-25.quickstream",
    "~/Library/HTTPStorages/io.github.eyo-25.quickstream",
    "~/Library/Preferences/io.github.eyo-25.quickstream.plist",
    "~/Library/Saved Application State/io.github.eyo-25.quickstream.savedState",
  ]
end
