// Copyright © 2023 Middleware. Licensed under the Apache License, Version 2.0

#if os(iOS) || targetEnvironment(macCatalyst) || os(tvOS)
import UIKit

/// Observes touch begin/end for the replay's touch indicators by swizzling
/// `UIApplication.sendEvent(_:)`. Distinct from UIInstrumentation's
/// `sendAction(_:to:from:for:)` swizzle — no interaction between the two.
///
/// Installed once per process; start/stop cycles toggle `isEnabled`.
class TouchTracker {
    static let shared = TouchTracker()

    /// interactionType is an rrweb MouseInteraction value (7 TouchStart /
    /// 9 TouchEnd); coordinates are window points. May be invoked on main —
    /// receivers must hop off-main for heavy work.
    var onTouch: ((_ interactionType: Int, _ x: CGFloat, _ y: CGFloat, _ timestampMs: Int64) -> Void)?

    /// Fired once per completed tap (`.ended` within the touch slop of the `.began`
    /// position — i.e. not a scroll/drag), carrying the window-point location and the
    /// window itself so the receiver can hit-test for the tapped view. Powers the click
    /// heatmap. Invoked synchronously on the main thread inside `sendEvent`, so the
    /// receiver may hit-test immediately (before UITouch data is recycled).
    var onTap: ((_ location: CGPoint, _ window: UIWindow, _ timestampMs: Int64) -> Void)?

    private(set) var isEnabled = false
    private(set) var isTapCaptureEnabled = false

    /// Down positions keyed by touch identity, used to reject scrolls/drags as taps.
    private var touchDownLocations: [ObjectIdentifier: CGPoint] = [:]
    private static let tapSlop: CGFloat = 10.0

    private static var hasSwizzled = false

    private init() {}

    func enable() {
        Self.installSwizzleIfNeeded()
        isEnabled = true
    }

    func disable() {
        isEnabled = false
    }

    /// Enables independent tap capture for the heatmap. Shares the single
    /// `sendEvent` swizzle with replay's touch indicators.
    func enableTapCapture() {
        Self.installSwizzleIfNeeded()
        isTapCaptureEnabled = true
    }

    func disableTapCapture() {
        isTapCaptureEnabled = false
        touchDownLocations.removeAll()
    }

    private static func installSwizzleIfNeeded() {
        guard !hasSwizzled else { return }
        hasSwizzled = true
        Swizzling.swizzle(
            cls: UIApplication.self,
            original: #selector(UIApplication.sendEvent(_:)),
            swizzled: #selector(UIApplication.mw_replaySendEvent(_:)))
    }

    /// Called from the swizzled sendEvent on the main thread. UITouch data is
    /// zeroed once the event is recycled, so phase + location must be read
    /// synchronously here, before any dispatch.
    fileprivate func handleEvent(_ event: UIEvent) {
        guard isEnabled || isTapCaptureEnabled, event.type == .touches else { return }
        guard let window = ViewLayoutObserver.keyWindow(),
              let touches = event.touches(for: window) else { return }
        let timestampMs = Int64(Date().timeIntervalSince1970 * 1000)
        for touch in touches {
            let location = touch.location(in: window)
            // zero coords are a known symptom of stale touches — drop them
            let isStale = location == .zero

            switch touch.phase {
            case .began:
                if !isStale, isEnabled, let onTouch = onTouch {
                    onTouch(RRWebEvents.mouseInteractionTouchStart, location.x, location.y, timestampMs)
                }
                if isTapCaptureEnabled {
                    touchDownLocations[ObjectIdentifier(touch)] = location
                }
            case .ended:
                if !isStale, isEnabled, let onTouch = onTouch {
                    onTouch(RRWebEvents.mouseInteractionTouchEnd, location.x, location.y, timestampMs)
                }
                if isTapCaptureEnabled, let onTap = onTap {
                    let down = touchDownLocations.removeValue(forKey: ObjectIdentifier(touch))
                    // Treat as a tap only if the finger barely moved (not a scroll/drag).
                    let moved = down.map { hypot(location.x - $0.x, location.y - $0.y) } ?? 0
                    if !isStale && moved <= Self.tapSlop {
                        onTap(location, window, timestampMs)
                    }
                }
            case .cancelled:
                if isTapCaptureEnabled {
                    touchDownLocations.removeValue(forKey: ObjectIdentifier(touch))
                }
            default:
                continue
            }
        }
    }
}

extension UIApplication {
    @objc func mw_replaySendEvent(_ event: UIEvent) {
        // calls the original implementation (methods are exchanged)
        mw_replaySendEvent(event)
        TouchTracker.shared.handleEvent(event)
    }
}
#endif
