// Copyright © 2023 Middleware. Licensed under the Apache License, Version 2.0

import Foundation

public class MiddlewareRumBuilder: NSObject {
    public var target: String?
    public var serviceName: String?
    public var projectName: String?
    public var rumAccessToken: String?
    public var deploymentEnvironment: String?
    public var globalAttributes: [String: Any]? = [:]
    
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
    
    public func build() throws -> MiddlewareRum {
        if(rumAccessToken == nil || target == nil || projectName == nil || serviceName == nil) {
            throw MiddlewareError.invalidConfiguration(message: "Middleware: You must provide a rumAccessToken, target, projectName and serviceName to create a valid Config instance.")
            
        }
        return MiddlewareRum.create(builder: self)
    }
    
}
