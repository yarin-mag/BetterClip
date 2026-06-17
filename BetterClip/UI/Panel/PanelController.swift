// BetterClip/UI/Panel/PanelController.swift
import AppKit
import SwiftUI
import Combine

class KeyAcceptingHostingView: NSHostingView<PanelView> {
    var viewModel: AppViewModel?
    private var lastArrowTime: TimeInterval = 0

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard let vm = viewModel else { super.keyDown(with: event); return }

        let isArrow = event.keyCode == 126 || event.keyCode == 125
        if isArrow && event.isARepeat {
            let now = Date().timeIntervalSinceReferenceDate
            guard now - lastArrowTime >= 0.05 else { return }
            lastArrowTime = now
        }

        switch event.keyCode {
        case 126: vm.moveSelectionUp()
        case 125: vm.moveSelectionDown()
        case 123: vm.switchTabLeft()
        case 124: vm.switchTabRight()
        case 36:  vm.pasteSelected()
        case 53:  vm.shouldClosePanel.send(())
        default:  super.keyDown(with: event)
        }
    }

    // ⌘A always focuses the search field and selects all text in it.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "a",
           let tf = firstSearchField() {
            window?.makeFirstResponder(tf)
            tf.selectText(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    func focusSearchField() {
        guard let tf = firstSearchField() else { return }
        window?.makeFirstResponder(tf)
    }

    private func firstSearchField(in view: NSView? = nil) -> NSTextField? {
        let root = view ?? self
        for sub in root.subviews {
            if let tf = sub as? NSTextField, tf.isEditable { return tf }
            if let found = firstSearchField(in: sub) { return found }
        }
        return nil
    }
}

final class PanelController {
    private var panel: NSPanel?
    private var popover: NSPopover?
    private let viewModel = AppViewModel()
    private var cancellables = Set<AnyCancellable>()
    private var panelCancellables = Set<AnyCancellable>()
    private var panelResignObserver: NSObjectProtocol?
    private var escapeMonitor: Any?
    var capturedPreviousApp: NSRunningApplication?
    private weak var hostingView: KeyAcceptingHostingView?

    func toggle() {
        switch Preferences.shared.layoutMode {
        case .compact: toggleFloatingPanel(width: 480, height: 400)
        case .full:    toggleFloatingPanel(width: 720, height: 480)
        case .popover: togglePopover()
        }
    }

    func showPopover(from button: NSStatusBarButton) {
        if let pop = popover, pop.isShown {
            pop.close()
            return
        }
        let pop = NSPopover()
        pop.contentSize = NSSize(width: 320, height: 480)
        pop.behavior = .transient
        pop.contentViewController = NSHostingController(
            rootView: PanelView(viewModel: viewModel).frame(width: 320)
        )
        pop.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover = pop
    }

    private func toggleFloatingPanel(width: CGFloat, height: CGFloat) {
        if let panel, panel.isVisible {
            viewModel.pasteSelected()
            return
        }
        // Ensure any ghost panel is gone before creating a new one
        hideFloatingPanel()
        panel = nil

        viewModel.searchQuery = ""
        viewModel.previousApp = capturedPreviousApp

        let p = makePanel(width: width, height: height)
        let hostingView = KeyAcceptingHostingView(rootView: PanelView(viewModel: viewModel))
        hostingView.viewModel = viewModel
        hostingView.frame = p.contentView!.bounds
        hostingView.autoresizingMask = [.width, .height]
        self.hostingView = hostingView

        let effect = NSVisualEffectView(frame: p.contentView!.bounds)
        effect.blendingMode = .behindWindow
        effect.material = .hudWindow
        effect.state = .active
        effect.autoresizingMask = [.width, .height]
        effect.addSubview(hostingView)
        p.contentView = effect

        panelCancellables.removeAll()
        removeEscapeMonitor()
        viewModel.shouldClosePanel
            .sink { [weak self] in
                self?.hideFloatingPanel()
            }
            .store(in: &panelCancellables)
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.viewModel.shouldClosePanel.send()
                return nil
            }
            return event
        }

        p.center()
        p.makeFirstResponder(hostingView)
        p.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel = p

        // Focus search field after window is key and SwiftUI has rendered
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak hostingView] in
            hostingView?.focusSearchField()
        }
    }

    private func makePanel(width: CGFloat, height: CGFloat) -> NSPanel {
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.titlebarAppearsTransparent = true
        p.titleVisibility = .hidden
        p.isMovableByWindowBackground = true
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true

        p.contentView?.wantsLayer = true
        p.contentView?.layer?.cornerRadius = 12
        p.contentView?.layer?.masksToBounds = true

        panelResignObserver.flatMap { NotificationCenter.default.removeObserver($0) }
        panelResignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: p, queue: .main
        ) { [weak self] _ in self?.hideFloatingPanel() }

        return p
    }

    private func togglePopover() {
        // Handled via menu action in AppDelegate
    }

    func close() {
        hideFloatingPanel()
        popover?.close()
    }

    private func hideFloatingPanel() {
        removeEscapeMonitor()
        panel?.orderOut(nil)
    }

    private func removeEscapeMonitor() {
        if let m = escapeMonitor {
            NSEvent.removeMonitor(m)
            escapeMonitor = nil
        }
    }
}
