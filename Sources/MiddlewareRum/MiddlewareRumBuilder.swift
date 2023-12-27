// Copyright © 2023 Middleware. Licensed under the Apache License, Version 2.0

import Foundation

@objc public class MiddlewareRumBuilder: NSObject {
    public var target: String?
    public var serviceName: String?
    public var projectName: String?
    public var rumAccessToken: String?
    public var deploymentEnvironment: String?
    public var globalAttributes: [String: Any]? = [:]
    public var slowFrameDetectionThresholdMs: Double = 16.7
    public var frozenFrameDetectionThresholdMs: Double = 700
    public var sessionSamplingRatio: Double = 1.0
    private var configFlags: ConfigFlags
    
    @objc public override init () {
        configFlags = ConfigFlags()
    }
    
    @objc public func target(_ target: String) -> MiddlewareRumBuilder {
        self.target = target
        return self
    }
    
    @objc public func serviceName(_ serviceName: String) -> MiddlewareRumBuilder {
        self.serviceName = serviceName
        return self
    }
    
    @objc public func projectName(_ projectName: String) -> MiddlewareRumBuilder {
        self.projectName = projectName
        return self
    }
    
    @objc public func rumAccessToken(_ rumAccessToken: String) -> MiddlewareRumBuilder {
        self.rumAccessToken = rumAccessToken
        return self
    }
    
    @objc public func deploymentEnvironment(_ deploymentEnvironment: String) -> MiddlewareRumBuilder {
        self.deploymentEnvironment = deploymentEnvironment
        return self
    }
    
    @objc public func globalAttributes(_ globalAttributes: [String: Any]) -> MiddlewareRumBuilder {
        self.globalAttributes = globalAttributes
        return self
    }
    
    @objc public func slowFrameDetectionThresholdMs(thresholdMs: Double) -> MiddlewareRumBuilder {
        self.slowFrameDetectionThresholdMs = thresholdMs
        return self
    }
    
    @objc public func frozenFrameDetectionThresholdMs(thresholdMs: Double) -> MiddlewareRumBuilder {
        self.frozenFrameDetectionThresholdMs = thresholdMs
        return self
    }
    
    @objc public func sessionSamplingRatio(samplingRatio: Double) -> MiddlewareRumBuilder {
        self.sessionSamplingRatio = samplingRatio
        return self
    }
    
    @objc public func disableNetworkMonitoring() -> MiddlewareRumBuilder {
        configFlags.disableNetworkMonitoring();
        return self
    }
    
    @objc public func isNetworkMonitoringEnabled() -> Bool {
        return configFlags.isNetworkMonitoringEnabled()
    }
    
    @objc public func disableSlowRenderingDetection() -> MiddlewareRumBuilder {
        configFlags.disableSlowRenderingDetection()
        return self
    }
    
    @objc public func isSlowRenderingDetectionEnabled() -> Bool {
        return configFlags.isSlowRenderingEnabled()
    }
    
    @objc public func disableAppLifcycleInstrumentation() -> MiddlewareRumBuilder {
        configFlags.disableAppLifecycleInstrumentation()
        return self
    }
    
    @objc public func disableCrashReportingInstrumentation() -> MiddlewareRumBuilder {
        configFlags.disableCrashReporting()
        return self
    }
    
    @objc public func isAppLifecycleInstrumentationEnabled() -> Bool {
        return configFlags.isAppLifecycleInstrumentationEnabled()
    }
    
    @objc public func isUiInstrumentationEnabled() -> Bool {
        return configFlags.isUiInsrumentationEnabled()
    }
    
    @objc public func isCrashReportingEnabled() -> Bool {
        return configFlags.isCrashReportingEnabled()
    }
    
    @objc public func build() -> Bool {
        if(rumAccessToken == nil || target == nil || projectName == nil || serviceName == nil) {
            print("Middleware: You must provide a rumAccessToken, target, projectName and serviceName to create a valid Config instance.")
            return false
            
        }
        return MiddlewareRum.create(builder: self)
    }
}
