import CoreGraphics
import XCTest

@testable import GhostTextCore

final class CaretResolverTests: XCTestCase {
    private let mainScreen = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    private func makePlacement(source: CaretPlacement.Source = .axRange) -> CaretPlacement {
        CaretPlacement(origin: CGPoint(x: 500, y: 500), lineHeight: 16, source: source)
    }

    // MARK: - Rung 1: axRangeBounds

    func testRung1SaneRectResolvesAsAXRange() {
        let resolver = CaretResolver()
        let rect = CGRect(x: 100, y: 200, width: 8, height: 18)
        let result = resolver.resolve(
            axRangeBounds: rect,
            focusedElementFrame: nil,
            focusedWindowFrame: nil,
            lastKnownGood: nil,
            currentBundleID: "com.test.app",
            now: 0,
            screens: [mainScreen]
        )
        XCTAssertEqual(result?.source, .axRange)
        XCTAssertEqual(result?.origin, CGPoint(x: 100, y: 200))
        XCTAssertEqual(result?.lineHeight, 18)
    }

    func testRung1RejectsZeroSizeRect() {
        let resolver = CaretResolver()
        let rect = CGRect(x: 100, y: 200, width: 0, height: 0)
        let result = resolver.resolve(
            axRangeBounds: rect,
            focusedElementFrame: nil,
            focusedWindowFrame: nil,
            lastKnownGood: nil,
            currentBundleID: nil,
            now: 0,
            screens: [mainScreen]
        )
        XCTAssertNil(result, "zero-size rect at every rung with no fallback should resolve to nil")
    }

    func testRung1RejectsHeightBelowFour() {
        let resolver = CaretResolver()
        let rect = CGRect(x: 100, y: 200, width: 8, height: 2)
        let elementFrame = CGRect(x: 100, y: 200, width: 8, height: 18)
        let result = resolver.resolve(
            axRangeBounds: rect,
            focusedElementFrame: elementFrame,
            focusedWindowFrame: nil,
            lastKnownGood: nil,
            currentBundleID: nil,
            now: 0,
            screens: [mainScreen]
        )
        XCTAssertEqual(result?.source, .axElement, "too-short axRange rect should fall through to rung 2")
    }

    func testRung1RejectsHeightAboveTwoHundred() {
        let resolver = CaretResolver()
        let rect = CGRect(x: 100, y: 200, width: 8, height: 201)
        let elementFrame = CGRect(x: 100, y: 200, width: 8, height: 18)
        let result = resolver.resolve(
            axRangeBounds: rect,
            focusedElementFrame: elementFrame,
            focusedWindowFrame: nil,
            lastKnownGood: nil,
            currentBundleID: nil,
            now: 0,
            screens: [mainScreen]
        )
        XCTAssertEqual(result?.source, .axElement)
    }

    func testRung1AcceptsBoundaryHeightsFourAndTwoHundred() {
        let resolver = CaretResolver()
        let rectLow = CGRect(x: 100, y: 200, width: 8, height: 4)
        let resultLow = resolver.resolve(
            axRangeBounds: rectLow, focusedElementFrame: nil, focusedWindowFrame: nil,
            lastKnownGood: nil, currentBundleID: nil, now: 0, screens: [mainScreen]
        )
        XCTAssertEqual(resultLow?.source, .axRange)

        let rectHigh = CGRect(x: 100, y: 200, width: 8, height: 200)
        let resultHigh = resolver.resolve(
            axRangeBounds: rectHigh, focusedElementFrame: nil, focusedWindowFrame: nil,
            lastKnownGood: nil, currentBundleID: nil, now: 0, screens: [mainScreen]
        )
        XCTAssertEqual(resultHigh?.source, .axRange)
    }

