@preconcurrency import AVFoundation
import Darwin
import Foundation
import MoonshineVoice
import VoceKit

/// Manages live microphone capture and streaming Moonshine transcription.
///
/// This intentionally stays close to Moonshine's upstream `MicTranscriber`
/// flow: each captured mic buffer is converted immediately and fed to the
/// stream without an intermediate batching timer.
final class MoonshineStreamingSession: @unchecked Sendable {
    private static let audioDrainTimeout: TimeInterval = 0.35
    private static let captureBoundaryWaitTimeout: TimeInterval = 0.55
    fileprivate static let captureTailTimeout: TimeInterval = 0.32
    private static let captureSilenceGracePeriod: TimeInterval = 0.12
    private static let captureIdleGracePeriod: TimeInterval = 0.04
    private static let captureBoundaryPollInterval: TimeInterval = 0.01
    private static let finalTranscriptSettleWindow: TimeInterval = 0.35
    private static let finalTranscriptPollInterval: TimeInterval = 0.05
    private static let speechActivityFloor: Float = 0.0035

    struct Configuration: Sendable {
        var modelDirectoryPath: String
        var modelArch: MoonshineModelPreset
    }

    private let config: Configuration
    private let onPartialText: @Sendable (String) -> Void
    private let captureStopState = CaptureStopState()

    // Accessed only on processingQueue.
    private let processingQueue = DispatchQueue(label: "voce.moonshine-stream", qos: .userInitiated)
    private let audioDrainGroup = DispatchGroup()
    private var stream: MoonshineVoice.Stream?
    private var latestTranscript: Transcript = .init()
    private var latestStreamError: Error?
    private var isStopped = false

    // Accessed on main thread.
    private var audioEngine: AVAudioEngine?

    init(config: Configuration, onPartialText: @escaping @Sendable (String) -> Void) {
        self.config = config
        self.onPartialText = onPartialText
    }

    /// Starts audio capture and streaming transcription.
    /// Must be called from the main thread.
    func start() throws {
        try ensureMicrophonePermission()

        try processingQueue.sync {
            let transcriber = try MoonshineTranscriberCache.shared.transcriber(for: config)
            let stream = try transcriber.createStream(updateInterval: 0.3)
            stream.addListener { [weak self] event in
                self?.handle(event: event)
            }
            try stream.start()

            self.stream = stream
            self.latestTranscript = .init()
            self.latestStreamError = nil
            self.isStopped = false
        }
        captureStopState.reset()

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)

