// Copyright © 2023 Middleware. Licensed under the Apache License, Version 2.0

#if os(iOS) || targetEnvironment(macCatalyst) || os(tvOS)
import Foundation
import UIKit

@available(macOS 14.0, *)
class SlowRenderingDetector {
    
    private var displayLink: CADisplayLink?
    private var previousTimestamp: CFTimeInterval = 0.0
    private var slowFrames: [String: Int] = [:]
    private var frozenFrames: [String: Int] = [:]
    
    private var configuration: SlowRenderingConfiguration
    
    public private(set) var tracer: Tracer
    
    private var activityName: String
    private var timer = Timer()
    
    public init(configuration: SlowRenderingConfiguration) {
        self.tracer = OpenTelemetry.instance.tracerProvider.get(instrumentationName: "io.opentelemetry.slow-rendering", instrumentationVersion: "0.0.1")
        self.activityName = getScreenName()
        self.configuration = configuration
        start()
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
        
        self.timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true, block: { _ in
            self.flushFrames()
        })
    }
    
    @objc func displayLinkCallback(displayLink: CADisplayLink) {
        if(previousTimestamp == 0.0) {
            previousTimestamp = displayLink.timestamp
            return
        }
        
        let duration = displayLink.timestamp - previousTimestamp
        previousTimestamp = displayLink.timestamp
        
        let slowThresholdInSecs = configuration.slowFrameThreshold / 1e3
        let frozenThresholdInSecs = configuration.frozenFrameThreshold / 1e3
        
        if duration >= frozenThresholdInSecs {
            if let count = self.frozenFrames[activityName] {
                self.frozenFrames[activityName] = count + 1
            } else {
                self.frozenFrames[activityName] = 1
            }
        } else if(duration >= slowThresholdInSecs) {
            if let count = self.slowFrames[activityName] {
                self.slowFrames[activityName] = count + 1
            } else {
                self.slowFrames[activityName] = 1
            }
        }
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
        for (activityName, count) in self.slowFrames {
            reportFrame("slowRenders", activityName, count)
        }
        
        for (activityName, count) in self.frozenFrames {
            reportFrame("frozenRenders", activityName, count)
        }
        self.slowFrames.removeAll()
        self.frozenFrames.removeAll()
    }
    
    func reportFrame(_ type: String, _ activityName: String, _ count: Int) {
        let now = Date()
        let span = tracer.spanBuilder(spanName: type).setStartTime(time: now).startSpan()
        span.setAttribute(key: "component", value: "ui")
        span.setAttribute(key: "count", value: count)
        span.setAttribute(key: "activity.name", value: activityName)
        span.end(time: now)
    }
}
#endif
