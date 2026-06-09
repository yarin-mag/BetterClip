# BetterClip Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build BetterClip, a macOS clipboard manager with history, full-text search, saved snippets, and a global ⌘⇧V hotkey that opens a floating panel.

**Architecture:** AppKit NSPanel shell hosts SwiftUI content views. ClipboardMonitor polls NSPasteboard every 300ms and persists clips to SQLite via GRDB with FTS5. Three panel layout modes (compact / full+preview / popover) are user-configurable via Preferences.

**Tech Stack:** Swift 5.9+, AppKit + SwiftUI, GRDB 6.x, KeyboardShortcuts 2.x, LaunchAtLogin-Modern 1.x, XCTest, xcodegen

---

## File Map

| File | Responsibility |
|---|---|
| `project.yml` | xcodegen project spec |
| `BetterClip/Resources/Info.plist` | LSUIElement=YES, bundle metadata |
| `BetterClip/Resources/BetterClip.entitlements` | Apple Events permission for CGEvent paste |
| `BetterClip/App/AppDelegate.swift` | Entry point, menu bar icon, polling timer, hotkey |
| `BetterClip/Core/ClipboardMonitor.swift` | Poll changeCount, publish new clips via Combine |
| `BetterClip/Core/Database.swift` | GRDB setup, migrations, FTS5, all CRUD |
| `BetterClip/Core/BlobStore.swift` | SHA256-keyed binary storage for images |
| `BetterClip/Core/PasteboardWriter.swift` | Write clip to NSPasteboard, simulate ⌘V |
| `BetterClip/Core/Preferences.swift` | UserDefaults wrapper, layout mode, history limit |
| `BetterClip/Core/SnippetStore.swift` | Snippet + folder CRUD, wraps Database |
| `BetterClip/Models/Clip.swift` | Clip struct + GRDB conformance |
| `BetterClip/Models/Snippet.swift` | Snippet struct + GRDB conformance |
| `BetterClip/Models/SnippetFolder.swift` | SnippetFolder struct + GRDB conformance |
| `BetterClip/UI/Panel/PanelController.swift` | NSPanel lifecycle, 3 layout modes, animation |
| `BetterClip/UI/Panel/AppViewModel.swift` | ObservableObject, search debounce, paste/delete |
| `BetterClip/UI/Panel/PanelView.swift` | SwiftUI root: search bar + tabs + list |
| `BetterClip/UI/Panel/ClipRowView.swift` | Single history item row |
| `BetterClip/UI/Panel/PreviewPane.swift` | Right-side preview pane (mode B only) |
| `BetterClip/UI/Panel/SnippetRowView.swift` | Single snippet row |
| `BetterClip/UI/Snippets/SnippetEditorView.swift` | Create/edit snippet sheet |
| `BetterClip/UI/Snippets/FolderTreeView.swift` | Folder sidebar in snippet manager |
| `BetterClip/UI/Preferences/PreferencesView.swift` | Settings: layout, limit, hotkey, login |
| `BetterClipTests/DatabaseTests.swift` | GRDB insert, fetch, FTS5 search, trim |
| `BetterClipTests/BlobStoreTests.swift` | Write, read, dedup |

---

### Task 1: Project Scaffold

**Files:**
- Create: `project.yml`
- Create: `BetterClip/Resources/Info.plist`
- Create: `BetterClip/Resources/BetterClip.entitlements`
- Create: `BetterClip/App/AppDelegate.swift`

- [ ] **Step 1: Install xcodegen**

```bash
brew list xcodegen 2>/dev/null || brew install xcodegen
```

- [ ] **Step 2: Create folder structure**

```bash
mkdir -p BetterClip/App BetterClip/Core BetterClip/Models \
  BetterClip/UI/Panel BetterClip/UI/Snippets BetterClip/UI/Preferences \
  BetterClip/Resources BetterClipTests
```

- [ ] **Step 3: Write project.yml**

```yaml
name: BetterClip
options:
  deploymentTarget:
    macOS: "13.0"
  bundleIdPrefix: com.betterclip
  createIntermediateGroups: true
targets:
  BetterClip:
    type: application
    platform: macOS
    sources:
      - BetterClip
    settings:
      PRODUCT_BUNDLE_IDENTIFIER: com.betterclip.app
      MACOSX_DEPLOYMENT_TARGET: "13.0"
      INFOPLIST_FILE: BetterClip/Resources/Info.plist
      CODE_SIGN_ENTITLEMENTS: BetterClip/Resources/BetterClip.entitlements
      SWIFT_VERSION: "5.9"
      CODE_SIGN_IDENTITY: "-"
      CODE_SIGNING_REQUIRED: "NO"
    dependencies:
      - package: GRDB
      - package: KeyboardShortcuts
      - package: LaunchAtLogin
  BetterClipTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - BetterClipTests
    settings:
      MACOSX_DEPLOYMENT_TARGET: "13.0"
    dependencies:
      - target: BetterClip
packages:
  GRDB:
    url: https://github.com/groue/GRDB.swift
    majorVersion: 6
  KeyboardShortcuts:
    url: https://github.com/sindresorhus/KeyboardShortcuts
    majorVersion: 2
  LaunchAtLogin:
    url: https://github.com/sindresorhus/LaunchAtLogin-Modern
    majorVersion: 1
```

- [ ] **Step 4: Write Info.plist**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.betterclip.app</string>
    <key>CFBundleName</key>
    <string>BetterClip</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
