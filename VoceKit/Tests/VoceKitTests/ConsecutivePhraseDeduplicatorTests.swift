import Testing
@testable import VoceKit

@Test("Deduplicator collapses repeated adjacent clauses")
func deduplicatorCollapsesRepeatedClause() {
    let result = ConsecutivePhraseDeduplicator.collapse(
        "Okay, so at first I see a hold the talk and then like a time okay, so at first I see a hold the talk and then like a time Or something like that."
    )

    #expect(result == "Okay, so at first I see a hold the talk and then like a time Or something like that.")
}

@Test("Deduplicator preserves short intentional repetition")
func deduplicatorKeepsShortRepetition() {
    let result = ConsecutivePhraseDeduplicator.collapse("very very good")

    #expect(result == "very very good")
}
