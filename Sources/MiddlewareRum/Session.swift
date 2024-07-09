// Copyright © 2023 Middleware. Licensed under the Apache License, Version 2.0

import Foundation

let MAX_SESSION_AGE_SECONDS = 4 * 60 * 60

private var rumSessionId = generateNewSessionId()
private var sessionIdExpiration = Date().addingTimeInterval(TimeInterval(MAX_SESSION_AGE_SECONDS))
private let sessionIdLock = NSLock()
private var sessionIdCallbacks: [(() -> Void)] = []

func generateNewSessionId() -> String {
    var i=0
    var answer = ""
    while i < 16 {
        i += 1
        let b = Int.random(in: 0..<256)
        answer += String(format: "%02x", b)
    }
    return answer
}

func addSessionIdCallback(_ callback: @escaping (() -> Void)) {
    sessionIdLock.lock()
    defer {
        sessionIdLock.unlock()
    }
    sessionIdCallbacks.append(callback)
}

func getRumSessionId(forceNewSessionId: Bool = false) -> String {
    sessionIdLock.lock()
    var unlocked = false
    var isSessionIdChanged = false
    var oldRumSessionId = ""
    var callbacks: [(() -> Void)] = []
    defer {
        if !unlocked {
            sessionIdLock.unlock()
        }
    }
    if Date() > sessionIdExpiration || forceNewSessionId {
        sessionIdExpiration = Date().addingTimeInterval(TimeInterval(MAX_SESSION_AGE_SECONDS))
        oldRumSessionId = rumSessionId
        rumSessionId = generateNewSessionId()
        isSessionIdChanged = true
        callbacks = sessionIdCallbacks
    }
    sessionIdLock.unlock()
    unlocked = true
    for callback in callbacks {
        callback()
    }
    if isSessionIdChanged {
        createSessionIdChangeSpan(previousSessionId: oldRumSessionId)
    }
    return rumSessionId
}
func createSessionIdChangeSpan(previousSessionId: String) {
    let now = Date()
    let tracer = OpenTelemetry.instance.tracerProvider.get(
        instrumentationName: MiddlewareConstants.Global.INSTRUMENTATION_NAME,
        instrumentationVersion: MiddlewareConstants.Global.VERSION_STRING)
    let span = tracer.spanBuilder(spanName: MiddlewareConstants.Spans.SESSION_ID_CHANGE).setStartTime(time: now).startSpan()
    span.setAttribute(key: MiddlewareConstants.Attributes.PREVIOUS_SESSION_ID, value: previousSessionId)
    span.end(time: now)
}
