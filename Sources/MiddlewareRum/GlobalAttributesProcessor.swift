// Copyright © 2023 Middleware. Licensed under the Apache License, Version 2.0

import Foundation
import OpenTelemetrySdk
import OpenTelemetryApi
import UIKit
import DeviceKit

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
            self.appName = Constants.Global.UNKNOWN_APP_NAME
        }
        let bundleVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        let bundleShortVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        appVersion = bundleShortVersion ?? bundleVersion
        deviceModel = Device.current.description
    }
    
    func onStart(parentContext: OpenTelemetryApi.SpanContext?, span: OpenTelemetrySdk.ReadableSpan) {
        span.setAttribute(key: Constants.Attributes.APP, value: appName)
        if appVersion != nil {
            span.setAttribute(key: Constants.Attributes.APP_VERSION, value: appVersion!)
        }
        // glossing over iPadOS, watchOS, etc. here, knowing that the device model spells out reality
        span.setAttribute(key: Constants.Attributes.OS_NAME, value: "iOS")
        span.setAttribute(key: Constants.Attributes.SESSION_ID, value: getRumSessionId())
        span.setAttribute(key: Constants.Attributes.RUM_SDK_VERSION, value: Constants.Global.VERSION_STRING)
        span.setAttribute(key: Constants.Attributes.DEVICE_MODEL_NAME, value: deviceModel)
        span.setAttribute(key: Constants.Attributes.OS_VERSION, value: UIDevice.current.systemVersion)
        // It would be nice to drop this field when the span-ending thread isn't the same...
        if Thread.current.isMainThread {
            span.setAttribute(key: Constants.Attributes.THREAD_NAME, value: "main")
        } else if isUsefulString(Thread.current.name) {
            span.setAttribute(key: Constants.Attributes.THREAD_NAME, value: Thread.current.name!)
        }
        MiddlewareRum.addGlobalAttributesToSpan(span)
    }
    
    func onEnd(span: OpenTelemetrySdk.ReadableSpan) {}
    
    func shutdown(explicitTimeout: TimeInterval?) {}
    
    func forceFlush(timeout: TimeInterval?) {}
    
    
}
