// Copyright © 2023 Middleware. Licensed under the Apache License, Version 2.0

#if os(iOS) || targetEnvironment(macCatalyst) || os(tvOS)
import UIKit

/// v3 session recorder: captures throttled, masked screenshots of the key
/// window on every layout pass and emits them as rrweb events (Meta +
/// FullSnapshot per epoch, img-src mutations per frame, MouseInteraction per
/// touch) through `RRWebExporterV3` to the metrics endpoint.
///
/// An "epoch" — Meta + FullSnapshot pair — restarts when the recorder starts,
/// the session id rotates, the viewport size changes (rotation/resize), or the
/// app returns to the foreground.
class ReplayRecorderV3 {
    static let shared = ReplayRecorderV3()

    private let processQueue = DispatchQueue(label: "io.middleware.replay.v3.process", qos: .utility)
    private var capturer = ScreenshotCapturerV3()
    private var maskCollector = MaskRectCollector()

    private var exporter: RRWebExporterV3?
    private var sanitizedElements: [Sanitizable] = []
    private let sanitizedLock = NSLock()

    private(set) var isRunning = false
    private var captureInFlight = false

    // Epoch state — mutated on the main thread (captureFrame) and the process
    // queue (processFrame); each field is only written by one side at a time
    // thanks to the captureInFlight gate.
    private var sentMeta = false
    private var lastMetaWidth = -1
    private var lastMetaHeight = -1
    private var lastFrameHash = 0
    private var lastSessionId = ""
    private var lastScreenName: String?

    private var lifecycleObservers: [NSObjectProtocol] = []
    private var sessionCallbackRegistered = false

    private init() {}

    // MARK: - Lifecycle

    /// Called from syncSessionRecordingWithSampler (main thread or timer).
    func start(target: String, token: String, options: RecordingOptions = RecordingOptions()) {
        guard !isRunning else { return }
        isRunning = true
        resetEpoch()

        capturer = ScreenshotCapturerV3(jpegQuality: options.jpegQuality)
        maskCollector = MaskRectCollector(
            maskAllTextInputs: options.maskAllTextInputs,
            maskAllImages: options.maskAllImages)
        ViewLayoutObserver.shared.throttleInterval = options.frequency.intervalSeconds

        exporter = RRWebExporterV3(
            target: target,
            token: token,
            resourceAttributesProvider: { sessionId in
                ReplayRecorderV3.resourceAttributes(sessionId: sessionId)
            })

        ViewLayoutObserver.shared.onLayout = { [weak self] in
            self?.captureFrame()
        }
        ViewLayoutObserver.shared.enable()

        TouchTracker.shared.onTouch = { [weak self] interactionType, x, y, timestampMs in
            self?.handleTouch(interactionType: interactionType, x: x, y: y, timestampMs: timestampMs)
        }
        TouchTracker.shared.enable()

        if !sessionCallbackRegistered {
            sessionCallbackRegistered = true
            addSessionIdCallback { [weak self] in
                DispatchQueue.main.async {
                    self?.resetEpoch()
                }
            }
        }

        let center = NotificationCenter.default
        lifecycleObservers.append(center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            // get buffered events out while the process is alive
            self?.exporter?.flush()
        })
        lifecycleObservers.append(center.addObserver(
            forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.resetEpoch()
            self?.captureFrame()
        })

