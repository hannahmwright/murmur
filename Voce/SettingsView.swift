import SwiftUI
import VoceKit

struct SettingsView: View {
    @EnvironmentObject private var controller: DictationController
    @State private var preferencesDraft: AppPreferences = .default
    @State private var expandedGroup: SettingsGroup? = .setup

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VoceDesign.sm) {
                ForEach(SettingsGroup.allCases, id: \.self) { group in
                    settingsGroupHeader(group)
                    settingsGroupBody(group)
                }

                // Save button
                HStack(spacing: VoceDesign.sm) {
                    Button("Save & Apply") {
                        controller.applySettingsDraft(preferences: preferencesDraft)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(VoceDesign.accent)

                    Spacer()
                }
                .padding(.top, VoceDesign.sm)
            }
            .padding(.vertical, VoceDesign.lg)
        }
        .onAppear {
            preferencesDraft = controller.preferences
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: expandedGroup)
    }

    @ViewBuilder
    private func groupContent(_ group: SettingsGroup) -> some View {
        switch group {
        case .setup:
            PermissionsSettingsSection()
            RecordingSettingsSection(
                preferences: $preferencesDraft,
                hotkeyRegistrationMessage: controller.hotkeyRegistrationMessage
            )
            EngineSettingsSection(
                preferences: $preferencesDraft,
                controller: controller
            )
        case .behavior:
            InsertionSettingsSection(preferences: $preferencesDraft)
            MediaSettingsSection(preferences: $preferencesDraft)
            CleanupStyleSettingsSection(preferences: $preferencesDraft)
        case .vocabulary:
            LexiconSettingsSection(preferences: $preferencesDraft)
            SnippetsSettingsSection(preferences: $preferencesDraft)
            VoiceCommandsSettingsSection(preferences: $preferencesDraft)
            LearningSettingsSection()
        case .general:
            GeneralSettingsSection(
                preferences: $preferencesDraft,
                launchAtLoginWarning: controller.launchAtLoginWarning
            )
        }
    }

    private func settingsGroupHeader(_ group: SettingsGroup) -> some View {
        let isExpanded = expandedGroup == group

        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                expandedGroup = isExpanded ? nil : group
            }
        } label: {
            HStack(spacing: VoceDesign.sm) {
                Image(systemName: group.icon)
                    .font(.system(size: VoceDesign.iconMD))
                    .foregroundStyle(isExpanded ? VoceDesign.accent : VoceDesign.textSecondary)
                    .frame(width: VoceDesign.xl)

                Text(group.title)
                    .font(VoceDesign.heading3())
                    .foregroundStyle(VoceDesign.textPrimary)

                Spacer()

                if !isExpanded {
                    Text(group.subtitle)
                        .font(VoceDesign.caption())
                        .foregroundStyle(VoceDesign.textSecondary)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(VoceDesign.textSecondary)
                    .rotationEffect(isExpanded ? .degrees(90) : .degrees(0))
            }
            .padding(.horizontal, VoceDesign.md)
            .padding(.vertical, VoceDesign.md)
            .background {
                if isExpanded {
                    RoundedRectangle(cornerRadius: VoceDesign.radiusSmall)
                        .fill(VoceDesign.accent.opacity(0.06))
                }
            }
            .glassBackground(cornerRadius: VoceDesign.radiusSmall)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(group.title), \(isExpanded ? "expanded" : "collapsed")")
    }

    private func settingsGroupBody(_ group: SettingsGroup) -> some View {
        let isExpanded = expandedGroup == group

        return VStack(alignment: .leading, spacing: VoceDesign.sm) {
            groupContent(group)
        }
        .padding(.top, VoceDesign.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: isExpanded ? nil : 0, alignment: .top)
        .clipped()
        .opacity(isExpanded ? 1 : 0)
        .allowsHitTesting(isExpanded)
        .accessibilityHidden(!isExpanded)
    }
}

private enum SettingsGroup: String, CaseIterable {
    case setup
    case behavior
    case vocabulary
    case general

    var title: String {
        switch self {
        case .setup: return "Setup"
        case .behavior: return "Behavior"
        case .vocabulary: return "Vocabulary & Commands"
        case .general: return "General"
        }
    }

    var subtitle: String {
        switch self {
        case .setup: return "Permissions, hotkeys, engine"
        case .behavior: return "Insertion, media, cleanup"
        case .vocabulary: return "Lexicon, snippets, voice"
        case .general: return "Launch, updates"
        }
    }

    var icon: String {
        switch self {
        case .setup: return "gearshape"
        case .behavior: return "slider.horizontal.3"
        case .vocabulary: return "text.book.closed"
        case .general: return "wrench.and.screwdriver"
        }
    }
}
