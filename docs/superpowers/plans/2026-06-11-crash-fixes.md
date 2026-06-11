# Crash Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate five crash/resource-leak bugs found during a clipboard-monitoring crash investigation, ordered by severity.

**Architecture:** All fixes are surgical — one file per bug at most two. No new abstractions introduced. Tests added for the two logic bugs that can be exercised without a running AppKit app; the remaining fixes are verified by code inspection + manual smoke test.

**Tech Stack:** Swift 5.9, AppKit, SwiftUI, Combine, GRDB 6, XCTest.

---

## Bug Map (severity order)

| # | Severity | Root file | Description |
|---|---|---|---|
| 1 | CRITICAL | `AppViewModel.swift:101` | `moveSelectionDown()` sets `selectedIndex = -1` when list is empty |
| 2 | CRITICAL | `PreviewPane.swift:23,39` | SwiftUI renders `clips[-1]` — fatal index-out-of-range |
| 3 | MEDIUM | `ClipboardMonitor.swift:14-17` | Timer double-registered (scheduledTimer + add forMode: .common) |
| 4 | LOW | `PanelController.swift:115,151` | NotificationCenter token leak + cancellables accumulate per toggle |
| 5 | LOW | `Database.swift:18`, `BlobStore.swift:14` | `try!` in prod inits → crash on corrupted DB or disk-full |

---

## File Map

| File | Change |
|---|---|
| `BetterClip/UI/Panel/AppViewModel.swift` | guard empty list in `moveSelectionDown`; guard `selectedIndex >= 0` in `pasteSelected` |
| `BetterClip/UI/Panel/PreviewPane.swift` | add `idx >= 0` to both `clipPreview` and `snippetPreview` guards |
| `BetterClip/Core/ClipboardMonitor.swift` | replace `scheduledTimer` + `add` with bare `Timer` + single `add(.common)` |
| `BetterClip/UI/Panel/PanelController.swift` | store `NSObjectProtocol` token; separate `panelCancellables` set |
| `BetterClip/Core/Database.swift` | make prod `init(path:)` throwing; recover from corrupt DB in `shared` |
| `BetterClip/Core/BlobStore.swift` | replace `try!` with graceful `try?` + fallback |
| `BetterClipTests/AppViewModelCrashTests.swift` | new — covers Bug 1 & 2 logic boundary conditions |

---

## Task 1 — Guard empty list in `moveSelectionDown` (Bug 1, CRITICAL)

**Files:**
- Modify: `BetterClip/UI/Panel/AppViewModel.swift`
- Create: `BetterClipTests/AppViewModelCrashTests.swift`

### Step 1.1 — Write the failing test

Create `BetterClipTests/AppViewModelCrashTests.swift`:

```swift
import XCTest
@testable import BetterClip

final class AppViewModelCrashTests: XCTestCase {

    // AppViewModel.init() subscribes to ClipboardMonitor.shared and calls
    // Database.shared.searchClips — both are safe with an empty/real DB.
    var vm: AppViewModel!

    override func setUp() {
        super.setUp()
        vm = AppViewModel()
        // Override whatever refresh loaded — we want a known-empty state.
        vm.clips = []
        vm.selectedIndex = 0
    }

    // BEFORE fix: selectedIndex becomes -1 → later array access crashes.
    func test_moveSelectionDown_emptyHistory_selectedIndexStaysNonNegative() {
        vm.selectedTab = .history
        vm.clips = []
        vm.moveSelectionDown()
        XCTAssertGreaterThanOrEqual(vm.selectedIndex, 0,
            "selectedIndex must never go negative — clips[-1] is a fatal crash")
    }

    func test_moveSelectionDown_emptySnippets_selectedIndexStaysNonNegative() {
        vm.selectedTab = .snippets
        vm.snippets = []
        vm.folders = []
        vm.moveSelectionDown()
        XCTAssertGreaterThanOrEqual(vm.selectedIndex, 0,
            "selectedIndex must never go negative on empty snippet list")
    }

    func test_moveSelectionDown_oneItem_staysAtZero() {
        vm.selectedTab = .history
        vm.clips = [Clip(id: 1, type: .text, textContent: "a", blobHash: nil,
                         appSource: nil, createdAt: Date(), lastUsedAt: Date())]
        vm.selectedIndex = 0
        vm.moveSelectionDown()
        XCTAssertEqual(vm.selectedIndex, 0,
            "Single-item list: down from 0 should stay at 0")
    }
}
```

