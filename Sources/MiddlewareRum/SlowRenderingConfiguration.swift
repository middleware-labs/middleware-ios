// Copyright © 2023 Middleware. Licensed under the Apache License, Version 2.0

import Foundation

public class SlowRenderingConfiguration {
    public var slowFrameThreshold: CFTimeInterval = 16.7
    public var frozenFrameThreshold: CFTimeInterval = 700
    
    public init () {}
    
    public init(slowFrameThreshold: CFTimeInterval, frozenFrameThreshold: CFTimeInterval) {
        self.slowFrameThreshold = slowFrameThreshold
        self.frozenFrameThreshold = frozenFrameThreshold
    }
}
