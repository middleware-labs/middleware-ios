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
    /// Compiled `tracePropagationTargets`. `nil` means propagate to every URL, which is the
    /// default and matches the browser SDK; an empty array means propagate to none.
    public private(set) var tracePropagationTargets: [NSRegularExpression]?
    private var configFlags: ConfigFlags
#if os(iOS) || targetEnvironment(macCatalyst) || os(tvOS)
    public var recordingOptions = RecordingOptions()
#endif
    
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
    
    /// Restricts which outbound requests carry `traceparent`, so that backend correlation works
    /// for your own services without handing your trace ids to third parties.
    ///
    /// Each entry is a regular expression searched for anywhere in the request URL, so
    /// `"api.example.com"` matches `https://api.example.com/orders`. Requests to other hosts are
    /// still timed and still appear in the session; they just travel without trace headers.
    /// Patterns that fail to compile are ignored.
    ///
    /// Not calling this propagates to every URL. Passing an empty array disables propagation.
    @objc public func tracePropagationTargets(_ patterns: [String]) -> MiddlewareRumBuilder {
        self.tracePropagationTargets = patterns.compactMap { pattern in
            do {
                return try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            } catch {
                print("Middleware: ignoring invalid tracePropagationTargets pattern '\(pattern)'")
                return nil
            }
        }
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
    
    @objc public func disableUIInstrumentation() -> MiddlewareRumBuilder {
        configFlags.disableUiInsrumentation()
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
    
    @objc public func disableRecording() -> MiddlewareRumBuilder {
        configFlags.disableRecording()
        return self
    }
    
    @objc public func enableRecording() -> MiddlewareRumBuilder {
        configFlags.enableRecording()
        return self
    }
    
    @objc public func isRecordingEnabled() -> Bool {
        return configFlags.isRecordingEnabled()
    }

#if os(iOS) || targetEnvironment(macCatalyst) || os(tvOS)
    /// Sets the session recording options (frequency, image quality,
    /// masking toggles), mirroring the Android SDK's setRecordingOptions.
    @objc public func recordingOptions(_ options: RecordingOptions) -> MiddlewareRumBuilder {
        self.recordingOptions = options
        return self
    }
#endif

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

