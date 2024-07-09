// Copyright © 2023 Middleware. Licensed under the Apache License, Version 2.0

import Foundation
#if os(iOS) || targetEnvironment(macCatalyst) || os(tvOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

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
#if os(iOS) || targetEnvironment(macCatalyst) || os(tvOS)
        didBecomeActiveNotificationToken = notifCenter.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main, using: didBecomeActiveClosure)
#elseif os(macOS)
        didBecomeActiveNotificationToken = notifCenter.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main, using: didBecomeActiveClosure)
#endif
        
        var didFinishLaunchingNotificationToken: NSObjectProtocol?
        let didFinishLaunchingClosure: (Notification) -> Void = { notification in
            self.appStart?.addEvent(name: notification.name.rawValue)
            if let didFinishLaunchingNotificationToken = didFinishLaunchingNotificationToken {
                notifCenter.removeObserver(didFinishLaunchingNotificationToken)
            }
        }
        
#if os(iOS) || targetEnvironment(macCatalyst) || os(tvOS)
        didFinishLaunchingNotificationToken = notifCenter.addObserver(forName: UIApplication.didFinishLaunchingNotification, object: nil, queue: .main, using: didFinishLaunchingClosure)
#elseif os(macOS)
        didFinishLaunchingNotificationToken = notifCenter.addObserver(forName: NSApplication.didFinishLaunchingNotification, object: nil, queue: .main, using: didFinishLaunchingClosure)
        
#endif
        
        // willEnterForeground
        var willEnterForegroundNotificationToken: NSObjectProtocol?
        let willEnterForegroundClosure: (Notification) -> Void = { notification in
#if os(iOS) || targetEnvironment(macCatalyst) || os(tvOS)
            self.wasBackgroundedBeforeWillEnterForeground = UIApplication.shared.applicationState == .background
#elseif os(macOS)
            self.wasBackgroundedBeforeWillEnterForeground = NSApplication.shared.isActive == false
#endif
            
            self.appStart?.addEvent(name: notification.name.rawValue)
            if let willEnterForegroundNotificationToken = willEnterForegroundNotificationToken {
                notifCenter.removeObserver(willEnterForegroundNotificationToken)
            }
        }
#if os(iOS) || targetEnvironment(macCatalyst) || os(tvOS)
        willEnterForegroundNotificationToken = notifCenter.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main, using: willEnterForegroundClosure)
#elseif os(macOS)
        willEnterForegroundNotificationToken = notifCenter.addObserver(forName: NSApplication.willBecomeActiveNotification, object: nil, queue: .main, using: willEnterForegroundClosure)
#endif
    }
    
    private func constructAppStartSpan() {
        var procStart: Date?
        do {
            procStart = try processStartTime()
            spanStart = procStart!
        } catch {
            // swallow
        }
        
        let tracer = OpenTelemetry.instance.tracerProvider.get(instrumentationName: MiddlewareConstants.Global.INSTRUMENTATION_NAME, instrumentationVersion: MiddlewareConstants.Global.VERSION_STRING)
        appStart = tracer.spanBuilder(spanName: MiddlewareConstants.Spans.APP_START).setStartTime(time: spanStart).startSpan()
        appStart!.setAttribute(key: MiddlewareConstants.Attributes.COMPONENT, value: "appstart")
        appStart!.setAttribute(key: MiddlewareConstants.Attributes.EVENT_TYPE, value: "app_activity")
        if let procStart = procStart {
            appStart!.addEvent(name: MiddlewareConstants.Events.PROCESS_START, timestamp: procStart)
        }
        
        OpenTelemetry.instance.contextProvider.setActiveSpan(appStart!)
    }
}
