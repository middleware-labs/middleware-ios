// Copyright © 2023 Middleware. Licensed under the Apache License, Version 2.0

import Foundation

/// Emits a `screen_view` span (the mobile counterpart of the browser's `pageview`)
/// whenever the visible screen changes; the backend counts these as RUM views.
///
/// Armed only by UIInstrumentation, so hybrid hosts (Flutter / React Native) that
/// disable UI instrumentation and emit their own `screen_view` are not double-counted
/// when they push route names through `MiddlewareRum.setScreenName`.
final class ScreenViews {
    static let shared = ScreenViews()
    static let EVENT_TYPE_SCREEN_VIEW = "screen_view"

    private let lock = NSLock()
    private var armed = false
    private var callbackRegistered = false
    private var lastScreenName: String?

    /// Starts reporting screen changes from the shared screen-name store.
    func install() {
        lock.lock()
        armed = true
        let register = !callbackRegistered
        callbackRegistered = true
        lock.unlock()
        if register {
            addScreenNameCallback { name in ScreenViews.shared.record(name) }
        }
    }

    /// Records a view of `screenName` unless it is already the current screen.
    func record(_ screenName: String) {
        lock.lock()
        if !armed || screenName.isEmpty || screenName == "unknown" || screenName == lastScreenName {
            lock.unlock()
            return
        }
        let previous = lastScreenName
        lastScreenName = screenName
        lock.unlock()

        let span = tracer().spanBuilder(spanName: screenName).startSpan()
        span.setAttribute(key: MiddlewareConstants.Attributes.COMPONENT, value: "ui")
        span.setAttribute(key: MiddlewareConstants.Attributes.EVENT_TYPE, value: ScreenViews.EVENT_TYPE_SCREEN_VIEW)
        span.setAttribute(key: MiddlewareConstants.Attributes.SCREEN_NAME, value: screenName)
        if let previous = previous {
            span.setAttribute(key: MiddlewareConstants.Attributes.LAST_SCREEN_NAME, value: previous)
        }
        span.end()
    }

    func resetForTest() {
        lock.lock()
        armed = false
        lastScreenName = nil
        lock.unlock()
    }

    func armForTest() {
        lock.lock()
        armed = true
        lock.unlock()
    }
}