    func testRung1RejectsFullyOffscreenRect() {
        let resolver = CaretResolver()
        let rect = CGRect(x: 5000, y: 5000, width: 8, height: 18)
        let elementFrame = CGRect(x: 100, y: 200, width: 8, height: 18)
        let result = resolver.resolve(
            axRangeBounds: rect,
            focusedElementFrame: elementFrame,
            focusedWindowFrame: nil,
            lastKnownGood: nil,
            currentBundleID: nil,
            now: 0,
            screens: [mainScreen]
        )
        XCTAssertEqual(result?.source, .axElement)
    }

    func testRung1NilInputFallsThroughImmediately() {
        let resolver = CaretResolver()
        let elementFrame = CGRect(x: 100, y: 200, width: 8, height: 18)
        let result = resolver.resolve(
            axRangeBounds: nil,
            focusedElementFrame: elementFrame,
            focusedWindowFrame: nil,
            lastKnownGood: nil,
            currentBundleID: nil,
            now: 0,
            screens: [mainScreen]
        )
        XCTAssertEqual(result?.source, .axElement)
    }

    // MARK: - Rung 2: focusedElementFrame

    func testRung2SaneRectResolvesAsAXElement() {
        let resolver = CaretResolver()
        let rect = CGRect(x: 50, y: 60, width: 300, height: 40)
        let result = resolver.resolve(
            axRangeBounds: nil,
            focusedElementFrame: rect,
            focusedWindowFrame: nil,
            lastKnownGood: nil,
            currentBundleID: nil,
            now: 0,
            screens: [mainScreen]
        )
        XCTAssertEqual(result?.source, .axElement)
        XCTAssertEqual(result?.origin, CGPoint(x: 50, y: 60))
    }

    func testRung2RejectsZeroSize() {
        let resolver = CaretResolver()
        let rect = CGRect(x: 50, y: 60, width: 0, height: 0)
        let windowFrame = CGRect(x: 0, y: 0, width: 800, height: 600)
        let result = resolver.resolve(
            axRangeBounds: nil,
            focusedElementFrame: rect,
            focusedWindowFrame: windowFrame,
            lastKnownGood: nil,
            currentBundleID: nil,
            now: 0,
            screens: [mainScreen]
        )
        XCTAssertEqual(result?.source, .window)
    }

    func testRung2RejectsHeightAtOrAboveTwoThousand() {
        let resolver = CaretResolver()
        let rect = CGRect(x: 50, y: 60, width: 300, height: 2000)
        let windowFrame = CGRect(x: 0, y: 0, width: 800, height: 600)
        let result = resolver.resolve(
            axRangeBounds: nil,
            focusedElementFrame: rect,
            focusedWindowFrame: windowFrame,
            lastKnownGood: nil,
            currentBundleID: nil,
            now: 0,
            screens: [mainScreen]
        )
        XCTAssertEqual(result?.source, .window)
    }

    func testRung2RejectsOffscreenRect() {
        let resolver = CaretResolver()
        let rect = CGRect(x: 9000, y: 9000, width: 300, height: 40)
        let windowFrame = CGRect(x: 0, y: 0, width: 800, height: 600)
        let result = resolver.resolve(
            axRangeBounds: nil,
            focusedElementFrame: rect,
            focusedWindowFrame: windowFrame,
            lastKnownGood: nil,
            currentBundleID: nil,
            now: 0,
            screens: [mainScreen]
        )
        XCTAssertEqual(result?.source, .window)
    }

    // MARK: - Rung 3: focusedWindowFrame

    func testRung3SaneRectResolvesAsWindowWithInset() {
        let resolver = CaretResolver()
        let windowFrame = CGRect(x: 0, y: 0, width: 800, height: 600)
        let result = resolver.resolve(
            axRangeBounds: nil,
            focusedElementFrame: nil,
            focusedWindowFrame: windowFrame,
            lastKnownGood: nil,
            currentBundleID: nil,
            now: 0,
            screens: [mainScreen]
        )
        XCTAssertEqual(result?.source, .window)
        // Inset means the origin is not exactly on the frame's raw edge.
        XCTAssertNotEqual(result?.origin, CGPoint(x: 0, y: 0))
        XCTAssertGreaterThan(result?.origin.x ?? 0, 0)
        XCTAssertGreaterThan(result?.origin.y ?? 0, 0)
    }