</dict>
</plist>
```

- [ ] **Step 5: Write entitlements**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.automation.apple-events</key>
    <true/>
</dict>
</plist>
```

- [ ] **Step 6: Write stub AppDelegate**

```swift
// BetterClip/App/AppDelegate.swift
import AppKit

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("BetterClip started")
    }
}
```

- [ ] **Step 7: Generate and build**

```bash
xcodegen generate
xcodebuild build -project BetterClip.xcodeproj -scheme BetterClip \
  -destination 'platform=macOS' 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

---

### Task 2: Models

**Files:**
- Create: `BetterClip/Models/Clip.swift`
- Create: `BetterClip/Models/Snippet.swift`
- Create: `BetterClip/Models/SnippetFolder.swift`

- [ ] **Step 1: Write Clip.swift**

```swift
// BetterClip/Models/Clip.swift
import Foundation
import GRDB

enum ClipType: String, Codable {
    case text, image, rtf, url, file
}

struct Clip: Identifiable, Codable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?
    var type: ClipType
    var textContent: String?
    var blobHash: String?
    var appSource: String?
    var createdAt: Date
    var lastUsedAt: Date

    static let databaseTableName = "clips"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
```

- [ ] **Step 2: Write SnippetFolder.swift**

```swift
// BetterClip/Models/SnippetFolder.swift
import Foundation
import GRDB

struct SnippetFolder: Identifiable, Codable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?
    var name: String
    var parentId: Int64?
    var sortOrder: Int

    static let databaseTableName = "snippet_folders"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
```

- [ ] **Step 3: Write Snippet.swift**

```swift
// BetterClip/Models/Snippet.swift
import Foundation
import GRDB

struct Snippet: Identifiable, Codable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?
    var folderId: Int64?
    var name: String
    var content: String
    var shortcut: String?
    var createdAt: Date
    var sortOrder: Int

    static let databaseTableName = "snippets"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
```

- [ ] **Step 4: Build**

```bash
xcodebuild build -project BetterClip.xcodeproj -scheme BetterClip \
  -destination 'platform=macOS' 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

---

### Task 3: Database

**Files:**
- Create: `BetterClip/Core/Database.swift`

- [ ] **Step 1: Write Database.swift**

```swift
// BetterClip/Core/Database.swift
import Foundation
import GRDB

final class Database {
    static let shared: Database = {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BetterClip")
        try! FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return Database(path: appSupport.appendingPathComponent("betterclip.sqlite").path)
    }()

    private let queue: DatabaseQueue

    // Production init
    init(path: String) {
        queue = try! DatabaseQueue(path: path)
        try! applyMigrations()
    }

    // In-memory init for tests
    init() {
        queue = try! DatabaseQueue()
        try! applyMigrations()
    }

    private func applyMigrations() throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "clips") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("type", .text).notNull()
                t.column("textContent", .text)
                t.column("blobHash", .text)
                t.column("appSource", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("lastUsedAt", .datetime).notNull()
            }
            try db.create(virtualTable: "clips_fts", using: FTS5()) { t in
                t.synchronize(withTable: "clips")
                t.column("textContent")
            }
            try db.create(table: "snippet_folders") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("parentId", .integer).references("snippet_folders")
                t.column("sortOrder", .integer).notNull().defaults(to: 0)
            }
            try db.create(table: "snippets") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("folderId", .integer).references("snippet_folders")
                t.column("name", .text).notNull()
                t.column("content", .text).notNull()
                t.column("shortcut", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("sortOrder", .integer).notNull().defaults(to: 0)
            }
        }
        try migrator.migrate(queue)
    }

    // MARK: - Clips

    func insertClip(_ clip: inout Clip) throws {
        try queue.write { db in try clip.insert(db) }
    }

    func fetchRecentClips(limit: Int = 50) throws -> [Clip] {
        try queue.read { db in
            try Clip.order(Column("createdAt").desc).limit(limit).fetchAll(db)
        }
    }

    func searchClips(query: String) throws -> [Clip] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            return try fetchRecentClips()
        }
        return try queue.read { db in
            guard let pattern = FTS5Pattern(matchingAllTokensIn: query) else {
                return try Clip.order(Column("createdAt").desc).limit(50).fetchAll(db)
            }
            return try Clip.matching(pattern).order(Column("createdAt").desc).fetchAll(db)
        }
    }

    func updateClipLastUsed(id: Int64) throws {
        try queue.write { db in
            try db.execute(sql: "UPDATE clips SET lastUsedAt = ? WHERE id = ?",
                           arguments: [Date(), id])
        }
    }

    func deleteClip(id: Int64) throws {
        try queue.write { db in
            try db.execute(sql: "DELETE FROM clips WHERE id = ?", arguments: [id])
        }
    }

    func trimClips(keepingLatest limit: Int) throws {
        try queue.write { db in
            try db.execute(sql: """
                DELETE FROM clips WHERE id NOT IN (
                    SELECT id FROM clips ORDER BY createdAt DESC LIMIT ?
                )
            """, arguments: [limit])
        }
    }

    func mostRecentClip() throws -> Clip? {
        try queue.read { db in
            try Clip.order(Column("createdAt").desc).limit(1).fetchOne(db)
        }
    }

    // MARK: - Snippets

    func insertSnippet(_ snippet: inout Snippet) throws {
        try queue.write { db in try snippet.insert(db) }
    }

    func fetchSnippets(folderId: Int64? = nil) throws -> [Snippet] {
        try queue.read { db in
            var request = Snippet.order(Column("sortOrder"))
            if let folderId { request = request.filter(Column("folderId") == folderId) }
            return try request.fetchAll(db)
        }
    }

    func searchSnippets(query: String) throws -> [Snippet] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            return try fetchSnippets()
        }
        return try queue.read { db in
            try Snippet.filter(
                Column("name").like("%\(query)%") || Column("content").like("%\(query)%")
            ).fetchAll(db)
        }
    }

    func updateSnippet(_ snippet: Snippet) throws {
        try queue.write { db in try snippet.update(db) }
    }

    func deleteSnippet(id: Int64) throws {
        try queue.write { db in
            try db.execute(sql: "DELETE FROM snippets WHERE id = ?", arguments: [id])
        }
    }

    func insertFolder(_ folder: inout SnippetFolder) throws {
        try queue.write { db in try folder.insert(db) }
    }

    func fetchFolders() throws -> [SnippetFolder] {
        try queue.read { db in
            try SnippetFolder.order(Column("sortOrder")).fetchAll(db)
        }
    }

    func deleteFolder(id: Int64) throws {
        try queue.write { db in
            try db.execute(sql: "DELETE FROM snippets WHERE folderId = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM snippet_folders WHERE id = ?", arguments: [id])
        }
    }
}
```

