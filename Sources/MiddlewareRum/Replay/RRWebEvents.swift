// Copyright © 2023 Middleware. Licensed under the Apache License, Version 2.0

import Foundation

/// A single rrweb event of the v3 session recording stream.
struct RRWebEvent {
    let type: Int
    let timestampMs: Int64
    let data: [String: Any]

    /// Meta and FullSnapshot events must never be evicted from the export
    /// buffer — the frames that follow them are unplayable without them.
    var isKeyframe: Bool {
        type == RRWebEvents.typeFullSnapshot || type == RRWebEvents.typeMeta
    }
}

/// Factory for the rrweb events emitted by v3 session recording.
///
/// The recording is screenshot-based: the replayed "DOM" is a fixed six-node
/// document whose only visible element is a full-viewport `<img>`; every new
/// frame is an attribute mutation swapping that image's `src`. The shapes are
/// identical to the Android SDK's `RRWebEvents.kt` — this is a wire contract
/// consumed by the standard rrweb player, do not change casually.
///
/// All coordinates and sizes are in points (equivalent to Android dp),
/// all timestamps epoch milliseconds.
enum RRWebEvents {

    // rrweb event types
    static let typeFullSnapshot = 2
    static let typeIncrementalSnapshot = 3
    static let typeMeta = 4
    static let typeCustom = 5

    // rrweb incremental sources
    static let sourceMutation = 0
    static let sourceMouseInteraction = 2

    // rrweb mouse interaction types
    static let mouseInteractionTouchStart = 7
    static let mouseInteractionTouchEnd = 9

    // rrweb serialized node types
    private static let nodeDocument = 0
    private static let nodeDocumentType = 1
    private static let nodeElement = 2

    // Fixed node ids of the synthetic document
    private static let nodeIdDocument = 1
    private static let nodeIdDoctype = 2
    private static let nodeIdHtml = 3
    private static let nodeIdHead = 4
    private static let nodeIdBody = 5
    static let nodeIdScreen = 6

    private static let pointerTypeTouch = 2

    static func meta(href: String, width: Int, height: Int, timestampMs: Int64) -> RRWebEvent {
        return RRWebEvent(
            type: typeMeta,
            timestampMs: timestampMs,
            data: [
                "href": href,
                "width": width,
                "height": height,
            ]
        )
    }

    static func fullSnapshot(frameDataUri: String, width: Int, height: Int, timestampMs: Int64) -> RRWebEvent {
        let img = element(
            id: nodeIdScreen, tagName: "img",
            attributes: [
                "id": "mw-screen",
                "src": frameDataUri,
                "style": "width:\(width)px;height:\(height)px;display:block;",
            ]
        )
        let head = element(id: nodeIdHead, tagName: "head", attributes: [:])
        let body = element(
            id: nodeIdBody, tagName: "body",
            attributes: ["style": "margin:0;padding:0;background:#000;overflow:hidden;"],
            childNodes: [img]
        )
        let html = element(id: nodeIdHtml, tagName: "html", attributes: [:], childNodes: [head, body])
        let doctype: [String: Any] = [
            "type": nodeDocumentType,
            "id": nodeIdDoctype,
            "name": "html",
            "publicId": "",
            "systemId": "",
        ]
        let document: [String: Any] = [
            "type": nodeDocument,
            "id": nodeIdDocument,
            "childNodes": [doctype, html],
        ]
        return RRWebEvent(
            type: typeFullSnapshot,
            timestampMs: timestampMs,
            data: [
                "node": document,
                "initialOffset": ["left": 0, "top": 0],
            ]
        )
    }

    static func frameMutation(frameDataUri: String, timestampMs: Int64) -> RRWebEvent {
        return RRWebEvent(
            type: typeIncrementalSnapshot,
            timestampMs: timestampMs,
            data: [
                "source": sourceMutation,
                "texts": [Any](),
                "removes": [Any](),
                "adds": [Any](),
                "attributes": [
                    [
                        "id": nodeIdScreen,
                        "attributes": ["src": frameDataUri],
                    ] as [String: Any],
                ],
            ]
        )
    }

    static func touch(interactionType: Int, x: Int, y: Int, timestampMs: Int64) -> RRWebEvent {
        return RRWebEvent(
            type: typeIncrementalSnapshot,
            timestampMs: timestampMs,
            data: [
                "source": sourceMouseInteraction,
                "type": interactionType,
                "id": nodeIdScreen,
                "x": x,
                "y": y,
                "pointerType": pointerTypeTouch,
            ]
        )
    }

    static func screenCustom(screenName: String, timestampMs: Int64) -> RRWebEvent {
        return RRWebEvent(
            type: typeCustom,
            timestampMs: timestampMs,
            data: [
                "tag": "screen",
                "payload": ["name": screenName],
            ]
        )
    }

    private static func element(
        id: Int,
        tagName: String,
        attributes: [String: Any],
        childNodes: [Any] = []
    ) -> [String: Any] {
        return [
            "type": nodeElement,
            "id": id,
            "tagName": tagName,
            "attributes": attributes,
            "childNodes": childNodes,
        ]
    }
}
