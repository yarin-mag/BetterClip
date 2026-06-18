// BetterClip/Core/PasteboardWriter.swift
import AppKit

struct PasteboardWriter {
    static func write(clip: Clip) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        switch clip.type {
        case .text, .url:
            if let text = clip.textContent {
                pasteboard.setString(text, forType: .string)
            }
        case .image:
            if let hash = clip.blobHash, let data = BlobStore.shared.read(hash: hash),
                let image = NSImage(data: data) {
                pasteboard.writeObjects([image])
            }
        default:
            break
        }
        ClipboardMonitor.shared.ignoreChangeCount(pasteboard.changeCount)
    }

    static func write(snippet: Snippet) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(snippet.content, forType: .string)
        ClipboardMonitor.shared.ignoreChangeCount(pasteboard.changeCount)
    }

    static func hasAccessibilityPermission() -> Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibilityPermission() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true]
        AXIsProcessTrustedWithOptions(options)
    }

    // The destination app is activated before this runs, so post to the active session.
    @discardableResult
    static func simulatePaste(
        isTrusted: () -> Bool = { AXIsProcessTrusted() },
        post: (CGEvent) -> Void = { $0.post(tap: .cghidEventTap) }
    ) -> Bool {
        guard isTrusted() else { return false }
        let src = CGEventSource(stateID: .hidSystemState)
        guard let vDown = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true),
              let vUp   = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false) else { return false }
        vDown.flags = .maskCommand
        vUp.flags   = .maskCommand
        post(vDown)
        post(vUp)
        return true
    }
}
