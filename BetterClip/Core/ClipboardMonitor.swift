// BetterClip/Core/ClipboardMonitor.swift
import AppKit
import Combine

final class ClipboardMonitor {
    static let shared = ClipboardMonitor()

    let newClipPublisher = PassthroughSubject<Clip, Never>()

    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    private var timer: Timer?

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        guard let clip = read(pasteboard) else { return }

        // Dedup: skip if identical to most recent clip
        if let recent = try? Database.shared.mostRecentClip() {
            if clip.type == .text, clip.textContent == recent.textContent { return }
            if let h = clip.blobHash, h == recent.blobHash { return }
        }

        var mutableClip = clip
        try? Database.shared.insertClip(&mutableClip)
        try? Database.shared.trimClips(keepingLatest: Preferences.shared.historyLimit)
        newClipPublisher.send(mutableClip)
    }

    private func read(_ pasteboard: NSPasteboard) -> Clip? {
        let appSource = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let now = Date()

        if let string = pasteboard.string(forType: .string), !string.isEmpty {
            let maxTextBytes = 10 * 1_024 * 1_024
            let text = string.utf8.count <= maxTextBytes ? string : String(string.prefix(maxTextBytes / 4))
            return Clip(id: nil, type: .text, textContent: text, blobHash: nil,
                        appSource: appSource, createdAt: now, lastUsedAt: now)
        }

        let maxBytes = Preferences.shared.maxImageSizeMB * 1_024 * 1_024
        if let data = pasteboard.data(forType: .tiff) ?? pasteboard.data(forType: .png),
           data.count <= maxBytes {
            let hash = BlobStore.shared.write(data)
            return Clip(id: nil, type: .image, textContent: nil, blobHash: hash,
                        appSource: appSource, createdAt: now, lastUsedAt: now)
        }

        if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
           let url = urls.first {
            return Clip(id: nil, type: .url, textContent: url.absoluteString, blobHash: nil,
                        appSource: appSource, createdAt: now, lastUsedAt: now)
        }

        return nil
    }
}
