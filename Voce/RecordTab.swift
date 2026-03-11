import SwiftUI
import VoceKit

struct RecordTab: View {
    @EnvironmentObject private var controller: DictationController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showErrorBanner = false

    var body: some View {
        Group {
            if #available(macOS 14.0, *) {
                content
                    .onChange(of: controller.lastError) { _, _ in
                        animateErrorBannerUpdate()
                    }
                    .onChange(of: controller.hotkeyRegistrationMessage) { _, _ in
                        animateErrorBannerUpdate()
                    }
            } else {
                content
                    .onChange(of: controller.lastError) { _ in
                        animateErrorBannerUpdate()
                    }
                    .onChange(of: controller.hotkeyRegistrationMessage) { _ in
                        animateErrorBannerUpdate()
                    }
            }
        }
        .onAppear {
            showErrorBanner = hasError
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            // Error/warning banner
            if showErrorBanner {
                errorBanner
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(errorBannerAccessibilityLabel)
                    .padding(.bottom, VoceDesign.md)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .move(edge: .top).combined(with: .opacity)
                    )
            }

            Spacer()

            // Mic button
            MicButton(
                isRecording: controller.isRecording,
                isTranscribing: controller.recordingLifecycleState == .transcribing,
                handsFreeOn: controller.handsFreeOn,
                onTap: { controller.toggleHandsFree() }
            )

            // Recording elapsed time
            if controller.isRecording {
                Text(formatElapsedTime(controller.recordingElapsed))
                    .font(VoceDesign.caption().monospacedDigit())
                    .foregroundStyle(VoceDesign.accent)
                    .padding(.top, VoceDesign.xs)
                    .transition(.opacity)
                    .accessibilityLabel("Recording time")
                    .accessibilityValue(formatElapsedTime(controller.recordingElapsed))
            }

