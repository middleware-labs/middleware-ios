// Copyright © 2023 Middleware. Licensed under the Apache License, Version 2.0

import Foundation
#if !os(macOS)
import DeviceKit
#endif

class GlobalAttributesProcessor: SpanProcessor {
    var isStartRequired = true
    
    var isEndRequired = false
    let appName: String
    let appVersion: String?
    let deviceModel: String
    init(appName: String? = nil) {
        let app = Bundle.main.infoDictionary?["CFBundleName"] as? String
        if let name = appName {
            self.appName = name
        } else if let app = app {
            self.appName = app
        } else {
            self.appName = MiddlewareConstants.Global.UNKNOWN_APP_NAME
        }
        let bundleVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        let bundleShortVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        appVersion = bundleShortVersion ?? bundleVersion
#if !os(macOS)
        deviceModel = DeviceKit.Device.current.description
#else
        deviceModel = Device.current.model
#endif
    }
    
    func onStart(parentContext: SpanContext?, span: ReadableSpan) {
        span.setAttribute(key: MiddlewareConstants.Attributes.BROWSER_TRACE, value: "true")
        span.setAttribute(key: MiddlewareConstants.Attributes.MW_AGENT, value: "true")
        span.setAttribute(key: MiddlewareConstants.Attributes.APP, value: appName)
        if appVersion != nil {
            span.setAttribute(key: MiddlewareConstants.Attributes.APP_VERSION, value: appVersion!)
        }
        span.setAttribute(key: MiddlewareConstants.Attributes.SESSION_ID, value: getRumSessionId())
        span.setAttribute(key: MiddlewareConstants.Attributes.RUM_SDK_VERSION, value: MiddlewareConstants.Global.VERSION_STRING)
        span.setAttribute(key: MiddlewareConstants.Attributes.DEVICE_MODEL_NAME, value: deviceModel)
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
