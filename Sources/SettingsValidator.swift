import Foundation

/// http/https URL 만 허용한다. 설정 검증과 실행 시점 검사가 같은 규칙을 쓴다(파일을 손으로 고쳐도 다른 스킴이 실행되지 않게).
func isHttpURL(_ value: String) -> Bool {
    guard let url = URL(string: value), let scheme = url.scheme?.lowercased() else { return false }
    guard scheme == "http" || scheme == "https" else { return false }
    return !(url.host ?? "").isEmpty
}

/// 설정 검증. Electron 판 zod 스키마(src/shared/schema.ts)와 같은 제약을 걸고,
/// 위치 문자열은 설정 창 issues.ts 와 같은 형식(`탭 "고정 앱" > 슬롯 3 > URL: …`)으로 만든다.
enum SettingsValidator {
    /// 문제가 없으면 빈 배열
    static func validate(_ settings: Settings) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []

        func general(_ field: String, _ message: String) {
            issues.append(ValidationIssue(tabIndex: nil, slotIndex: nil, text: "\(field): \(message)"))
        }

        if settings.schemaVersion != Limits.schemaVersion { general("스키마 버전", Message.invalid) }
        if settings.platform != "darwin" { general("플랫폼", Message.invalid) }
        if settings.shortcut.isEmpty {
            general("단축키", Message.empty)
        } else if !Accelerator.isWellFormed(settings.shortcut) {
            general("단축키", "해석할 수 없는 단축키입니다(수정키와 키가 모두 필요합니다)")
        }
        if !Limits.alphaRange.contains(settings.overlay.alpha) { general("패널 투명도", Message.range) }
        if !Limits.radiusRange.contains(settings.overlay.radius) { general("모서리", Message.range) }
        // 크기는 파이·오비트 각자의 값을 모두 검사한다(독립 범위만; 조합 보정은 그릴 때와 슬라이더에서).
        for (theme, sizes) in [("파이", settings.overlay.pieSizes), ("오비트", settings.overlay.orbitSizes)] {
            if !Limits.ringRange.contains(sizes.ring) { general("\(theme) 바깥 크기", Message.range) }
            if !Limits.centerAbsoluteRange.contains(sizes.center) { general("\(theme) 중앙 원 크기", Message.range) }
            if !Limits.centerBorderRange.contains(sizes.border) { general("\(theme) 중앙 원 테두리", Message.range) }
        }
        if FocusColors.normalized(settings.overlay.focusHex) == nil { general("포커스 색", Message.invalid) }
        if settings.overlay.slotCount != Limits.slots { general("슬롯 수", Message.invalid) }

        if settings.tabs.isEmpty { general("탭", Message.tooFewItems) }
        if settings.tabs.count > Limits.maxTabs { general("탭", Message.tooManyItems) }

