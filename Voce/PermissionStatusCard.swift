import SwiftUI

struct PermissionStatusCard: View {
    let title: String
    let description: String
    let status: PermissionDiagnostics.AccessStatus
    let onRequest: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: VoceDesign.md) {
            Image(systemName: statusIconName)
                .font(.system(size: VoceDesign.iconLG))
                .foregroundStyle(statusColor)

            VStack(alignment: .leading, spacing: VoceDesign.xxs) {
                Text(title)
                    .font(VoceDesign.bodyEmphasis())
                    .foregroundStyle(VoceDesign.textPrimary)

                Text(description)
                    .font(VoceDesign.caption())
                    .foregroundStyle(VoceDesign.textSecondary)
            }

            Spacer()

            Text(status.rawValue)
                .font(VoceDesign.label())
                .foregroundStyle(statusColor)
                .padding(.horizontal, VoceDesign.sm)
                .padding(.vertical, VoceDesign.xxs)
                .background(statusColor.opacity(VoceDesign.opacitySubtle))
                .clipShape(Capsule())
                .accessibilityLabel("Status: \(status.rawValue)")

            actionButton
        }
        .padding(VoceDesign.md)
        .glassBackground(cornerRadius: VoceDesign.radiusSmall)
        .overlay(
            RoundedRectangle(cornerRadius: VoceDesign.radiusSmall)
                .stroke(statusBorderColor, lineWidth: VoceDesign.borderThin)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(status.rawValue). \(description)")
    }

    private var statusIconName: String {
        switch status {
        case .granted: return "checkmark.circle.fill"
        case .denied: return "xmark.circle.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    private var statusColor: Color {
        switch status {
        case .granted: return VoceDesign.success
        case .denied: return VoceDesign.error
        case .unknown: return VoceDesign.warning
        }
    }

    private var statusBorderColor: Color {
        switch status {
        case .granted: return VoceDesign.successBorder
        case .denied: return VoceDesign.errorBorder
        case .unknown: return VoceDesign.border
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch status {
        case .granted:
            EmptyView()
        case .denied:
            Button("Open Settings") {
                onOpenSettings()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel("Open \(title) settings")
        case .unknown:
            Button("Grant") {
                onRequest()
            }
            .buttonStyle(.borderedProminent)
            .tint(VoceDesign.accent)
            .controlSize(.small)
            .accessibilityLabel("Grant \(title) permission")
        }
    }
}
