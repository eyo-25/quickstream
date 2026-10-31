import Foundation

// 의존성 없는 최소 테스트 하네스(XCTest 없이 swiftc 로 직접 빌드: tests/swift/run.sh).
// 각 영역은 자기 파일에서 run<Area>Tests() 를 정의하고, main.swift 가 모두 호출한다.

nonisolated(unsafe) var testFailures = 0
nonisolated(unsafe) var testChecks = 0
nonisolated(unsafe) var currentSection = ""

/// Electron 판이 실제로 쓰던 형태의 설정 파일(알 수 없는 키 포함). 소스 위치 기준이라 어디서 실행해도 같은 파일을 읽는다.
let electronSettingsFixturePath = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("fixtures/electron-settings.json").path

func section(_ name: String) { currentSection = name }

func check(_ condition: @autoclosure () -> Bool, _ message: String, file: StaticString = #file, line: UInt = #line) {
    testChecks += 1
    if !condition() {
        testFailures += 1
        FileHandle.standardError.write(Data("FAIL [\(currentSection)] \(message)  (\(file):\(line))\n".utf8))
    }
}

func checkEqual<T: Equatable>(_ actual: @autoclosure () -> T, _ expected: @autoclosure () -> T, _ message: String, file: StaticString = #file, line: UInt = #line) {
    let a = actual(), e = expected()
    testChecks += 1
    if a != e {
        testFailures += 1
        FileHandle.standardError.write(Data("FAIL [\(currentSection)] \(message): got \(a), expected \(e)  (\(file):\(line))\n".utf8))
    }
}

/// async 테스트를 동기 main 에서 돌린다
func runAsync(_ body: @escaping @Sendable () async -> Void) {
    let done = DispatchSemaphore(value: 0)
    Task.detached { await body(); done.signal() }
    done.wait()
}
