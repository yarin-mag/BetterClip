// BetterClipTests/ClipboardMonitorTests.swift
import XCTest
@testable import BetterClip

final class ClipboardMonitorTests: XCTestCase {
    func testIgnoreChangeCountStoresAndConsumesCount() {
        let monitor = ClipboardMonitor()
        monitor.ignoreChangeCount(42)
        XCTAssertTrue(monitor.ignoredChangeCounts.contains(42),
            "ignoreChangeCount must store the count")
        let removed = monitor.ignoredChangeCounts.remove(42)
        XCTAssertNotNil(removed,
            "Count must be removable (simulating poll() consuming it)")
        XCTAssertFalse(monitor.ignoredChangeCounts.contains(42),
            "After removal, count must no longer be present")
    }

    func testMultipleIgnoredCountsAreTrackedIndependently() {
        let monitor = ClipboardMonitor()
        monitor.ignoreChangeCount(10)
        monitor.ignoreChangeCount(20)
        XCTAssertTrue(monitor.ignoredChangeCounts.contains(10))
        XCTAssertTrue(monitor.ignoredChangeCounts.contains(20))
        monitor.ignoredChangeCounts.remove(10)
        XCTAssertFalse(monitor.ignoredChangeCounts.contains(10))
        XCTAssertTrue(monitor.ignoredChangeCounts.contains(20),
            "Removing one count must not affect others")
    }
}
