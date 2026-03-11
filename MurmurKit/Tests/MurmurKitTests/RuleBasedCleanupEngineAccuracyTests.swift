import Testing
@testable import MurmurKit

@Test("Balanced filler policy preserves meaning-bearing like in noun phrase")
func balancedPolicyPreservesLikeInNounPhrase() async throws {
    let cleaned = try await runLocalCleanup(
        text: "From the respect paid her on all sides she seemed like a queen.",
        fillerPolicy: .balanced
    )

    #expect(cleaned.text == "From the respect paid her on all sides she seemed like a queen.")
    #expect(cleaned.removedFillers.isEmpty)
    #expect(cleaned.edits.contains(where: { $0.kind == .fillerRemoval && $0.from.caseInsensitiveCompare("like") == .orderedSame }) == false)
}

@Test("Balanced filler policy preserves like before determiner")
func balancedPolicyPreservesLikeBeforeDeterminer() async throws {
    let cleaned = try await runLocalCleanup(
        text: "Two innocent babies like that.",
        fillerPolicy: .balanced
    )

    #expect(cleaned.text == "Two innocent babies like that.")
    #expect(cleaned.removedFillers.isEmpty)
    #expect(cleaned.edits.contains(where: { $0.kind == .fillerRemoval && $0.from.caseInsensitiveCompare("like") == .orderedSame }) == false)
}

@Test("Balanced filler policy preserves like as verb complement")
func balancedPolicyPreservesLikeAsVerbComplement() async throws {
    let cleaned = try await runLocalCleanup(
        text: "The twin brother did something she didn't like and she turned his picture to the wall.",
        fillerPolicy: .balanced
    )

    #expect(cleaned.text == "The twin brother did something she didn't like and she turned his picture to the wall.")
    #expect(cleaned.removedFillers.isEmpty)
    #expect(cleaned.edits.contains(where: { $0.kind == .fillerRemoval && $0.from.caseInsensitiveCompare("like") == .orderedSame }) == false)
}

@Test("Balanced filler policy preserves multiple meaning-bearing like occurrences")
func balancedPolicyPreservesMultipleMeaningBearingLikes() async throws {
    let cleaned = try await runLocalCleanup(
        text: "I'd like to see what this lovely furniture looks like without such quantities of dust all over it.",
        fillerPolicy: .balanced
    )

    #expect(cleaned.text == "I'd like to see what this lovely furniture looks like without such quantities of dust all over it.")
    #expect(cleaned.removedFillers.isEmpty)
    #expect(cleaned.edits.contains(where: { $0.kind == .fillerRemoval && $0.from.caseInsensitiveCompare("like") == .orderedSame }) == false)
}

@Test("Balanced filler policy removes standalone interjectional like")
func balancedPolicyRemovesInterjectionalLike() async throws {
    let cleaned = try await runLocalCleanup(
        text: "Like, we should head out now.",
        fillerPolicy: .balanced
    )

    #expect(cleaned.text == "we should head out now.")
    #expect(cleaned.removedFillers == ["like"])
    #expect(cleaned.text.hasPrefix(",") == false)
    #expect(cleaned.edits.contains(where: { $0.kind == .fillerRemoval && $0.from.caseInsensitiveCompare("like") == .orderedSame }))
}

@Test("Balanced filler policy removes um and uh disfluencies")
func balancedPolicyRemovesUmAndUh() async throws {
    let cleaned = try await runLocalCleanup(
        text: "Um I think uh this should stay clear.",
        fillerPolicy: .balanced
    )

    #expect(cleaned.text == "I think this should stay clear.")
    #expect(cleaned.removedFillers == ["um", "uh"])
    #expect(cleaned.edits.filter { $0.kind == .fillerRemoval }.count == 2)
}

// MARK: - Context-Aware "you know" Tests

@Test("Balanced policy preserves 'you know' before article")
func balancedPolicyPreservesYouKnowBeforeArticle() async throws {
    let cleaned = try await runLocalCleanup(
        text: "you know the answer to that question",
        fillerPolicy: .balanced
    )
    #expect(cleaned.text == "you know the answer to that question")
    #expect(cleaned.removedFillers.isEmpty)
}

@Test("Balanced policy preserves 'you know' before wh-word")
func balancedPolicyPreservesYouKnowBeforeWhWord() async throws {
    let cleaned = try await runLocalCleanup(
        text: "you know what I think about that",
        fillerPolicy: .balanced
    )
    #expect(cleaned.text == "you know what I think about that")
    #expect(cleaned.removedFillers.isEmpty)
}

@Test("Balanced policy preserves 'you know' before 'how'")
func balancedPolicyPreservesYouKnowBeforeHow() async throws {
    let cleaned = try await runLocalCleanup(
        text: "you know how it works",
        fillerPolicy: .balanced
    )
    #expect(cleaned.text == "you know how it works")
    #expect(cleaned.removedFillers.isEmpty)
}

