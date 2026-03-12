import Foundation
import Testing
@testable import VoceKit

private let testConfiguration = PressToTalkTailPolicy.Configuration(
    minimumTailDuration: 0.25,
    maximumTailDuration: 1.0,
    silenceGraceDuration: 0.18,
    idleGraceDuration: 0.04,
    speechActivityFloor: 0.002
)

@Test("PressToTalkTailPolicy keeps full capture before stop is requested")
func pressToTalkTailPolicyCapturesNormallyBeforeStop() {
    let policy = PressToTalkTailPolicy(configuration: testConfiguration)
    let decision = policy.captureDecision(
        for: .init(startTime: 1.0, endTime: 1.1, duration: 0.1)
    )

    #expect(decision.allowedDuration == 0.1)
}

@Test("PressToTalkTailPolicy trims buffers that cross the hard tail cutoff")
func pressToTalkTailPolicyTrimsAtHardTailCutoff() {
    var policy = PressToTalkTailPolicy(configuration: testConfiguration)
    policy.requestStop(at: 5.0)

    let decision = policy.captureDecision(
        for: .init(startTime: 5.95, endTime: 6.05, duration: 0.1)
    )

    #expect(abs(decision.allowedDuration - 0.05) < 0.0001)
}

@Test("PressToTalkTailPolicy waits through the minimum tail before declaring silence complete")
func pressToTalkTailPolicyHonorsMinimumTail() {
    var policy = PressToTalkTailPolicy(configuration: testConfiguration)
    policy.requestStop(at: 10.0)
    policy.incrementPendingAudioBuffers()
    policy.decrementPendingAudioBuffers()
    policy.noteAcceptedAudio(
        timing: .init(startTime: 10.01, endTime: 10.05, duration: 0.04),
        acceptedDuration: 0.04,
        rms: 0
    )

    #expect(policy.shouldFinishWaiting(at: 10.20) == false)
    #expect(policy.shouldFinishWaiting(at: 10.43) == true)
}

@Test("PressToTalkTailPolicy extends capture until silence after post-release speech")
func pressToTalkTailPolicyWaitsForSilenceAfterAudibleTail() {
    var policy = PressToTalkTailPolicy(configuration: testConfiguration)
    policy.requestStop(at: 20.0)
    policy.incrementPendingAudioBuffers()
    policy.decrementPendingAudioBuffers()
    policy.noteAcceptedAudio(
        timing: .init(startTime: 20.22, endTime: 20.30, duration: 0.08),
        acceptedDuration: 0.08,
        rms: 0.01
    )

    #expect(policy.shouldFinishWaiting(at: 20.40) == false)
    #expect(policy.shouldFinishWaiting(at: 20.49) == true)
}

@Test("PressToTalkTailPolicy hard-stops after the maximum tail if speech never settles")
func pressToTalkTailPolicyHardStopsAtMaximumTail() {
    var policy = PressToTalkTailPolicy(configuration: testConfiguration)
    policy.requestStop(at: 30.0)
    policy.incrementPendingAudioBuffers()
    policy.decrementPendingAudioBuffers()
    policy.noteAcceptedAudio(
        timing: .init(startTime: 30.90, endTime: 30.98, duration: 0.08),
        acceptedDuration: 0.08,
        rms: 0.02
    )

    #expect(policy.shouldFinishWaiting(at: 30.99) == false)
    #expect(policy.shouldFinishWaiting(at: 31.04) == true)
}
