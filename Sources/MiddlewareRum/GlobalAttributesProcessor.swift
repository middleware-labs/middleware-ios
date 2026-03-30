// Copyright © 2023 Middleware. Licensed under the Apache License, Version 2.0

import Foundation

class GlobalAttributesProcessor: SpanProcessor {
    var isStartRequired = true
    
    var isEndRequired = false
    init(appName: String? = nil) {}
    
    func onStart(parentContext: SpanContext?, span: ReadableSpan) {
        if Thread.current.isMainThread {
            span.setAttribute(key: MiddlewareConstants.Attributes.THREAD_NAME, value: "main")
        } else if isUsefulString(Thread.current.name) {
            span.setAttribute(key: MiddlewareConstants.Attributes.THREAD_NAME, value: Thread.current.name!)
        }
        MiddlewareRum.addGlobalAttributesToSpan(span)
    }
    
    func onEnd(span: ReadableSpan) {}
    
    func shutdown(explicitTimeout: TimeInterval?) {}
    
    func forceFlush(timeout: TimeInterval?) {}
    
}
