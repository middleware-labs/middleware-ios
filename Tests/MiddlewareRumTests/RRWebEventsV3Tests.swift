import XCTest
@testable import MiddlewareRum

/// Golden-shape tests for the rrweb events emitted by v3 session recording.
/// These payloads are consumed by the standard rrweb player in bifrost and
/// must stay identical to the Android SDK's output — wire-contract tests.
final class RRWebEventsV3Tests: XCTestCase {

    func testMetaEventShape() throws {
        let event = RRWebEvents.meta(href: "ios-app://io.test/Main", width: 393, height: 852, timestampMs: 1750000000000)
        XCTAssertEqual(event.type, 4)
        XCTAssertEqual(event.timestampMs, 1750000000000)
        XCTAssertTrue(event.isKeyframe)
        XCTAssertEqual(event.data["href"] as? String, "ios-app://io.test/Main")
        XCTAssertEqual(event.data["width"] as? Int, 393)
        XCTAssertEqual(event.data["height"] as? Int, 852)
    }

    func testFullSnapshotShape() throws {
        let event = RRWebEvents.fullSnapshot(frameDataUri: "data:image/jpeg;base64,AAAA", width: 393, height: 852, timestampMs: 1)
        XCTAssertEqual(event.type, 2)
        XCTAssertTrue(event.isKeyframe)

        let node = try XCTUnwrap(event.data["node"] as? [String: Any])
        XCTAssertEqual(node["type"] as? Int, 0)
        XCTAssertEqual(node["id"] as? Int, 1)

        let children = try XCTUnwrap(node["childNodes"] as? [[String: Any]])
        XCTAssertEqual(children.count, 2)

        let doctype = children[0]
        XCTAssertEqual(doctype["type"] as? Int, 1)
        XCTAssertEqual(doctype["id"] as? Int, 2)
        XCTAssertEqual(doctype["name"] as? String, "html")
        XCTAssertEqual(doctype["publicId"] as? String, "")
        XCTAssertEqual(doctype["systemId"] as? String, "")

        let html = children[1]
        XCTAssertEqual(html["tagName"] as? String, "html")
        XCTAssertEqual(html["id"] as? Int, 3)
        let htmlChildren = try XCTUnwrap(html["childNodes"] as? [[String: Any]])
        XCTAssertEqual(htmlChildren[0]["tagName"] as? String, "head")
        XCTAssertEqual(htmlChildren[0]["id"] as? Int, 4)

        let body = htmlChildren[1]
        XCTAssertEqual(body["tagName"] as? String, "body")
        XCTAssertEqual(body["id"] as? Int, 5)
        let bodyAttrs = try XCTUnwrap(body["attributes"] as? [String: Any])
        XCTAssertEqual(bodyAttrs["style"] as? String, "margin:0;padding:0;background:#000;overflow:hidden;")

        let img = try XCTUnwrap((body["childNodes"] as? [[String: Any]])?.first)
        XCTAssertEqual(img["tagName"] as? String, "img")
        XCTAssertEqual(img["id"] as? Int, 6)
        let imgAttrs = try XCTUnwrap(img["attributes"] as? [String: Any])
        XCTAssertEqual(imgAttrs["id"] as? String, "mw-screen")
        XCTAssertEqual(imgAttrs["src"] as? String, "data:image/jpeg;base64,AAAA")
        XCTAssertEqual(imgAttrs["style"] as? String, "width:393px;height:852px;display:block;")

        let offset = try XCTUnwrap(event.data["initialOffset"] as? [String: Any])
        XCTAssertEqual(offset["left"] as? Int, 0)
        XCTAssertEqual(offset["top"] as? Int, 0)

        XCTAssertTrue(JSONSerialization.isValidJSONObject(event.data))
    }

    func testFrameMutationShape() throws {
        let event = RRWebEvents.frameMutation(frameDataUri: "data:image/jpeg;base64,BBBB", timestampMs: 2)
        XCTAssertEqual(event.type, 3)
        XCTAssertFalse(event.isKeyframe)
        XCTAssertEqual(event.data["source"] as? Int, 0)
        XCTAssertEqual((event.data["texts"] as? [Any])?.count, 0)
        XCTAssertEqual((event.data["removes"] as? [Any])?.count, 0)
        XCTAssertEqual((event.data["adds"] as? [Any])?.count, 0)

        let attributes = try XCTUnwrap(event.data["attributes"] as? [[String: Any]])
        XCTAssertEqual(attributes.count, 1)
        XCTAssertEqual(attributes[0]["id"] as? Int, 6)
        let srcAttrs = try XCTUnwrap(attributes[0]["attributes"] as? [String: Any])
        XCTAssertEqual(srcAttrs["src"] as? String, "data:image/jpeg;base64,BBBB")

        XCTAssertTrue(JSONSerialization.isValidJSONObject(event.data))
    }

    func testTouchEventShape() throws {
        let event = RRWebEvents.touch(interactionType: RRWebEvents.mouseInteractionTouchStart, x: 210, y: 480, timestampMs: 3)
        XCTAssertEqual(event.type, 3)
        XCTAssertEqual(event.data["source"] as? Int, 2)
        XCTAssertEqual(event.data["type"] as? Int, 7)
        XCTAssertEqual(event.data["id"] as? Int, 6)
        XCTAssertEqual(event.data["x"] as? Int, 210)
        XCTAssertEqual(event.data["y"] as? Int, 480)
        XCTAssertEqual(event.data["pointerType"] as? Int, 2)
    }

    func testScreenCustomEventShape() throws {
        let event = RRWebEvents.screenCustom(screenName: "CheckoutView", timestampMs: 4)
        XCTAssertEqual(event.type, 5)
        XCTAssertEqual(event.data["tag"] as? String, "screen")
        let payload = try XCTUnwrap(event.data["payload"] as? [String: Any])
        XCTAssertEqual(payload["name"] as? String, "CheckoutView")
    }
}
