import AppKit
import XCTest
@testable import BetterClip

final class PasteboardWriterTests: XCTestCase {
    func testSimulatePasteReturnsFalseWithoutAccessibilityPermission() {
        var postedEvent = false

        let didPaste = PasteboardWriter.simulatePaste(
            isTrusted: { false },
            post: { _ in postedEvent = true }
        )

        XCTAssertFalse(didPaste)
        XCTAssertFalse(postedEvent)
    }

    func testSimulatePastePostsKeyDownAndKeyUpToActiveSession() {
        var postedEvents: [CGEvent] = []

        let didPaste = PasteboardWriter.simulatePaste(
            isTrusted: { true },
            post: { postedEvents.append($0) }
        )

        XCTAssertTrue(didPaste)
        XCTAssertEqual(postedEvents.count, 2)
    }

    func testWriteSnippetCopiesContentToPasteboard() {
        let snippet = Snippet(id: 1, folderId: nil, name: "Sig",
                              content: "Best, Yarin", shortcut: nil,
                              createdAt: Date(), sortOrder: 0)

        PasteboardWriter.write(snippet: snippet)

        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "Best, Yarin")
    }
}
