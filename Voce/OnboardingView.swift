import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var controller: DictationController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var currentStep: OnboardingStep = .welcome
    @State private var modelArch: MoonshineModelPreset = .smallStreaming
    @StateObject private var downloader = MoonshineModelDownloader()

    var body: some View {
        VStack(spacing: 0) {
            // Progress bar
            progressBar
                .padding(.horizontal, VoceDesign.lg)
                .padding(.top, VoceDesign.lg)

            // Step content
            Group {
                switch currentStep {
                case .welcome:
                    welcomeStep
                case .permissions:
                    permissionsStep
                case .modelSetup:
                    modelSetupStep
                case .featureTour:
                    featureTourStep
                }
            }
            .id(currentStep)
            .transition(stepTransition)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, VoceDesign.xl)

            // Navigation bar
            navigationBar
                .padding(.horizontal, VoceDesign.lg)
                .padding(.bottom, VoceDesign.lg)
        }
        .frame(
            minWidth: VoceDesign.windowMinWidth,
            idealWidth: VoceDesign.windowIdealWidth,
            minHeight: VoceDesign.windowMinHeight,
            idealHeight: VoceDesign.windowIdealHeight
        )
        .background {
            ZStack {
                VoceDesign.windowBackground
                LinearGradient(
                    colors: [
                        VoceDesign.skyBlue.opacity(0.10),
                        Color.clear,
                        VoceDesign.roseLight.opacity(0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .animation(
            reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.85, blendDuration: 0),
            value: currentStep
        )
        .onAppear {
            modelArch = controller.preferences.dictation.modelArch
        }
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        HStack(spacing: VoceDesign.xs) {
            ForEach(OnboardingStep.allCases, id: \.self) { step in
                RoundedRectangle(cornerRadius: VoceDesign.radiusTiny)
                    .fill(step.rawValue <= currentStep.rawValue ? VoceDesign.accent : VoceDesign.border)
                    .frame(height: VoceDesign.xs)
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: VoceDesign.animationNormal),
                        value: currentStep
                    )
            }
        }
        .accessibilityLabel("Step \(currentStep.rawValue + 1) of \(OnboardingStep.allCases.count)")
    }

    // MARK: - Step Transition

    private var stepTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }

    // MARK: - Step 1: Welcome

    private var welcomeStep: some View {
        VStack(spacing: VoceDesign.xl) {
            Spacer()

            Image(systemName: "mic.fill")
                .font(.system(size: 72))
                .foregroundStyle(VoceDesign.accentGradient)
                .accessibilityHidden(true)

            VStack(spacing: VoceDesign.sm) {
                Text("Welcome to Voce")
                    .font(VoceDesign.heading1())
                    .foregroundStyle(VoceDesign.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                Text("Private dictation that types into your active app")
                    .font(VoceDesign.subheadline())
                    .foregroundStyle(VoceDesign.textSecondary)
            }

            VStack(alignment: .leading, spacing: VoceDesign.md) {
                featureRow(icon: "lock.shield", title: "Private by default", detail: "Audio and transcript cleanup stay on your Mac.")
                featureRow(icon: "bolt", title: "Fast", detail: "Moonshine transcribes locally with low-latency models.")
                featureRow(icon: "text.cursor", title: "Works across apps", detail: "Types or pastes into editors, terminals, and most text fields.")
            }
            .cardStyle()

            Spacer()
        }
    }

    private func featureRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: VoceDesign.md) {
            Image(systemName: icon)
                .font(.system(size: VoceDesign.iconLG))
                .foregroundStyle(VoceDesign.accent)
                .frame(width: VoceDesign.xl)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: VoceDesign.xxs) {
                Text(title)
                    .font(VoceDesign.bodyEmphasis())
                    .foregroundStyle(VoceDesign.textPrimary)
                Text(detail)
                    .font(VoceDesign.caption())
                    .foregroundStyle(VoceDesign.textSecondary)
            }
        }
    }

    // MARK: - Step 2: Permissions

    private var permissionsStep: some View {
        VStack(spacing: VoceDesign.lg) {
            Spacer()

            VStack(spacing: VoceDesign.sm) {
                Text("Permissions")
                    .font(VoceDesign.heading1())
                    .foregroundStyle(VoceDesign.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                Text("Voce needs a few permissions to work properly.")
                    .font(VoceDesign.subheadline())
                    .foregroundStyle(VoceDesign.textSecondary)
            }

            VStack(spacing: VoceDesign.sm) {
                PermissionStatusCard(
                    title: "Microphone",
                    description: "Required to capture audio for transcription.",
                    status: controller.microphonePermissionStatus,
                    onRequest: { controller.requestMicrophonePermission() },
                    onOpenSettings: { controller.openMicrophoneSettings() }
                )

                PermissionStatusCard(
                    title: "Accessibility",
                    description: "Lets Voce type or paste into the app you're using.",
                    status: controller.accessibilityPermissionStatus,
                    onRequest: { controller.requestAccessibilityPermission() },
                    onOpenSettings: { controller.openAccessibilitySettings() }
                )

                PermissionStatusCard(
                    title: "Input Monitoring",
                    description: "Lets Voce detect global hotkeys while other apps are focused.",
                    status: controller.inputMonitoringPermissionStatus,
                    onRequest: { controller.requestInputMonitoringPermission() },
                    onOpenSettings: { controller.openInputMonitoringSettings() }
                )
            }

            if controller.microphonePermissionStatus != .granted {
                Text("Microphone access is required to continue.")
                    .font(VoceDesign.caption())
                    .foregroundStyle(VoceDesign.warning)
            }

            Spacer()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            controller.refreshPermissionStatuses()
        }
    }

    // MARK: - Step 3: Model Setup

    private var modelSetupStep: some View {
        VStack(spacing: VoceDesign.lg) {
            Spacer()

            VStack(spacing: VoceDesign.sm) {
                Text("Moonshine Model")
                    .font(VoceDesign.heading1())
                    .foregroundStyle(VoceDesign.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                Text("Choose a model size and Voce will download it automatically.")
                    .font(VoceDesign.subheadline())
                    .foregroundStyle(VoceDesign.textSecondary)
            }

            VStack(alignment: .leading, spacing: VoceDesign.md) {
                VStack(alignment: .leading, spacing: VoceDesign.xs) {
                    Text("Model")
                        .font(VoceDesign.bodyEmphasis())
                        .foregroundStyle(VoceDesign.textPrimary)
                    Picker("Model", selection: $modelArch) {
                        Text("Tiny Streaming (~50 MB)").tag(MoonshineModelPreset.tinyStreaming)
                        Text("Small Streaming (~160 MB)").tag(MoonshineModelPreset.smallStreaming)
                    }
                    .pickerStyle(.menu)
                    .disabled(isDownloading)
                }

                if MoonshineModelDownloader.isModelReady(preset: modelArch) {
                    HStack(spacing: VoceDesign.xs) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(VoceDesign.success)
                        Text("Model ready")
                            .font(VoceDesign.caption())
                            .foregroundStyle(VoceDesign.success)
                    }
                } else {
                    downloadSection
                }
            }
            .cardStyle()

            Spacer()
        }
    }

    private var downloadSection: some View {
        VStack(alignment: .leading, spacing: VoceDesign.sm) {
            switch downloader.status {
            case .idle:
                Button("Download Model") {
                    downloader.download(preset: modelArch)
                }
                .buttonStyle(.bordered)
            case .downloading:
                VStack(alignment: .leading, spacing: VoceDesign.xs) {
                    ProgressView(value: downloader.overallProgress)
                        .progressViewStyle(.linear)
                    HStack {
                        Text(downloadStatusText)
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
                }
            case .completed:
                HStack(spacing: VoceDesign.xs) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(VoceDesign.success)
                    Text("Download complete")
                        .font(VoceDesign.caption())
                        .foregroundStyle(VoceDesign.success)
                }
            case .failed(let message):
                VStack(alignment: .leading, spacing: VoceDesign.xs) {
                    HStack(spacing: VoceDesign.xs) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(VoceDesign.error)
                        Text(message)
                            .font(VoceDesign.caption())
                            .foregroundStyle(VoceDesign.error)
                    }
                    Button("Retry") {
                        downloader.download(preset: modelArch)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var downloadStatusText: String {
        if case .downloading(let fileIndex, let fileCount, _) = downloader.status {
            let percent = Int(downloader.overallProgress * 100)
            return "Downloading file \(fileIndex + 1) of \(fileCount) (\(percent)%)"
        }
        return ""
    }

    private var isDownloading: Bool {
        if case .downloading = downloader.status { return true }
        return false
    }

    // MARK: - Step 4: Feature Tour

    private var featureTourStep: some View {
        VStack(spacing: VoceDesign.xl) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(VoceDesign.success)
                .accessibilityHidden(true)

            VStack(spacing: VoceDesign.sm) {
                Text("You're all set!")
                    .font(VoceDesign.heading1())
                    .foregroundStyle(VoceDesign.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                Text("Here are a few tips to get started.")
                    .font(VoceDesign.subheadline())
                    .foregroundStyle(VoceDesign.textSecondary)
            }

            VStack(alignment: .leading, spacing: VoceDesign.md) {
                tipRow(number: "1", text: "Hold Option to dictate (press-to-talk)")
                tipRow(number: "2", text: "Press F18 to toggle hands-free mode")
                tipRow(number: "3", text: "Check the History tab for past transcripts")
            }
            .cardStyle()

            Spacer()
        }
    }

    private func tipRow(number: String, text: String) -> some View {
        HStack(spacing: VoceDesign.md) {
            Text(number)
                .font(VoceDesign.bodyEmphasis())
                .foregroundStyle(.white)
                .frame(width: VoceDesign.xl, height: VoceDesign.xl)
                .background(VoceDesign.accentGradient)
                .clipShape(Circle())
                .accessibilityHidden(true)

            Text(text)
                .font(VoceDesign.body())
                .foregroundStyle(VoceDesign.textPrimary)
        }
    }

    // MARK: - Navigation Bar

    private var navigationBar: some View {
        HStack {
            if currentStep != .welcome {
                Button("Back") {
                    goBack()
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Go to previous step")
            }

            Spacer()

            if currentStep != .welcome && currentStep != .featureTour && canSkip {
                Button("Skip") {
                    goForward()
                }
                .buttonStyle(.plain)
                .foregroundStyle(VoceDesign.textSecondary)
                .accessibilityLabel("Skip this step")
            }

            if currentStep == .featureTour {
                Button("Get Started") {
                    completeOnboarding()
                }
                .buttonStyle(.borderedProminent)
                .tint(VoceDesign.accent)
                .accessibilityLabel("Finish onboarding and start using Voce")
            } else {
                Button("Continue") {
                    goForward()
                }
                .buttonStyle(.borderedProminent)
                .tint(VoceDesign.accent)
                .disabled(!canContinue)
                .accessibilityLabel("Continue to next step")
            }
        }
    }

    // MARK: - Navigation Logic

    private var canContinue: Bool {
        switch currentStep {
        case .welcome:
            return true
        case .permissions:
            return controller.microphonePermissionStatus == .granted
        case .modelSetup:
            return MoonshineModelDownloader.isModelReady(preset: modelArch)
        case .featureTour:
            return true
        }
    }

    private var canSkip: Bool {
        switch currentStep {
        case .welcome, .featureTour:
            return false
        case .permissions, .modelSetup:
            return true
        }
    }

    private func goForward() {
        guard let nextIndex = OnboardingStep(rawValue: currentStep.rawValue + 1) else { return }
        currentStep = nextIndex
    }

    private func goBack() {
        guard let prevIndex = OnboardingStep(rawValue: currentStep.rawValue - 1) else { return }
        currentStep = prevIndex
    }

    private func completeOnboarding() {
        let modelDir = MoonshineModelPaths.defaultModelDirectoryPath(for: modelArch)
        if modelDir != controller.preferences.dictation.modelDirectoryPath {
            controller.preferences.dictation.modelDirectoryPath = modelDir
        }
        if modelArch != controller.preferences.dictation.modelArch {
            controller.preferences.dictation.modelArch = modelArch
        }

        controller.completeOnboarding()
    }
}

// MARK: - Onboarding Step Enum

private enum OnboardingStep: Int, CaseIterable {
    case welcome = 0
    case permissions = 1
    case modelSetup = 2
    case featureTour = 3
}
