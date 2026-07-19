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

    private(set) var isEnabled = false

    private static var hasSwizzled = false

    private init() {}

    func enable() {
        Self.installSwizzleIfNeeded()
        isEnabled = true
    }

    func disable() {
        isEnabled = false
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
        guard isEnabled, let onTouch = onTouch, event.type == .touches else { return }
        guard let window = ViewLayoutObserver.keyWindow(),
              let touches = event.touches(for: window) else { return }
        let timestampMs = Int64(Date().timeIntervalSince1970 * 1000)
        for touch in touches {
            let interactionType: Int
            switch touch.phase {
            case .began:
                interactionType = RRWebEvents.mouseInteractionTouchStart
            case .ended:
                interactionType = RRWebEvents.mouseInteractionTouchEnd
            default:
                continue
            }
            let location = touch.location(in: window)
            // zero coords are a known symptom of stale touches — drop them
            if location == .zero {
                continue
            }
            onTouch(interactionType, location.x, location.y, timestampMs)
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
