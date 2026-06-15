# BetterClip — Architecture

## Overview

BetterClip is a native macOS menu-bar app (macOS 14+, Swift 5, SwiftUI + AppKit hybrid). It monitors the system clipboard every 300ms, persists history and user snippets to SQLite, and exposes them through a global hotkey panel with full-text search.

---

## Layer Map

```
BetterClip/
├── App/          AppDelegate — lifecycle, menu bar, hotkey registration
├── Core/         Stateful singletons — DB, clipboard, blob store, preferences
├── Models/       Value types — Clip, Snippet, SnippetFolder (GRDB records)
└── UI/
    ├── Panel/    PanelController + AppViewModel + history/snippet views
    ├── Preferences/  PreferencesView
    └── Snippets/ Snippet manager views
```

---

## Component Reference

### `AppDelegate` — App/AppDelegate.swift

Entry point (`@main`). Owns:
- `NSStatusItem` — menu bar button (📋)
- `PanelController` — panel/popover lifecycle
- Global hotkey (⌘⇧V) via `KeyboardShortcuts`

On hotkey fire, captures `NSWorkspace.frontmostApplication` **before** activating BetterClip — this reference is used later to restore focus and send ⌘V to the right process.

Requests Accessibility permission on first launch via `AXIsProcessTrustedWithOptions`.

---

### `ClipboardMonitor` — Core/ClipboardMonitor.swift

Polls `NSPasteboard.general.changeCount` every 300ms on the main `RunLoop` (`.common` mode).

**On change:**
1. `read(_:)` — extracts text / image (TIFF or PNG, capped at `maxImageSizeMB`) / URL from pasteboard
2. Deduplicates against `Database.mostRecentClip()` — skips if same text or blob hash
3. Checks `ignoredChangeCounts` — skips counts recorded by `PasteboardWriter` (prevents re-inserting just-pasted content)
4. `Database.insertClip()` — persists the new clip
5. `Database.trimClips(keepingLatest: Preferences.historyLimit)` — enforces history cap
6. Publishes on `newClipPublisher` → `AppViewModel.refresh()`

**Self-suppress mechanism:** `ignoredChangeCounts: Set<Int>` holds change counts written by BetterClip itself. `PasteboardWriter` calls `ignoreChangeCount(pasteboard.changeCount)` after every write. `poll()` removes-and-skips any matching count. This prevents pasting from history from duplicating the pasted item at the top.

---

### `PasteboardWriter` — Core/PasteboardWriter.swift

Writes a `Clip` or `Snippet` to `NSPasteboard.general`, then records the resulting `changeCount` in `ClipboardMonitor.ignoredChangeCounts`.

For auto-paste, `simulatePaste(toPid:)` sends a CGEvent ⌘V keystroke. Guarded by `AXIsProcessTrusted()` — silently does nothing if Accessibility permission is not granted.

---

### `Database` — Core/Database.swift

SQLite wrapper using GRDB's thread-safe `DatabaseQueue`. Initialized as a lazy singleton pointing to `~/Library/Application Support/BetterClip/betterclip.sqlite`.

**Recovery:** if the initial open fails (corrupt file), deletes the file and retries. If the retry also fails → falls back to an in-memory `Database()` so the app never crashes at launch.

**Schema (v1 migration):**

| Table | Key columns |
|-------|-------------|
| `clips` | `id`, `type` (text/image/rtf/url/file), `textContent`, `blobHash`, `appSource`, `createdAt`, `lastUsedAt` |
| `clips_fts` | FTS5 virtual table synchronized with `clips.textContent` |
| `snippets` | `id`, `folderId`, `name`, `content`, `shortcut`, `createdAt`, `sortOrder` |
| `snippet_folders` | `id`, `name`, `parentId`, `sortOrder` |

**Search strategy (`searchClips`):**
1. Exact type-filter keywords (`img`, `url`, `text`, `file`) → filter by `type` column
2. FTS5 prefix query — tokens stripped to `[a-zA-Z0-9]`, wrapped as `"token"*`, joined with spaces
3. Fallback: `LOWER(textContent) LIKE ?` for Unicode / short queries

All SQL uses GRDB's parameterized `arguments:` API — no string interpolation into queries.

---

### `BlobStore` — Core/BlobStore.swift