- [ ] **Step 2: Build**

```bash
xcodebuild build -project BetterClip.xcodeproj -scheme BetterClip \
  -destination 'platform=macOS' 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

---

### Task 4: BlobStore

**Files:**
- Create: `BetterClip/Core/BlobStore.swift`

- [ ] **Step 1: Write BlobStore.swift**

```swift
// BetterClip/Core/BlobStore.swift
import Foundation
import CryptoKit

final class BlobStore {
    static let shared = BlobStore(directory: FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("BetterClip/blobs"))

    private let directory: URL

    init(directory: URL) {
        self.directory = directory
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func write(_ data: Data) -> String {
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let url = directory.appendingPathComponent(hash)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? data.write(to: url, options: .atomic)
        }
        return hash
    }

    func read(hash: String) -> Data? {
        try? Data(contentsOf: directory.appendingPathComponent(hash))
    }

    func delete(hash: String) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(hash))
    }

    func deleteAll() {
        try? FileManager.default.removeItem(at: directory)
    }
}
```

- [ ] **Step 2: Build**

```bash
xcodebuild build -project BetterClip.xcodeproj -scheme BetterClip \
  -destination 'platform=macOS' 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

---

### Task 5: Tests — Database & BlobStore

**Files:**
- Create: `BetterClipTests/DatabaseTests.swift`
- Create: `BetterClipTests/BlobStoreTests.swift`

- [ ] **Step 1: Write DatabaseTests.swift**

```swift
// BetterClipTests/DatabaseTests.swift
import XCTest
@testable import BetterClip

final class DatabaseTests: XCTestCase {
    var db: Database!

    override func setUp() {
        super.setUp()
        db = Database() // in-memory
    }

    func testInsertAndFetch() throws {
        var clip = Clip(type: .text, textContent: "hello world",
                        blobHash: nil, appSource: "com.test",
                        createdAt: Date(), lastUsedAt: Date())
        try db.insertClip(&clip)
        let results = try db.fetchRecentClips(limit: 10)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].textContent, "hello world")
    }

    func testFTS5Search() throws {
        var c1 = Clip(type: .text, textContent: "swift programming language",
                      blobHash: nil, appSource: nil, createdAt: Date(), lastUsedAt: Date())
        var c2 = Clip(type: .text, textContent: "python scripting tools",
                      blobHash: nil, appSource: nil, createdAt: Date(), lastUsedAt: Date())
        try db.insertClip(&c1)
        try db.insertClip(&c2)
        let results = try db.searchClips(query: "swift")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].textContent, "swift programming language")
    }

    func testEmptySearchReturnsRecent() throws {
        var clip = Clip(type: .text, textContent: "anything",
                        blobHash: nil, appSource: nil, createdAt: Date(), lastUsedAt: Date())
        try db.insertClip(&clip)
        let results = try db.searchClips(query: "")
        XCTAssertEqual(results.count, 1)
    }

    func testTrimKeepsLatest() throws {
        for i in 1...5 {
            var clip = Clip(type: .text, textContent: "item \(i)",
                            blobHash: nil, appSource: nil,
                            createdAt: Date().addingTimeInterval(Double(i)),
                            lastUsedAt: Date())
            try db.insertClip(&clip)
        }
        try db.trimClips(keepingLatest: 3)
        let remaining = try db.fetchRecentClips(limit: 10)
        XCTAssertEqual(remaining.count, 3)
        XCTAssertEqual(remaining[0].textContent, "item 5")
    }

    func testSnippetCRUD() throws {
        var folder = SnippetFolder(id: nil, name: "Work", parentId: nil, sortOrder: 0)
        try db.insertFolder(&folder)
        XCTAssertNotNil(folder.id)

        var snippet = Snippet(id: nil, folderId: folder.id, name: "Email sig",
                              content: "Best, Yarin", shortcut: nil,
                              createdAt: Date(), sortOrder: 0)
        try db.insertSnippet(&snippet)

        let fetched = try db.fetchSnippets(folderId: folder.id)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].content, "Best, Yarin")
    }
}
```

- [ ] **Step 2: Write BlobStoreTests.swift**

