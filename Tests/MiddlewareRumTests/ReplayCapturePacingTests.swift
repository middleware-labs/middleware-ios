#if os(iOS) || targetEnvironment(macCatalyst) || os(tvOS)
import XCTest
import UIKit
@testable import MiddlewareRum

final class ReplayCapturePacingTests: XCTestCase {

    override func tearDown() {
        ViewLayoutObserver.shared.disable()
        ViewLayoutObserver.shared.onLayout = nil
        ViewLayoutObserver.shared.throttleInterval = 1
        super.tearDown()
    }

    private func spinRunLoop(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    // MARK: - Run loop trigger

    func testCaptureRunsAfterTheRunLoopPassNotInsideIt() {
        var calls = 0
        ViewLayoutObserver.shared.onLayout = { calls += 1; return true }
        ViewLayoutObserver.shared.enable()

        ViewLayoutObserver.shared.setNeedsCapture()
        XCTAssertEqual(calls, 0, "capture must wait for the end of the run loop pass")

        spinRunLoop(0.2)
        XCTAssertEqual(calls, 1)
    }

    func testLayoutInsideThrottleWindowIsCapturedOnceItPasses() {
        var calls = 0
        ViewLayoutObserver.shared.throttleInterval = 0.3
        ViewLayoutObserver.shared.onLayout = { calls += 1; return true }
        ViewLayoutObserver.shared.enable()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        window.isHidden = false

        ViewLayoutObserver.shared.setNeedsCapture()
        spinRunLoop(0.1)
        XCTAssertEqual(calls, 1)

        window.layer.setNeedsLayout()
        window.layer.layoutIfNeeded()
        spinRunLoop(0.1)
        XCTAssertEqual(calls, 1, "throttled")

        spinRunLoop(0.4)
        XCTAssertEqual(calls, 2, "trailing layout still captured")
    }

    func testDeferredCaptureIsRetried() {
        var calls = 0
        ViewLayoutObserver.shared.onLayout = {
            calls += 1
            return calls >= 2
        }
        ViewLayoutObserver.shared.enable()

        ViewLayoutObserver.shared.setNeedsCapture()
        spinRunLoop(0.1)
        XCTAssertEqual(calls, 1)

        spinRunLoop(ViewLayoutObserver.retryInterval + 0.2)
        XCTAssertEqual(calls, 2)

        spinRunLoop(0.4)
        XCTAssertEqual(calls, 2, "nothing pending once the capture was taken")
    }

    func testDisabledObserverNeverCaptures() {
        var calls = 0
        ViewLayoutObserver.shared.onLayout = { calls += 1; return true }
        ViewLayoutObserver.shared.enable()
        ViewLayoutObserver.shared.disable()

        ViewLayoutObserver.shared.setNeedsCapture()
        spinRunLoop(0.2)
        XCTAssertEqual(calls, 0)
    }

    // MARK: - Adaptive backoff

    func testSlowCaptureDoublesIntervalUpToCap() {
        var interval: TimeInterval = 0
        interval = ReplayRecorderV3.nextAdaptiveInterval(current: interval, base: 0.33, mainThreadDuration: 0.2)
        XCTAssertEqual(interval, 0.66, accuracy: 0.001)
        interval = ReplayRecorderV3.nextAdaptiveInterval(current: interval, base: 0.33, mainThreadDuration: 0.2)
        XCTAssertEqual(interval, 1.32, accuracy: 0.001)
        interval = ReplayRecorderV3.nextAdaptiveInterval(current: interval, base: 0.33, mainThreadDuration: 0.2)
        XCTAssertEqual(interval, ReplayRecorderV3.maximumAdaptiveInterval)
    }

    func testFastCaptureHalvesIntervalBackToBase() {
        var interval: TimeInterval = 2
        interval = ReplayRecorderV3.nextAdaptiveInterval(current: interval, base: 1, mainThreadDuration: 0.02)
        XCTAssertEqual(interval, 0, "halving to the base interval clears the backoff")

        XCTAssertEqual(ReplayRecorderV3.nextAdaptiveInterval(current: 0, base: 1, mainThreadDuration: 0.1), 0)
    }

    // MARK: - Capture guard

    /// UIKit ignores state changes outside touch handling, so fake the state.
    private final class StateGestureRecognizer: UIGestureRecognizer {
        var fakeState: UIGestureRecognizer.State = .possible
        override var state: UIGestureRecognizer.State {
            get { fakeState }
            set { fakeState = newValue }
        }
    }

    func testIdleWindowDoesNotWait() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        window.isHidden = false
        window.addSubview(UIView(frame: window.bounds))

        XCTAssertNil(CaptureActivityGuard.reasonToWait(window: window))
    }

    func testActiveGestureIsInteraction() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        window.isHidden = false
        let view = UIView(frame: window.bounds)
        let recognizer = StateGestureRecognizer()
        view.addGestureRecognizer(recognizer)
        window.addSubview(view)

        recognizer.fakeState = .began
        XCTAssertEqual(CaptureActivityGuard.reasonToWait(window: window), .interaction)
    }

    func testGestureInHiddenSubtreeIsIgnored() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        window.isHidden = false
        let view = UIView(frame: window.bounds)
        view.isHidden = true
        let recognizer = StateGestureRecognizer()
        view.addGestureRecognizer(recognizer)
        window.addSubview(view)

        recognizer.fakeState = .began
        XCTAssertNil(CaptureActivityGuard.reasonToWait(window: window))
    }

    func testFewAnimationsDoNotWaitButManyDo() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        window.isHidden = false
        func addAnimatedView(_ key: String) {
            let view = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
            let animation = CABasicAnimation(keyPath: "opacity")
            animation.duration = 60
            view.layer.add(animation, forKey: key)
            window.addSubview(view)
        }

        for index in 0..<(CaptureActivityGuard.activeAnimationThreshold - 1) {
            addAnimatedView("a\(index)")
        }
        XCTAssertNil(CaptureActivityGuard.reasonToWait(window: window), "a spinner or caret alone must not hold captures back")

        addAnimatedView("last")
        XCTAssertEqual(CaptureActivityGuard.reasonToWait(window: window), .animation)
    }
}
#endif
