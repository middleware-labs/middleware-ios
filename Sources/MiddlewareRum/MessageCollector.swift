// Copyright © 2023 Middleware. Licensed under the Apache License, Version 2.0

#if os(iOS) || targetEnvironment(macCatalyst) || os(tvOS)
import UIKit

struct BatchArch {
    var name: String
    var data: Data
}

class MessageCollector: NSObject {
    private var imagesWaiting = [BatchArch]()
    private var imagesSending = [BatchArch]()
    private let messagesQueue = OperationQueue()
    private var target: String?
    private var token: String?
    private var sendInterval: Timer?
    
    
    init(target: String?, token: String?) {
        self.target = target
        self.token = token
    }
    
    func start() {
        sendInterval = Timer.scheduledTimer(withTimeInterval: 5, repeats: true, block: { [weak self] _ in
            self?.flush()
        })
        messagesQueue.maxConcurrentOperationCount = 1
    }
    
    func stop() {
        sendInterval?.invalidate()
        self.flush()
    }
    
    func sendImagesBatch(batch: Data, fileName: String) {
        self.imagesWaiting.append(BatchArch(name: fileName, data: batch))
        messagesQueue.addOperation {
            self.flushImages()
        }
    }
    
    @objc func flush() {
        messagesQueue.addOperation {
            self.flushImages()
        }
    }
    
    private func flushImages() {
        let images = imagesWaiting.first
        guard !imagesWaiting.isEmpty, let images = images else { return }
        imagesWaiting.remove(at: 0)
        
        imagesSending.append(images)
        
        Log.debug("Sending images \(images.name) \(images.data.count)")
        NetworkManager(target: self.target!, token: self.token!).sendImages(sessionId: getRumSessionId(), images: images.data, name: images.name) { (success) in
            self.imagesSending.removeAll { (waiting) -> Bool in
                images.name == waiting.name
            }
            guard success else {
                self.imagesWaiting.append(images)
                return
            }
        }
    }
}
#endif