        // Let Moonshine handle resampling internally. The probe showed our
        // app-side 24 kHz -> 16 kHz conversion path crushes AirPods input
        // amplitude, while the raw float samples are healthy.
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: inputFormat.sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw MoonshineTranscriptionError.unsupportedAudioFormat
        }

        let needsConversion = inputFormat.sampleRate != targetFormat.sampleRate
            || inputFormat.channelCount != targetFormat.channelCount
            || inputFormat.commonFormat != targetFormat.commonFormat
        let converter = needsConversion ? AVAudioConverter(from: inputFormat, to: targetFormat) : nil

        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: inputFormat) { [weak self] buffer, when in
            guard let self else { return }

            let bufferTiming = self.bufferTiming(
                frameLength: buffer.frameLength,
                sampleRate: inputFormat.sampleRate,
                time: when
            )
            let captureDecision = self.captureStopState.captureDecision(for: bufferTiming)
            guard captureDecision.allowedDuration > 0 else { return }

            let converted = self.convertBuffer(
                buffer,
                converter: converter,
                inputFormat: inputFormat,
                targetFormat: targetFormat
            )
            let trimmed = self.trimConvertedSamples(
                converted,
                allowedDuration: captureDecision.allowedDuration
            )
            let rms = Self.rootMeanSquare(for: trimmed.samples)
            self.captureStopState.noteTap(
                timing: bufferTiming,
                acceptedDuration: captureDecision.allowedDuration,
                rms: rms,
                speechActivityFloor: Self.speechActivityFloor
            )
            guard !trimmed.samples.isEmpty else { return }

            self.audioDrainGroup.enter()
            self.captureStopState.incrementPendingAudioBuffers()
            self.processingQueue.async { [weak self] in
                defer {
                    self?.captureStopState.decrementPendingAudioBuffers()
                    self?.audioDrainGroup.leave()
                }
                guard let self, !self.isStopped else { return }

                do {
                    try self.stream?.addAudio(
                        trimmed.samples,
                        sampleRate: Int32(trimmed.sampleRate.rounded())
                    )
                } catch {
                    self.latestStreamError = error
                }
            }
        }

        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            processingQueue.sync {
                stream?.close()
                stream = nil
                latestTranscript = .init()
                latestStreamError = nil
                isStopped = true
            }
            throw error
        }

        audioEngine = engine
    }

    /// Stops capture, finalises the transcript, and returns the result.
    /// Must be called from the main thread.
    func stop() throws -> RawTranscript {
        captureStopState.requestStop()
        waitForCaptureBoundary()
        tearDownAudio()
        _ = audioDrainGroup.wait(timeout: .now() + Self.audioDrainTimeout)

        return try processingQueue.sync {
            defer {
                stream?.close()
                stream = nil
                latestTranscript = .init()
                latestStreamError = nil
                isStopped = true
            }

            try stream?.stop()
            let finalTranscript = try settleFinalTranscript()
            latestTranscript = finalTranscript

            if finalTranscript.lines.isEmpty, let latestStreamError {
                throw latestStreamError
            }

            let rawTranscript = Self.buildRawTranscript(from: finalTranscript)
            if rawTranscript.text.isEmpty {
                throw MoonshineTranscriptionError.emptyLiveTranscript
            }

            return rawTranscript
        }
    }

    /// Cancels without producing a transcript.
    func cancel() {
        captureStopState.requestStop()
        tearDownAudio()
        processingQueue.sync {
            isStopped = true
            stream?.close()
            stream = nil
            latestTranscript = .init()
            latestStreamError = nil
        }
    }

    private func handle(event: TranscriptEvent) {
        if let transcriptError = event as? TranscriptError {
            latestStreamError = transcriptError.error
            return
        }

        let currentText = event.line.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !currentText.isEmpty else { return }

        let mergedLines = latestTranscript.lines
            .filter { $0.lineId != event.line.lineId } + [event.line]
        let orderedLines = mergedLines.sorted {
            if $0.startTime == $1.startTime {
                return $0.lineId < $1.lineId
            }
            return $0.startTime < $1.startTime
        }
        latestTranscript = Transcript(lines: orderedLines)

        let mergedText = orderedLines
            .map(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !mergedText.isEmpty else { return }

        DispatchQueue.main.async { [weak self] in
            self?.onPartialText(mergedText)
        }
    }

    private func convertBuffer(
        _ buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter?,
        inputFormat: AVAudioFormat,
        targetFormat: AVAudioFormat
    ) -> (samples: [Float], sampleRate: Double) {
        final class ConversionState: @unchecked Sendable {
            var didSupplyInput = false
        }

        guard let converter else {
            guard let channelData = buffer.floatChannelData?[0] else {
                return ([], inputFormat.sampleRate)
            }

            let samples = Array(
                UnsafeBufferPointer(start: channelData, count: Int(buffer.frameLength))
            )
            return (samples, inputFormat.sampleRate)
        }

        let capacity = AVAudioFrameCount(
            (Double(buffer.frameLength) * targetFormat.sampleRate / inputFormat.sampleRate).rounded(.up)
        ) + 256
        guard let convertedBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: capacity
        ) else {
            return ([], targetFormat.sampleRate)
        }

        let state = ConversionState()
        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if state.didSupplyInput {
                outStatus.pointee = .endOfStream
                return nil
            }

            state.didSupplyInput = true
            outStatus.pointee = .haveData
            return buffer
        }

        converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)

        guard error == nil, let channelData = convertedBuffer.floatChannelData?[0] else {
            return ([], targetFormat.sampleRate)
        }

        let samples = Array(
            UnsafeBufferPointer(start: channelData, count: Int(convertedBuffer.frameLength))
        )
        return (samples, targetFormat.sampleRate)
    }

    private func tearDownAudio() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
    }

    private func waitForCaptureBoundary() {
        let deadline = mach_absolute_time() + AVAudioTime.hostTime(forSeconds: Self.captureBoundaryWaitTimeout)
        let tailHostTime = AVAudioTime.hostTime(forSeconds: Self.captureTailTimeout)
        let silenceGraceHostTime = AVAudioTime.hostTime(forSeconds: Self.captureSilenceGracePeriod)
        let idleGraceHostTime = AVAudioTime.hostTime(forSeconds: Self.captureIdleGracePeriod)

        while mach_absolute_time() < deadline {
            let snapshot = captureStopState.snapshot()
            guard let stopRequestedHostTime = snapshot.stopRequestedHostTime else {
                return
            }

            let now = mach_absolute_time()
            let idleSatisfied = snapshot.pendingAudioBuffers == 0
                && snapshot.lastTapHostTime > 0
                && now &- snapshot.lastTapHostTime >= idleGraceHostTime
            let hardStopSatisfied = now >= stopRequestedHostTime &+ tailHostTime
            let silenceReferenceHostTime = max(stopRequestedHostTime, snapshot.lastAudibleHostTime)
            let silenceSatisfied = now >= silenceReferenceHostTime
                && now &- silenceReferenceHostTime >= silenceGraceHostTime

            if idleSatisfied && (hardStopSatisfied || silenceSatisfied) {
                return
            }

            Thread.sleep(forTimeInterval: Self.captureBoundaryPollInterval)
        }
    }

    private func settleFinalTranscript() throws -> Transcript {
        var settledTranscript = latestTranscript
        var settledSignature = transcriptSignature(for: settledTranscript)
        let deadline = Date().addingTimeInterval(Self.finalTranscriptSettleWindow)

        while true {
            let updatedTranscript = try stream?.updateTranscription(
                flags: TranscribeStreamFlags.flagForceUpdate
            ) ?? latestTranscript
            latestTranscript = updatedTranscript

            let updatedSignature = transcriptSignature(for: updatedTranscript)
            let changed = updatedSignature != settledSignature
            if changed {
                settledTranscript = updatedTranscript
                settledSignature = updatedSignature
            }

            let hasIncompleteLines = updatedTranscript.lines.contains { !$0.isComplete }
            if !hasIncompleteLines && !changed {
                return updatedTranscript
            }

            if Date() >= deadline {
                return changed ? updatedTranscript : settledTranscript
            }

            Thread.sleep(forTimeInterval: Self.finalTranscriptPollInterval)
        }
    }

    private func bufferTiming(
        frameLength: AVAudioFrameCount,
        sampleRate: Double,
        time: AVAudioTime?
    ) -> BufferTiming {
        let duration = Double(frameLength) / sampleRate
        if let time, time.hostTime != 0 {
            let startHostTime = time.hostTime
            let durationHostTime = AVAudioTime.hostTime(forSeconds: duration)
            return BufferTiming(
                startHostTime: startHostTime,
                endHostTime: startHostTime &+ durationHostTime,
                durationSeconds: duration
            )
        }

        let callbackHostTime = mach_absolute_time()
        let durationHostTime = AVAudioTime.hostTime(forSeconds: duration)
        let startHostTime = callbackHostTime > durationHostTime ? callbackHostTime - durationHostTime : 0
        return BufferTiming(
            startHostTime: startHostTime,
            endHostTime: callbackHostTime,
            durationSeconds: duration
        )
    }

    private func trimConvertedSamples(
        _ converted: (samples: [Float], sampleRate: Double),
        allowedDuration: TimeInterval
    ) -> (samples: [Float], sampleRate: Double) {
        guard allowedDuration > 0 else {
            return ([], converted.sampleRate)
        }

        let maxSamples = Int((allowedDuration * converted.sampleRate).rounded(.down))
        guard maxSamples < converted.samples.count else {
            return converted
        }

        return (Array(converted.samples.prefix(maxSamples)), converted.sampleRate)
    }

    private func transcriptSignature(for transcript: Transcript) -> String {
        transcript.lines
            .map { line in
                "\(line.lineId)|\(line.text)|\(line.isComplete)|\(line.startTime)|\(line.duration)"
            }
            .joined(separator: "\n")
    }

    private static func rootMeanSquare(for samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }

        let sumOfSquares = samples.reduce(into: Float.zero) { partialResult, sample in
            partialResult += sample * sample
        }
        return sqrt(sumOfSquares / Float(samples.count))
    }

    private static func buildRawTranscript(from transcript: Transcript) -> RawTranscript {
        let segments = transcript.lines.map { line in
            TranscriptSegment(
                startMS: Int(line.startTime * 1_000),
                endMS: Int((line.startTime + line.duration) * 1_000),
                text: line.text
            )
        }

        let text = transcript.lines
            .map(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let durationMS = Int(
            (transcript.lines.last.map { $0.startTime + $0.duration } ?? 0) * 1_000
        )
        return RawTranscript(text: text, segments: segments, durationMS: durationMS)
    }

    private func ensureMicrophonePermission() throws {
        let permissionStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if permissionStatus == .denied {
            throw MoonshineTranscriptionError.microphonePermissionDenied
        }

        if permissionStatus == .notDetermined {
            var permissionGranted = false
            let semaphore = DispatchSemaphore(value: 0)

            AVCaptureDevice.requestAccess(for: .audio) { granted in
                permissionGranted = granted
                semaphore.signal()
            }

            semaphore.wait()

            if !permissionGranted {
                throw MoonshineTranscriptionError.microphonePermissionDenied
            }
        }
    }
}

