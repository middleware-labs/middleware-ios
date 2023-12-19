// Copyright © 2023 Middleware. Licensed under the Apache License, Version 2.0

import Foundation

public class MiddlewareRumBuilder: NSObject {
    public var target: String?
    public var serviceName: String?
    public var projectName: String?
    public var rumAccessToken: String?
    public var deploymentEnvironment: String?
    public var globalAttributes: [String: Any]? = [:]
    private var configFlags: ConfigFlags
    public var slowFrameDetectionThresholdMs: Double = 16.7
    public var frozenFrameDetectionThresholdMs: Double = 700
    
    public override init () {
        configFlags = ConfigFlags()
    }
    
    public func target(_ target: String) -> MiddlewareRumBuilder {
        self.target = target
        return self
    }
    
    public func serviceName(_ serviceName: String) -> MiddlewareRumBuilder {
        self.serviceName = serviceName
        return self
    }
    
    public func projectName(_ projectName: String) -> MiddlewareRumBuilder {
        self.projectName = projectName
        return self
    }
    
    public func rumAccessToken(_ rumAccessToken: String) -> MiddlewareRumBuilder {
        self.rumAccessToken = rumAccessToken
        return self
    }
    
    public func deploymentEnvironment(_ deploymentEnvironment: String) -> MiddlewareRumBuilder {
        self.deploymentEnvironment = deploymentEnvironment
        return self
    }
    
    public func globalAttributes(_ globalAttributes: [String: Any]) -> MiddlewareRumBuilder {
        self.globalAttributes = globalAttributes
        return self
    }
    
    public func slowFrameDetectionThresholdMs(thresholdMs: Double) -> MiddlewareRumBuilder {
        self.slowFrameDetectionThresholdMs = thresholdMs
        return self
    }
    
    public func frozenFrameDetectionThresholdMs(thresholdMs: Double) -> MiddlewareRumBuilder {
        self.frozenFrameDetectionThresholdMs = thresholdMs
        return self
    }
    
    public func disableNetworkMonitoring() -> MiddlewareRumBuilder {
        configFlags.disableNetworkMonitoring();
        return self
    }
    
    public func isNetworkMonitoringEnabled() -> Bool {
        return configFlags.isNetworkMonitoringEnabled()
    }
    
    public func disableSlowRenderingDetection() -> MiddlewareRumBuilder {
        configFlags.disableSlowRenderingDetection()
        return self
    }
    
    public func isSlowRenderingDetectionEnabled() -> Bool {
        return configFlags.isSlowRenderingEnabled()
    }
    
    public func build() throws -> MiddlewareRum {
        if(rumAccessToken == nil || target == nil || projectName == nil || serviceName == nil) {
            throw MiddlewareError.invalidConfiguration(message: "Middleware: You must provide a rumAccessToken, target, projectName and serviceName to create a valid Config instance.")
            
        }
        return MiddlewareRum.create(builder: self)
    }
    
}