```swift
// BetterClipTests/BlobStoreTests.swift
import XCTest
@testable import BetterClip

final class BlobStoreTests: XCTestCase {
    var store: BlobStore!

    override func setUp() {
        super.setUp()
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = BlobStore(directory: tmpDir)
    }

    override func tearDown() {
        store.deleteAll()
        super.tearDown()
    }

    func testWriteAndRead() {
        let data = Data("hello betterclip".utf8)
        let hash = store.write(data)
        XCTAssertEqual(store.read(hash: hash), data)
    }

    func testDedupSameHash() {
        let data = Data("same content".utf8)
        let h1 = store.write(data)
        let h2 = store.write(data)
        XCTAssertEqual(h1, h2)
    }

    func testDeleteRemovesFile() {
        let data = Data("to delete".utf8)
        let hash = store.write(data)
        store.delete(hash: hash)
        XCTAssertNil(store.read(hash: hash))
    }
}
```

- [ ] **Step 3: Run tests**

```bash
xcodebuild test -project BetterClip.xcodeproj -scheme BetterClipTests \
  -destination 'platform=macOS' 2>&1 | grep -E "Test.*passed|Test.*failed|error:"
```

Expected: All tests passed.

---

### Task 6: Preferences

**Files:**
- Create: `BetterClip/Core/Preferences.swift`

- [ ] **Step 1: Write Preferences.swift**

```swift
// BetterClip/Core/Preferences.swift
import Foundation

enum LayoutMode: String, CaseIterable {
    case compact = "compact"
    case full = "full"
    case popover = "popover"

    var displayName: String {
        switch self {
        case .compact: return "Compact (list only)"
        case .full:    return "Full (list + preview)"
        case .popover: return "Popover (menu bar)"
        }
    }
}

final class Preferences {
    static let shared = Preferences()

    private let defaults = UserDefaults.standard

    var layoutMode: LayoutMode {
        get { LayoutMode(rawValue: defaults.string(forKey: "layoutMode") ?? "") ?? .full }
        set { defaults.set(newValue.rawValue, forKey: "layoutMode") }
    }

    var historyLimit: Int {
        get {
            let v = defaults.integer(forKey: "historyLimit")
            return v > 0 ? v : 200
        }
        set { defaults.set(newValue, forKey: "historyLimit") }
    }

    var maxImageSizeMB: Int {
        get {
            let v = defaults.integer(forKey: "maxImageSizeMB")
            return v > 0 ? v : 10
        }
        set { defaults.set(newValue, forKey: "maxImageSizeMB") }
    }

    var launchAtLogin: Bool {
        get { defaults.bool(forKey: "launchAtLogin") }
        set { defaults.set(newValue, forKey: "launchAtLogin") }
    }
}
```

- [ ] **Step 2: Build**

```bash
xcodebuild build -project BetterClip.xcodeproj -scheme BetterClip \
  -destination 'platform=macOS' 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

---

### Task 7: ClipboardMonitor + PasteboardWriter

**Files:**
- Create: `BetterClip/Core/ClipboardMonitor.swift`
- Create: `BetterClip/Core/PasteboardWriter.swift`

- [ ] **Step 1: Write ClipboardMonitor.swift**

```swift
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
            return Clip(type: .text, textContent: string, blobHash: nil,
                        appSource: appSource, createdAt: now, lastUsedAt: now)
        }

        let maxBytes = Preferences.shared.maxImageSizeMB * 1_024 * 1_024
        if let data = pasteboard.data(forType: .tiff) ?? pasteboard.data(forType: .png),
           data.count <= maxBytes {
            let hash = BlobStore.shared.write(data)
            return Clip(type: .image, textContent: nil, blobHash: hash,
                        appSource: appSource, createdAt: now, lastUsedAt: now)
        }

        if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
           let url = urls.first {
            return Clip(type: .url, textContent: url.absoluteString, blobHash: nil,
                        appSource: appSource, createdAt: now, lastUsedAt: now)
        }

        return nil
    }
}
```

- [ ] **Step 2: Write PasteboardWriter.swift**

```swift
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
    }

    static func write(snippet: Snippet) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(snippet.content, forType: .string)
    }

    // Requires Accessibility permission. Falls back silently if denied.
    static func simulatePaste() {
        let src = CGEventSource(stateID: .hidSystemState)
        let vDown = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
        let vUp   = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
        vDown?.flags = .maskCommand
        vUp?.flags   = .maskCommand
        vDown?.post(tap: .cgAnnotatedSessionEventTap)
        vUp?.post(tap: .cgAnnotatedSessionEventTap)
    }
}
```

- [ ] **Step 3: Build**

```bash
xcodebuild build -project BetterClip.xcodeproj -scheme BetterClip \
  -destination 'platform=macOS' 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

---

### Task 8: SnippetStore

**Files:**
- Create: `BetterClip/Core/SnippetStore.swift`

- [ ] **Step 1: Write SnippetStore.swift**

