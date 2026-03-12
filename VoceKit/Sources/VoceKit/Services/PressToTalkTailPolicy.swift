import Foundation

public struct PressToTalkTailPolicy: Sendable {
    public struct Configuration: Sendable, Equatable {
        public let minimumTailDuration: TimeInterval
        public let maximumTailDuration: TimeInterval
        public let silenceGraceDuration: TimeInterval
        public let idleGraceDuration: TimeInterval
        public let speechActivityFloor: Float

        public init(
            minimumTailDuration: TimeInterval,
            maximumTailDuration: TimeInterval,
            silenceGraceDuration: TimeInterval,
            idleGraceDuration: TimeInterval,
            speechActivityFloor: Float
        ) {
            self.minimumTailDuration = minimumTailDuration
            self.maximumTailDuration = maximumTailDuration
            self.silenceGraceDuration = silenceGraceDuration
            self.idleGraceDuration = idleGraceDuration
            self.speechActivityFloor = speechActivityFloor
        }
    }

    public struct CaptureTiming: Sendable, Equatable {
        public let startTime: TimeInterval
        public let endTime: TimeInterval
        public let duration: TimeInterval

        public init(startTime: TimeInterval, endTime: TimeInterval, duration: TimeInterval) {
            self.startTime = startTime
            self.endTime = endTime
            self.duration = duration
        }
    }

    public struct CaptureDecision: Sendable, Equatable {
        public let allowedDuration: TimeInterval

        public init(allowedDuration: TimeInterval) {
            self.allowedDuration = allowedDuration
        }
    }

    public struct Snapshot: Sendable, Equatable {
        public let stopRequestedTime: TimeInterval?
        public let lastBufferTime: TimeInterval
        public let lastAudibleTime: TimeInterval
        public let pendingAudioBuffers: Int

        public init(
            stopRequestedTime: TimeInterval?,
            lastBufferTime: TimeInterval,
            lastAudibleTime: TimeInterval,
            pendingAudioBuffers: Int
        ) {
            self.stopRequestedTime = stopRequestedTime
            self.lastBufferTime = lastBufferTime
            self.lastAudibleTime = lastAudibleTime
            self.pendingAudioBuffers = pendingAudioBuffers
        }
    }

    public let configuration: Configuration
    private var stopRequestedTime: TimeInterval?
    private var lastBufferTime: TimeInterval = 0
    private var lastAudibleTime: TimeInterval = 0
    private var pendingAudioBuffers = 0

    public init(configuration: Configuration) {
        self.configuration = configuration
    }

    public mutating func reset() {
        stopRequestedTime = nil
        lastBufferTime = 0
        lastAudibleTime = 0
        pendingAudioBuffers = 0
    }

    public mutating func requestStop(at time: TimeInterval) {
        stopRequestedTime = time
    }

    public func captureDecision(for timing: CaptureTiming) -> CaptureDecision {
        guard let stopRequestedTime else {
            return CaptureDecision(allowedDuration: timing.duration)
        }

        let cutoffTime = stopRequestedTime + configuration.maximumTailDuration
        if timing.startTime >= cutoffTime {
            return CaptureDecision(allowedDuration: 0)
        }

        if timing.endTime <= cutoffTime {
            return CaptureDecision(allowedDuration: timing.duration)
        }

        let allowedDuration = max(0, min(timing.duration, cutoffTime - timing.startTime))
        return CaptureDecision(allowedDuration: allowedDuration)
    }

    public mutating func noteAcceptedAudio(
        timing: CaptureTiming,
        acceptedDuration: TimeInterval,
        rms: Float
    ) {
        lastBufferTime = timing.endTime
        if acceptedDuration > 0, rms >= configuration.speechActivityFloor {
            lastAudibleTime = timing.endTime
        }
    }

    public mutating func incrementPendingAudioBuffers() {
        pendingAudioBuffers += 1
    }

    public mutating func decrementPendingAudioBuffers() {
        pendingAudioBuffers = max(0, pendingAudioBuffers - 1)
    }

    public func shouldFinishWaiting(at time: TimeInterval) -> Bool {
        guard let stopRequestedTime else {
            return true
        }

        let idleSatisfied = pendingAudioBuffers == 0
            && lastBufferTime > 0
            && time - lastBufferTime >= configuration.idleGraceDuration
        let hardStopSatisfied = time >= stopRequestedTime + configuration.maximumTailDuration
        let minimumTailSatisfied = time >= stopRequestedTime + configuration.minimumTailDuration
        let silenceReferenceTime = max(stopRequestedTime, lastAudibleTime)
        let silenceSatisfied = minimumTailSatisfied
            && time >= silenceReferenceTime
            && time - silenceReferenceTime >= configuration.silenceGraceDuration

        return idleSatisfied && (hardStopSatisfied || silenceSatisfied)
    }

    public func snapshot() -> Snapshot {
        Snapshot(
            stopRequestedTime: stopRequestedTime,
            lastBufferTime: lastBufferTime,
            lastAudibleTime: lastAudibleTime,
            pendingAudioBuffers: pendingAudioBuffers
        )
    }
}
