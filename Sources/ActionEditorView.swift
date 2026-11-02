import SwiftUI

/// 슬롯/매크로 단계의 동작 편집기. 종류를 바꾸면 기존 필드는 버리고 새 종류의 기본값으로 시작한다.
struct ActionEditorView: View {
    @Environment(\.settingsPalette) private var pal
    @Binding var action: Action
    let apps: [InstalledApp]
    /// 슬롯에서는 매크로를 고를 수 있지만 매크로 단계에서는 안 된다
    let allowMacro: Bool
    /// 접근성 레이블 접두("슬롯 3", "단계 2")
    let label: String

    /// 매크로 단계 행의 안정적인 id(Action 에는 id 가 없다). 이동/삭제/추가 버튼이 같은 동작으로 갱신해 행이 제자리를 따라 움직이게 한다.
    @StateObject private var stepIDs = StepIDs()

    private typealias Kind = SettingsDraft.ActionKind

    private var kindChoices: [Kind] {
        let base = allowMacro ? Kind.slotChoices : Kind.stepChoices
        let current = SettingsDraft.kind(of: action)
        return base.contains(current) ? base : [current] + base
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            block("동작 종류") {
                // Picker(.menu)는 AppKit 컨트롤이라 알약 세그먼트로 대체한다
                OneUISegmented(
                    options: kindChoices.map { (value: $0, title: $0.label) },
                    selected: SettingsDraft.kind(of: action),
                    accessibilityPrefix: "\(label): 동작 종류",
                    onSelect: { newKind in chewyChange { action = SettingsDraft.changeActionKind(action, to: newKind) } })
            }
            OneUIDivider(inset: OneUI.rowInset)
            fields
        }
    }

    /// 입력 행: 위에 작은 제목, 아래에 컨트롤(입력 행은 56pt 최소 높이 규칙을 따르지 않고 내용에 맞춘다)
    private func block<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(pal.muted)
            content()
        }
        .padding(.horizontal, OneUI.rowInset).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var fields: some View {
        switch action {
        case let .launchApp(bundleId, appPath):
            launchFields(bundleId: bundleId, appPath: appPath)
        case let .openURL(url):
            block("URL") {
                TextField("https://example.com", text: Binding(get: { url }, set: { action = .openURL($0) }))
                    .oneUIField()
                    .accessibilityLabel("\(label): URL")
                hintText("http:// 또는 https:// 주소만 열 수 있습니다.")
            }
        case let .clipboardText(text):
            block("복사할 텍스트") {
                TextEditor(text: Binding(get: { text }, set: { action = .clipboardText(String($0.prefix(10_000))) }))
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .oneUIField()
                    .frame(height: 120)
                    .accessibilityLabel("\(label): 복사할 텍스트")
            }
        case let .activateApp(bundleId, _):
            block("앱 전환") {
                hintText("앱 전환 (번들 ID: \(bundleId)) — 종류를 바꾸면 되돌릴 수 없습니다.")
            }
        case let .macroSequence(stopOnError, steps):
            macroFields(stopOnError: stopOnError, steps: steps)
        }
    }

    private func launchFields(bundleId: String?, appPath: String?) -> some View {
        let usingPath = appPath != nil
        return VStack(alignment: .leading, spacing: 0) {
            block("앱 선택") {
                AppPickerView(apps: apps, selected: bundleId, label: label) { app in
                    action = SettingsDraft.launchApp(.bundleId, app.bundleId)
                }
            }
            OneUIDivider(inset: OneUI.rowInset)
            block("직접 입력") {
                // 모드를 바꾸면 값은 비운다: 번들 ID 가 경로로(또는 반대로) 넘어가면 항상 검증 오류가 된다.
                OneUISegmented(
                    options: [(value: SettingsDraft.AppField.bundleId, title: "번들 ID"),
                              (value: SettingsDraft.AppField.appPath, title: ".app 경로")],
                    selected: usingPath ? SettingsDraft.AppField.appPath : .bundleId,
                    accessibilityPrefix: "\(label): 직접 입력 방식",
                    onSelect: { action = SettingsDraft.launchApp($0, "") })
                    .frame(width: 220)
                TextField(usingPath ? "/Applications/Example.app" : "com.example.app",
                          text: Binding(
                              get: { (usingPath ? appPath : bundleId) ?? "" },
                              set: { action = SettingsDraft.launchApp(usingPath ? .appPath : .bundleId, $0) }))
                    .oneUIField()
                    .autocorrectionDisabled()
                    .accessibilityLabel("\(label): \(usingPath ? ".app 경로" : "번들 ID")")
                hintText("번들 ID 또는 .app 경로 중 하나만 사용됩니다.")
            }
        }
    }

    private func macroFields(stopOnError: Bool, steps: [Action]) -> some View {
        let macro = SettingsDraft.Macro(stopOnError: stopOnError, steps: steps)
        return VStack(alignment: .leading, spacing: 0) {
            OneUIRow(title: "실패 시 중단", subtitle: "한 단계가 실패하면 나머지 단계를 실행하지 않습니다.") {
                Toggle("실패 시 중단", isOn: Binding(
                    get: { stopOnError },
                    set: { newValue in chewyChange { action = SettingsDraft.Macro(stopOnError: newValue, steps: steps).action } }))
                    .toggleStyle(OneUIToggleStyle())
                    .labelsHidden()
                    .accessibilityLabel("\(label): 실패 시 중단")
            }
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(stepIDs.reconciled(count: steps.count).enumerated()), id: \.element) { i, _ in
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 6) {
                            Text("단계 \(i + 1)").font(.system(size: 14, weight: .semibold))
                            Spacer()
                            iconButton("arrow.up", "단계 \(i + 1) 위로 이동", disabled: i == 0) {
                                chewyChange {
                                    stepIDs.swap(i, i - 1)
                                    action = SettingsDraft.moveStep(macro, at: i, by: -1).action
                                }
                            }
                            iconButton("arrow.down", "단계 \(i + 1) 아래로 이동", disabled: i == steps.count - 1) {
                                chewyChange {
                                    stepIDs.swap(i, i + 1)
                                    action = SettingsDraft.moveStep(macro, at: i, by: 1).action
                                }
                            }
                            iconButton("trash", "단계 \(i + 1) 삭제", disabled: steps.count <= 1, destructive: true) {
                                chewyChange {
                                    stepIDs.remove(i)
                                    action = SettingsDraft.removeStep(macro, at: i).action
                                }
                            }
                        }
                        .padding(.horizontal, OneUI.rowInset).padding(.top, 10).padding(.bottom, 4)
                        OneUIDivider(inset: OneUI.rowInset)
                        ActionEditorView(
                            action: Binding(
                                get: { steps.indices.contains(i) ? steps[i] : SettingsDraft.defaultAction(.launchApp) },
                                set: { action = SettingsDraft.setStep(macro, at: i, $0).action }),
                            apps: apps,
                            allowMacro: false,
                            label: "\(label) 단계 \(i + 1)")
                    }
                    // 단계 블록은 카드보다 어두운 면으로 한 단계 안쪽임을 보인다
                    .background(pal.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(pal.line))
                    .transition(.scale(scale: 0.92, anchor: .top).combined(with: .opacity))
                }
                OneUIPillButton(title: "+ 단계 추가 (\(steps.count)/\(Limits.maxMacroSteps))", symbol: "plus") {
                    chewyChange {
                        stepIDs.append(afterCount: steps.count)
                        action = SettingsDraft.addStep(macro).action
                    }
                }
                .disabled(steps.count >= Limits.maxMacroSteps)
                .accessibilityLabel("매크로 단계 추가")
            }
            .padding(.horizontal, OneUI.rowInset).padding(.vertical, 12)
        }
    }
}