    func testRung3RejectsZeroSizeFallsToLastKnownGood() {
        let resolver = CaretResolver()
        let windowFrame = CGRect(x: 0, y: 0, width: 0, height: 0)
        let lastKnownGood = LastKnownGood(placement: makePlacement(source: .lastKnownGood), timestamp: 0, bundleID: "com.test.app")
        let result = resolver.resolve(
            axRangeBounds: nil,
            focusedElementFrame: nil,
            focusedWindowFrame: windowFrame,
            lastKnownGood: lastKnownGood,
            currentBundleID: "com.test.app",
            now: 1,
            screens: [mainScreen]
        )
        XCTAssertEqual(result?.source, .lastKnownGood)
    }

    func testRung3RejectsOffscreenWindowFrame() {
        let resolver = CaretResolver()
        let windowFrame = CGRect(x: 9000, y: 9000, width: 800, height: 600)
        let lastKnownGood = LastKnownGood(placement: makePlacement(source: .lastKnownGood), timestamp: 0, bundleID: "com.test.app")
        let result = resolver.resolve(
            axRangeBounds: nil,
            focusedElementFrame: nil,
            focusedWindowFrame: windowFrame,
            lastKnownGood: lastKnownGood,
            currentBundleID: "com.test.app",
            now: 1,
            screens: [mainScreen]
        )
        XCTAssertEqual(result?.source, .lastKnownGood)
    }

    func testRung3TinyWindowFrameDoesNotDegenerateFromInset() {
        let resolver = CaretResolver()
        // A window smaller than 2x the inset would otherwise produce a
        // negative-size rect after insetBy; the resolver must fall back to
        // the un-inset rect rather than emit garbage geometry.
        let windowFrame = CGRect(x: 100, y: 100, width: 10, height: 10)
        let result = resolver.resolve(
            axRangeBounds: nil,
            focusedElementFrame: nil,
            focusedWindowFrame: windowFrame,
            lastKnownGood: nil,
            currentBundleID: nil,
            now: 0,
            screens: [mainScreen]
        )
        XCTAssertEqual(result?.source, .window)
        XCTAssertEqual(result?.origin, CGPoint(x: 100, y: 100))
    }

    // MARK: - Rung 4: lastKnownGood

    func testRung4UsedWhenAllElseFailsAndFresh() {
        let resolver = CaretResolver(staleAfter: 5)
        let cached = makePlacement(source: .lastKnownGood)
        let lastKnownGood = LastKnownGood(placement: cached, timestamp: 10, bundleID: "com.test.app")
        let result = resolver.resolve(
            axRangeBounds: nil,
            focusedElementFrame: nil,
            focusedWindowFrame: nil,
            lastKnownGood: lastKnownGood,
            currentBundleID: "com.test.app",
            now: 12,
            screens: [mainScreen]
        )
        XCTAssertEqual(result, cached)
    }

    func testRung4RejectsMismatchedBundleID() {
        let resolver = CaretResolver(staleAfter: 5)
        let lastKnownGood = LastKnownGood(placement: makePlacement(), timestamp: 10, bundleID: "com.other.app")
        let result = resolver.resolve(
            axRangeBounds: nil,
            focusedElementFrame: nil,
            focusedWindowFrame: nil,
            lastKnownGood: lastKnownGood,
            currentBundleID: "com.test.app",
            now: 12,
            screens: [mainScreen]
        )
        XCTAssertNil(result)
    }

    func testRung4RejectsStaleTimestamp() {
        let resolver = CaretResolver(staleAfter: 5)
        let lastKnownGood = LastKnownGood(placement: makePlacement(), timestamp: 0, bundleID: "com.test.app")
        let result = resolver.resolve(
            axRangeBounds: nil,
            focusedElementFrame: nil,
            focusedWindowFrame: nil,
            lastKnownGood: lastKnownGood,
            currentBundleID: "com.test.app",
            now: 10,  // 10s elapsed, staleAfter is 5s
            screens: [mainScreen]
        )
        XCTAssertNil(result)
    }

