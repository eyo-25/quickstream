import Foundation

// 영역별 테스트 진입점. 각 함수는 해당 담당 파일(tests/swift/<Area>Tests.swift)에 정의한다.
runCoreTests()
runOverlayTests()
runSettingsTests()
runUpdateTests()

print("checks: \(testChecks), failures: \(testFailures)")
exit(testFailures == 0 ? 0 : 1)
