import AppKit
import SwiftUI
import VoceKit

enum VoceTab: String, CaseIterable {
    case record = "Record"
    case history = "History"
    case settings = "Settings"

    var icon: String {
        switch self {
        case .record: return "mic.fill"
        case .history: return "clock.fill"
        case .settings: return "gearshape"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var controller: DictationController
    @State private var selectedTab: VoceTab = .record
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            // Glass header bar
            HStack(spacing: VoceDesign.md) {
                Text("Voce")
                    .font(VoceDesign.heading1())
                    .foregroundStyle(VoceDesign.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                Spacer()

                // Glass tab bar
                HStack(spacing: VoceDesign.xxs) {
                    ForEach(VoceTab.allCases, id: \.self) { tab in
                        tabButton(tab)
                    }
                }
                .padding(VoceDesign.xs)
                .glassBackground(cornerRadius: VoceDesign.radiusPill)

                Spacer()

                Button {
                    appMainWindow()?.orderOut(nil)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: VoceDesign.iconSM, weight: .medium))
                        .foregroundStyle(VoceDesign.textSecondary)
                        .frame(width: VoceDesign.xl, height: VoceDesign.xl)
                }
                .buttonStyle(.plain)
                .help("Hide Window")
                .accessibilityLabel("Hide Window")
            }
            .padding(.horizontal, VoceDesign.lg)
            .padding(.vertical, VoceDesign.sm)
            .background {
                Rectangle()
                    .fill(VoceDesign.surfaceSolid.opacity(0.96))
                    .overlay(.regularMaterial.opacity(0.28))
            }

            // Tab content
            ZStack {
                RecordTab()
                    .tabContentVisibility(selectedTab == .record)

                HistoryTab()
                    .tabContentVisibility(selectedTab == .history)

                SettingsView()
                    .tabContentVisibility(selectedTab == .settings)
            }
            .animation(
                reduceMotion ? nil : .easeInOut(duration: VoceDesign.animationNormal),
                value: selectedTab
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, VoceDesign.lg)
        }
        .background {
            ZStack {
                VoceDesign.windowBackground
                LinearGradient(
                    colors: [
                        VoceDesign.skyBlue.opacity(0.10),
                        Color.clear,
                        VoceDesign.wheat.opacity(0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .frame(
            minWidth: VoceDesign.windowMinWidth,
            idealWidth: VoceDesign.windowIdealWidth,
            minHeight: VoceDesign.windowMinHeight,
            idealHeight: VoceDesign.windowIdealHeight
        )
        .task {
            await controller.refreshHistory()
        }
        .onAppear {
            appMainWindow()?.setFrameAutosaveName("VoceMainWindow")
        }
    }

    private func tabButton(_ tab: VoceTab) -> some View {
        Button {
            withAnimation(.easeInOut(duration: VoceDesign.animationFast)) {
                selectedTab = tab
            }
        } label: {
            HStack(spacing: VoceDesign.xs) {
                Image(systemName: tab.icon)
                    .font(.system(size: VoceDesign.iconSM))
                if selectedTab == tab {
                    Text(tab.rawValue)
                        .font(VoceDesign.captionEmphasis())
                }
            }
            .foregroundStyle(selectedTab == tab ? VoceDesign.accent : VoceDesign.textSecondary)
            .padding(.horizontal, selectedTab == tab ? VoceDesign.md : VoceDesign.sm)
            .padding(.vertical, VoceDesign.xs + VoceDesign.xxs)
            .background(
                selectedTab == tab
                    ? AnyShapeStyle(VoceDesign.accent.opacity(0.10))
                    : AnyShapeStyle(Color.clear)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.rawValue)
        .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
    }

    private func appMainWindow() -> NSWindow? {
        NSApp.windows.first { !($0 is NSPanel) && $0.canBecomeMain }
            ?? NSApp.windows.first { !($0 is NSPanel) }
    }
}

private struct TabContentVisibilityModifier: ViewModifier {
    let isVisible: Bool

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .opacity(isVisible ? 1 : 0)
            .allowsHitTesting(isVisible)
            .accessibilityHidden(!isVisible)
            .zIndex(isVisible ? 1 : 0)
    }
}

private extension View {
    func tabContentVisibility(_ isVisible: Bool) -> some View {
        modifier(TabContentVisibilityModifier(isVisible: isVisible))
    }
}
