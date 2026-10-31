import Foundation

/// 슬롯 타일 약어. 여러 단어면 앞 두 단어의 첫 글자, 한 단어면 앞 두 글자(대문자). 빈 이름이면 빈 문자열.
/// Deck(오버레이)과 설정 창 미리보기가 같은 규칙을 쓴다.
func slotInitials(_ name: String) -> String {
    let words = name.split(whereSeparator: { $0.isWhitespace })
    let chars: [Character]
    if words.count >= 2 {
        chars = [words[0].first, words[1].first].compactMap { $0 }
    } else if let word = words.first {
        chars = Array(word.prefix(2))
    } else {
        chars = []
    }
    return String(chars).uppercased()
}