```swift
// BetterClip/Core/SnippetStore.swift
import Foundation

final class SnippetStore {
    static let shared = SnippetStore()
    private let db = Database.shared

    func createFolder(name: String, parentId: Int64? = nil) throws -> SnippetFolder {
        var folder = SnippetFolder(id: nil, name: name, parentId: parentId, sortOrder: 0)
        try db.insertFolder(&folder)
        return folder
    }

    func folders() throws -> [SnippetFolder] {
        try db.fetchFolders()
    }

    func deleteFolder(id: Int64) throws {
        try db.deleteFolder(id: id)
    }

    func createSnippet(name: String, content: String, folderId: Int64? = nil) throws -> Snippet {
        var snippet = Snippet(id: nil, folderId: folderId, name: name,
                              content: content, shortcut: nil,
                              createdAt: Date(), sortOrder: 0)
        try db.insertSnippet(&snippet)
        return snippet
    }

    func snippets(folderId: Int64? = nil) throws -> [Snippet] {
        try db.fetchSnippets(folderId: folderId)
    }

    func search(query: String) throws -> [Snippet] {
        try db.searchSnippets(query: query)
    }

    func update(_ snippet: Snippet) throws {
        try db.updateSnippet(snippet)
    }

    func delete(id: Int64) throws {
        try db.deleteSnippet(id: id)
    }

    func saveAsSnippet(clip: Clip, name: String, folderId: Int64? = nil) throws -> Snippet {
        let content = clip.textContent ?? ""
        return try createSnippet(name: name, content: content, folderId: folderId)
    }
}
```

- [ ] **Step 2: Build**

```bash
xcodebuild build -project BetterClip.xcodeproj -scheme BetterClip \
  -destination 'platform=macOS' 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

---

### Task 9: AppViewModel

**Files:**
- Create: `BetterClip/UI/Panel/AppViewModel.swift`

- [ ] **Step 1: Write AppViewModel.swift**

```swift
// BetterClip/UI/Panel/AppViewModel.swift
import Foundation
import Combine

enum PanelTab { case history, snippets }

final class AppViewModel: ObservableObject {
    @Published var searchQuery: String = ""
    @Published var clips: [Clip] = []
    @Published var snippets: [Snippet] = []
    @Published var selectedTab: PanelTab = .history
    @Published var selectedIndex: Int = 0

    private var cancellables = Set<AnyCancellable>()

    init() {
        refresh(query: "")

        $searchQuery
            .debounce(for: .milliseconds(80), scheduler: DispatchQueue.main)
            .sink { [weak self] query in self?.refresh(query: query) }
            .store(in: &cancellables)

        ClipboardMonitor.shared.newClipPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh(query: self?.searchQuery ?? "") }
            .store(in: &cancellables)
    }

    func refresh(query: String) {
        clips    = (try? Database.shared.searchClips(query: query)) ?? []
        snippets = (try? SnippetStore.shared.search(query: query)) ?? []
        selectedIndex = 0
    }

    func pasteClip(_ clip: Clip) {
        PasteboardWriter.write(clip: clip)
        if let id = clip.id { try? Database.shared.updateClipLastUsed(id: id) }
        PasteboardWriter.simulatePaste()
        refresh(query: searchQuery)
    }

    func pasteSnippet(_ snippet: Snippet) {
        PasteboardWriter.write(snippet: snippet)
        PasteboardWriter.simulatePaste()
    }

    func deleteClip(_ clip: Clip) {
        guard let id = clip.id else { return }
        try? Database.shared.deleteClip(id: id)
        if let hash = clip.blobHash { BlobStore.shared.delete(hash: hash) }
        refresh(query: searchQuery)
    }

    func moveSelectionUp() {
        selectedIndex = max(0, selectedIndex - 1)
    }

    func moveSelectionDown() {
        let count = selectedTab == .history ? clips.count : snippets.count
        selectedIndex = min(count - 1, selectedIndex + 1)
    }

    func pasteSelected() {
        switch selectedTab {
        case .history:
            guard selectedIndex < clips.count else { return }
            pasteClip(clips[selectedIndex])
        case .snippets:
            guard selectedIndex < snippets.count else { return }
            pasteSnippet(snippets[selectedIndex])
        }
    }
}
```

- [ ] **Step 2: Build**

```bash
xcodebuild build -project BetterClip.xcodeproj -scheme BetterClip \
  -destination 'platform=macOS' 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

---

### Task 10: AppDelegate + Menu Bar

**Files:**
- Modify: `BetterClip/App/AppDelegate.swift`

- [ ] **Step 1: Rewrite AppDelegate.swift**

```swift
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
```

- [ ] **Step 2: Build**

```bash
xcodebuild build -project BetterClip.xcodeproj -scheme BetterClip \
  -destination 'platform=macOS' 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

---

### Task 11: PanelController

**Files:**
- Create: `BetterClip/UI/Panel/PanelController.swift`

- [ ] **Step 1: Write PanelController.swift**

```swift
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

        // Dismiss on outside click
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: p, queue: .main
        ) { [weak p] _ in p?.orderOut(nil) }

        return p
    }

    private func togglePopover() {
        // Handled via NSStatusItem button in AppDelegate
        // Delegate popover anchor to AppDelegate if needed
    }

    func close() {
        panel?.orderOut(nil)
        popover?.close()
    }
}
```

- [ ] **Step 2: Build**

```bash
xcodebuild build -project BetterClip.xcodeproj -scheme BetterClip \
  -destination 'platform=macOS' 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

---

### Task 12: PanelView + ClipRowView

**Files:**
- Create: `BetterClip/UI/Panel/PanelView.swift`
- Create: `BetterClip/UI/Panel/ClipRowView.swift`

- [ ] **Step 1: Write PanelView.swift**

