// BetterClipTests/PreferencesTests.swift
import XCTest
@testable import BetterClip

final class PreferencesTests: XCTestCase {

    private var suiteName: String!
    private var testDefaults: UserDefaults!
    private var prefs: Preferences!

    override func setUp() {
        super.setUp()
        suiteName = "com.betterclip.tests.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
        prefs = Preferences(defaults: testDefaults)
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testHistoryLimit_missingKey_returnsDefault() {
        XCTAssertEqual(prefs.historyLimit, 200)
    }

    func testHistoryLimit_validStoredValue_returnsIt() {
        testDefaults.set(150, forKey: "historyLimit")
        XCTAssertEqual(prefs.historyLimit, 150)
    }

    func testHistoryLimit_legacyValueBelowMinimum_returnsDefault() {
        testDefaults.set(4, forKey: "historyLimit")
        XCTAssertEqual(prefs.historyLimit, 200,
            "historyLimit=4 is a legacy out-of-range value; must fall back to 200, not return 4")
    }

    func testHistoryLimit_exactlyMinimum_returnsIt() {
        testDefaults.set(50, forKey: "historyLimit")
        XCTAssertEqual(prefs.historyLimit, 50)
    }

    func testHistoryLimit_zero_returnsDefault() {
        testDefaults.set(0, forKey: "historyLimit")
        XCTAssertEqual(prefs.historyLimit, 200)
    }
}