    func testRung4AcceptsJustUnderStaleThreshold() {
        let resolver = CaretResolver(staleAfter: 5)
        let cached = makePlacement(source: .lastKnownGood)
        let lastKnownGood = LastKnownGood(placement: cached, timestamp: 0, bundleID: "com.test.app")
        let result = resolver.resolve(
            axRangeBounds: nil,
            focusedElementFrame: nil,
            focusedWindowFrame: nil,
            lastKnownGood: lastKnownGood,
            currentBundleID: "com.test.app",
            now: 4.9,
            screens: [mainScreen]
        )
        XCTAssertEqual(result, cached)
    }

    func testRung4NilLastKnownGoodResolvesToNil() {
        let resolver = CaretResolver()
        let result = resolver.resolve(
            axRangeBounds: nil,
            focusedElementFrame: nil,
            focusedWindowFrame: nil,
            lastKnownGood: nil,
            currentBundleID: "com.test.app",
            now: 0,
            screens: [mainScreen]
        )
        XCTAssertNil(result)
    }

    // MARK: - Full ladder / priority

    func testAllRungsFailResolvesToNil() {
        let resolver = CaretResolver()
        let badRect = CGRect(x: 9000, y: 9000, width: 8, height: 18)
        let result = resolver.resolve(
            axRangeBounds: badRect,
            focusedElementFrame: badRect,
            focusedWindowFrame: badRect,
            lastKnownGood: nil,
            currentBundleID: "com.test.app",
            now: 0,
            screens: [mainScreen]
        )
        XCTAssertNil(result)
    }

    func testAXRangeTakesPriorityOverAllOtherSaneRungs() {
        let resolver = CaretResolver()
        let axRect = CGRect(x: 10, y: 10, width: 8, height: 18)
        let elementRect = CGRect(x: 50, y: 50, width: 100, height: 20)
        let windowRect = CGRect(x: 0, y: 0, width: 800, height: 600)
        let lastKnownGood = LastKnownGood(placement: makePlacement(), timestamp: 0, bundleID: "com.test.app")
        let result = resolver.resolve(
            axRangeBounds: axRect,
            focusedElementFrame: elementRect,
            focusedWindowFrame: windowRect,
            lastKnownGood: lastKnownGood,
            currentBundleID: "com.test.app",
            now: 0,
            screens: [mainScreen]
        )
        XCTAssertEqual(result?.source, .axRange)
        XCTAssertEqual(result?.origin, CGPoint(x: 10, y: 10))
    }

    func testElementFrameTakesPriorityOverWindowAndLastKnownGood() {
        let resolver = CaretResolver()
        let elementRect = CGRect(x: 50, y: 50, width: 100, height: 20)
        let windowRect = CGRect(x: 0, y: 0, width: 800, height: 600)
        let lastKnownGood = LastKnownGood(placement: makePlacement(), timestamp: 0, bundleID: "com.test.app")
        let result = resolver.resolve(
            axRangeBounds: nil,
            focusedElementFrame: elementRect,
            focusedWindowFrame: windowRect,
            lastKnownGood: lastKnownGood,
            currentBundleID: "com.test.app",
            now: 0,
            screens: [mainScreen]
        )
        XCTAssertEqual(result?.source, .axElement)
    }

    func testMultipleScreensIntersectionAcrossEither() {
        let resolver = CaretResolver()
        let secondScreen = CGRect(x: 1920, y: 0, width: 1920, height: 1080)
        let rect = CGRect(x: 1950, y: 10, width: 8, height: 18)
        let result = resolver.resolve(
            axRangeBounds: rect,
            focusedElementFrame: nil,
            focusedWindowFrame: nil,
            lastKnownGood: nil,
            currentBundleID: nil,
            now: 0,
            screens: [mainScreen, secondScreen]
        )
        XCTAssertEqual(result?.source, .axRange, "rect on the second screen should still be sane")
    }

