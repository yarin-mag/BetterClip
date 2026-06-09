// BetterClip/App/AppDelegate.swift
import AppKit
import KeyboardShortcuts
import LaunchAtLogin

extension KeyboardShortcuts.Name {
    static let togglePanel = Self("togglePanel", default: .init(.v, modifiers: [.command, .shift]))
}

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panelController: PanelController!

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
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "📋"
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
        KeyboardShortcuts.onKeyUp(for: .togglePanel) { [weak self] in
            self?.togglePanel()
        }
    }

    @objc func togglePanel() {
        panelController.toggle()
    }

    @objc func openSnippetManager() {
        // Opened in Task 15
    }

    @objc func openPreferences() {
        // Opened in Task 16
    }

    private func requestAccessibilityIfNeeded() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true]
        AXIsProcessTrustedWithOptions(options)
    }
}