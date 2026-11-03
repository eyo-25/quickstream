import SwiftUI

/// 일반 화면: 단축키 · 시작 · 초기화. (패널 모양은 `PanelPane` 이 따로 맡는다.)
struct GeneralPane: View {
    @ObservedObject var model: SettingsModel

    private var generalIssues: [ValidationIssue] { model.issues.filter { $0.tabIndex == nil } }

    var body: some View {
        OneUIPage(title: "일반", subtitle: "오버레이를 여는 방법과 시작 방식") {
            OneUICard(title: "단축키") {
                OneUIRow(
                    symbol: "command", title: "오버레이 단축키",
                    subtitle: model.recorderHint ?? "버튼을 클릭한 뒤 키 조합을 누르세요.",
                    warnSubtitle: model.recorderHint != nil) {
                    ShortcutRecorder(
                        value: model.draft.shortcut,
                        accent: model.palette.swatches.accentText.nsColor,
                        onChange: { model.draft.shortcut = $0 },
                        onHint: { model.recorderHint = $0 },
                        onRecordingChange: { model.setShortcutRecording($0) })
                        .frame(width: 200, height: 30)
                        // 새 단축키가 녹화되면 버튼이 톡 튀어 오른다(값이 바뀔 때만). 동작 줄이기이면 1배 고정.
                        .keyframeAnimator(initialValue: 1.0, trigger: model.draft.shortcut) { view, scale in
                            view.scaleEffect(scale)
                        } keyframes: { _ in
                            let peak = Motion.reduced ? 1.0 : 1.08
                            CubicKeyframe(peak, duration: 0.09)
                            SpringKeyframe(1.0, duration: 0.35, spring: .init(response: 0.30, dampingRatio: 0.58))
                        }
                }
            }

            OneUICard(title: "오버레이") {
                OneUIRow(
                    symbol: "xmark.circle", title: "닫기 키",
                    subtitle: model.closeKeyHint ?? "오버레이를 여는 동안 이 키(영문자·숫자)로 닫습니다. Esc 는 늘 닫고, Delete 로 기본(Q)으로 되돌립니다.",
                    warnSubtitle: model.closeKeyHint != nil) {
                    KeyRecorder(
                        display: SlotKey.display(model.draft.closeKey) + (model.draft.closeKey == "q" ? " (기본)" : ""),
                        accent: model.palette.swatches.accentText.nsColor,
                        accessibilityLabel: "닫기 키 녹화. 클릭한 뒤 영문자나 숫자 키를 누르세요",
                        validate: { SettingsDraft.closeKeyConflict(model.draft, key: $0) },
                        onChange: { key in
                            // 기본(Q)으로 되돌리려는데 어느 슬롯이 이미 Q 를 쓰면 막고 이유를 보인다
                            if key == nil, let reason = SettingsDraft.closeKeyConflict(model.draft, key: "q") {
                                model.closeKeyHint = "기본 키(Q)로 되돌릴 수 없습니다 — \(reason)"
                                return
                            }
                            model.draft = SettingsDraft.settingCloseKey(model.draft, to: key ?? "q")
                        },
                        onHint: { model.closeKeyHint = $0 })
                        .frame(width: 130, height: 30)
                }
            }

            OneUICard(title: "시작") {
                OneUIToggleRow(
                    symbol: "power", title: "로그인 시 자동 시작", subtitle: "서명되지 않은 앱은 macOS 가 거부할 수 있습니다.",
                    isOn: model.draft.launchAtLogin) { model.draft.launchAtLogin = $0 }
            }

            OneUICard(title: "초기화") {
                OneUIRow(
                    symbol: "arrow.counterclockwise", title: "기본값으로 초기화",
                    subtitle: "편집 중인 내용만 기본값으로 바뀌며, ‘저장’을 눌러야 적용됩니다.",
                    action: { chewyChange { model.resetToDefaults() } })
                    .accessibilityLabel("설정을 기본값으로 초기화")
            }

            ForEach(Array(generalIssues.enumerated()), id: \.offset) { _, issue in
                Text(issue.text).font(.callout).foregroundStyle(SettingsTheme.danger)
                    .padding(.horizontal, 14)
            }
        }
    }
}