    // MARK: - AXCoordinates

    func testFlipToAppKitConvertsTopLeftOriginToBottomLeft() {
        // A rect sitting flush at the very top of an 1080-tall screen in
        // AX/CG (top-left, y-down) coordinates should land flush at the
        // very top in AppKit (bottom-left, y-up) coordinates too.
        let axRect = CGRect(x: 100, y: 0, width: 50, height: 20)
        let flipped = AXCoordinates.flipToAppKit(rect: axRect, primaryScreenHeight: 1080)
        XCTAssertEqual(flipped, CGRect(x: 100, y: 1060, width: 50, height: 20))
    }

    func testFlipToAppKitRoundTripsWithItself() {
        let original = CGRect(x: 30, y: 40, width: 60, height: 20)
        let flippedOnce = AXCoordinates.flipToAppKit(rect: original, primaryScreenHeight: 1080)
        let flippedTwice = AXCoordinates.flipToAppKit(rect: flippedOnce, primaryScreenHeight: 1080)
        XCTAssertEqual(flippedTwice, original)
    }

    func testFlipToAppKitBottomOfScreenMapsToZero() {
        let axRect = CGRect(x: 0, y: 1060, width: 50, height: 20)
        let flipped = AXCoordinates.flipToAppKit(rect: axRect, primaryScreenHeight: 1080)
        XCTAssertEqual(flipped.origin.y, 0, accuracy: 0.001)
    }

    // MARK: - Collapsed carets (regression)

    /// Real caret rects from PROBE.md. Every one of these was previously rejected
    /// for having zero or near-zero width, which silently dropped the AX-first
    /// path onto the element-frame fallback in every app that actually works.
    func testRealWorldCaretRectsResolveAsAXRange() {
        let resolver = CaretResolver()
        let observed: [(String, CGRect)] = [
            ("TextEdit", CGRect(x: 157, y: 159, width: 0, height: 14)),
            ("Safari", CGRect(x: 347, y: 235, width: 2, height: 19)),
            ("Brave", CGRect(x: 342, y: 224, width: 0, height: 20)),
            ("Notes", CGRect(x: 980, y: 94, width: 0, height: 23)),
            ("Terminal", CGRect(x: 17, y: 786, width: 7, height: 14)),
        ]
        for (app, rect) in observed {
            let result = resolver.resolve(
                axRangeBounds: rect,
                focusedElementFrame: CGRect(x: 0, y: 0, width: 800, height: 600),
                focusedWindowFrame: nil,
                lastKnownGood: nil,
                currentBundleID: "com.test.app",
                now: 0,
                screens: [mainScreen]
            )
            XCTAssertEqual(result?.source, .axRange, "\(app) should use the caret rect, not a fallback")
            XCTAssertEqual(result?.origin, CGPoint(x: rect.minX, y: rect.minY), "\(app) origin")
        }
    }

    /// The Electron shape: attribute advertised, rect meaningless. Must fall through.
    func testElectronZeroSizeRectFallsThroughToElement() {
        let resolver = CaretResolver()
        let result = resolver.resolve(
            axRangeBounds: CGRect(x: 0, y: 982, width: 0, height: 0),
            focusedElementFrame: CGRect(x: 10, y: 20, width: 800, height: 600),
            focusedWindowFrame: nil,
            lastKnownGood: nil,
            currentBundleID: "com.test.app",
            now: 0,
            screens: [mainScreen]
        )
        XCTAssertEqual(result?.source, .axElement)
    }

    func testZeroWidthCaretFullyOffScreenIsRejected() {
        let resolver = CaretResolver()
        let result = resolver.resolve(
            axRangeBounds: CGRect(x: 5000, y: 200, width: 0, height: 18),
            focusedElementFrame: nil,
            focusedWindowFrame: nil,
            lastKnownGood: nil,
            currentBundleID: "com.test.app",
            now: 0,
            screens: [mainScreen]
        )
        XCTAssertNil(result)
    }
}