```swift
// BetterClip/UI/Panel/PanelView.swift
import SwiftUI

struct PanelView: View {
    @ObservedObject var viewModel: AppViewModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                searchBar
                Divider()
                tabBar
                Divider()
                itemList
            }
            .frame(width: Preferences.shared.layoutMode == .full ? 320 : nil)

            if Preferences.shared.layoutMode == .full {
                Divider()
                PreviewPane(viewModel: viewModel)
            }
        }
        .onAppear { searchFocused = true }
        .onKeyPress(.escape) { viewModel.searchQuery = ""; return .ignored }
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search clipboard…", text: $viewModel.searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($searchFocused)
                .onSubmit { viewModel.pasteSelected() }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            tabButton("History", tab: .history)
            tabButton("Snippets", tab: .snippets)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private func tabButton(_ title: String, tab: PanelTab) -> some View {
        Button(title) { viewModel.selectedTab = tab }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: viewModel.selectedTab == tab ? .semibold : .regular))
            .foregroundStyle(viewModel.selectedTab == tab ? .primary : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
    }

    private var itemList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if viewModel.selectedTab == .history {
                        ForEach(Array(viewModel.clips.enumerated()), id: \.element.id) { index, clip in
                            ClipRowView(clip: clip, isSelected: index == viewModel.selectedIndex)
                                .id(index)
                                .onTapGesture { viewModel.selectedIndex = index }
                                .onTapGesture(count: 2) { viewModel.pasteClip(clip) }
                                .contextMenu {
                                    Button("Paste") { viewModel.pasteClip(clip) }
                                    Button("Delete", role: .destructive) { viewModel.deleteClip(clip) }
                                }
                        }
                    } else {
                        ForEach(Array(viewModel.snippets.enumerated()), id: \.element.id) { index, snippet in
                            SnippetRowView(snippet: snippet, isSelected: index == viewModel.selectedIndex)
                                .id(index)
                                .onTapGesture { viewModel.selectedIndex = index }
                                .onTapGesture(count: 2) { viewModel.pasteSnippet(snippet) }
                        }
                    }
                }
            }
            .onChange(of: viewModel.selectedIndex) { _, idx in
                withAnimation { proxy.scrollTo(idx) }
            }
        }
        .onKeyPress(.upArrow)   { viewModel.moveSelectionUp();   return .handled }
        .onKeyPress(.downArrow) { viewModel.moveSelectionDown(); return .handled }
        .onKeyPress(.return)    { viewModel.pasteSelected();     return .handled }
    }
}
```

- [ ] **Step 2: Write ClipRowView.swift**

```swift
// BetterClip/UI/Panel/ClipRowView.swift
import SwiftUI

struct ClipRowView: View {
    let clip: Clip
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            typeIcon
            content
            Spacer()
            if clip.type == .image, let hash = clip.blobHash,
               let data = BlobStore.shared.read(hash: hash),
               let img = NSImage(data: data) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 40, height: 28)
                    .cornerRadius(3)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .contentShape(Rectangle())
    }

    private var typeIcon: some View {
        Text(clip.type.iconLabel)
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.secondary)
            .frame(width: 28)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(clip.displayText)
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.tail)
            if let source = clip.appSource {
                Text(source)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private extension ClipType {
    var iconLabel: String {
        switch self {
        case .text:  return "txt"
        case .image: return "img"
        case .rtf:   return "rtf"
        case .url:   return "url"
        case .file:  return "file"
        }
    }
}

private extension Clip {
    var displayText: String {
        switch type {
        case .image: return "Image — \(createdAt.formatted(.dateTime.month().day().hour().minute()))"
        default:     return textContent ?? "—"
        }
    }
}
```

- [ ] **Step 3: Build**

```bash
xcodebuild build -project BetterClip.xcodeproj -scheme BetterClip \
  -destination 'platform=macOS' 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

---

### Task 13: PreviewPane + SnippetRowView

**Files:**
- Create: `BetterClip/UI/Panel/PreviewPane.swift`
- Create: `BetterClip/UI/Panel/SnippetRowView.swift`

- [ ] **Step 1: Write PreviewPane.swift**

```swift
// BetterClip/UI/Panel/PreviewPane.swift
import SwiftUI

struct PreviewPane: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        Group {
            if viewModel.selectedTab == .history {
                clipPreview
            } else {
                snippetPreview
            }
        }
        .frame(minWidth: 300)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(16)
    }

    @ViewBuilder
    private var clipPreview: some View {
        if viewModel.selectedIndex < viewModel.clips.count {
            let clip = viewModel.clips[viewModel.selectedIndex]
            switch clip.type {
            case .image:
                if let hash = clip.blobHash,
                   let data = BlobStore.shared.read(hash: hash),
                   let img = NSImage(data: data) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .cornerRadius(6)
                } else {
                    placeholder("No image data")
                }
            default:
                ScrollView {
                    Text(clip.textContent ?? "")
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } else {
            placeholder("Select an item")
        }
    }

    @ViewBuilder
    private var snippetPreview: some View {
        if viewModel.selectedIndex < viewModel.snippets.count {
            let snippet = viewModel.snippets[viewModel.selectedIndex]
            VStack(alignment: .leading, spacing: 8) {
                Text(snippet.name).font(.headline)
                Divider()
                ScrollView {
                    Text(snippet.content)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } else {
            placeholder("Select a snippet")
        }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text).foregroundStyle(.tertiary).font(.system(size: 13))
    }
}
```

- [ ] **Step 2: Write SnippetRowView.swift**

```swift
// BetterClip/UI/Panel/SnippetRowView.swift
import SwiftUI

struct SnippetRowView: View {
    let snippet: Snippet
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "pin.fill")
                .font(.system(size: 10))
                .foregroundStyle(.orange)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(snippet.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(snippet.content)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer()
            if let shortcut = snippet.shortcut {
                Text(shortcut)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15))
                    .cornerRadius(3)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .contentShape(Rectangle())
    }
}
```

- [ ] **Step 3: Build**

```bash
xcodebuild build -project BetterClip.xcodeproj -scheme BetterClip \
  -destination 'platform=macOS' 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

