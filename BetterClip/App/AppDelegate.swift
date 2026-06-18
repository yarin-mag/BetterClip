// BetterClip/App/AppDelegate.swift
import AppKit
import SwiftUI
import KeyboardShortcuts
import LaunchAtLogin

extension KeyboardShortcuts.Name {
    static let togglePanel = Self("togglePanel", default: .init(.v, modifiers: [.command, .shift]))
}

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panelController: PanelController!
    private var preferencesWindow: NSWindow?
    private var snippetsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        panelController = PanelController()
        ClipboardMonitor.shared.start()
        setupHotkey()
        requestAccessibilityIfNeeded()

        if Preferences.shared.launchAtLogin {
            LaunchAtLogin.isEnabled = true
        }
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = StatusBarIcon.makeImage()
        statusItem.button?.toolTip = "BetterClip"

        let menu = NSMenu()
        menu.addItem(withTitle: "Open BetterClip", action: #selector(togglePanel), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Manage Snippets", action: #selector(openSnippetManager), keyEquivalent: "")
        menu.addItem(withTitle: "Preferences…", action: #selector(openPreferences), keyEquivalent: ",")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit BetterClip", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    private func setupHotkey() {
        KeyboardShortcuts.onKeyDown(for: .togglePanel) { [weak self] in
            // Capture frontmost app NOW, before BetterClip activates.
            let app = NSWorkspace.shared.frontmostApplication
            self?.panelController.capturedPreviousApp = app
            self?.togglePanel()
        }
    }

    @objc func togglePanel() {
        if Preferences.shared.layoutMode == .popover,
           let button = statusItem.button {
            panelController.showPopover(from: button)
        } else {
            panelController.toggle()
        }
    }

    @objc func openSnippetManager() {
        if snippetsWindow?.isVisible ?? false {
            snippetsWindow?.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 440),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Snippets"
        window.contentView = NSHostingView(rootView: SnippetManagerView())
        window.center()
        window.makeKeyAndOrderFront(nil)
        snippetsWindow = window
    }

    @objc func openPreferences() {
        if preferencesWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 320),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "BetterClip Preferences"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: PreferencesView())
            window.center()
            preferencesWindow = window
        }
        preferencesWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func requestAccessibilityIfNeeded() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true]
        AXIsProcessTrustedWithOptions(options)
    }

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

private enum StatusBarIcon {
    static func makeImage() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()

        NSColor.black.setStroke()
        NSColor.black.setFill()

        let body = NSBezierPath(roundedRect: NSRect(x: 4, y: 3, width: 10, height: 12),
                                xRadius: 2,
                                yRadius: 2)
        body.lineWidth = 1.6
        body.stroke()

        let clip = NSBezierPath(roundedRect: NSRect(x: 6.2, y: 13, width: 5.6, height: 2.4),
                                xRadius: 1.2,
                                yRadius: 1.2)
        clip.fill()

        let cut = NSBezierPath()
        cut.move(to: NSPoint(x: 7, y: 10.8))
        cut.line(to: NSPoint(x: 11, y: 7))
        cut.move(to: NSPoint(x: 11, y: 10.8))
        cut.line(to: NSPoint(x: 7, y: 7))
        cut.lineWidth = 1.45
        cut.lineCapStyle = .round
        cut.stroke()

        image.unlockFocus()
        image.isTemplate = true
        return image
    }
}