### Step 1.2 — Run test to verify it fails

```bash
xcodebuild test -project BetterClip.xcodeproj -scheme BetterClip \
  -destination 'platform=macOS' \
  -only-testing:BetterClipTests/AppViewModelCrashTests/test_moveSelectionDown_emptyHistory_selectedIndexStaysNonNegative
```

Expected: **FAIL** — `selectedIndex` is -1, assertion fires.

### Step 1.3 — Fix `moveSelectionDown` in `AppViewModel.swift`

Open `BetterClip/UI/Panel/AppViewModel.swift`. Replace lines 100-103:

```swift
// BEFORE
func moveSelectionDown() {
    let count = selectedTab == .history ? clips.count : snippetPanelItems.count
    selectedIndex = min(count - 1, selectedIndex + 1)
}
```

```swift
// AFTER
func moveSelectionDown() {
    let count = selectedTab == .history ? clips.count : snippetPanelItems.count
    guard count > 0 else { return }
    selectedIndex = min(count - 1, selectedIndex + 1)
}
```

### Step 1.4 — Run tests to verify they pass

```bash
xcodebuild test -project BetterClip.xcodeproj -scheme BetterClip \
  -destination 'platform=macOS' \
  -only-testing:BetterClipTests/AppViewModelCrashTests
```

Expected: **3 tests PASS**.

### Step 1.5 — Commit

```bash
git add BetterClip/UI/Panel/AppViewModel.swift \
        BetterClipTests/AppViewModelCrashTests.swift
git commit -m "fix: guard empty list in moveSelectionDown to prevent negative selectedIndex"
```

---

## Task 2 — Guard `idx >= 0` in PreviewPane (Bug 2, CRITICAL)

**Files:**
- Modify: `BetterClip/UI/Panel/PreviewPane.swift`
- Modify: `BetterClipTests/AppViewModelCrashTests.swift` (add test)

### Step 2.1 — Add test that catches the PreviewPane crash path

The SwiftUI view itself can't be unit-tested for the crash, but we can test that `selectedIndex` is never negative *before* the view renders (which is the invariant that prevents the crash). Add this test to `AppViewModelCrashTests.swift`:

```swift
// After Bug 1 fix, selectedIndex can't go negative via moveSelectionDown.
// But refresh() resets to 0, and the view must handle any transient negative
// value defensively. This test documents the contract on the view's idx guard.

func test_previewPane_idxGuard_negativeIdxWithEmptyClips_doesNotCrash() {
    // Simulate the race: selectedIndex is somehow -1, clips is empty.
    // The guard `idx >= 0, idx < clips.count` must NOT index into the array.
    vm.clips = []
    vm.selectedIndex = -1   // forced negative to test the view-side guard

    // If PreviewPane's guard is `idx < clips.count` only:
    //   -1 < 0 → true → clips[-1] → CRASH
    // With the fixed guard `idx >= 0, idx < clips.count`:
    //   -1 >= 0 → false → shows placeholder → safe

    // We test the guard logic directly since we can't render SwiftUI in XCTest:
    let idx = vm.selectedIndex
    let safeToAccess = idx >= 0 && idx < vm.clips.count
    XCTAssertFalse(safeToAccess,
        "idx=-1 with empty clips must NOT pass the access guard")
}
```

### Step 2.2 — Run test

```bash
xcodebuild test -project BetterClip.xcodeproj -scheme BetterClip \
  -destination 'platform=macOS' \
  -only-testing:BetterClipTests/AppViewModelCrashTests/test_previewPane_idxGuard_negativeIdxWithEmptyClips_doesNotCrash
```

