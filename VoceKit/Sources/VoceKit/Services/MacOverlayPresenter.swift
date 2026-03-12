#if os(macOS)
import AppKit
import ApplicationServices
import QuartzCore

@MainActor
public final class MacOverlayPresenter: NSObject, OverlayPresenter {
    private enum LayoutMode {
        case compact
        case transcript
    }

    private static let axSelectedTextMarkerRangeAttribute = "AXSelectedTextMarkerRange"
    private static let axBoundsForTextMarkerRangeParameterizedAttribute = "AXBoundsForTextMarkerRange"
    private static let compactSize = NSSize(width: 260, height: 44)
    private static let transcriptSize = NSSize(width: 320, height: 84)

    public struct AnchorSnapshot: Sendable, Equatable {
        public let frame: CGRect

        public init(frame: CGRect) {
            self.frame = frame
        }
    }

    private var window: NSWindow?
    private var statusDot: NSView?
    private var statusTextField: NSTextField?
    private var transcriptScrollView: NSScrollView?
    private var transcriptTextView: NSTextView?
    private var timer: Timer?
    private var listeningStartDate: Date?
    private var listeningHandsFree = false
    private var pulseTimer: Timer?
    private var dotPulseHigh = true
    private var wasHidden = true
    private var anchorSnapshot: AnchorSnapshot?
    private var layoutMode: LayoutMode = .compact
    private var lastLiveTranscriptText: String = ""

    private static let dotBlue = NSColor(red: 0.32, green: 0.60, blue: 0.82, alpha: 1.0)

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    public override init() {
        super.init()
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(accessibilityDisplayOptionsDidChange(_:)),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
    }

    deinit {
        MainActor.assumeIsolated {
            timer?.invalidate()
            timer = nil
            pulseTimer?.invalidate()
            pulseTimer = nil
            NSWorkspace.shared.notificationCenter.removeObserver(self)
        }
    }

    /// Pre-create the overlay window so the first `show` has no lazy-init stutter.
    public func prepareWindow() {
        ensureWindow()
    }

    public func captureAnchorSnapshot() -> AnchorSnapshot? {
        guard AXIsProcessTrusted(),
              let frame = currentFocusedFrame() else {
            return nil
        }

        return AnchorSnapshot(frame: frame)
    }

    public func setAnchorSnapshot(_ snapshot: AnchorSnapshot?) {
        anchorSnapshot = snapshot
    }

