import AppKit
import Sparkle
import SwiftUI

@main
struct VoceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var controller = DictationController()
    @StateObject private var updaterController = UpdaterController()

    var body: some Scene {
        WindowGroup("Voce") {
            Group {
                if !controller.hasBootstrapped {
                    VoceDesign.windowBackground
                } else if controller.preferences.general.showOnboarding {
                    OnboardingView()
                        .environmentObject(controller)
                } else {
                    ContentView()
                        .environmentObject(controller)
                        .environmentObject(updaterController)
                }
            }
        }
        .defaultSize(width: VoceDesign.windowIdealWidth, height: VoceDesign.windowIdealHeight)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Delay slightly so the window is fully created before configuring transparency
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.configureTransparentWindows()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            if let reopenWindow = sender.windows.first(where: { !($0 is NSPanel) && $0.canBecomeMain }) {
                reopenWindow.makeKeyAndOrderFront(nil)
                configureTransparentWindows()
            }
        }
        return true
    }

    @MainActor
    private func configureTransparentWindows() {
        for window in NSApp.windows where isPrimaryVoceWindow(window) {
            window.isOpaque = false
            window.backgroundColor = .clear
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
        }
    }

    @MainActor
    private func isPrimaryVoceWindow(_ window: NSWindow) -> Bool {
        guard !(window is NSPanel) else {
            return false
        }

        return window.title == "Voce"
    }
}
