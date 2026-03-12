import Foundation

public enum ConsecutivePhraseDeduplicator {
    private static let minimumRepeatedTokenCount = 4
    private static let minimumRepeatedCharacterCount = 16

    public static func collapse(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }

        var tokens = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        guard tokens.count >= minimumRepeatedTokenCount * 2 else {
            return trimmed
        }

        var changed = true
        while changed {
            changed = false
            var index = 0

            while index < tokens.count {
                let maxSpan = (tokens.count - index) / 2
                guard maxSpan >= minimumRepeatedTokenCount else { break }

                var removedSpan = false
                for span in stride(from: maxSpan, through: minimumRepeatedTokenCount, by: -1) {
                    let lhs = Array(tokens[index..<(index + span)])
                    let rhs = Array(tokens[(index + span)..<(index + (span * 2))])
                    guard normalized(lhs) == normalized(rhs) else { continue }

                    let repeatedText = lhs.joined(separator: " ")
                    guard repeatedText.count >= minimumRepeatedCharacterCount else { continue }

                    tokens.removeSubrange((index + span)..<(index + (span * 2)))
                    changed = true
                    removedSpan = true
                    break
                }

                if !removedSpan {
                    index += 1
                }
            }
        }

        return tokens.joined(separator: " ")
    }

    private static func normalized(_ tokens: [String]) -> [String] {
        tokens.map {
            $0.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.symbols))
        }
    }
}
