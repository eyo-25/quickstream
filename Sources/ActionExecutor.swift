import AppKit

/// 액션 실행. 외부 효과(URL 열기, 클립보드)는 클로저로 주입받아 테스트에서 바꿔 끼운다.
enum ActionExecutor {
    static let systemOpenURL: (URL) async throws -> Void = { url in
        _ = try await NSWorkspace.shared.open(url, configuration: NSWorkspace.OpenConfiguration())
    }

    static let systemWriteClipboard: (String) -> Void = { text in
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    static func execute(
        _ action: Action,
        catalog: AppCatalog,
        openURL: (URL) async throws -> Void = systemOpenURL,
        writeClipboard: (String) -> Void = systemWriteClipboard
    ) async -> ActionResult {
        switch action {
        case let .activateApp(bundleId, pid):
            return await catalog.activate(bundleId: bundleId, pid: pid)

        case let .launchApp(bundleId, appPath):
            // 실행 중이면 앞으로, 꺼져 있으면 실행(카탈로그의 open 이 둘 다 처리)
            return await catalog.open(bundleId: bundleId, appPath: bundleId == nil ? (appPath ?? "") : nil)

        case let .openURL(value):
            // 설정 검증을 통과했더라도 파일을 직접 고친 경우를 대비해 실행 시점에 다시 확인한다
            guard isHttpURL(value), let url = URL(string: value) else { return .failure("허용되지 않는 URL: \(value)") }
            do {
                try await openURL(url)
                return .success
            } catch {
                return .failure(error.localizedDescription)
            }

        case let .clipboardText(text):
            writeClipboard(text)
            return .success

        case let .macroSequence(stopOnError, steps):
            var failures: [String] = []
            for (index, step) in steps.enumerated() {
                let result = await execute(step, catalog: catalog, openURL: openURL, writeClipboard: writeClipboard)
                if result.ok { continue }
                failures.append("\(index + 1)단계: \(result.error ?? "알 수 없는 오류")")
                if stopOnError { break }
            }
            return failures.isEmpty ? .success : .failure(failures.joined(separator: " / "))
        }
    }
}