        var tabIds = Set<String>()
        for (tabIndex, tab) in settings.tabs.enumerated() {
            let tabLabel = "탭 \"\(tab.name)\""

            func tabIssue(_ field: String, _ message: String) {
                issues.append(ValidationIssue(tabIndex: tabIndex, slotIndex: nil, text: "\(tabLabel) > \(field): \(message)"))
            }

            if !isValidTabId(tab.id) { tabIssue("식별자", "탭 id 는 영문/숫자/-/_ 1~32자") }
            if !(1...20).contains(tab.name.utf16.count) { tabIssue("이름", tab.name.isEmpty ? Message.empty : Message.tooLong) }
            if !tabIds.insert(tab.id).inserted { tabIssue("식별자", "탭 id 중복: \(tab.id)") }
            if tab.slots.count > Limits.slots { tabIssue("슬롯", Message.tooManyItems) }

            var slotIds = Set<String>()
            for (slotIndex, slot) in tab.slots.enumerated() {
                let prefix = "\(tabLabel) > 슬롯 \(slotIndex + 1)"

                func slotIssue(_ parts: [String], _ message: String) {
                    issues.append(ValidationIssue(tabIndex: tabIndex, slotIndex: slotIndex, text: "\((CollectionOfOne(prefix) + parts).joined(separator: " > ")): \(message)"))
                }

                if !(1...64).contains(slot.id.utf16.count) {
                    slotIssue(["식별자"], slot.id.isEmpty ? Message.empty : Message.tooLong)
                }
                if !(1...40).contains(slot.name.utf16.count) {
                    slotIssue(["이름"], slot.name.isEmpty ? Message.empty : Message.tooLong)
                }
                if let label = slot.label, !(1...3).contains(label.utf16.count) {
                    slotIssue(["라벨"], label.isEmpty ? Message.empty : Message.tooLong)
                }
                if !slotIds.insert(slot.id).inserted { slotIssue(["식별자"], "슬롯 id 중복: \(slot.id)") }

                for problem in actionProblems(slot.action, step: nil) { slotIssue(problem.path, problem.message) }
            }
        }
        return issues
    }

    // MARK: - 내부

    private enum Message {
        static let empty = "비워 둘 수 없습니다"
        static let tooLong = "너무 깁니다"
        static let range = "허용 범위를 벗어났습니다"
        static let invalid = "값이 올바르지 않습니다"
        static let tooFewItems = "항목이 부족합니다"
        static let tooManyItems = "항목이 너무 많습니다"
    }

    private static func isValidTabId(_ id: String) -> Bool {
        let units = id.unicodeScalars
        guard (1...32).contains(units.count) else { return false }
        return units.allSatisfy { ("a"..."z").contains($0) || ("A"..."Z").contains($0) || ("0"..."9").contains($0) || $0 == "-" || $0 == "_" }
    }

    private struct Problem {
        var path: [String]
        var message: String
    }

    private static func bundleIdProblem(_ value: String, _ path: [String]) -> Problem? {
        if value.isEmpty { return Problem(path: path + ["번들 ID"], message: Message.empty) }
        if value.utf16.count > 255 { return Problem(path: path + ["번들 ID"], message: Message.tooLong) }
        return nil
    }

    /// `step` 이 있으면 매크로 안의 단계(1부터 센 번호)다. 단계에는 단일 액션만 올 수 있다.
    private static func actionProblems(_ action: Action, step: Int?) -> [Problem] {
        let base = step.map { ["매크로 단계 \($0)"] } ?? []
        var out: [Problem] = []
        switch action {
        case let .activateApp(bundleId, pid):
            if step != nil {
                out.append(Problem(path: base + ["종류"], message: "매크로 단계에는 앱 전환(activate_app)을 쓸 수 없습니다"))
                break
            }
            if let p = bundleIdProblem(bundleId, base) { out.append(p) }
            if let pid, pid <= 0 { out.append(Problem(path: base + ["pid"], message: Message.range)) }
        case let .launchApp(bundleId, appPath):
            if (bundleId == nil) == (appPath == nil) {
                out.append(Problem(path: base, message: "launch_app 은 bundleId 또는 appPath 중 정확히 하나가 필요합니다"))
            }
            if let bundleId, let p = bundleIdProblem(bundleId, base) { out.append(p) }
            if let appPath {
                if appPath.isEmpty {
                    out.append(Problem(path: base + ["앱 경로"], message: Message.empty))
                } else if !appPath.hasSuffix(".app") {
                    out.append(Problem(path: base + ["앱 경로"], message: Message.invalid))
                }
            }
        case let .openURL(url):
            if !isHttpURL(url) { out.append(Problem(path: base + ["URL"], message: "http/https URL 만 허용됩니다")) }
        case let .clipboardText(text):
            if text.utf16.count > 10_000 { out.append(Problem(path: base + ["텍스트"], message: Message.tooLong)) }
        case let .macroSequence(_, steps):
            if step != nil {
                out.append(Problem(path: base + ["종류"], message: "매크로 안에 매크로를 넣을 수 없습니다"))
                break
            }
            if steps.isEmpty { out.append(Problem(path: ["단계"], message: Message.tooFewItems)) }
            if steps.count > Limits.maxMacroSteps { out.append(Problem(path: ["단계"], message: Message.tooManyItems)) }
            for (index, inner) in steps.enumerated() { out += actionProblems(inner, step: index + 1) }
        }
        return out
    }
}
