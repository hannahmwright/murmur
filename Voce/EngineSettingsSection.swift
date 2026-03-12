import SwiftUI
import VoceKit

struct EngineSettingsSection: View {
    @Binding var preferences: AppPreferences
    let controller: DictationController
    @State private var testResult: String?
    @State private var testResultIsError = false
    @State private var isTesting = false
    @StateObject private var downloader = MoonshineModelDownloader()

    var body: some View {
        settingsCard("Engine") {
            Picker("Model", selection: $preferences.dictation.modelArch) {
                ForEach(MoonshineModelPreset.allCases) { preset in
                    Text(preset.displayName).tag(preset)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: preferences.dictation.modelArch) { newArch in
                preferences.dictation.modelDirectoryPath = MoonshineModelPaths.defaultModelDirectoryPath(for: newArch)
            }

            Toggle("Keep model warmed in memory", isOn: $preferences.dictation.keepModelWarm)
            Text("Faster recording start, higher idle memory use.")
                .font(VoceDesign.caption())
                .foregroundStyle(VoceDesign.textSecondary)

            if modelIsReady {
                modelReadySection
            } else {
                modelDownloadSection
            }
        }
    }

    private var modelReadySection: some View {
        HStack(spacing: VoceDesign.sm) {
            Button {
                runTestSetup()
            } label: {
                if isTesting {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: VoceDesign.iconMD, height: VoceDesign.iconMD)
                } else {
                    Text("Test Setup")
                }
            }
            .buttonStyle(.bordered)
            .disabled(isTesting)
            .accessibilityLabel("Test Moonshine setup")

            if let result = testResult {
                Text(result)
                    .font(VoceDesign.caption())
                    .foregroundStyle(testResultIsError ? VoceDesign.error : VoceDesign.success)
            } else {
                HStack(spacing: VoceDesign.xs) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(VoceDesign.success)
                    Text("Model ready")
                        .font(VoceDesign.caption())
                        .foregroundStyle(VoceDesign.success)
                }
            }
        }
    }

    private var modelIsReady: Bool {
        MoonshineModelPaths.missingFiles(
            in: preferences.dictation.modelDirectoryPath,
            preset: preferences.dictation.modelArch
        ).isEmpty
    }

    private var modelDownloadSection: some View {
        VStack(alignment: .leading, spacing: VoceDesign.sm) {
            switch downloader.status {
            case .idle, .failed:
                if case .failed(let message) = downloader.status {
                    Text(message)
                        .font(VoceDesign.caption())
                        .foregroundStyle(VoceDesign.error)
                }
                Button("Download Model") {
                    downloader.download(preset: preferences.dictation.modelArch)
                }
                .buttonStyle(.bordered)
            case .downloading:
                ProgressView(value: downloader.overallProgress)
                    .progressViewStyle(.linear)
                HStack {
                    Text("\(Int(downloader.overallProgress * 100))%")
                        .font(VoceDesign.caption())
                        .foregroundStyle(VoceDesign.textSecondary)
                    Spacer()
                    Button("Cancel") {
                        downloader.cancel()
                    }
                    .font(VoceDesign.caption())
                    .buttonStyle(.plain)
                    .foregroundStyle(VoceDesign.textSecondary)
                }
            case .completed:
                HStack(spacing: VoceDesign.xs) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(VoceDesign.success)
                    Text("Download complete")
                        .font(VoceDesign.caption())
                        .foregroundStyle(VoceDesign.success)
                }
            }
        }
    }

    private func runTestSetup() {
        isTesting = true
        testResult = nil

        Task {
            let micStatus = PermissionDiagnostics.microphoneStatus()
            guard micStatus == .granted else {
                await MainActor.run {
                    testResult = "Microphone permission not granted."
                    testResultIsError = true
                    isTesting = false
                }
                return
            }

            do {
                let modelDirectoryPath = preferences.dictation.modelDirectoryPath
                let modelArch = preferences.dictation.modelArch
                try await Task.detached(priority: .userInitiated) {
                    try MoonshineTranscriptionEngine.preflightCheck(
                        modelDirectoryPath: modelDirectoryPath,
                        modelArch: modelArch
                    )
                }.value

                await MainActor.run {
                    testResult = "Moonshine model is ready."
                    testResultIsError = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        if testResult == "Moonshine model is ready." {
                            testResult = nil
                        }
                    }
                    isTesting = false
                }
            } catch is CancellationError {
                await MainActor.run {
                    testResult = "Moonshine test cancelled."
                    testResultIsError = true
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    testResult = "Failed to load Moonshine model: \(error.localizedDescription)"
                    testResultIsError = true
                    isTesting = false
                }
            }
        }
    }
}
