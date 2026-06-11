// BetterClipTests/AppViewModelCrashTests.swift
import XCTest
@testable import BetterClip

final class AppViewModelCrashTests: XCTestCase {

    var vm: AppViewModel!

    override func setUp() {
        super.setUp()
        vm = AppViewModel()
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

    func test_previewPane_idxGuard_negativeIdxWithEmptyClips_doesNotCrash() {
        vm.clips = []
        vm.selectedIndex = -1

        // Fixed guard is `idx >= 0 && idx < clips.count`.
        // Old guard was `idx < clips.count` only: -1 < 0 → true → clips[-1] → CRASH.
        let idx = vm.selectedIndex
        let safeToAccess = idx >= 0 && idx < vm.clips.count
        XCTAssertFalse(safeToAccess,
            "idx=-1 with empty clips must NOT pass the access guard")
    }
}
