// BetterClip/App/AppDelegate.swift
import AppKit
import SwiftUI
import KeyboardShortcuts
import LaunchAtLogin

extension KeyboardShortcuts.Name {
    static let togglePanel = Self("togglePanel", default: .init(.v, modifiers: [.command, .shift]))
}

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panelController: PanelController!
    private var preferencesWindow: NSWindow?

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
    }

    @objc func openPreferences() {
        if preferencesWindow == nil {
            preferencesWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 320),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            preferencesWindow?.title = "BetterClip Preferences"
            preferencesWindow?.contentView = NSHostingView(rootView: PreferencesView())
            preferencesWindow?.center()
        }
        preferencesWindow?.makeKeyAndOrderFront(nil)
    }

    private func requestAccessibilityIfNeeded() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true]
        AXIsProcessTrustedWithOptions(options)
    }
}