---

### Task 14: Snippet Management UI

**Files:**
- Create: `BetterClip/UI/Snippets/SnippetEditorView.swift`
- Create: `BetterClip/UI/Snippets/FolderTreeView.swift`

- [ ] **Step 1: Write SnippetEditorView.swift**

```swift
// BetterClip/UI/Snippets/SnippetEditorView.swift
import SwiftUI

struct SnippetEditorView: View {
    @Environment(\.dismiss) private var dismiss

    var existingSnippet: Snippet? = nil
    var prefillContent: String = ""
    var folderId: Int64? = nil
    var onSave: (() -> Void)? = nil

    @State private var name: String = ""
    @State private var content: String = ""
    @State private var error: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(existingSnippet == nil ? "New Snippet" : "Edit Snippet")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("Name").font(.subheadline).foregroundStyle(.secondary)
                TextField("e.g. Email signature", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Content").font(.subheadline).foregroundStyle(.secondary)
                TextEditor(text: $content)
                    .font(.system(size: 13, design: .monospaced))
                    .frame(minHeight: 120)
                    .border(Color.secondary.opacity(0.3))
            }

            if let error {
                Text(error).foregroundStyle(.red).font(.caption)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.escape)
                Button("Save") { save() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
        .onAppear {
            name = existingSnippet?.name ?? ""
            content = existingSnippet?.content ?? prefillContent
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        do {
            if var existing = existingSnippet {
                existing.name = trimmedName
                existing.content = content
                try SnippetStore.shared.update(existing)
            } else {
                _ = try SnippetStore.shared.createSnippet(
                    name: trimmedName, content: content, folderId: folderId)
            }
            onSave?()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
```

- [ ] **Step 2: Write FolderTreeView.swift**

```swift
// BetterClip/UI/Snippets/FolderTreeView.swift
import SwiftUI

struct SnippetManagerView: View {
    @State private var folders: [SnippetFolder] = []
    @State private var snippets: [Snippet] = []
    @State private var selectedFolderId: Int64? = nil
    @State private var showingEditor = false
    @State private var editingSnippet: Snippet? = nil

    var body: some View {
        HSplitView {
            folderSidebar
                .frame(minWidth: 160, maxWidth: 220)
            snippetList
        }
        .frame(minWidth: 560, minHeight: 400)
        .toolbar {
            ToolbarItem {
                Button { showingEditor = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            SnippetEditorView(folderId: selectedFolderId) { refreshSnippets() }
        }
        .onAppear { refresh() }
    }

    private var folderSidebar: some View {
        List(selection: $selectedFolderId) {
            Label("All Snippets", systemImage: "tray.full")
                .tag(Optional<Int64>.none)
            ForEach(folders) { folder in
                Label(folder.name, systemImage: "folder")
                    .tag(Optional(folder.id!))
                    .contextMenu {
                        Button("Delete Folder", role: .destructive) {
                            try? SnippetStore.shared.deleteFolder(id: folder.id!)
                            refresh()
                        }
                    }
            }
            Button {
                let name = "New Folder"
                _ = try? SnippetStore.shared.createFolder(name: name)
                refresh()
            } label: {
                Label("Add Folder", systemImage: "folder.badge.plus")
            }
            .buttonStyle(.plain)
        }
        .onChange(of: selectedFolderId) { _, _ in refreshSnippets() }
    }

    private var snippetList: some View {
        List {
            ForEach(snippets) { snippet in
                VStack(alignment: .leading, spacing: 3) {
                    Text(snippet.name).font(.system(size: 13, weight: .medium))
                    Text(snippet.content)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .contextMenu {
                    Button("Edit") { editingSnippet = snippet; showingEditor = true }
                    Button("Delete", role: .destructive) {
                        guard let id = snippet.id else { return }
                        try? SnippetStore.shared.delete(id: id)
                        refreshSnippets()
                    }
                }
            }
        }
        .sheet(item: $editingSnippet) { snippet in
            SnippetEditorView(existingSnippet: snippet) { refreshSnippets() }
        }
    }

    private func refresh() {
        folders = (try? SnippetStore.shared.folders()) ?? []
        refreshSnippets()
    }

    private func refreshSnippets() {
        snippets = (try? SnippetStore.shared.snippets(folderId: selectedFolderId)) ?? []
    }
}
```

- [ ] **Step 3: Wire up "Manage Snippets" in AppDelegate**

In `AppDelegate.swift`, replace the `openSnippetManager()` stub:

```swift
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
```

- [ ] **Step 4: Build**

```bash
xcodebuild build -project BetterClip.xcodeproj -scheme BetterClip \
  -destination 'platform=macOS' 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

---

### Task 15: Save-as-Snippet Context Menu

**Files:**
- Modify: `BetterClip/UI/Panel/PanelView.swift`

- [ ] **Step 1: Add "Save as Snippet" to clip context menu**

In `PanelView.swift`, replace the `.contextMenu` on `ClipRowView` with:

```swift
.contextMenu {
    Button("Paste") { viewModel.pasteClip(clip) }
    Button("Save as Snippet…") { viewModel.showSaveAsSnippet(clip: clip) }
    Divider()
    Button("Delete", role: .destructive) { viewModel.deleteClip(clip) }
}
```

- [ ] **Step 2: Add save-as-snippet state to AppViewModel**

In `AppViewModel.swift`, add:

```swift
@Published var clipToSaveAsSnippet: Clip? = nil