/// 단계 id 목록. 개수가 어긋나면(종류 변경 등 다른 경로로 단계가 바뀜) 새로 만든다. 화면 갱신을 일으키지 않는 순수 저장소다.
private final class StepIDs: ObservableObject {
    private var ids: [UUID] = []

    func reconciled(count: Int) -> [UUID] {
        if ids.count != count { ids = (0..<count).map { _ in UUID() } }
        return ids
    }

    func swap(_ a: Int, _ b: Int) {
        guard ids.indices.contains(a), ids.indices.contains(b) else { return }
        ids.swapAt(a, b)
    }

    func remove(_ i: Int) {
        guard ids.indices.contains(i) else { return }
        ids.remove(at: i)
    }

    func append(afterCount count: Int) {
        if ids.count == count { ids.append(UUID()) }
    }
}

/// 검색어 상태(SwiftUI 의 @State 매크로는 명령줄 도구만 있는 빌드 환경에서 쓸 수 없다)
private final class AppSearch: ObservableObject {
    @Published var query = ""
}

/// 설치된 앱 검색 선택기. 한글 이름·영문 이름·번들 ID 어느 쪽으로든 찾는다.
private struct AppPickerView: View {
    @Environment(\.settingsPalette) private var pal
    let apps: [InstalledApp]
    let selected: String?
    let label: String
    let onPick: (InstalledApp) -> Void
    @StateObject private var search = AppSearch()

    var body: some View {
        let shown = apps.filter { SettingsDraft.matches($0, query: search.query) }
        VStack(alignment: .leading, spacing: 8) {
            TextField("설치된 앱 검색", text: $search.query)
                .oneUIField()
                .accessibilityLabel("\(label): 설치된 앱 검색")
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if shown.isEmpty {
                        Text(apps.isEmpty ? "설치된 앱 목록을 불러오지 못했습니다" : "검색 결과가 없습니다")
                            .foregroundStyle(pal.muted)
                            .padding(12)
                    }
                    ForEach(shown) { app in
                        AppPickerRow(app: app, isSelected: app.bundleId == selected) { onPick(app) }
                    }
                }
                // 검색어를 칠 때 행이 튀지 않도록 바깥(예: 선택 변경)에서 내려오는 애니메이션을 끊는다
                .transaction { $0.animation = nil }
            }
            .frame(height: 150)
            .background(pal.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(pal.line))
            .accessibilityLabel("\(label): 설치된 앱 목록")
        }
    }
}

private struct AppPickerRow: View {
    @Environment(\.settingsPalette) private var pal
    let app: InstalledApp
    let isSelected: Bool
    let onPick: () -> Void

    var body: some View {
        Button(action: onPick) {
            HStack {
                Text(app.name).foregroundStyle(pal.text)
                Spacer(minLength: 8)
                Text(app.bundleId).font(.caption).foregroundStyle(pal.muted).lineLimit(1)
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(pal.accentText)
                    .scaleEffect(isSelected ? 1 : 0.2)
                    .opacity(isSelected ? 1 : 0)
                    .frame(width: 12)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? pal.selection : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(SquishButtonStyle(pressedScale: 0.99))
        // 선택 표시만 쫀득하게: 이 값이 바뀔 때만 애니메이션한다(필터링으로 행이 생기고 사라지는 건 목록의 transaction 이 막는다)
        .animation(Motion.animation(Motion.chewy), value: isSelected)
        .accessibilityLabel("\(app.name), \(app.bundleId)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
