import SwiftUI

struct AboutPane: View {
    @Environment(\.settingsPalette) private var pal
    @ObservedObject var model: SettingsModel

    var body: some View {
        OneUIPage(title: AppInfo.displayName, subtitle: "정보") {
            OneUICard(title: "버전") {
                OneUIRow(symbol: "info.circle", title: "버전 \(model.versionText())")
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("버전 \(model.versionText())")
                OneUIDivider()
                OneUIRow(symbol: "arrow.triangle.2.circlepath", title: "업데이트 확인") {
                    OneUIPillButton(title: "업데이트 확인", kind: .primary) {
                        model.checkForUpdates()
                    }
                    .accessibilityLabel("업데이트 확인")
                }
                OneUIDivider()
                OneUIToggleRow(
                    symbol: "clock.arrow.circlepath", title: "새 버전 자동 확인",
                    subtitle: "하루에 한 번 GitHub 에서 새 버전이 있는지 확인합니다. 새 버전은 서명을 확인한 뒤에만 설치합니다.",
                    isOn: model.updateChecksAutomatically()) { model.setAutomaticUpdateChecks($0) }
            }

            OneUICard(title: "저장소") {
                OneUIRow(symbol: "link", title: "릴리스 페이지",
                         subtitle: "새 버전과 변경 내역은 릴리스 페이지에서 확인할 수 있습니다.") {
                    Link(destination: AppInfo.releasesURL) {
                        Text(AppInfo.releasesURL.absoluteString)
                            .font(.system(size: 12))
                            .foregroundStyle(pal.accentText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .frame(maxWidth: 280, alignment: .trailing)
                    .accessibilityLabel("릴리스 페이지 열기")
                }
            }
        }
    }
}
