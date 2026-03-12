import Testing
@testable import VoceKit

@Test("Ranker prefers meaning-preserving candidate over destructive filler removal")
func rankerPrefersMeaningPreservation() {
    let raw = "I'd like to see what this lovely furniture looks like without such quantities of dust all over it."
    let profile = StyleProfile(
        name: "Ranker",
        tone: .natural,
        structureMode: .natural,
        fillerPolicy: .balanced,
        commandPolicy: .passthrough
    )

    let safe = CleanupCandidate(
        text: raw,
        appliedEdits: [],
        removedFillers: [],
        rulePathID: "safe"
    )
    let destructive = CleanupCandidate(
        text: "I'd to see what this lovely furniture looks without such quantities of dust all over it.",
        appliedEdits: [.init(kind: .fillerRemoval, from: "like", to: "")],
        removedFillers: ["like", "like"],
        rulePathID: "destructive"
    )

    let ranker = LocalCleanupRanker()
    let safeScore = ranker.scoreCandidate(
        rawText: raw,
        candidate: safe,
        profile: profile
    )
    let destructiveScore = ranker.scoreCandidate(
        rawText: raw,
        candidate: destructive,
        profile: profile
    )
    let best = ranker.bestCandidate(
        rawText: raw,
        candidates: [destructive, safe],
        profile: profile
    )

    #expect(safeScore.semanticPreservationScore > destructiveScore.semanticPreservationScore)
    #expect(destructiveScore.editDistancePenalty > safeScore.editDistancePenalty)
    #expect(safeScore.totalScore > destructiveScore.totalScore)
    #expect(best.rulePathID == "safe")
}

@Test("Ranker penalizes command mutation when command policy is passthrough")
func rankerPrefersUnchangedCommandCandidate() {
    let raw = "/todo refactor parser"
    let profile = StyleProfile(
        name: "Ranker",
        tone: .technical,
        structureMode: .command,
        fillerPolicy: .balanced,
        commandPolicy: .passthrough
    )

    let unchanged = CleanupCandidate(
        text: raw,
        appliedEdits: [],
        removedFillers: [],
        rulePathID: "unchanged-command"
    )
    let rewritten = CleanupCandidate(
        text: "Todo: refactor parser",
        appliedEdits: [.init(kind: .commandTransform, from: "/todo", to: "Todo:")],
        removedFillers: [],
        rulePathID: "rewritten-command"
    )

    let ranker = LocalCleanupRanker()
    let unchangedScore = ranker.scoreCandidate(
        rawText: raw,
        candidate: unchanged,
        profile: profile
    )
    let rewrittenScore = ranker.scoreCandidate(
        rawText: raw,
        candidate: rewritten,
        profile: profile
    )
    let best = ranker.bestCandidate(
        rawText: raw,
        candidates: [rewritten, unchanged],
        profile: profile
    )

    #expect(rewrittenScore.commandSafetyPenalty > unchangedScore.commandSafetyPenalty)
    #expect(unchangedScore.totalScore > rewrittenScore.totalScore)
    #expect(best.rulePathID == "unchanged-command")
}

@Test("Ranker preserves meaning-bearing 'what I mean' tails")
func rankerPrefersCandidateThatKeepsWhatIMean() {
    let raw = "Alright, we've got another test to see if my speech gets clipped, which I'm really hoping it does not. Anyways, if you know what I mean."
    let profile = StyleProfile(
        name: "Ranker",
        tone: .natural,
        structureMode: .paragraph,
        fillerPolicy: .balanced,
        commandPolicy: .transform
    )

    let preserved = CleanupCandidate(
        text: raw,
        appliedEdits: [],
        removedFillers: [],
        rulePathID: "preserved"
    )
    let truncated = CleanupCandidate(
        text: "Alright, we've got another test to see if my speech gets clipped, which I'm really hoping it does not. Anyways, if you know what.",
        appliedEdits: [.init(kind: .fillerRemoval, from: "i mean", to: "")],
        removedFillers: ["i mean"],
        rulePathID: "truncated"
    )

    let ranker = LocalCleanupRanker()
    let preservedScore = ranker.scoreCandidate(
        rawText: raw,
        candidate: preserved,
        profile: profile
    )
    let truncatedScore = ranker.scoreCandidate(
        rawText: raw,
        candidate: truncated,
        profile: profile
    )
    let best = ranker.bestCandidate(
        rawText: raw,
        candidates: [truncated, preserved],
        profile: profile
    )

    #expect(preservedScore.semanticPreservationScore > truncatedScore.semanticPreservationScore)
    #expect(preservedScore.totalScore > truncatedScore.totalScore)
    #expect(best.rulePathID == "preserved")
}

@Test("Candidate generator emits deterministic, deduplicated candidate set")
func candidateGeneratorDeterministicDeduped() async throws {
    let raw = RawTranscript(text: "Like, I'd like to ship this, you know.")
    let profile = StyleProfile(
        name: "Generator",
        tone: .natural,
        structureMode: .natural,
        fillerPolicy: .balanced,
        commandPolicy: .passthrough
    )
    let lexicon = PersonalLexicon(entries: [])

    let generator = RuleBasedCleanupCandidateGenerator()
    let first = try await generator.generateCandidates(raw: raw, profile: profile, lexicon: lexicon)
    let second = try await generator.generateCandidates(raw: raw, profile: profile, lexicon: lexicon)

    #expect(first == second)
    #expect(first.isEmpty == false)
    #expect(first.first?.rulePathID == "raw-pass-through")
    #expect(first.contains(where: { !$0.removedFillers.isEmpty }))

    let uniqueTexts = Set(first.map(\.text))
    #expect(uniqueTexts.count == first.count)

    let uniquePaths = Set(first.map(\.rulePathID))
    #expect(uniquePaths.count == first.count)
}
