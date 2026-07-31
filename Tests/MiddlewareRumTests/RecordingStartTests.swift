import XCTest
@testable import MiddlewareRum

#if os(iOS) || targetEnvironment(macCatalyst) || os(tvOS)

/// Regression tests for how session recording is started.
///
/// Recording used to be deferred to `Timer.scheduledTimer`, which binds to
/// `RunLoop.current`. Native apps call `build()` from the main thread so it
/// worked there, but hybrid hosts (React Native, Flutter) call it from a GCD
/// queue with no run loop — the timer never fired and recording never started.
final class RecordingStartTests: XCTestCase {

    /// Whether the automatic start path brought recording up after the SDK was
    /// built off the main thread. Captured once, before any test can influence
    /// recording state through the start/stop API.
    private static var autoStartedAfterOffMainBuild = false

    /// `create()` registers global providers, so the SDK is built once for the
    /// whole suite — deliberately from a GCD queue with no run loop, which is
    /// the scenario that used to break. This also gives every test the recording
    /// context (target/token) that the start/stop API needs.
    private static let booted: Bool = {
        let built = DispatchSemaphore(value: 0)
        var ok = false
        DispatchQueue.global(qos: .userInitiated).async {
            ok = MiddlewareRumBuilder()
                .target("http://127.0.0.1:1")
                .rumAccessToken("test-token")
                .serviceName("recording-start-tests")
                .projectName("recording-start-tests")
                .disableCrashReportingInstrumentation()
                .disableAppLifcycleInstrumentation()
                .disableUIInstrumentation()
                .build()
            built.signal()
        }
        built.wait()

        // The start is dispatched to the main run loop; spin it until recording
        // comes up or we run out of patience.
        let deadline = Date().addingTimeInterval(15)
        while !MiddlewareRum.isRecording() && Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.1))
        }
        autoStartedAfterOffMainBuild = MiddlewareRum.isRecording()
        return ok
    }()

    override func setUp() {
        super.setUp()
        XCTAssertTrue(Self.booted, "MiddlewareRum failed to build")
    }

    override func tearDown() {
        MiddlewareRum.stopRecording()
        super.tearDown()
    }

    /// Documents the root cause: a timer scheduled from a GCD queue is attached
    /// to a run loop that is never run, so its block never executes. This is why
    /// the start path had to move to the main run loop.
    func testTimerScheduledOnGCDQueueNeverFires() {
        let neverFires = expectation(description: "timer block on a GCD queue")
        neverFires.isInverted = true

        DispatchQueue.global().async {
            // Same call shape as the old start path.
            Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
                neverFires.fulfill()
            }
        }

        wait(for: [neverFires], timeout: 1.0)
    }

    /// The fix: the start is scheduled on the main run loop, so it fires no
    /// matter which thread `build()` was called from.
    func testRecordingStartsWhenBuiltOffMainThread() throws {
        try XCTSkipUnless(
            NetworkReachability.isNetworkAvailable(),
            "The automatic start path waits for reachability; skipping offline.")

        XCTAssertTrue(
            Self.autoStartedAfterOffMainBuild,
            "Recording must start when build() is called from a thread with no run loop")
    }

    /// `startRecording()` is an explicit host intent: it overrides both the
    /// sampler and a `disableRecording()` configuration.
    func testStartRecordingOverridesSamplerAndInitFlag() {
        MiddlewareRum.stopRecording()
        XCTAssertFalse(MiddlewareRum.isRecording())

        MiddlewareRum.startRecording()

        XCTAssertTrue(
            MiddlewareRum.isRecording(),
            "startRecording() must turn recording on regardless of the sampler decision")
    }

    /// `stopRecording()` is sticky: a session rotation must not silently resume
    /// recording behind the host's back.
    func testStopRecordingSurvivesSessionRotation() {
        MiddlewareRum.startRecording()
        XCTAssertTrue(MiddlewareRum.isRecording())

        MiddlewareRum.stopRecording()
        XCTAssertFalse(MiddlewareRum.isRecording())

        // Rotate the session; the registered callback re-applies recording state.
        MiddlewareRum.setNativeSession("aaaaaaaabbbbbbbbccccccccdddddddd", startTimeMs: 1_750_000_000_000)
        let settled = expectation(description: "session rotation processed")
        DispatchQueue.main.async { settled.fulfill() }
        wait(for: [settled], timeout: 5.0)

        XCTAssertFalse(
            MiddlewareRum.isRecording(),
            "stopRecording() must survive session rotation until startRecording() is called")

        resetNativeSessionControlInternal()
    }

    /// And `startRecording()` clears the manual stop.
    func testStartRecordingClearsManualStop() {
        MiddlewareRum.stopRecording()
        XCTAssertFalse(MiddlewareRum.isRecording())

        MiddlewareRum.startRecording()
        XCTAssertTrue(MiddlewareRum.isRecording())
    }
}

#endif