func showSaveAsSnippet(clip: Clip) {
    clipToSaveAsSnippet = clip
}
```

- [ ] **Step 3: Present SnippetEditorView from PanelView**

In `PanelView.swift`, add a `.sheet` modifier to the root `HStack`:

```swift
.sheet(item: $viewModel.clipToSaveAsSnippet) { clip in
    SnippetEditorView(prefillContent: clip.textContent ?? "") {
        viewModel.refresh(query: viewModel.searchQuery)
    }
}
```

Also make `Clip` conform to `Identifiable` (it already does via `id: Int64?`) — ensure `id` is non-nil when presenting. The sheet item binding requires `Clip` to conform to `Identifiable`, which it does.

- [ ] **Step 4: Build**

```bash
xcodebuild build -project BetterClip.xcodeproj -scheme BetterClip \
  -destination 'platform=macOS' 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

---

### Task 16: Preferences UI

**Files:**
- Create: `BetterClip/UI/Preferences/PreferencesView.swift`
- Modify: `BetterClip/App/AppDelegate.swift`

- [ ] **Step 1: Write PreferencesView.swift**

```swift
// BetterClip/UI/Preferences/PreferencesView.swift
import SwiftUI
import KeyboardShortcuts
import LaunchAtLogin

struct PreferencesView: View {
    @AppStorage("layoutMode")    private var layoutModeRaw = LayoutMode.full.rawValue
    @AppStorage("historyLimit")  private var historyLimit  = 200
    @AppStorage("maxImageSizeMB") private var maxImageSizeMB = 10
    @AppStorage("launchAtLogin") private var launchAtLogin = true

    private var layoutMode: Binding<LayoutMode> {
        Binding(
            get: { LayoutMode(rawValue: layoutModeRaw) ?? .full },
            set: { layoutModeRaw = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Section("Panel") {
                Picker("Layout", selection: layoutMode) {
                    ForEach(LayoutMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                KeyboardShortcuts.Recorder("Open hotkey", name: .togglePanel)
            }

            Section("History") {
                Stepper("Keep last \(historyLimit) items", value: $historyLimit,
                        in: 50...1000, step: 50)
                Stepper("Max image size: \(maxImageSizeMB) MB", value: $maxImageSizeMB,
                        in: 1...100, step: 5)
            }

            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, val in LaunchAtLogin.isEnabled = val }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 380)
    }
}
```

- [ ] **Step 2: Wire up Preferences in AppDelegate**

In `AppDelegate.swift`, replace the `openPreferences()` stub:

```swift
private var preferencesWindow: NSWindow?

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
```

- [ ] **Step 3: Build and run**

```bash
xcodebuild build -project BetterClip.xcodeproj -scheme BetterClip \
  -destination 'platform=macOS' 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

---

### Task 17: Final Polish + Popover Mode

**Files:**
- Modify: `BetterClip/UI/Panel/PanelController.swift`
- Modify: `BetterClip/App/AppDelegate.swift`

- [ ] **Step 1: Implement popover mode in PanelController**

In `PanelController.swift`, replace `togglePopover()`:

```swift
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
```

- [ ] **Step 2: Route popover mode through AppDelegate**

In `AppDelegate.swift`, update `togglePanel()`:

```swift
@objc func togglePanel() {
    if Preferences.shared.layoutMode == .popover,
       let button = statusItem.button {
        panelController.showPopover(from: button)
    } else {
        panelController.toggle()
    }
}
```

- [ ] **Step 3: Add corner radius to panel**

In `PanelController.makePanel()`, after `p.isOpaque = false`, add:

```swift
p.contentView?.wantsLayer = true
p.contentView?.layer?.cornerRadius = 12
p.contentView?.layer?.masksToBounds = true
```

- [ ] **Step 4: Final build and smoke test**

```bash
xcodebuild build -project BetterClip.xcodeproj -scheme BetterClip \
  -destination 'platform=macOS' 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

Launch `BetterClip.app` from the build products directory. Verify:
- Menu bar icon appears
- ⌘⇧V opens panel
- Copy text in another app → appears in history
- Search filters results
- ↑↓ navigates, ↩ pastes
- Right-click clip → "Save as Snippet" works
- Preferences window opens from menu

---

## Spec Coverage Checklist

| Requirement | Task |
|---|---|
| Clipboard history (text/image/url) | 7 |
| 300ms polling | 7 |
| SHA256 dedup | 7 |
| SQLite + FTS5 search | 3, 5 |
| Image blob storage | 4 |
| ⌘⇧V global hotkey | 10 |
| NSPanel floating panel | 11 |
| 3 layout modes (A/B/C) | 11, 17 |
| Keyboard navigation | 12 |
| Auto-paste via CGEvent | 7 |
| Snippets with folders | 8, 14 |
| Save-as-snippet from history | 15 |
| Preview pane (mode B) | 13 |
| Preferences UI | 16 |
| Launch at login | 16 |
| Menu bar icon | 10 |
| NSVisualEffectView frosted glass | 11 |
| Popover mode (mode C) | 17 |