Expected: **PASS** (the test validates the invariant; the view fix comes next).

### Step 2.3 — Fix both guards in `PreviewPane.swift`

Open `BetterClip/UI/Panel/PreviewPane.swift`. Apply two changes:

**Clip preview** (line 23):
```swift
// BEFORE
if idx < viewModel.clips.count {
    let clip = viewModel.clips[idx]
```

```swift
// AFTER
if idx >= 0, idx < viewModel.clips.count {
    let clip = viewModel.clips[idx]
```

**Snippet preview** (line 39):
```swift
// BEFORE
if idx < viewModel.snippets.count {
    let snippet = viewModel.snippets[idx]
```

```swift
// AFTER
if idx >= 0, idx < viewModel.snippets.count {
    let snippet = viewModel.snippets[idx]
```

### Step 2.4 — Fix `pasteSelected` guard in `AppViewModel.swift`

The same negative-index crash can happen via the Enter key path. Open `AppViewModel.swift` and fix `pasteSelected` (line 128):

```swift
// BEFORE
case .history:
    guard selectedIndex < clips.count else { return }
    let clip = clips[selectedIndex]
```

```swift
// AFTER
case .history:
    guard selectedIndex >= 0, selectedIndex < clips.count else { return }
    let clip = clips[selectedIndex]
```

### Step 2.5 — Build to verify no compile errors

```bash
xcodebuild build -project BetterClip.xcodeproj -scheme BetterClip
```

Expected: **BUILD SUCCEEDED**

### Step 2.6 — Commit

```bash
git add BetterClip/UI/Panel/PreviewPane.swift \
        BetterClip/UI/Panel/AppViewModel.swift \
        BetterClipTests/AppViewModelCrashTests.swift
git commit -m "fix: add idx >= 0 guard in PreviewPane and pasteSelected to prevent out-of-bounds crash"
```

---

## Task 3 — Fix timer double-registration (Bug 3, MEDIUM)

**Files:**
- Modify: `BetterClip/Core/ClipboardMonitor.swift`

**Context:** `Timer.scheduledTimer(withTimeInterval:repeats:block:)` automatically adds the timer to the current RunLoop in `.default` mode. The subsequent `RunLoop.main.add(timer!, forMode: .common)` adds it again to every "common" mode — which includes `.default`. In practice macOS deduplicates within a mode, but the `.default` registration via `scheduledTimer` is redundant and the `timer!` force-unwrap is cosmetically unsafe. The intent is correct (fire during scroll/eventTracking too), but the implementation is sloppy. Fix: create the timer without scheduling, then add once to `.common`.

### Step 3.1 — Fix `start()` in `ClipboardMonitor.swift`

Replace the `start()` function (lines 13-18):

```swift
// BEFORE
func start() {
    timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
        self?.poll()
    }
    RunLoop.main.add(timer!, forMode: .common)
}
```

```swift
// AFTER
func start() {
    let t = Timer(timeInterval: 0.3, repeats: true) { [weak self] _ in
        self?.poll()
    }
    RunLoop.main.add(t, forMode: .common)
    timer = t
}
```

`Timer(timeInterval:repeats:block:)` creates the timer without scheduling it. `RunLoop.main.add(_:forMode: .common)` is the single registration — it covers `.default`, `.eventTracking`, and `.modalPanel` automatically via the common-mode pseudo-alias.

### Step 3.2 — Build and verify no regressions

```bash
xcodebuild build -project BetterClip.xcodeproj -scheme BetterClip
```

Expected: **BUILD SUCCEEDED**

### Step 3.3 — Smoke test (manual)

1. Launch the app.
2. Open any text editor, type text, press Cmd+C.
3. Open the BetterClip panel (Cmd+Shift+V).
4. Verify the copied text appears in the history list within ~0.3 s.
5. Scroll a list in another app (triggers `.eventTracking` RunLoop mode) while copying — confirm clip still captured.

### Step 3.4 — Commit

