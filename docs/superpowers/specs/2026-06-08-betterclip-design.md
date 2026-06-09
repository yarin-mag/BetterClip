# BetterClip — Design Spec
**Date:** 2026-06-08

## Overview

macOS clipboard manager with history, search, and saved snippets. Global hotkey opens a floating panel above all windows. Keyboard-first UX, smooth animations, native macOS look and feel.

---

## Core Features

| Feature | Detail |
|---|---|
| Clipboard history | Auto-captured, last 200 items, text + images + files + RTF + URLs |
| Search | Unified full-text search across history and snippets, 80ms debounce |
| Snippets | Manually saved permanent items, organized in folder tree |
| Panel | Floating NSPanel, 3 layout modes, frosted glass, dark/light adaptive |
| Global hotkey | ⌘⇧V — user-configurable in Preferences |
| Menu bar | NSStatusItem icon, always running in background |
| Auto-paste | ↩ pastes selected item directly into previous app |

---

## Tech Stack

- **Language:** Swift 5.9+
- **UI:** AppKit (NSPanel shell) + SwiftUI (content views)
- **Database:** SQLite via [GRDB](https://github.com/groue/GRDB.swift) with FTS5
- **Global hotkey:** [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts)
- **Login item:** [LaunchAtLogin](https://github.com/sindresorhus/LaunchAtLogin)
- **macOS target:** 13.0+ (Ventura)
- **Package manager:** Swift Package Manager

---

## Folder Structure

```
BetterClip/
├── BetterClip.xcodeproj
└── BetterClip/
    ├── App/
    │   ├── AppDelegate.swift          — menu bar, hotkey registration, polling timer
    │   └── BetterClipApp.swift        — @main entry point
    ├── Core/
    │   ├── ClipboardMonitor.swift     — polls NSPasteboard.changeCount every 300ms
    │   ├── Database.swift             — GRDB setup, migrations, FTS5 queries
    │   ├── BlobStore.swift            — image/file storage on disk keyed by SHA256
    │   └── SnippetStore.swift         — CRUD for snippets and folders
    ├── Models/
    │   ├── Clip.swift                 — history item model
    │   ├── Snippet.swift              — snippet model
    │   └── SnippetFolder.swift        — folder model
    ├── UI/
    │   ├── Panel/
    │   │   ├── PanelController.swift  — NSPanel lifecycle, show/hide, spring animation
    │   │   ├── PanelView.swift        — SwiftUI root: search bar + list + preview
    │   │   ├── ClipRowView.swift      — single history item row
    │   │   ├── SnippetRowView.swift   — single snippet row
    │   │   └── PreviewPane.swift      — right-side preview (text/image)
    │   ├── Snippets/
    │   │   ├── SnippetEditorView.swift — create/edit snippet
    │   │   └── FolderTreeView.swift   — folder sidebar in snippet manager
    │   └── Preferences/
    │       └── PreferencesView.swift  — settings: layout, history limit, hotkey
    └── Resources/
        └── Assets.xcassets
```

---

## Data Layer

### SQLite Schema

```sql
-- Clipboard history
CREATE TABLE clips (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    type          TEXT NOT NULL,         -- text | image | rtf | url | file
    text_content  TEXT,                  -- searchable text (nil for images)
    blob_hash     TEXT,                  -- SHA256 → BlobStore file
    app_source    TEXT,                  -- bundle ID of app that copied
    created_at    INTEGER NOT NULL,      -- Unix timestamp
    last_used_at  INTEGER NOT NULL
);

CREATE VIRTUAL TABLE clips_fts USING fts5(
    text_content,
    content=clips,
    content_rowid=id
);

-- Snippets
CREATE TABLE snippet_folders (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    name       TEXT NOT NULL,
    parent_id  INTEGER REFERENCES snippet_folders(id),
    sort_order INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE snippets (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    folder_id  INTEGER REFERENCES snippet_folders(id),
    name       TEXT NOT NULL,
    content    TEXT NOT NULL,
    shortcut   TEXT,                     -- optional e.g. "cmd+1"
    created_at INTEGER NOT NULL,
    sort_order INTEGER NOT NULL DEFAULT 0
);
```

### BlobStore

Images and files stored at `~/Library/Application Support/BetterClip/blobs/<sha256>`. Referenced by hash in the `clips` table. Dedup is free — same image copied twice = one file.

---

## Clipboard Monitor

```
Timer (300ms)
  → read NSPasteboard.changeCount
  → if changed:
      → read all available types (text, image, rtf, url, file)
      → compute SHA256 of raw data
      → skip if hash matches most recent clip (dedup)
      → write to Database + BlobStore
      → trim history: delete oldest beyond limit (default 200)
      → notify UI via Combine publisher
```

---

## Panel

### Modes

| Mode | Size | Layout | Default |
|---|---|---|---|
| A — Compact | 480×400 | Search + list only | |
| B — Full | 720×480 | Search + list + preview pane | ✓ |
| C — Popover | 320×auto | Anchored to menu bar icon | |

### Behavior

- `NSPanel` with `.nonactivatingPanel` — opening panel doesn't steal focus from previous app
- `.canJoinAllSpaces` — visible on every Space/fullscreen app
- `NSVisualEffectView` with `.hudWindow` material — frosted glass
- Show: spring animation, 0.2s, panel slides in from slightly above center
- Hide: instant on ↩ paste, spring out on ⎋
- Clicking outside panel dismisses it
- Search bar auto-focuses on show

### Keyboard Navigation

| Key | Action |
|---|---|
| Type | Searches immediately |
| ↑ ↓ | Navigate list |
| ↩ | Paste selected item, close panel |
| ⌘↩ | Copy to clipboard only (no paste) |
| ⌫ | Delete selected item from history |
| ⎋ | Close panel |
| ⇥ | Switch between History / Snippets tab |

---

## Search

- Single search bar queries both history and snippets
- Snippets always appear at top of results (pinned section)
- History results ranked by FTS5 relevance, then recency
- Empty query → show most recent 50 items
- Image items matched by app source name and date, not content

---

## Snippets

- Created by: right-clicking any history item → "Save as Snippet", or manually in Snippet Editor
- Organized in a folder tree (unlimited depth, drag to reorder)
- Text content only (images stay in history only)
- Optional per-snippet shortcut (⌘1 through ⌘9 configurable)
- Accessible from same panel under Snippets tab, or via dedicated Snippet Manager window from menu bar

---

## Paste Behavior

1. User selects item and presses ↩
2. Panel hides immediately (feels instant)
3. Item written to `NSPasteboard.general`
4. `CGEvent` synthesizes ⌘V to the previously focused app
5. `last_used_at` updated in DB
6. Item moves to top of history list

---

## Preferences

| Setting | Default |
|---|---|
| Panel layout mode | B — Full |
| Global hotkey | ⌘⇧V |
| History limit | 200 items |
| Max image size to store | 10 MB |
| Launch at login | On |
| Clear history on quit | Off |

---

## Permissions Required

| Permission | Why |
|---|---|
| Accessibility | Simulate ⌘V via CGEvent for auto-paste |
| None for hotkey | KeyboardShortcuts lib uses CGEventTap without Accessibility |

App prompts for Accessibility on first launch with a clear explanation. Auto-paste degrades gracefully (copies to clipboard only) if permission denied.

---

## Non-Goals

- Cloud sync
- iOS / iPadOS version
- Password / sensitive data filtering
- Browser extension
