import XCTest

@testable import GhostTextCore

final class SuggestionSchedulerTests: XCTestCase {

    func testTypingSchedulesFireAtQuietPeriod() {
        var scheduler = SuggestionScheduler(quietPeriod: 0.25)
        let commands = scheduler.typingOccurred(at: 0)
        XCTAssertEqual(commands, [.cancelInFlight, .scheduleFire(at: 0.25)])
    }

    func testRetypingCancelsAndReschedules() {
        var scheduler = SuggestionScheduler(quietPeriod: 0.25)
        _ = scheduler.typingOccurred(at: 0)
        let commands = scheduler.typingOccurred(at: 0.10)
        XCTAssertEqual(commands, [.cancelInFlight, .scheduleFire(at: 0.35)])
    }

    func testSupersededFireIsIgnored() {
        var scheduler = SuggestionScheduler(quietPeriod: 0.25)
        _ = scheduler.typingOccurred(at: 0)
        _ = scheduler.typingOccurred(at: 0.10)
        XCTAssertFalse(scheduler.fireDue(at: 0.25), "the original 0.25 fire was superseded by the 0.10 retype")
    }

    func testCurrentFireFires() {
        var scheduler = SuggestionScheduler(quietPeriod: 0.25)
        _ = scheduler.typingOccurred(at: 0)
        _ = scheduler.typingOccurred(at: 0.10)
        XCTAssertTrue(scheduler.fireDue(at: 0.35))
    }

    func testFireDueWithNoScheduleReturnsFalse() {
        var scheduler = SuggestionScheduler()
        XCTAssertFalse(scheduler.fireDue(at: 1.0))
    }

    func testFireDueIsOneShot() {
        var scheduler = SuggestionScheduler(quietPeriod: 0.25)
        _ = scheduler.typingOccurred(at: 0)
        XCTAssertTrue(scheduler.fireDue(at: 0.25))
        XCTAssertFalse(scheduler.fireDue(at: 0.25), "a fire cannot be consumed twice")
    }

    func testSuggestionDismissedCancelsPending() {
        var scheduler = SuggestionScheduler(quietPeriod: 0.25)
        _ = scheduler.typingOccurred(at: 0)
        let commands = scheduler.suggestionDismissed()
        XCTAssertEqual(commands, [.cancelAll])
        XCTAssertFalse(scheduler.fireDue(at: 0.25), "dismissal must cancel the pending fire")
    }

    func testCustomQuietPeriod() {
        var scheduler = SuggestionScheduler(quietPeriod: 0.5)
        let commands = scheduler.typingOccurred(at: 2.0)
        XCTAssertEqual(commands, [.cancelInFlight, .scheduleFire(at: 2.5)])
        XCTAssertTrue(scheduler.fireDue(at: 2.5))
    }

    func testDefaultQuietPeriodIsQuarterSecond() {
        let scheduler = SuggestionScheduler()
        XCTAssertEqual(scheduler.quietPeriod, 0.25)
    }

    func testChainOfRetypesOnlyLastFires() {
        var scheduler = SuggestionScheduler(quietPeriod: 0.25)
        _ = scheduler.typingOccurred(at: 0)
        _ = scheduler.typingOccurred(at: 0.05)
        _ = scheduler.typingOccurred(at: 0.10)
        _ = scheduler.typingOccurred(at: 0.15)
        XCTAssertFalse(scheduler.fireDue(at: 0.25))
        XCTAssertFalse(scheduler.fireDue(at: 0.30))
        XCTAssertFalse(scheduler.fireDue(at: 0.35))
        XCTAssertTrue(scheduler.fireDue(at: 0.40))
    }

    func testDismissThenTypingAgainSchedulesFreshFire() {
        var scheduler = SuggestionScheduler(quietPeriod: 0.25)
        _ = scheduler.typingOccurred(at: 0)
        _ = scheduler.suggestionDismissed()
        let commands = scheduler.typingOccurred(at: 1.0)
        XCTAssertEqual(commands, [.cancelInFlight, .scheduleFire(at: 1.25)])
        XCTAssertTrue(scheduler.fireDue(at: 1.25))
    }
}
