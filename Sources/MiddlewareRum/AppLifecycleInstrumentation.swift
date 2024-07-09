// Copyright © 2023 Middleware. Licensed under the Apache License, Version 2.0

import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk

class AppLifecycleInstrumentation {
    
    let INACTIVITY_SESSION_TIMEOUT_SECONDS = 5 * 60
    private var sessionIdInactivityExpiration: Date
    
    private let events = [
        MiddlewareConstants.LifeCycleEvents.UI_APPLICATION_WILL_RESIGN_ACTIVE_NOTIFICATION,
        MiddlewareConstants.LifeCycleEvents.UI_APPLICATION_SUSPENDED_EVENTS_ONLY_NOTIFICATION,
        MiddlewareConstants.LifeCycleEvents.UI_APPLICATION_DID_ENTER_BACKGROUND_NOTIFICATION,
        MiddlewareConstants.LifeCycleEvents.UI_APPLICATION_WILL_ENTER_FOREGROUND_NOTIFICATION,
        MiddlewareConstants.LifeCycleEvents.UI_APPLICATION_DID_BECOME_ACTIVE_ACTIVE_NOTIFICATION,
        MiddlewareConstants.LifeCycleEvents.UI_APPLICATION_SUSPENDED_NOTIFICATION,
        MiddlewareConstants.LifeCycleEvents.UI_APPLICATION_WILL_TERMINATE_NOTIFICATION
    ]
    
    private var activeSpan: SpanHolder?
    private var tracer: Tracer
    
    init() {
        tracer = OpenTelemetry.instance.tracerProvider.get(
            instrumentationName: MiddlewareConstants.Global.INSTRUMENTATION_NAME,
            instrumentationVersion: MiddlewareConstants.Global.VERSION_STRING)
        sessionIdInactivityExpiration = Date().addingTimeInterval(TimeInterval(INACTIVITY_SESSION_TIMEOUT_SECONDS))
    }
    
    func registerLifecycleEvents() {
        for event in events {
            _ = NotificationCenter.default.addObserver(forName: NSNotification.Name(event), object: nil, queue: nil) { (_) in
                self.lifecycleEvent(event: event)
            }
        }
    }
    
    private func lifecycleEvent(event: String) {
        invalidateSession(event)
        if event == MiddlewareConstants.LifeCycleEvents.UI_APPLICATION_WILL_RESIGN_ACTIVE_NOTIFICATION ||
            event == MiddlewareConstants.LifeCycleEvents.UI_APPLICATION_WILL_ENTER_FOREGROUND_NOTIFICATION {
            if activeSpan == nil {
                let span = tracer.spanBuilder(spanName: event == MiddlewareConstants.LifeCycleEvents.UI_APPLICATION_WILL_RESIGN_ACTIVE_NOTIFICATION ? MiddlewareConstants.Spans.RESIGNACTIVE : MiddlewareConstants.Spans.ENTER_FOREGROUND).startSpan()
                span.setAttribute(key: MiddlewareConstants.Attributes.COMPONENT, value: "ui")
                span.setAttribute(key: MiddlewareConstants.Attributes.EVENT_TYPE, value: "app_activity")
                self.activeSpan = SpanHolder(span)
            }
        }
        
        if activeSpan != nil {
            activeSpan!.span.addEvent(name: event)
        }
        
        if event == MiddlewareConstants.LifeCycleEvents.UI_APPLICATION_DID_BECOME_ACTIVE_ACTIVE_NOTIFICATION ||
            event == MiddlewareConstants.LifeCycleEvents.UI_APPLICATION_DID_ENTER_BACKGROUND_NOTIFICATION {
            activeSpan?.span.end()
            activeSpan = nil
        }
        
        if event == MiddlewareConstants.LifeCycleEvents.UI_APPLICATION_WILL_TERMINATE_NOTIFICATION {
            let now = Date()
            let span = tracer.spanBuilder(spanName: MiddlewareConstants.Spans.APP_TERMINATING).setStartTime(time: now).startSpan()
            span.setAttribute(key: MiddlewareConstants.Attributes.COMPONENT, value: "ui")
            span.setAttribute(key: MiddlewareConstants.Attributes.EVENT_TYPE, value: "app_activity")
            span.end(time: now)
        }
        
        if event == MiddlewareConstants.LifeCycleEvents.UI_APPLICATION_WILL_TERMINATE_NOTIFICATION ||
            event == MiddlewareConstants.LifeCycleEvents.UI_APPLICATION_DID_ENTER_BACKGROUND_NOTIFICATION {
            DispatchQueue.global(qos: .background).async {
                (OpenTelemetry.instance.tracerProvider as! TracerProviderSdk).forceFlush(timeout: 2)
            }
            
        }
    }
    
    private func invalidateSession(_ event: String) {
        if event == MiddlewareConstants.LifeCycleEvents.UI_APPLICATION_WILL_RESIGN_ACTIVE_NOTIFICATION {
            sessionIdInactivityExpiration = Date().addingTimeInterval(TimeInterval(INACTIVITY_SESSION_TIMEOUT_SECONDS))
        } else if event == MiddlewareConstants.LifeCycleEvents.UI_APPLICATION_WILL_ENTER_FOREGROUND_NOTIFICATION {
            if Date() > sessionIdInactivityExpiration {
                _  = getRumSessionId(forceNewSessionId: true)
            }
        }
    }
}