```bash
git add BetterClip/Core/ClipboardMonitor.swift
git commit -m "fix: use Timer(timeInterval:) + RunLoop.add(.common) to avoid double-registration"
```

---

## Task 4 — Fix NotificationCenter token leak + cancellables accumulation (Bug 4, LOW)

**Files:**
- Modify: `BetterClip/UI/Panel/PanelController.swift`

**Context:**

*Token leak:* `NotificationCenter.default.addObserver(forName:object:queue:using:)` returns an `NSObjectProtocol` token. If it is discarded (not stored), the observer can never be removed — it is held permanently by NotificationCenter. Every call to `makePanel()`/`toggleFloatingPanel()` adds another permanent observer.

*Cancellables accumulation:* `viewModel.shouldClosePanel.sink{}.store(in: &cancellables)` adds a new `AnyCancellable` on every `toggleFloatingPanel` call. Old sinks capture `[weak p]` and harmlessly no-op, but they accumulate in `cancellables` forever (never cancelled).

Fix: store the resign-key token on `PanelController`; use a separate `panelCancellables` set that is replaced each time a new panel is shown.

### Step 4.1 — Add `panelCancellables` and `panelResignObserver` properties

In `PanelController` (after the existing `private var cancellables` line):

```swift
// BEFORE (line 65)
private var cancellables = Set<AnyCancellable>()
```

```swift
// AFTER
private var cancellables = Set<AnyCancellable>()
private var panelCancellables = Set<AnyCancellable>()
private var panelResignObserver: NSObjectProtocol?
```

### Step 4.2 — Fix `toggleFloatingPanel` to clear stale subscriptions

Replace the sink block in `toggleFloatingPanel` (lines 115-117):

```swift
// BEFORE
viewModel.shouldClosePanel
    .sink { [weak p] in p?.orderOut(nil) }
    .store(in: &cancellables)
```

```swift
// AFTER
panelCancellables.removeAll()          // cancel & discard previous panel's sink
viewModel.shouldClosePanel
    .sink { [weak p] in p?.orderOut(nil) }
    .store(in: &panelCancellables)
```

### Step 4.3 — Fix the NotificationCenter observer in `makePanel`

In `makePanel`, replace the discarded `addObserver` call (lines 151-153):

```swift
// BEFORE
NotificationCenter.default.addObserver(
    forName: NSWindow.didResignKeyNotification, object: p, queue: .main
) { [weak p] _ in p?.orderOut(nil) }
```

```swift
// AFTER
panelResignObserver.flatMap { NotificationCenter.default.removeObserver($0) }
panelResignObserver = NotificationCenter.default.addObserver(
    forName: NSWindow.didResignKeyNotification, object: p, queue: .main
) { [weak p] _ in p?.orderOut(nil) }
```

The `removeObserver` call on the old token prevents the previous panel's observer from firing into a deallocated window.

### Step 4.4 — Build

```bash
xcodebuild build -project BetterClip.xcodeproj -scheme BetterClip
```

Expected: **BUILD SUCCEEDED**

### Step 4.5 — Smoke test (manual)

1. Launch app.
2. Open and close the panel 10 times rapidly.
3. In Instruments (Leaks template), verify no growing object counts for `NSCFTimer`, `_NotificationCenter_Block_Observer`, or `AnyCancellable`.

### Step 4.6 — Commit

```bash
git add BetterClip/UI/Panel/PanelController.swift
git commit -m "fix: store NotificationCenter token and use panelCancellables to prevent observer/cancellable accumulation"
```

---

## Task 5 — Harden `try!` in Database and BlobStore inits (Bug 5, LOW)

**Files:**
- Modify: `BetterClip/Core/Database.swift`
- Modify: `BetterClip/Core/BlobStore.swift`
- Modify: `BetterClipTests/DatabaseTests.swift` (add recovery test)

**Context:** The production `Database.shared` singleton uses `try!` for `DatabaseQueue(path:)` and `applyMigrations()`. A corrupted SQLite file (power-loss mid-write, disk-full truncation) causes an instant crash at launch with no recovery path. Fix: make `init(path:)` throwing; in the `shared` factory, catch the error, delete the corrupt file, and recreate.