private struct BufferTiming: Sendable {
    let startHostTime: UInt64
    let endHostTime: UInt64
    let durationSeconds: TimeInterval
}

private struct CaptureDecision: Sendable {
    let allowedDuration: TimeInterval
}

private final class CaptureStopState: @unchecked Sendable {
    struct Snapshot: Sendable {
        let stopRequestedHostTime: UInt64?
        let lastTapHostTime: UInt64
        let lastAudibleHostTime: UInt64
        let pendingAudioBuffers: Int
    }

    private let lock = NSLock()
    private var stopRequestedHostTime: UInt64?
    private var lastTapHostTime: UInt64 = 0
    private var lastAudibleHostTime: UInt64 = 0
    private var pendingAudioBuffers: Int = 0

    func reset() {
        lock.lock()
        stopRequestedHostTime = nil
        lastTapHostTime = 0
        lastAudibleHostTime = 0
        pendingAudioBuffers = 0
        lock.unlock()
    }

    func requestStop() {
        lock.lock()
        stopRequestedHostTime = mach_absolute_time()
        lock.unlock()
    }

    func captureDecision(for timing: BufferTiming) -> CaptureDecision {
        lock.lock()
        let stopRequestedHostTime = stopRequestedHostTime
        lock.unlock()

        guard let stopRequestedHostTime else {
            return CaptureDecision(allowedDuration: timing.durationSeconds)
        }

        let cutoffHostTime = stopRequestedHostTime &+ AVAudioTime.hostTime(forSeconds: 0.32)

        if timing.startHostTime >= cutoffHostTime {
            return CaptureDecision(allowedDuration: 0)
        }

        if timing.endHostTime <= cutoffHostTime {
            return CaptureDecision(allowedDuration: timing.durationSeconds)
        }

        let allowedHostTime = cutoffHostTime &- timing.startHostTime
        let allowedDuration = max(0, min(timing.durationSeconds, AVAudioTime.seconds(forHostTime: allowedHostTime)))
        return CaptureDecision(allowedDuration: allowedDuration)
    }

    func noteTap(
        timing: BufferTiming,
        acceptedDuration: TimeInterval,
        rms: Float,
        speechActivityFloor: Float
    ) {
        lock.lock()
        lastTapHostTime = timing.endHostTime
        if acceptedDuration > 0, rms >= speechActivityFloor {
            lastAudibleHostTime = timing.endHostTime
        }
        lock.unlock()
    }

    func incrementPendingAudioBuffers() {
        lock.lock()
        pendingAudioBuffers += 1
        lock.unlock()
    }

    func decrementPendingAudioBuffers() {
        lock.lock()
        pendingAudioBuffers = max(0, pendingAudioBuffers - 1)
        lock.unlock()
    }

    func snapshot() -> Snapshot {
        lock.lock()
        let snapshot = Snapshot(
            stopRequestedHostTime: stopRequestedHostTime,
            lastTapHostTime: lastTapHostTime,
            lastAudibleHostTime: lastAudibleHostTime,
            pendingAudioBuffers: pendingAudioBuffers,
        )
        lock.unlock()
        return snapshot
    }
}
