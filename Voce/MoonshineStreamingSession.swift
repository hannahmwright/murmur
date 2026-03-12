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
    private static let captureBoundaryWaitTimeout: TimeInterval = 1.35
    private static let captureBoundaryPollInterval: TimeInterval = 0.01
    private static let finalTranscriptSettleWindow: TimeInterval = 1.5
    private static let finalTranscriptStableWindow: TimeInterval = 0.25
    private static let finalTranscriptPollInterval: TimeInterval = 0.05
    private static let tailPolicyConfiguration = PressToTalkTailPolicy.Configuration(
        minimumTailDuration: 0.25,
        maximumTailDuration: 1.0,
        silenceGraceDuration: 0.18,
        idleGraceDuration: 0.04,
        speechActivityFloor: 0.002
    )

    struct Configuration: Sendable {
        var modelDirectoryPath: String
        var modelArch: MoonshineModelPreset
        var keepModelWarm: Bool = true
    }

    private let config: Configuration
    private let onPartialText: @Sendable (String) -> Void
    private let captureStopState: CaptureStopState
    private let diagnostics = StreamingStopDiagnostics()

    // Accessed only on processingQueue.
    private let processingQueue = DispatchQueue(label: "voce.moonshine-stream", qos: .userInitiated)
    private let audioDrainGroup = DispatchGroup()
    private var stream: MoonshineVoice.Stream?
    private var latestTranscript: Transcript = .init()
    private var latestStreamError: Error?
    private var isStopped = false

    // Accessed on main thread.
    private var audioEngine: AVAudioEngine?
    private var uncachedTranscriber: Transcriber?

    init(config: Configuration, onPartialText: @escaping @Sendable (String) -> Void) {
        self.config = config
        self.onPartialText = onPartialText
        self.captureStopState = CaptureStopState(configuration: Self.tailPolicyConfiguration)
    }

    /// Starts audio capture and streaming transcription.
    /// Must be called from the main thread.
    func start() throws {
        diagnostics.reset()
        diagnostics.record("start session modelArch=\(config.modelArch.rawValue) modelDirectory=\(config.modelDirectoryPath)")
        try ensureMicrophonePermission()

        try processingQueue.sync {
            let transcriber: Transcriber
            if config.keepModelWarm {
                transcriber = try MoonshineTranscriberCache.shared.transcriber(for: config)
            } else {
                transcriber = try Transcriber(
                    modelPath: config.modelDirectoryPath,
                    modelArch: config.modelArch.moonshineArch
                )
                uncachedTranscriber = transcriber
            }
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
        diagnostics.record(
            String(
                format: "audio input format sampleRate=%.1f channels=%d commonFormat=%d",
                inputFormat.sampleRate,
                inputFormat.channelCount,
                inputFormat.commonFormat.rawValue
            )
        )

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
            if self.captureStopState.hasPendingStopRequest {
                self.diagnostics.record(
                    String(
                        format: "tail buffer start=%.3f end=%.3f duration=%.3f allowed=%.3f",
                        bufferTiming.startTime,
                        bufferTiming.endTime,
                        bufferTiming.duration,
                        captureDecision.allowedDuration
                    )
                )
            }
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
            let averageRMS = Self.rootMeanSquare(for: trimmed.samples)
            let activityRMS = Self.windowedActivityRMS(
                for: trimmed.samples,
                sampleRate: trimmed.sampleRate
            )
            self.captureStopState.noteTap(
                timing: bufferTiming,
                acceptedDuration: captureDecision.allowedDuration,
                rms: activityRMS
            )
            if self.captureStopState.hasPendingStopRequest {
                self.diagnostics.record(
                    String(
                        format: "accepted tail audio duration=%.3f sampleRate=%.1f samples=%d avgRms=%.6f activityRms=%.6f",
                        captureDecision.allowedDuration,
                        trimmed.sampleRate,
                        trimmed.samples.count,
                        averageRMS,
                        activityRMS
                    )
                )
            }
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
            diagnostics.record("audio engine start failed error=\(error.localizedDescription)")
            inputNode.removeTap(onBus: 0)
            processingQueue.sync {
                stream?.close()
                stream = nil
                latestTranscript = .init()
                latestStreamError = nil
                isStopped = true
            }
            uncachedTranscriber?.close()
            uncachedTranscriber = nil
            throw error
        }

        audioEngine = engine
    }

    /// Stops capture, finalises the transcript, and returns the result.
    /// Must be called from the main thread.
    func stop() throws -> RawTranscript {
        let stopRequestTime = currentCaptureTime()
        diagnostics.record(
            String(
                format: "stop requested at %.3f snapshot=%@",
                stopRequestTime,
                captureStopState.snapshotDescription
            )
        )
        captureStopState.requestStop(at: stopRequestTime)
        waitForCaptureBoundary()
        diagnostics.record("capture boundary reached snapshot=\(captureStopState.snapshotDescription)")
        tearDownAudio()
        _ = audioDrainGroup.wait(timeout: .now() + Self.audioDrainTimeout)
        diagnostics.record("audio drain wait completed snapshot=\(captureStopState.snapshotDescription)")

        return try processingQueue.sync {
            defer {
                diagnostics.flush()
                stream?.close()
                stream = nil
                latestTranscript = .init()
                latestStreamError = nil
                isStopped = true
                uncachedTranscriber?.close()
                uncachedTranscriber = nil
            }

            diagnostics.record("calling stream.stop()")
            try stream?.stop()
            diagnostics.record("stream.stop() returned latestTranscript='\(latestTranscript.lines.map(\.text).joined(separator: " "))'")
            let finalTranscript = try settleFinalTranscript()
            latestTranscript = finalTranscript
            diagnostics.record("final transcript lines=\(finalTranscript.lines.count) text='\(finalTranscript.lines.map(\.text).joined(separator: " "))'")

            if finalTranscript.lines.isEmpty, let latestStreamError {
                diagnostics.record("stop failed with latestStreamError=\(latestStreamError.localizedDescription)")
                throw latestStreamError
            }

            let rawTranscript = Self.buildRawTranscript(from: finalTranscript)
            if rawTranscript.text.isEmpty {
                diagnostics.record("raw transcript empty after finalization")
                throw MoonshineTranscriptionError.emptyLiveTranscript
            }

            diagnostics.record("returning raw transcript durationMS=\(rawTranscript.durationMS) text='\(rawTranscript.text)'")
            return rawTranscript
        }
    }

    /// Cancels without producing a transcript.
    func cancel() {
        diagnostics.record("session cancelled")
        captureStopState.requestStop(at: currentCaptureTime())
        tearDownAudio()
        processingQueue.sync {
            isStopped = true
            stream?.close()
            stream = nil
            latestTranscript = .init()
            latestStreamError = nil
        }
        uncachedTranscriber?.close()
        uncachedTranscriber = nil
        diagnostics.flush()
    }

    private func handle(event: TranscriptEvent) {
        if let transcriptError = event as? TranscriptError {
            latestStreamError = transcriptError.error
            diagnostics.record("stream error event=\(transcriptError.error.localizedDescription)")
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
        let displayText = ConsecutivePhraseDeduplicator.collapse(mergedText)

        diagnostics.record(
            "event lineId=\(event.line.lineId) complete=\(event.line.isComplete) text='\(currentText)' merged='\(mergedText)' display='\(displayText)'"
        )

        DispatchQueue.main.async { [weak self] in
            self?.onPartialText(displayText)
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
        let deadline = currentCaptureTime() + Self.captureBoundaryWaitTimeout

        while currentCaptureTime() < deadline {
            if captureStopState.shouldFinishWaiting(at: currentCaptureTime()) {
                return
            }

            Thread.sleep(forTimeInterval: Self.captureBoundaryPollInterval)
        }

        diagnostics.record("capture boundary timed out snapshot=\(captureStopState.snapshotDescription)")
    }

    private func settleFinalTranscript() throws -> Transcript {
        var settledTranscript = latestTranscript
        var settledSignature = transcriptSignature(for: settledTranscript)
        var lastChangeDate = Date()
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
                lastChangeDate = Date()
            }

            let hasIncompleteLines = updatedTranscript.lines.contains { !$0.isComplete }
            let isStable = Date().timeIntervalSince(lastChangeDate) >= Self.finalTranscriptStableWindow
            diagnostics.record(
                "finalize poll changed=\(changed) incomplete=\(hasIncompleteLines) stable=\(isStable) text='\(updatedTranscript.lines.map(\.text).joined(separator: " "))'"
            )
            if !hasIncompleteLines && isStable {
                return updatedTranscript
            }

            if Date() >= deadline {
                diagnostics.record(
                    "finalize deadline reached returning='\((changed ? updatedTranscript : settledTranscript).lines.map(\.text).joined(separator: " "))'"
                )
                return changed ? updatedTranscript : settledTranscript
            }

            Thread.sleep(forTimeInterval: Self.finalTranscriptPollInterval)
        }
    }

    private func bufferTiming(
        frameLength: AVAudioFrameCount,
        sampleRate: Double,
        time: AVAudioTime?
    ) -> PressToTalkTailPolicy.CaptureTiming {
        let duration = Double(frameLength) / sampleRate
        if let time, time.hostTime != 0 {
            let startTime = AVAudioTime.seconds(forHostTime: time.hostTime)
            return PressToTalkTailPolicy.CaptureTiming(
                startTime: startTime,
                endTime: startTime + duration,
                duration: duration
            )
        }

        let callbackTime = currentCaptureTime()
        return PressToTalkTailPolicy.CaptureTiming(
            startTime: max(0, callbackTime - duration),
            endTime: callbackTime,
            duration: duration
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

    private static func windowedActivityRMS(
        for samples: [Float],
        sampleRate: Double
    ) -> Float {
        guard !samples.isEmpty else { return 0 }

        let windowSize = max(1, Int((sampleRate * 0.025).rounded()))
        var bestRMS: Float = 0
        var index = 0

        while index < samples.count {
            let endIndex = min(samples.count, index + windowSize)
            let window = Array(samples[index..<endIndex])
            bestRMS = max(bestRMS, rootMeanSquare(for: window))
            index += windowSize
        }

        return bestRMS
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
        let deduplicatedText = ConsecutivePhraseDeduplicator.collapse(text)

        let durationMS = Int(
            (transcript.lines.last.map { $0.startTime + $0.duration } ?? 0) * 1_000
        )
        return RawTranscript(text: deduplicatedText, segments: segments, durationMS: durationMS)
    }

    private func currentCaptureTime() -> TimeInterval {
        AVAudioTime.seconds(forHostTime: mach_absolute_time())
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

private final class CaptureStopState: @unchecked Sendable {
    private let lock = NSLock()
    private var policy: PressToTalkTailPolicy

    init(configuration: PressToTalkTailPolicy.Configuration) {
        policy = PressToTalkTailPolicy(configuration: configuration)
    }

    func reset() {
        lock.lock()
        policy.reset()
        lock.unlock()
    }

    func requestStop(at time: TimeInterval) {
        lock.lock()
        policy.requestStop(at: time)
        lock.unlock()
    }

    func captureDecision(
        for timing: PressToTalkTailPolicy.CaptureTiming
    ) -> PressToTalkTailPolicy.CaptureDecision {
        lock.lock()
        let decision = policy.captureDecision(for: timing)
        lock.unlock()
        return decision
    }

    func noteTap(
        timing: PressToTalkTailPolicy.CaptureTiming,
        acceptedDuration: TimeInterval,
        rms: Float
    ) {
        lock.lock()
        policy.noteAcceptedAudio(timing: timing, acceptedDuration: acceptedDuration, rms: rms)
        lock.unlock()
    }

    func incrementPendingAudioBuffers() {
        lock.lock()
        policy.incrementPendingAudioBuffers()
        lock.unlock()
    }

    func decrementPendingAudioBuffers() {
        lock.lock()
        policy.decrementPendingAudioBuffers()
        lock.unlock()
    }

    func shouldFinishWaiting(at time: TimeInterval) -> Bool {
        lock.lock()
        let shouldFinish = policy.shouldFinishWaiting(at: time)
        lock.unlock()
        return shouldFinish
    }

    var hasPendingStopRequest: Bool {
        lock.lock()
        let hasPendingStopRequest = policy.snapshot().stopRequestedTime != nil
        lock.unlock()
        return hasPendingStopRequest
    }

    var snapshotDescription: String {
        lock.lock()
        let snapshot = policy.snapshot()
        lock.unlock()
        return "stopRequested=\(snapshot.stopRequestedTime.map { String(format: "%.3f", $0) } ?? "nil") lastBuffer=\(String(format: "%.3f", snapshot.lastBufferTime)) lastAudible=\(String(format: "%.3f", snapshot.lastAudibleTime)) pending=\(snapshot.pendingAudioBuffers)"
    }
}

private final class StreamingStopDiagnostics: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    private let sessionID = UUID().uuidString

    func reset() {
        lock.lock()
        lines.removeAll(keepingCapacity: true)
        lock.unlock()
    }

    func record(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        lock.lock()
        lines.append("[\(timestamp)] \(message)")
        if lines.count > 500 {
            lines.removeFirst(lines.count - 500)
        }
        lock.unlock()
    }

    func flush() {
        lock.lock()
        let content = lines.joined(separator: "\n")
        lock.unlock()

        guard !content.isEmpty else { return }

        let fileManager = FileManager.default
        let baseDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Voce/Diagnostics", isDirectory: true)
        guard let directory = baseDirectory else { return }

        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let logURL = directory.appendingPathComponent("live-stop-\(sessionID).log")
            try content.write(to: logURL, atomically: true, encoding: .utf8)
        } catch {
            return
        }
    }
}
