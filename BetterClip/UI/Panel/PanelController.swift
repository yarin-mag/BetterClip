// BetterClip/UI/Panel/PanelController.swift
import AppKit
import SwiftUI

final class PanelController {
    private var panel: NSPanel?
    private var popover: NSPopover?
    private let viewModel = AppViewModel()

    func toggle() {
        switch Preferences.shared.layoutMode {
        case .compact: toggleFloatingPanel(width: 480, height: 400)
        case .full:    toggleFloatingPanel(width: 720, height: 480)
        case .popover: togglePopover()
        }
    }

    private func toggleFloatingPanel(width: CGFloat, height: CGFloat) {
        if let panel, panel.isVisible {
            panel.orderOut(nil)
            return
        }

        let p = makePanel(width: width, height: height)
        let hostingView = NSHostingView(rootView: PanelView(viewModel: viewModel))
        hostingView.frame = p.contentView!.bounds
        hostingView.autoresizingMask = [.width, .height]

        let effect = NSVisualEffectView(frame: p.contentView!.bounds)
        effect.blendingMode = .behindWindow
        effect.material = .hudWindow
        effect.state = .active
        effect.autoresizingMask = [.width, .height]
        effect.addSubview(hostingView)
        p.contentView = effect

        p.center()
        p.makeKeyAndOrderFront(nil)
        panel = p
    }

    private func makePanel(width: CGFloat, height: CGFloat) -> NSPanel {
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
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

        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: p, queue: .main
        ) { [weak p] _ in p?.orderOut(nil) }

        return p
    }

    private func togglePopover() {
        // Handled via NSStatusItem button in AppDelegate
    }

    func close() {
        panel?.orderOut(nil)
        popover?.close()
    }
}