    public func show(state: OverlayState) {
        ensureWindow()

        let isFirstShow = wasHidden
        wasHidden = false

        switch state {
        case .listening(let handsFree, _):
            applyLayout(.transcript)
            listeningHandsFree = handsFree
            listeningStartDate = Date()
            lastLiveTranscriptText = ""
            updateTranscript("Transcribing…")
            stopTimer()
            animateDotColor(Self.dotBlue)
            startDotPulse()

        case .liveTranscript(let text, _):
            applyLayout(.transcript)
            stopTimer()
            lastLiveTranscriptText = text
            updateTranscript(text)
            animateDotColor(Self.dotBlue)
            startDotPulse()

        case .transcribing:
            stopTimer()
            applyLayout(.transcript)
            updateTranscript(lastLiveTranscriptText.isEmpty ? "Transcribing…" : lastLiveTranscriptText)
            animateDotColor(.systemOrange)
            startDotPulse()

        case .inserted:
            applyLayout(.compact)
            stopTimer()
            stopDotPulse()
            updateText("Inserted")
            animateDotColor(.systemGreen)

        case .copiedOnly:
            applyLayout(.compact)
            stopTimer()
            stopDotPulse()
            updateText("Copied to clipboard")
            animateDotColor(.systemOrange)

        case .failure(let message):
            applyLayout(.compact)
            stopTimer()
            stopDotPulse()
            updateText("Error: \(message)")
            animateDotColor(.systemRed)
        }

        positionWindow()

        if isFirstShow && !reduceMotion {
            // Entrance animation: fade in + slide up
            window?.alphaValue = 0
            let finalOrigin = window?.frame.origin ?? .zero
            window?.setFrameOrigin(NSPoint(x: finalOrigin.x, y: finalOrigin.y - 20))
            window?.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.window?.animator().alphaValue = 1
                self.window?.animator().setFrameOrigin(finalOrigin)
            }
        } else {
            window?.alphaValue = 1
            window?.orderFrontRegardless()
        }
    }

    public func hide() {
        stopTimer()
        stopDotPulse()
        wasHidden = true
        anchorSnapshot = nil
        lastLiveTranscriptText = ""

        if !reduceMotion {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                self.window?.animator().alphaValue = 0
            }, completionHandler: {
                self.window?.orderOut(nil)
            })
        } else {
            window?.orderOut(nil)
        }
    }

    private func ensureWindow() {
        if window != nil {
            return
        }

        let contentRect = NSRect(origin: .zero, size: Self.compactSize)
        let panel = NSPanel(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.backgroundColor = .clear
        panel.level = .statusBar
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        // Glass background with vibrancy
        let vibrancy = NSVisualEffectView(frame: contentRect)
        vibrancy.material = .hudWindow
        vibrancy.blendingMode = .behindWindow
        vibrancy.state = .active
        vibrancy.wantsLayer = true
        vibrancy.layer?.cornerRadius = 22
        vibrancy.layer?.masksToBounds = true
        vibrancy.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.88).cgColor

        // Outer container for shadow + border (can't put shadow on clipped view)
        let container = NSView(frame: contentRect)
        container.wantsLayer = true
        container.layer?.cornerRadius = 22
        container.layer?.masksToBounds = false
        container.layer?.borderWidth = 0.5
        container.layer?.borderColor = NSColor.white.withAlphaComponent(0.25).cgColor
        container.layer?.shadowColor = NSColor.black.withAlphaComponent(0.10).cgColor
        container.layer?.shadowOffset = CGSize(width: 0, height: -2)
        container.layer?.shadowRadius = 20
        container.layer?.shadowOpacity = 1
        container.addSubview(vibrancy)
        vibrancy.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            vibrancy.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            vibrancy.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            vibrancy.topAnchor.constraint(equalTo: container.topAnchor),
            vibrancy.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        // Status dot
        let dot = NSView(frame: .zero)
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 6
        dot.layer?.backgroundColor = Self.dotBlue.cgColor
        dot.translatesAutoresizingMaskIntoConstraints = false
        vibrancy.addSubview(dot)
        self.statusDot = dot

        // Compact status text.
        let label = NSTextField(labelWithString: "Listening 00:00")
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        label.alignment = .left
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        vibrancy.addSubview(label)
        self.statusTextField = label

        // Transcript preview grows to three wrapped lines and follows the latest partials.
        let transcriptTextView = NSTextView(frame: .zero)
        transcriptTextView.drawsBackground = false
        transcriptTextView.isEditable = false
        transcriptTextView.isSelectable = false
        transcriptTextView.isVerticallyResizable = true
        transcriptTextView.isHorizontallyResizable = false
        transcriptTextView.textContainerInset = NSSize(width: 0, height: 1)
        transcriptTextView.font = .systemFont(ofSize: 13, weight: .medium)
        transcriptTextView.textColor = .labelColor
        transcriptTextView.alignment = .left
        transcriptTextView.textContainer?.lineBreakMode = .byWordWrapping
        transcriptTextView.textContainer?.widthTracksTextView = true

        let transcriptScrollView = NSScrollView(frame: .zero)
        transcriptScrollView.drawsBackground = false
        transcriptScrollView.borderType = .noBorder
        transcriptScrollView.hasVerticalScroller = false
        transcriptScrollView.hasHorizontalScroller = false
        transcriptScrollView.autohidesScrollers = true
        transcriptScrollView.verticalScrollElasticity = .none
        transcriptScrollView.horizontalScrollElasticity = .none
        transcriptScrollView.documentView = transcriptTextView
        transcriptScrollView.translatesAutoresizingMaskIntoConstraints = false
        transcriptScrollView.isHidden = true
        vibrancy.addSubview(transcriptScrollView)
        self.transcriptTextView = transcriptTextView
        self.transcriptScrollView = transcriptScrollView

        NSLayoutConstraint.activate([
            dot.leadingAnchor.constraint(equalTo: vibrancy.leadingAnchor, constant: 16),
            dot.centerYAnchor.constraint(equalTo: vibrancy.centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 12),
            dot.heightAnchor.constraint(equalToConstant: 12),

            label.leadingAnchor.constraint(equalTo: vibrancy.leadingAnchor, constant: 36),
            label.trailingAnchor.constraint(equalTo: vibrancy.trailingAnchor, constant: -16),
            label.centerYAnchor.constraint(equalTo: vibrancy.centerYAnchor),

            transcriptScrollView.leadingAnchor.constraint(equalTo: vibrancy.leadingAnchor, constant: 36),
            transcriptScrollView.trailingAnchor.constraint(equalTo: vibrancy.trailingAnchor, constant: -16),
            transcriptScrollView.topAnchor.constraint(equalTo: vibrancy.topAnchor, constant: 12),
            transcriptScrollView.bottomAnchor.constraint(equalTo: vibrancy.bottomAnchor, constant: -12)
        ])

        panel.contentView = container
        self.window = panel
    }

    private func animateDotColor(_ color: NSColor) {
        guard !reduceMotion else {
            statusDot?.layer?.backgroundColor = color.cgColor
            return
        }
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.25)
        statusDot?.layer?.backgroundColor = color.cgColor
        CATransaction.commit()
    }

    private func updateText(_ newText: String) {
        transcriptScrollView?.isHidden = true
        statusTextField?.isHidden = false
        guard !reduceMotion else {
            statusTextField?.stringValue = newText
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.1
            self.statusTextField?.animator().alphaValue = 0
        }, completionHandler: {
            self.statusTextField?.stringValue = newText
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                self.statusTextField?.animator().alphaValue = 1
            }
        })
    }

    private func updateTranscript(_ text: String) {
        statusTextField?.isHidden = true
        transcriptScrollView?.isHidden = false
        transcriptTextView?.string = text
        transcriptTextView?.scrollToEndOfDocument(nil)
    }

    private func applyLayout(_ newLayout: LayoutMode) {
        guard let window, layoutMode != newLayout else {
            if newLayout == .transcript {
                statusTextField?.isHidden = true
                transcriptScrollView?.isHidden = false
            } else {
                statusTextField?.isHidden = false
                transcriptScrollView?.isHidden = true
            }
            return
        }

        layoutMode = newLayout
        let targetSize = newLayout == .transcript ? Self.transcriptSize : Self.compactSize
        window.setContentSize(targetSize)
        positionWindow()
        if newLayout == .transcript {
            statusTextField?.isHidden = true
            transcriptScrollView?.isHidden = false
        } else {
            statusTextField?.isHidden = false
            transcriptScrollView?.isHidden = true
        }
    }

    private func startDotPulse() {
        stopDotPulse()
        dotPulseHigh = true
        statusDot?.alphaValue = 1.0
        let newTimer = Timer(timeInterval: 0.8, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.dotPulseHigh.toggle()
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.6
                    self.statusDot?.animator().alphaValue = self.dotPulseHigh ? 1.0 : 0.4
                }
            }
        }
        RunLoop.current.add(newTimer, forMode: .common)
        pulseTimer = newTimer
    }

    private func stopDotPulse() {
        pulseTimer?.invalidate()
        pulseTimer = nil
        statusDot?.alphaValue = 1.0
    }

    private func startTimer() {
        timer?.invalidate()
        let newTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateListeningText()
            }
        }
        RunLoop.current.add(newTimer, forMode: .common)
        timer = newTimer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        listeningStartDate = nil
    }

    private func updateListeningText() {
        guard let start = listeningStartDate else {
            statusTextField?.stringValue = "Listening 00:00"
            return
        }

        let elapsed = Int(Date().timeIntervalSince(start))
        let minutes = elapsed / 60
        let seconds = elapsed % 60
        let mode = listeningHandsFree ? "Hands-Free" : "Hold-to-Talk"
        statusTextField?.stringValue = "\(mode) \(String(format: "%02d:%02d", minutes, seconds))"
    }

    private func positionWindow() {
        guard let window else { return }

        if let anchoredOrigin = anchoredWindowOrigin(for: window) {
            window.setFrameOrigin(anchoredOrigin)
            return
        }

        centerWindowNearTop()
    }

    private func anchoredWindowOrigin(for window: NSWindow) -> NSPoint? {
        if let anchorSnapshot {
            return anchoredWindowOrigin(for: window, frame: anchorSnapshot.frame)
        }

        guard AXIsProcessTrusted(),
              let frame = currentFocusedFrame() else {
            return nil
        }

        return anchoredWindowOrigin(for: window, frame: frame)
    }

    private func anchoredWindowOrigin(for window: NSWindow, frame: CGRect) -> NSPoint? {
        let anchorPoint = NSPoint(x: frame.midX, y: frame.maxY)
        guard let screen = screen(containing: anchorPoint) else {
            return nil
        }

        let visibleFrame = screen.visibleFrame
        let margin: CGFloat = 12
        var x = anchorPoint.x - (window.frame.width / 2)
        var y = frame.maxY + margin

        x = min(max(x, visibleFrame.minX + margin), visibleFrame.maxX - window.frame.width - margin)
        y = min(y, visibleFrame.maxY - window.frame.height - margin)

        if y < visibleFrame.minY + margin {
            return nil
        }

        return NSPoint(x: x, y: y)
    }

    private func currentFocusedFrame() -> NSRect? {
        guard let element = focusedElement() else {
            return focusedWindowFrame()
        }

        if let markerBounds = selectedTextMarkerBounds(for: element) {
            return markerBounds
        }

        if let caretBounds = selectedTextBounds(for: element) {
            return caretBounds
        }

        if let elementFrame = elementFrame(for: element) {
            return elementFrame
        }

        return focusedWindowFrame()
    }

    private func focusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        ) == .success,
        let focusedRef,
        CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else {
            return nil
        }

        return unsafeDowncast(focusedRef as AnyObject, to: AXUIElement.self)
    }

    private func selectedTextMarkerBounds(for element: AXUIElement) -> NSRect? {
        var selectedMarkerRangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            Self.axSelectedTextMarkerRangeAttribute as CFString,
            &selectedMarkerRangeRef
        ) == .success,
        let selectedMarkerRangeRef else {
            return nil
        }

        var boundsRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            Self.axBoundsForTextMarkerRangeParameterizedAttribute as CFString,
            selectedMarkerRangeRef,
            &boundsRef
        ) == .success,
        let boundsRef,
        CFGetTypeID(boundsRef) == AXValueGetTypeID() else {
            return nil
        }

        let boundsValue = unsafeDowncast(boundsRef as AnyObject, to: AXValue.self)
        guard AXValueGetType(boundsValue) == .cgRect else {
            return nil
        }

        var rect = CGRect.zero
        guard AXValueGetValue(boundsValue, .cgRect, &rect),
              !rect.isNull,
              !rect.isInfinite,
              rect.width >= 0,
              rect.height >= 0 else {
            return nil
        }

        return rect
    }

    private func selectedTextBounds(for element: AXUIElement) -> NSRect? {
        var selectedRangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedRangeRef
        ) == .success,
        let selectedRangeRef,
        CFGetTypeID(selectedRangeRef) == AXValueGetTypeID() else {
            return nil
        }

        let selectedRangeValue = unsafeDowncast(selectedRangeRef as AnyObject, to: AXValue.self)
        guard AXValueGetType(selectedRangeValue) == .cfRange else {
            return nil
        }

        var boundsRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            selectedRangeValue,
            &boundsRef
        ) == .success,
        let boundsRef,
        CFGetTypeID(boundsRef) == AXValueGetTypeID() else {
            return nil
        }

        let boundsValue = unsafeDowncast(boundsRef as AnyObject, to: AXValue.self)
        guard AXValueGetType(boundsValue) == .cgRect else {
            return nil
        }

        var rect = CGRect.zero
        guard AXValueGetValue(boundsValue, .cgRect, &rect),
              !rect.isNull,
              !rect.isInfinite,
              rect.width >= 0,
              rect.height >= 0 else {
            return nil
        }

        return rect
    }

    private func elementFrame(for element: AXUIElement) -> NSRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionValue = positionRef,
              let sizeValue = sizeRef,
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
            return nil
        }

        let positionAXValue = unsafeDowncast(positionValue as AnyObject, to: AXValue.self)
        let sizeAXValue = unsafeDowncast(sizeValue as AnyObject, to: AXValue.self)

        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetType(positionAXValue) == .cgPoint,
              AXValueGetType(sizeAXValue) == .cgSize,
              AXValueGetValue(positionAXValue, .cgPoint, &point),
              AXValueGetValue(sizeAXValue, .cgSize, &size) else {
            return nil
        }

        return NSRect(origin: point, size: size)
    }

    private func focusedWindowFrame() -> NSRect? {
        let systemWide = AXUIElementCreateSystemWide()
        var appRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedApplicationAttribute as CFString,
            &appRef
        ) == .success,
        let appRef,
        CFGetTypeID(appRef) == AXUIElementGetTypeID() else {
            return nil
        }

        let appElement = unsafeDowncast(appRef as AnyObject, to: AXUIElement.self)
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &windowRef
        ) == .success,
        let windowRef,
        CFGetTypeID(windowRef) == AXUIElementGetTypeID() else {
            return nil
        }

        let windowElement = unsafeDowncast(windowRef as AnyObject, to: AXUIElement.self)
        return elementFrame(for: windowElement)
    }

    private func screen(containing point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
    }

    private func centerWindowNearTop() {
        guard let window,
              let screen = NSScreen.main else { return }

        let screenFrame = screen.visibleFrame
        let x = screenFrame.origin.x + (screenFrame.width - window.frame.width) / 2
        let y = screenFrame.origin.y + screenFrame.height - window.frame.height - 40
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    @objc
    private func accessibilityDisplayOptionsDidChange(_: Notification) {
        handleAccessibilityDisplayOptionsDidChange()
    }

    private func handleAccessibilityDisplayOptionsDidChange() {
        guard reduceMotion else { return }
        stopDotPulse()
    }
}
#endif