@Test("Balanced policy removes filler 'you know' at end of clause")
func balancedPolicyRemovesFillerYouKnow() async throws {
    let candidate = buildCandidate(
        text: "it was really hard you know",
        fillerPolicy: .balanced
    )
    #expect(candidate.text == "it was really hard")
    #expect(candidate.removedFillers == ["you know"])
}

@Test("Balanced policy removes filler 'you know' mid-sentence")
func balancedPolicyRemovesFillerYouKnowMidSentence() async throws {
    let candidate = buildCandidate(
        text: "I was you know trying to fix it",
        fillerPolicy: .balanced
    )
    #expect(candidate.text == "I was trying to fix it")
    #expect(candidate.removedFillers == ["you know"])
}

// MARK: - Context-Aware "I mean" Tests

@Test("Aggressive policy preserves 'I mean' before pronoun")
func aggressivePolicyPreservesIMeanBeforePronoun() async throws {
    let candidate = buildCandidate(
        text: "I mean it when I say that",
        fillerPolicy: .aggressive
    )
    #expect(candidate.text == "I mean it when I say that")
    #expect(!candidate.removedFillers.contains("i mean"))
}

@Test("Aggressive policy preserves 'I mean' before 'the'")
func aggressivePolicyPreservesIMeanBeforeThe() async throws {
    let candidate = buildCandidate(
        text: "I mean the one on the left",
        fillerPolicy: .aggressive
    )
    #expect(candidate.text == "I mean the one on the left")
    #expect(!candidate.removedFillers.contains("i mean"))
}

@Test("Aggressive policy removes filler 'I mean' before non-safe word")
func aggressivePolicyRemovesFillerIMean() async throws {
    let candidate = buildCandidate(
        text: "I mean sure let's go",
        fillerPolicy: .aggressive
    )
    #expect(candidate.text == "sure let's go")
    #expect(candidate.removedFillers.contains("i mean"))
}

// MARK: - Context-Aware "sort of" / "kind of" Tests

@Test("Aggressive policy preserves 'kind of' before article")
func aggressivePolicyPreservesKindOfBeforeArticle() async throws {
    let candidate = buildCandidate(
        text: "what kind of a dog is that",
        fillerPolicy: .aggressive
    )
    #expect(candidate.text == "what kind of a dog is that")
    #expect(!candidate.removedFillers.contains("kind of"))
}

@Test("Aggressive policy preserves 'sort of' before 'thing'")
func aggressivePolicyPreservesSortOfBeforeThing() async throws {
    let candidate = buildCandidate(
        text: "it's a sort of thing you just have to see",
        fillerPolicy: .aggressive
    )
    #expect(candidate.text == "it's a sort of thing you just have to see")
    #expect(!candidate.removedFillers.contains("sort of"))
}

@Test("Aggressive policy removes filler 'kind of' before adjective")
func aggressivePolicyRemovesFillerKindOf() async throws {
    let candidate = buildCandidate(
        text: "it was kind of weird honestly",
        fillerPolicy: .aggressive
    )
    #expect(candidate.text == "it was weird honestly")
    #expect(candidate.removedFillers.contains("kind of"))
}

@Test("Aggressive policy removes filler 'sort of' mid-sentence")
func aggressivePolicyRemovesFillerSortOf() async throws {
    let candidate = buildCandidate(
        text: "I sort of expected that to happen",
        fillerPolicy: .aggressive
    )
    #expect(candidate.text == "I expected that to happen")
    #expect(candidate.removedFillers.contains("sort of"))
}

// MARK: - Balanced policy does NOT touch aggressive-only fillers

@Test("Balanced policy does not remove 'I mean' or 'kind of'")
func balancedPolicyLeavesAggressiveFillers() async throws {
    let cleaned = try await runLocalCleanup(
        text: "I mean it's kind of hard to explain",
        fillerPolicy: .balanced
    )
    #expect(cleaned.text == "I mean it's kind of hard to explain")
    #expect(cleaned.removedFillers.isEmpty)
}

private func runLocalCleanup(
    text: String,
    fillerPolicy: FillerPolicy
) async throws -> CleanTranscript {
    let engine = RuleBasedCleanupEngine()
    let profile = StyleProfile(
        name: "Accuracy Fixture",
        tone: .natural,
        structureMode: .natural,
        fillerPolicy: fillerPolicy,
        commandPolicy: .passthrough
    )

    return try await engine.cleanup(
        raw: RawTranscript(text: text),
        profile: profile,
        lexicon: PersonalLexicon(entries: [])
    )
}

/// Tests filler removal directly without the ranker choosing a different candidate.
private func buildCandidate(
    text: String,
    fillerPolicy: FillerPolicy
) -> CleanupCandidate {
    let engine = RuleBasedCleanupEngine()
    let profile = StyleProfile(
        name: "Accuracy Fixture",
        tone: .natural,
        structureMode: .natural,
        fillerPolicy: fillerPolicy,
        commandPolicy: .passthrough
    )

    return engine.buildCandidate(
        raw: RawTranscript(text: text),
        profile: profile,
        lexicon: PersonalLexicon(entries: []),
        rulePathID: "test"
    )
}
