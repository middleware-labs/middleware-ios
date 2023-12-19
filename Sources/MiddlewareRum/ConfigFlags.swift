// Copyright © 2023 Middleware. Licensed under the Apache License, Version 2.0

import Foundation

class ConfigFlags {
    var debugEnabled: Bool = false
    var networkMonitorEnabled: Bool = true
    var slowRenderingDetectionEnabled: Bool = true
    var appLifecycleInstumentationEnabled: Bool = true
    
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
    
    func isSlowRenderingEnabled()  -> Bool {
        return slowRenderingDetectionEnabled
    }
    
    func isNetworkMonitoringEnabled() -> Bool{
        return networkMonitorEnabled
    }
    
    func isAppLifecycleInstrumentationEnabled() -> Bool {
        return appLifecycleInstumentationEnabled
    }
    
}