        DispatchQueue.main.async { [weak self] in
            self?.captureFrame()
        }
        Log.debug("Replay v3 recording started")
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        ViewLayoutObserver.shared.disable()
        TouchTracker.shared.disable()
        for observer in lifecycleObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        lifecycleObservers.removeAll()
        exporter?.flush()
        exporter?.shutdown()
        exporter = nil
        Log.debug("Replay v3 recording stopped")
    }

    // MARK: - Sanitized elements (legacy masking API compatibility)

    func addSanitizedElement(_ element: Sanitizable) {
        sanitizedLock.lock()
        sanitizedElements.append(element)
        sanitizedLock.unlock()
    }

    func removeSanitizedElement(_ element: Sanitizable) {
        sanitizedLock.lock()
        sanitizedElements.removeAll { $0 as AnyObject === element as AnyObject }
        sanitizedLock.unlock()
    }

    // MARK: - Frame capture (main thread)

    private func captureFrame() {
        guard isRunning, Thread.isMainThread else { return }
        guard !captureInFlight else { return }
        guard let window = ViewLayoutObserver.keyWindow(),
              window.bounds.width > 0, window.bounds.height > 0 else { return }
        if isAnimatingTransition(window) {
            return // avoid black/torn frames mid-transition
        }
        let sessionId = getRumSessionId()
        guard !sessionId.isEmpty else { return }
        if sessionId != lastSessionId {
            resetEpoch()
            lastSessionId = sessionId
        }

        let width = Int(window.bounds.width)
        let height = Int(window.bounds.height)
        let needsMeta = !sentMeta || width != lastMetaWidth || height != lastMetaHeight
        let screenName = getScreenName()
        let href = "ios-app://\(Bundle.main.bundleIdentifier ?? "unknown")/\(screenName)"

        sanitizedLock.lock()
        let sanitized = sanitizedElements
        sanitizedLock.unlock()

        captureInFlight = true
        let maskRects = maskCollector.collect(in: window, sanitized: sanitized)
        guard let image = capturer.captureMaskedImage(window: window, maskRects: maskRects) else {
            captureInFlight = false
            return
        }

        processQueue.async { [weak self] in
            guard let self = self else { return }
            autoreleasepool {
                self.processFrame(
                    image: image,
                    needsMeta: needsMeta,
                    width: width,
                    height: height,
                    href: href,
                    screenName: screenName,
                    sessionId: sessionId)
            }
            self.captureInFlight = false
        }
    }

    /// Runs on the process queue.
    private func processFrame(
        image: UIImage,
        needsMeta: Bool,
        width: Int,
        height: Int,
        href: String,
        screenName: String,
        sessionId: String
    ) {
        guard isRunning, let exporter = exporter else { return }
        guard let dataUri = capturer.encodeDataUri(image) else { return }

        let frameHash = dataUri.hashValue
        if !needsMeta && frameHash == lastFrameHash {
            return // identical frame, nothing to ship
        }

        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        if needsMeta {
            exporter.enqueue(RRWebEvents.meta(href: href, width: width, height: height, timestampMs: timestamp), sessionId: sessionId)
            exporter.enqueue(RRWebEvents.fullSnapshot(frameDataUri: dataUri, width: width, height: height, timestampMs: timestamp), sessionId: sessionId)
            sentMeta = true
            lastMetaWidth = width
            lastMetaHeight = height
        } else {
            exporter.enqueue(RRWebEvents.frameMutation(frameDataUri: dataUri, timestampMs: timestamp), sessionId: sessionId)
        }
        lastFrameHash = frameHash

        if screenName != lastScreenName {
            lastScreenName = screenName
            exporter.enqueue(RRWebEvents.screenCustom(screenName: screenName, timestampMs: timestamp), sessionId: sessionId)
        }
    }

    // MARK: - Touch capture

    private func handleTouch(interactionType: Int, x: CGFloat, y: CGFloat, timestampMs: Int64) {
        guard isRunning, sentMeta else {
            return // touches before the first FullSnapshot are unplayable
        }
        let sessionId = lastSessionId
        guard !sessionId.isEmpty else { return }
        let event = RRWebEvents.touch(
            interactionType: interactionType,
            x: Int(x),
            y: Int(y),
            timestampMs: timestampMs)
        processQueue.async { [weak self] in
            self?.exporter?.enqueue(event, sessionId: sessionId)
        }
    }

    // MARK: - Helpers

    private func resetEpoch() {
        sentMeta = false
        lastMetaWidth = -1
        lastMetaHeight = -1
        lastFrameHash = 0
        lastScreenName = nil
    }

    /// Skip captures while any view controller in the hierarchy is animating a
    /// transition — drawHierarchy renders black/torn frames mid-animation.
    private func isAnimatingTransition(_ window: UIWindow) -> Bool {
        var controller = window.rootViewController
        while let current = controller {
            if current.transitionCoordinator?.isAnimated == true {
                return true
            }
            if let presented = current.presentedViewController {
                controller = presented
            } else if let navigation = current as? UINavigationController {
                controller = navigation.topViewController
            } else if let tabs = current as? UITabBarController {
                controller = tabs.selectedViewController
            } else {
                controller = nil
            }
        }
        return false
    }

    /// Live resource attributes for a batch: the SDK resource (kept current on
    /// session rotation) plus the session id and origin markers.
    private static func resourceAttributes(sessionId: String) -> [String: String] {
        var attributes: [String: String] = [:]
        let resource = OpenTelemetry.instance.tracerProvider.getActiveResource()
        for (key, value) in resource.attributes {
            attributes[key] = value.description
        }
        attributes[MiddlewareConstants.Attributes.SESSION_ID] = sessionId
        attributes["mw.client_origin"] = "sdk.middleware.io"
        attributes["rum_origin"] = "sdk.middleware.io"
        attributes["origin"] = "sdk.middleware.io"
        return attributes
    }
}
#endif