Content-addressable file store for clipboard images. Directory: `~/Library/Application Support/BetterClip/blobs/`.

- `write(_ data: Data) throws -> String` — computes SHA-256 hex digest, writes atomically (skips if file already exists), returns the hash. Throws on failure so callers (ClipboardMonitor) can skip the DB insertion rather than creating orphaned references.
- `read(hash:)` — returns `Data?`
- `delete(hash:)` / `deleteAll()` — used by clear-history and clip deletion

SHA-256 digests are used as filenames, making blobs self-deduplicating: copying the same image twice stores one file.

---

### `SnippetStore` — Core/SnippetStore.swift

Thin facade over `Database` for snippet and folder CRUD. Hides DB details from the UI layer. Provides `createSnippet`, `createFolder`, `search`, `update`, `delete`, and `saveAsSnippet(clip:name:folderId:)`.

---

### `Preferences` — Core/Preferences.swift

`UserDefaults.standard` wrapper (injectable via `init(defaults:)` for testing).

| Key | Type | Default | Notes |
|-----|------|---------|-------|
| `layoutMode` | `LayoutMode` enum | `.full` | compact / full / popover |
| `historyLimit` | `Int` | 200 | Clamped to ≥ 50 in getter; UI stepper range 50–1000 |
| `maxImageSizeMB` | `Int` | 10 | Image capture cap |
| `launchAtLogin` | `Bool` | `true` | Delegates to `LaunchAtLogin` package |
| `autoPasteAndClose` | `Bool` | `false` | Auto ⌘V after panel closes |

The `historyLimit` getter enforces `v >= 50` to protect against legacy stored values from older app versions (which could permanently cap history to a small number).

---

### `AppViewModel` — UI/Panel/AppViewModel.swift

`ObservableObject` owned by `PanelController`. Single source of truth for the panel UI.

**Published state:** `clips`, `snippets`, `folders`, `selectedIndex`, `selectedTab`, `searchQuery`, `clipToSaveAsSnippet`

**`refresh(query:)`** — calls `Database.searchClips(query:limit: Preferences.historyLimit)` and `SnippetStore.search`. Resets `selectedIndex = 0`. Called on:
- Init
- `searchQuery` changes (debounced 80ms via Combine)
- `ClipboardMonitor.newClipPublisher` fires

**Paste flow:** `pasteClip()` → `PasteboardWriter.write()` → `updateClipLastUsed()` → `refresh()` → optionally `triggerPasteAndClose()` (0.15s delayed ⌘V to previous app PID).

---

### `PanelController` — UI/Panel/PanelController.swift

Creates and manages the floating `NSPanel` or `NSPopover`. Layout mode determines presentation:

| Mode | Window | Size |
|------|--------|------|
| compact | NSPanel (floating) | 480 × 400 |
| full | NSPanel (floating) | 720 × 480 |
| popover | NSPopover (transient) | 320 × 480 |

The floating panel uses `NSVisualEffectView` (HUD material) with rounded corners, `.floating` window level, and `canJoinAllSpaces` so it appears on all Spaces and over full-screen apps. Auto-closes on `NSWindow.didResignKeyNotification`.

`KeyAcceptingHostingView` (`NSHostingView` subclass) intercepts keyboard events and routes arrow keys, Enter, and Escape to `AppViewModel` methods. ⌘A always focuses and selects the search field.

---

## Data Flow Diagrams

### Clipboard capture

```
User copies → NSPasteboard.changeCount++
    ↓ (within 300ms)
ClipboardMonitor.poll()
    ↓
read() → Clip value (text / image / URL)
    ↓
dedup: clip == mostRecentClip? → skip
    ↓
ignoredChangeCounts.remove(count) != nil? → skip
    ↓
Database.insertClip()
Database.trimClips(keepingLatest: historyLimit)
    ↓
newClipPublisher.send()
    ↓
AppViewModel.refresh() → UI update
```

### Paste (auto-paste mode)

```
User selects clip → AppViewModel.pasteClip()
    ↓
PasteboardWriter.write(clip:)
    ├── writes to NSPasteboard
    └── ClipboardMonitor.ignoreChangeCount(pasteboard.changeCount)
    ↓
Database.updateClipLastUsed(id:)
AppViewModel.refresh()
    ↓
shouldClosePanel.send() → panel closes
previousApp.activate()
    ↓ (0.15s delay)
PasteboardWriter.simulatePaste(toPid:) → CGEvent ⌘V
```

