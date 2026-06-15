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
            if let hash = clip.blobHash, let data = BlobStore.shared.read(hash: hash) {
                pasteboard.setData(data, forType: .tiff)
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

    // Requires Accessibility permission (prompted once at startup). Posts to target PID when given.
    static func simulatePaste(toPid pid: pid_t? = nil) {
        guard AXIsProcessTrusted() else { return }
        let src = CGEventSource(stateID: .hidSystemState)
        guard let vDown = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true),
              let vUp   = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false) else { return }
        vDown.flags = .maskCommand
        vUp.flags   = .maskCommand
        if let pid {
            vDown.postToPid(pid)
            vUp.postToPid(pid)
        } else {
            vDown.post(tap: .cgAnnotatedSessionEventTap)
            vUp.post(tap: .cgAnnotatedSessionEventTap)
        }
    }
}