            // Status text
            VStack(spacing: VoceDesign.xs) {
                Text(controller.status)
                    .font(VoceDesign.subheadline())
                    .foregroundStyle(VoceDesign.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .accessibilityLabel("Recording status")
                    .accessibilityValue(controller.status)

                if controller.recordingLifecycleState == .transcribing {
                    Text("(usually 2\u{2013}5 seconds)")
                        .font(VoceDesign.caption())
                        .foregroundStyle(VoceDesign.textSecondary)
                }
            }
            .padding(.top, VoceDesign.sm)

            Spacer()

            // Last transcript card or empty hint
            if controller.lastTranscript.isEmpty {
                emptyHintView
            } else {
                lastTranscriptCard
            }
        }
        .padding(.vertical, VoceDesign.lg)
        .animation(
            reduceMotion ? nil : .easeInOut(duration: VoceDesign.animationNormal),
            value: controller.lastTranscript
        )
    }

    private func animateErrorBannerUpdate() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: VoceDesign.animationNormal)) {
            showErrorBanner = hasError
        }
    }

    private var hasError: Bool {
        !controller.lastError.isEmpty || !controller.hotkeyRegistrationMessage.isEmpty
    }

    private var errorBannerAccessibilityLabel: String {
        var parts: [String] = []
        if !controller.hotkeyRegistrationMessage.isEmpty {
            parts.append(controller.hotkeyRegistrationMessage)
        }
        if !controller.lastError.isEmpty {
            parts.append(controller.lastError)
        }
        return parts.joined(separator: ". ")
    }

    private var isPermissionRelated: Bool {
        let combined = (controller.lastError + controller.hotkeyRegistrationMessage).lowercased()
        return combined.contains("accessibility")
            || combined.contains("microphone")
            || combined.contains("input monitoring")
    }

    // MARK: - Error Banner

    private var errorBanner: some View {
        HStack(spacing: VoceDesign.sm) {
            RoundedRectangle(cornerRadius: VoceDesign.radiusTiny)
                .fill(VoceDesign.error)
                .frame(width: VoceDesign.borderHeavy)

            VStack(alignment: .leading, spacing: VoceDesign.xs) {
                if !controller.hotkeyRegistrationMessage.isEmpty {
                    Text(controller.hotkeyRegistrationMessage)
                        .font(VoceDesign.caption())
                        .foregroundStyle(VoceDesign.error)
                }
                if !controller.lastError.isEmpty {
                    Text(controller.lastError)
                        .font(VoceDesign.caption())
                        .foregroundStyle(VoceDesign.error)
                }
                if isPermissionRelated {
                    Button {
                        PermissionDiagnostics.openAccessibilitySettings()
                    } label: {
                        Text("Open Settings")
                            .font(VoceDesign.caption())
                            .foregroundStyle(VoceDesign.accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open system settings for permissions")
                }
            }

            Spacer()

            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: VoceDesign.animationNormal)) {
                    controller.clearErrors()
                    showErrorBanner = false
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(VoceDesign.caption())
                    .foregroundStyle(VoceDesign.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss error")
        }
        .padding(VoceDesign.md)
        .glassBackground(cornerRadius: VoceDesign.radiusSmall)
        .overlay(
            RoundedRectangle(cornerRadius: VoceDesign.radiusSmall)
                .stroke(VoceDesign.errorBorder, lineWidth: VoceDesign.borderNormal)
        )
    }

    // MARK: - Empty Hint

    private var emptyHintView: some View {
        VStack(spacing: VoceDesign.sm) {
            if controller.microphonePermissionStatus == .denied {
                Label("Microphone access denied", systemImage: "mic.slash")
                    .font(VoceDesign.caption())
                    .foregroundStyle(VoceDesign.textSecondary)
            } else if controller.microphonePermissionStatus == .unknown {
                Label("Grant microphone access to start", systemImage: "mic.badge.plus")
                    .font(VoceDesign.caption())
                    .foregroundStyle(VoceDesign.textSecondary)
            } else {
                hotkeyHint
            }
        }
        .frame(maxWidth: .infinity)
        .padding(VoceDesign.md)
        .glassBackground(cornerRadius: VoceDesign.radiusMedium)
    }

    private var hotkeyHint: some View {
        HStack(spacing: VoceDesign.sm) {
            let hotkeys = controller.preferences.hotkeys
            if hotkeys.optionPressToTalkEnabled {
                keyBadge("Option")
                Text("hold to dictate")
                    .font(VoceDesign.caption())
                    .foregroundStyle(VoceDesign.textSecondary)
            }
            if hotkeys.optionPressToTalkEnabled, hotkeys.handsFreeGlobalKeyCode != nil {
                Text("or")
                    .font(VoceDesign.caption())
                    .foregroundStyle(VoceDesign.textSecondary.opacity(0.6))
            }
            if let keyCode = hotkeys.handsFreeGlobalKeyCode {
                keyBadge(keyLabel(for: keyCode))
                Text("hands-free")
                    .font(VoceDesign.caption())
                    .foregroundStyle(VoceDesign.textSecondary)
            }
            if !hotkeys.optionPressToTalkEnabled && hotkeys.handsFreeGlobalKeyCode == nil {
                Text("Set up a hotkey in Settings")
                    .font(VoceDesign.caption())
                    .foregroundStyle(VoceDesign.textSecondary)
            }
        }
    }

    private func keyBadge(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(VoceDesign.textPrimary)
            .padding(.horizontal, VoceDesign.sm)
            .padding(.vertical, VoceDesign.xs)
            .background(VoceDesign.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: VoceDesign.radiusSmall - 2))
            .overlay(
                RoundedRectangle(cornerRadius: VoceDesign.radiusSmall - 2)
                    .stroke(VoceDesign.border, lineWidth: VoceDesign.borderThin)
            )
    }

    // MARK: - Transcript Card

    private var lastTranscriptCard: some View {
        VStack(alignment: .leading, spacing: VoceDesign.sm) {
            Text(controller.lastTranscript)
                .font(VoceDesign.body())
                .foregroundStyle(VoceDesign.textPrimary)
                .lineLimit(6)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Action row
            HStack(spacing: VoceDesign.md) {
                Text("Last transcript")
                    .font(VoceDesign.caption())
                    .foregroundStyle(VoceDesign.textSecondary)

                Spacer()

                Button {
                    controller.copyCurrentTranscript()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(VoceDesign.caption())
                        .foregroundStyle(VoceDesign.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Copy last transcript")

                Button {
                    controller.pasteCurrentTranscript()
                } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
                        .font(VoceDesign.caption())
                        .foregroundStyle(VoceDesign.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Paste last transcript")
            }
        }
        .cardStyle()
    }

    // MARK: - Helpers

    private func keyLabel(for keyCode: UInt16) -> String {
        switch keyCode {
        case 79: return "F18"
        case 80: return "F19"
        case 90: return "F20"
        case 105: return "F13"
        case 107: return "F14"
        case 113: return "F15"
        case 106: return "F16"
        case 64: return "F17"
        default: return "F\(keyCode)"
        }
    }

    private func formatElapsedTime(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
