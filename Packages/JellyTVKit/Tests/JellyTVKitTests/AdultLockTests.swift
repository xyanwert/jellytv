import XCTest
@testable import JellyTVKit

/// The twelve-hour door: what opens it, and that it closes itself.
final class AdultLockTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testTheCodeIsTheCode() {
        XCTAssertTrue(AdultLock.matches("111282"))
        XCTAssertTrue(AdultLock.matches(" 111282 "))
        XCTAssertFalse(AdultLock.matches("111283"))
        XCTAssertFalse(AdultLock.matches("11128"))
        XCTAssertFalse(AdultLock.matches(""))
    }

    /// The keypad fills to this length and then submits itself, so a code
    /// whose length drifted from the pad's would make the pad unusable
    /// rather than merely wrong.
    func testTheKeypadLengthFollowsTheCode() {
        XCTAssertEqual(AdultLock.digits, AdultLock.code.count)
    }

    func testNothingStoredIsLocked() {
        XCTAssertFalse(AdultLock.isUnlocked(until: nil, now: now))
        XCTAssertNil(AdultLock.remainingLabel(until: nil, now: now))
        XCTAssertEqual(AdultLock.remaining(until: nil, now: now), 0)
    }

    func testTwelveHoursThenShut() {
        let until = AdultLock.expiry(from: now)
        XCTAssertEqual(until.timeIntervalSince(now), 12 * 60 * 60, accuracy: 0.001)
        XCTAssertTrue(AdultLock.isUnlocked(until: until, now: now))
        XCTAssertTrue(AdultLock.isUnlocked(until: until, now: now.addingTimeInterval(11 * 3600)))
        XCTAssertFalse(AdultLock.isUnlocked(until: until, now: until))
        XCTAssertFalse(AdultLock.isUnlocked(until: until, now: until.addingTimeInterval(1)))
    }

    /// A deadline stored before a relaunch that happened a day later has to
    /// read as locked — the whole point is that it expires unattended.
    func testAStaleDeadlineReadsAsLocked() {
        let yesterday = now.addingTimeInterval(-24 * 3600)
        let until = AdultLock.expiry(from: yesterday)
        XCTAssertFalse(AdultLock.isUnlocked(until: until, now: now))
    }

    func testTheReadoutCountsDown() {
        let until = AdultLock.expiry(from: now)
        XCTAssertEqual(AdultLock.remainingLabel(until: until, now: now), "12h 0m")
        XCTAssertEqual(AdultLock.remainingLabel(until: until,
                                                now: now.addingTimeInterval(18 * 60)), "11h 42m")
        XCTAssertEqual(AdultLock.remainingLabel(until: until,
                                                now: until.addingTimeInterval(-42 * 60)), "42m")
        XCTAssertEqual(AdultLock.remainingLabel(until: until,
                                                now: until.addingTimeInterval(-30)), "under a minute")
        XCTAssertNil(AdultLock.remainingLabel(until: until, now: until))
    }
}