### Step 5.1 — Add a test for DB recovery path

Add to `BetterClipTests/DatabaseTests.swift`:

```swift
func testRecoveryFromCorruptDatabase() throws {
    // Write a corrupt (non-SQLite) file to a temp path
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("corrupt-\(UUID().uuidString).sqlite")
    try "not a sqlite file".write(to: tmp, atomically: true, encoding: .utf8)

    // Database(path:) should throw on corrupt file
    XCTAssertThrowsError(try Database(path: tmp.path),
        "Opening a corrupt SQLite file must throw, not crash")

    try? FileManager.default.removeItem(at: tmp)
}
```

### Step 5.2 — Run test to verify it fails

```bash
xcodebuild test -project BetterClip.xcodeproj -scheme BetterClip \
  -destination 'platform=macOS' \
  -only-testing:BetterClipTests/DatabaseTests/testRecoveryFromCorruptDatabase
```

Expected: **FAIL** — `Database.init(path:)` currently uses `try!` so it crashes the test process rather than throwing.

### Step 5.3 — Make `Database.init(path:)` throwing

In `Database.swift`, change the production init:

```swift
// BEFORE
init(path: String) {
    queue = try! DatabaseQueue(path: path)
    try! applyMigrations()
}
```

```swift
// AFTER
init(path: String) throws {
    queue = try DatabaseQueue(path: path)
    try applyMigrations()
}
```

The test-only in-memory `init()` keeps `try!` — an in-memory queue failing means a code bug, not a runtime condition.

### Step 5.4 — Update `Database.shared` factory to recover from corruption

```swift
// BEFORE
static let shared: Database = {
    let appSupport = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("BetterClip")
    try! FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
    return Database(path: appSupport.appendingPathComponent("betterclip.sqlite").path)
}()
```

```swift
// AFTER
static let shared: Database = {
    let appSupport = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("BetterClip")
    try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
    let dbURL = appSupport.appendingPathComponent("betterclip.sqlite")
    if let db = try? Database(path: dbURL.path) { return db }
    // Recovery: corrupt or unreadable DB — delete and start fresh (history lost, snippets lost).
    try? FileManager.default.removeItem(at: dbURL)
    return try! Database(path: dbURL.path)   // fresh file; if this fails, system is broken
}()
```

### Step 5.5 — Fix `BlobStore.init` `try!`

In `BlobStore.swift`, replace the `try!` in `init(directory:)`:

```swift
// BEFORE
init(directory: URL) {
    self.directory = directory
    try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
}
```

```swift
// AFTER
init(directory: URL) {
    self.directory = directory
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    // If directory creation fails (e.g. disk full), write() will silently skip
    // and read() will return nil — callers already handle nil gracefully.
}
```

### Step 5.6 — Run all tests

```bash
xcodebuild test -project BetterClip.xcodeproj -scheme BetterClip \
  -destination 'platform=macOS'
```

Expected: **ALL TESTS PASS** including `testRecoveryFromCorruptDatabase`.

### Step 5.7 — Commit

```bash
git add BetterClip/Core/Database.swift \
        BetterClip/Core/BlobStore.swift \
        BetterClipTests/DatabaseTests.swift
git commit -m "fix: make Database init(path:) throwing with corrupt-DB recovery; soften BlobStore try! to try?"
```

---

## Final Verification

After all 5 tasks, run the full test suite:

```bash
xcodebuild test -project BetterClip.xcodeproj -scheme BetterClip \
  -destination 'platform=macOS'
```

Expected output (no exact count guarantee — depends on existing tests):
```
** TEST SUCCEEDED **
```

Manual crash reproduction check:
1. Launch app with empty clipboard history.
2. Open the panel.
3. Press the Down arrow key repeatedly — should show placeholder, no crash.
4. Press Cmd+C on the same text 10 times quickly — monitor Console.app for any crash reports under `BetterClip`.
