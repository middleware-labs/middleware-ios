// Copyright © 2023 Middleware. Licensed under the Apache License, Version 2.0

import Foundation

class ConfigFlags {
    var debugEnabled: Bool = false
    var networkMonitorEnabled: Bool = true
    var slowRenderingDetectionEnabled: Bool = true
    var appLifecycleInstumentationEnabled: Bool = true
    var crashReportingEnabled: Bool = true
    var uiInstrumentationEnabled: Bool = true
    var recordingEnabled: Bool = true
    var networkHeadersCaptureEnabled: Bool = false
    var responseBodyCaptureEnabled: Bool = false

    init () {}
    
    func disableNetworkMonitoring() {
        self.networkMonitorEnabled = false
    }
    
    func enableDebug() {
        self.debugEnabled = false
    }
    
    func disableSlowRenderingDetection() {
        self.slowRenderingDetectionEnabled = false
    }
    
    func disableAppLifecycleInstrumentation() {
        self.appLifecycleInstumentationEnabled = false
    }
    
    func disableCrashReporting(){
        self.crashReportingEnabled = false
    }
    
    func disableUiInsrumentation() {
        self.uiInstrumentationEnabled = false
    }
    
    func disableRecording() {
        self.recordingEnabled = false
    }
    
    func enableRecording() {
        self.recordingEnabled = true
    }

    func setNetworkHeadersCapture(_ enabled: Bool) {
        self.networkHeadersCaptureEnabled = enabled
    }

    func setResponseBodyCapture(_ enabled: Bool) {
        self.responseBodyCaptureEnabled = enabled
    }

    func isNetworkHeadersCaptureEnabled() -> Bool {
        return networkHeadersCaptureEnabled
    }

    func isResponseBodyCaptureEnabled() -> Bool {
        return responseBodyCaptureEnabled
    }

    func isRecordingEnabled() -> Bool {
        return self.recordingEnabled
    }

    func isSlowRenderingEnabled()  -> Bool {
        return slowRenderingDetectionEnabled
    }
    
    func isNetworkMonitoringEnabled() -> Bool{
        return networkMonitorEnabled
    }
    
    func isAppLifecycleInstrumentationEnabled() -> Bool {
        return appLifecycleInstumentationEnabled
    }
    
    func isCrashReportingEnabled() -> Bool {
        return crashReportingEnabled
    }
    func isUiInsrumentationEnabled() -> Bool {
        return uiInstrumentationEnabled
    }
}
