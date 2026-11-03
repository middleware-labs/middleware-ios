// Copyright © 2023 Middleware. Licensed under the Apache License, Version 2.0

#if os(iOS) || targetEnvironment(macCatalyst) || os(tvOS)
import Foundation
import UIKit

enum FrameClassification {
    case normal
    case slow
    case frozen
}

@available(macOS 14.0, *)
class SlowRenderingDetector {

    /// How many frame budgets a frame must take before it counts as slow. Halfway
    /// to the next vsync: timing jitter around one budget stays normal, and a frame
    /// that really missed a vsync (two budgets or more) is always caught.
    static let missedFrameFactor = 1.5

    private struct FrameStats {
        var count = 0
        var maxDuration: CFTimeInterval = 0

        mutating func record(_ duration: CFTimeInterval) {
            count += 1
            maxDuration = max(maxDuration, duration)
        }
    }

    private var displayLink: CADisplayLink?
    private var previousTimestamp: CFTimeInterval = 0.0
    private var slowFrames: [String: FrameStats] = [:]
    private var frozenFrames: [String: FrameStats] = [:]

    private var configuration: SlowRenderingConfiguration

    public private(set) var tracer: Tracer

    private var timer = Timer()

    public init(configuration: SlowRenderingConfiguration, startImmediately: Bool = true) {
        self.tracer = OpenTelemetry.instance.tracerProvider.get(instrumentationName: "io.opentelemetry.slow-rendering", instrumentationVersion: "0.0.1")
        self.configuration = configuration
        if startImmediately {
            start()
        }
    }

    func start() {
        if(self.displayLink != nil) {
            return
        }

        NotificationCenter.default.addObserver(self, selector: #selector(self.appPaused(notification:)), name: UIApplication.willResignActiveNotification, object: nil)

        NotificationCenter.default.addObserver(self, selector: #selector(self.appResumed(notification:)), name: UIApplication.didBecomeActiveNotification, object: nil)

        let displayLink = CADisplayLink(target: self, selector: #selector(displayLinkCallback))
        displayLink.add(to: .main, forMode: RunLoop.Mode.common)
        self.displayLink = displayLink

        // Installed on the main run loop explicitly: `Timer.scheduledTimer` binds to
        // `RunLoop.current`, which never runs when build() is called off the main
        // thread, and its default mode pauses while the user is scrolling.
        let timer = Timer(timeInterval: 1, repeats: true) { _ in
            self.flushFrames()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    @objc func displayLinkCallback(displayLink: CADisplayLink) {
        if(previousTimestamp == 0.0) {
            previousTimestamp = displayLink.timestamp
            return
        }

        let duration = displayLink.timestamp - previousTimestamp
        previousTimestamp = displayLink.timestamp

        recordFrame(duration: duration, frameBudget: displayLink.targetTimestamp - displayLink.timestamp)
    }

    func recordFrame(duration: CFTimeInterval, frameBudget: CFTimeInterval) {
        let classification = Self.classify(
            duration: duration,
            frameBudget: frameBudget,
            slowThreshold: configuration.slowFrameThreshold / 1e3,
            frozenThreshold: configuration.frozenFrameThreshold / 1e3)

        switch classification {
        case .normal:
            return
        case .slow:
            slowFrames[getScreenName(), default: FrameStats()].record(duration)
        case .frozen:
            frozenFrames[getScreenName(), default: FrameStats()].record(duration)
        }
    }

    /// A frame is slow once it takes longer than both the configured threshold and
    /// `missedFrameFactor` frame budgets. The budget comes from the display link, so
    /// the decision holds on 60Hz, ProMotion and Low Power Mode alike; a fixed 16.7ms
    /// is about one normal frame at 60Hz and every frame at 30Hz.
    static func classify(duration: CFTimeInterval, frameBudget: CFTimeInterval, slowThreshold: CFTimeInterval, frozenThreshold: CFTimeInterval) -> FrameClassification {
        if duration >= frozenThreshold {
            return .frozen
        }
        if duration >= max(slowThreshold, frameBudget * missedFrameFactor) {
            return .slow
        }
        return .normal
    }

    @objc func appPaused(notification: Notification) {
        self.displayLink?.isPaused = true
        flushFrames()
    }

    @objc func appResumed(notification: Notification) {
        previousTimestamp = 0.0
        self.displayLink?.isPaused = false
    }

    func flushFrames() {
        for (activityName, stats) in self.slowFrames {
            reportFrame("slowRenders", activityName, stats)
        }

        for (activityName, stats) in self.frozenFrames {
            reportFrame("frozenRenders", activityName, stats)
        }
        self.slowFrames.removeAll()
        self.frozenFrames.removeAll()
    }

    private func reportFrame(_ type: String, _ activityName: String, _ stats: FrameStats) {
        let now = Date()
        let span = tracer.spanBuilder(spanName: type).setStartTime(time: now).startSpan()
        span.setAttribute(key: "component", value: "ui")
        span.setAttribute(key: "count", value: stats.count)
        span.setAttribute(key: "activity.name", value: activityName)
        span.setAttribute(key: "frame.max_duration_ms", value: stats.maxDuration * 1e3)
        span.end(time: now)
    }
}
#endif
