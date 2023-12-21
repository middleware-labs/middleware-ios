// Copyright © 2023 Middleware. Licensed under the Apache License, Version 2.0

import Foundation
import UIKit
import OpenTelemetryApi
import OpenTelemetrySdk

class AppStart {
    var spanStart: Date
    var appStart: Span?
    var isPrewarm: Bool = false
    var prewarmAvailable: Bool {
        if #available(iOS 15.0, *) {
            return true
        }
        return false
    }
    
    var possibleAppStartTimingErrorThreshold: TimeInterval = 60 * 5
    var wasBackgroundedBeforeWillEnterForeground: Bool = false
    
    init(spanStart: Date) {
        self.spanStart = spanStart
    }
    
    func sendAppStartSpan() {
        isPrewarm = ProcessInfo.processInfo.environment["ActivePrewarm"] == "1"
        constructAppStartSpan()
        initializeAppStartupListeners()
    }
    
    private func processStartTime() throws -> Date {
        let name = "kern.proc.pid"
        var len: size_t = 4
        var mib = [Int32](repeating: 0, count: 4)
        var kp: kinfo_proc = kinfo_proc()
        try mib.withUnsafeMutableBufferPointer { (mibBP: inout UnsafeMutableBufferPointer<Int32>) throws in
            try name.withCString { (nbp: UnsafePointer<Int8>) throws in
                guard sysctlnametomib(nbp, mibBP.baseAddress, &len) == 0 else {
                    throw POSIXError(.EAGAIN)
                }
            }
            mibBP[3] = getpid()
            len =  MemoryLayout<kinfo_proc>.size
            guard sysctl(mibBP.baseAddress, 4, &kp, &len, nil, 0) == 0 else {
                throw POSIXError(.EAGAIN)
            }
        }
        let startTime = kp.kp_proc.p_un.__p_starttime
        let ti: TimeInterval = Double(startTime.tv_sec) + (Double(startTime.tv_usec) / 1e6)
        return Date(timeIntervalSince1970: ti)
    }
    
    private func initializeAppStartupListeners() {
        let notifCenter = NotificationCenter.default
        
        var didBecomeActiveNotificationToken: NSObjectProtocol?
        let didBecomeActiveClosure: (Notification) -> Void = { notification in
            defer {
                self.appStart = nil
                
                if let didBecomeActiveNotificationToken = didBecomeActiveNotificationToken {
                    notifCenter.removeObserver(didBecomeActiveNotificationToken)
                }
            }
            
            guard let appStart = self.appStart else { return }
            
            // If we are prewarmed, the app was made active from the background,
            // or we are over a nonsensical threshold, we do not report the appStart span.
            if (self.isPrewarm && self.prewarmAvailable)
                || self.wasBackgroundedBeforeWillEnterForeground
                || (Date().timeIntervalSince1970 - (self.spanStart.timeIntervalSince1970)) > self.possibleAppStartTimingErrorThreshold {
                OpenTelemetry.instance.contextProvider.removeContextForSpan(appStart)
            } else {
                appStart.addEvent(name: notification.name.rawValue)
                appStart.end()
            }
        }
        didBecomeActiveNotificationToken = notifCenter.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main, using: didBecomeActiveClosure)
        
        var didFinishLaunchingNotificationToken: NSObjectProtocol?
        let didFinishLaunchingClosure: (Notification) -> Void = { notification in
            self.appStart?.addEvent(name: notification.name.rawValue)
            if let didFinishLaunchingNotificationToken = didFinishLaunchingNotificationToken {
                notifCenter.removeObserver(didFinishLaunchingNotificationToken)
            }
        }
        didFinishLaunchingNotificationToken = notifCenter.addObserver(forName: UIApplication.didFinishLaunchingNotification, object: nil, queue: .main, using: didFinishLaunchingClosure)
        
        // willEnterForeground
        var willEnterForegroundNotificationToken: NSObjectProtocol?
        let willEnterForegroundClosure: (Notification) -> Void = { notification in
            self.wasBackgroundedBeforeWillEnterForeground = UIApplication.shared.applicationState == .background
            self.appStart?.addEvent(name: notification.name.rawValue)
            if let willEnterForegroundNotificationToken = willEnterForegroundNotificationToken {
                notifCenter.removeObserver(willEnterForegroundNotificationToken)
            }
        }
        willEnterForegroundNotificationToken = notifCenter.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main, using: willEnterForegroundClosure)
    }
    
    private func constructAppStartSpan() {
        var procStart: Date?
        do {
            procStart = try processStartTime()
            spanStart = procStart!
        } catch {
            // swallow
        }
        
        let tracer = OpenTelemetry.instance.tracerProvider.get(instrumentationName: Constants.Global.INSTRUMENTATION_NAME, instrumentationVersion: Constants.Global.VERSION_STRING)
        appStart = tracer.spanBuilder(spanName: Constants.Spans.APP_START).setStartTime(time: spanStart).startSpan()
        appStart!.setAttribute(key: Constants.Attributes.COMPONENT, value: "appstart")
        if let procStart = procStart {
            appStart!.addEvent(name: Constants.Events.PROCESS_START, timestamp: procStart)
        }
        
        OpenTelemetry.instance.contextProvider.setActiveSpan(appStart!)
    }
}