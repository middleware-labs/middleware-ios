// Copyright © 2023 Middleware. Licensed under the Apache License, Version 2.0

import Foundation

fileprivate var screenName: String = "unknown"
fileprivate var screenNameManuallySet = false
fileprivate var lock = NSLock()
fileprivate var screenNameCallbacks: [((String) -> Void)] = []

class ScreenName {
    
    // This method should be only called from main thread.
    func setScreenName(_ newName: String, _ manual: Bool) {
        var callbacks: [((String) -> Void)] = []
        lock.lock()
        
        if manual {
            screenNameManuallySet = true
        }
    
        if manual || !screenNameManuallySet {
            screenName = newName
        }
        callbacks = screenNameCallbacks
        lock.unlock()
        
        for callback in callbacks {
            callback(screenName)
        }
    }
    
    func isScreenNameManuallySet() -> Bool {
        lock.lock()
        defer {
            lock.unlock()
        }
        return screenNameManuallySet
    }
    func getScreenName() -> String {
        lock.lock()
        defer {
            lock.unlock()
        }
        return screenName
    }
    
    func addScreenNameCallback(_ callback: @escaping ((String) -> Void)) {
        lock.lock()
        defer {
            lock.unlock()
        }
        screenNameCallbacks.append(callback)
    }
}
