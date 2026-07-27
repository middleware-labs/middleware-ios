// Copyright © 2023 Middleware. Licensed under the Apache License, Version 2.0

import Foundation

let MAX_SESSION_AGE_SECONDS = 4 * 60 * 60

private var rumSessionId = generateNewSessionId()
private var sessionIdExpiration = Date().addingTimeInterval(TimeInterval(MAX_SESSION_AGE_SECONDS))
private let sessionIdLock = NSLock()
private var sessionIdCallbacks: [(() -> Void)] = []
private var sessionStartTime = Int(Date().timeIntervalSince1970 * 1000)
/// True once an external host (e.g. the React Native SDK) has injected a
/// session id via setNativeSessionInternal. While set, internal rotation
/// (4h expiry, forceNewSessionId) is suppressed — the host owns the session.
private var nativeSessionControl = false

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
    if !nativeSessionControl && (Date() > sessionIdExpiration || forceNewSessionId) {
        sessionIdExpiration = Date().addingTimeInterval(TimeInterval(MAX_SESSION_AGE_SECONDS))
        oldRumSessionId = rumSessionId
        rumSessionId = generateNewSessionId()
        sessionStartTime = Int(Date().timeIntervalSince1970 * 1000)
        isSessionIdChanged = true
        callbacks = sessionIdCallbacks
    }
    sessionIdLock.unlock()
    unlocked = true
    for callback in callbacks {
        callback()
    }
    if isSessionIdChanged {
        createSessionIdChangeSpan(newSessionId: rumSessionId, previousSessionId: oldRumSessionId, newSessionStartTime: sessionStartTime)
    }
    return rumSessionId
}

func getSessionStartTime() -> Int {
    return sessionStartTime
}

/// Binds the session to an externally-owned id (e.g. the React Native SDK's
/// JS session). Suppresses internal rotation until app restart — the external
/// host owns the session lifecycle from here on.
func setNativeSessionInternal(_ sessionId: String, startTimeMs: Int) {
    var callbacks: [(() -> Void)] = []
    var previousSessionId = ""
    var changed = false
    sessionIdLock.lock()
    previousSessionId = rumSessionId
    changed = (rumSessionId != sessionId)
    rumSessionId = sessionId
    sessionStartTime = startTimeMs
    nativeSessionControl = true
    sessionIdExpiration = Date.distantFuture
    callbacks = sessionIdCallbacks
    sessionIdLock.unlock()

    // Even a re-push of the same id must fix the active resource: the initial
    // resource was built with the auto-generated id before injection.
    updateActiveResourceSession(sessionId: sessionId, startTime: startTimeMs)
    if changed {
        for callback in callbacks {
            callback()
        }
        createSessionIdChangeSpan(newSessionId: sessionId, previousSessionId: previousSessionId, newSessionStartTime: startTimeMs)
    }
}

func isNativeSessionControlled() -> Bool {
    sessionIdLock.lock()
    defer {
        sessionIdLock.unlock()
    }
    return nativeSessionControl
}

/// Test hook: releases external session control and restores normal expiry.
func resetNativeSessionControlInternal() {
    sessionIdLock.lock()
    defer {
        sessionIdLock.unlock()
    }
    nativeSessionControl = false
    sessionIdExpiration = Date().addingTimeInterval(TimeInterval(MAX_SESSION_AGE_SECONDS))
}

private func updateActiveResourceSession(sessionId: String, startTime: Int) {
    var activeResource = OpenTelemetry.instance.tracerProvider.getActiveResource()
    activeResource.attributes[MiddlewareConstants.Attributes.SESSION_ID] = AttributeValue(sessionId)
    activeResource.attributes[MiddlewareConstants.Attributes.SESSION_START_TIME] = AttributeValue(startTime)
    OpenTelemetry.instance.tracerProvider.updateActiveResource(activeResource)
}

func createSessionIdChangeSpan(newSessionId: String, previousSessionId: String, newSessionStartTime: Int) {
    let now = Date()
    let tracer = OpenTelemetry.instance.tracerProvider.get(
        instrumentationName: MiddlewareConstants.Global.INSTRUMENTATION_NAME,
        instrumentationVersion: MiddlewareConstants.Global.VERSION_STRING)
    updateActiveResourceSession(sessionId: newSessionId, startTime: newSessionStartTime)

    let span = tracer.spanBuilder(spanName: MiddlewareConstants.Spans.SESSION_ID_CHANGE).setStartTime(time: now).startSpan()
    span.setAttribute(key: MiddlewareConstants.Attributes.PREVIOUS_SESSION_ID, value: previousSessionId)
    span.end(time: now)
}