### Hotkey activation

```
User presses ⌘⇧V
    ↓
KeyboardShortcuts callback (AppDelegate)
    ├── capture NSWorkspace.frontmostApplication
    └── PanelController.toggle()
        ↓
        makePanel / showPopover
        NSApp.activate()
        ↓ (0.15s delay)
        KeyAcceptingHostingView.focusSearchField()
```

---

## Storage Layout

```
~/Library/Application Support/BetterClip/
├── betterclip.sqlite     SQLite database (clips + snippets + folders)
└── blobs/
    ├── <sha256hex>       image blob (content-addressed by SHA-256)
    └── ...
```

---

## Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| [GRDB](https://github.com/groue/GRDB.swift) | 6.0.0+ | SQLite ORM, FTS5, DatabaseQueue |
| [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) | 2.0.0+ | Global hotkey registration |
| [LaunchAtLogin](https://github.com/sindresorhus/LaunchAtLogin-Modern) | 1.0.0+ | Launch-at-login Service Management API |

---

## macOS Permissions

| Permission | When requested | Required for |
|-----------|---------------|-------------|
| Accessibility (`AXIsProcessTrusted`) | First launch prompt | ⌘V CGEvent simulation (auto-paste) |
| Apple Events (`com.apple.security.automation.apple-events`) | Declared in entitlements | Apple Events automation |

Auto-paste silently no-ops if Accessibility is not granted — panel still opens and clipboard write still works; only the ⌘V simulation is skipped.

---

## Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| Single-process, no IPC | No XPC / Mach / DistributedNotifications; minimizes attack surface |
| Content-addressed blob store | Identical images stored once; hash can't contain path separators (SHA-256 hex) |
| FTS5 `synchronize(withTable:)` | GRDB keeps FTS index consistent with `clips` automatically; no manual trigger needed |
| All SQL parameterized | GRDB `arguments:` everywhere; string interpolation into SQL never used |
| `ignoredChangeCounts` self-suppress | Prevents pasting from history creating a duplicate entry at the top |
| `historyLimit` minimum clamp (≥ 50) | Protects against legacy UserDefaults values from older app versions |
| `BlobStore.write() throws` | Disk-full failures propagate; ClipboardMonitor skips DB insertion on failure — no orphaned hash references |
| `Database` in-memory fallback | Recovery path can never crash the app; history is lost for the session but app stays functional |

---

## Test Coverage

Tests live in `BetterClipTests/`. All DB tests use in-memory `Database()` (no disk I/O, no state leakage between tests). Preferences tests use an isolated `UserDefaults` suite destroyed in `tearDown`.

| Test file | Coverage |
|-----------|---------|
| `AppViewModelCrashTests` | `selectedIndex` boundary safety (negative index guard) |
| `BlobStoreTests` | write/read/dedup/delete; `throws` on read-only directory |
| `ClipboardMonitorTests` | `ignoredChangeCounts` store and consume mechanics |
| `DatabaseTests` | CRUD, FTS5 search, trim, snippet/folder ops, corrupt-DB recovery, fetch limit |
| `PreferencesTests` | `historyLimit` clamp, default, boundary (50), zero, valid stored value |

```bash
xcodebuild test -scheme BetterClip -destination 'platform=macOS'
```

---

## npm Installer (`npm/bin/install.js`)

Published as `@betterclip/betterclip` on npm. On install:

1. Downloads `BetterClip-{VERSION}.dmg` from GitHub Releases over HTTPS
2. Downloads companion `.sha256` checksum file from the same release
3. Verifies SHA-256 digest (aborts if mismatch)
4. Validates redirect `Location` headers against allowed domains (`github.com`, `objects.githubusercontent.com`, `codeload.github.com`)
5. Mounts DMG with `hdiutil attach`
6. Copies `BetterClip.app` to `/Applications`
7. Unmounts and cleans up temp files

**Release pipeline:** the tag-triggered GitHub Actions workflow tests the app, builds the DMG, generates and verifies `BetterClip-{VERSION}.dmg.sha256`, then publishes both assets.
