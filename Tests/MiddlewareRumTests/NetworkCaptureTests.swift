import XCTest
@testable import MiddlewareRum

final class NetworkCaptureTests: XCTestCase {

    private let url = URL(string: "https://api.example.com/orders")!

    private func response(_ headers: [String: String], status: Int = 200) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
    }

    // MARK: Builder

    func testCaptureIsOffByDefault() {
        let builder = MiddlewareRumBuilder()
        XCTAssertFalse(builder.isNetworkHeadersCaptureEnabled())
        XCTAssertFalse(builder.isResponseBodyCaptureEnabled())
        XCTAssertEqual(builder.ignoredHeaders, [])
    }

    func testBuilderSetters() {
        let builder = MiddlewareRumBuilder()
            .captureNetworkHeaders(true)
            .captureResponseBodies(true)
            .ignoreHeaders(["Authorization", "Cookie"])
        XCTAssertTrue(builder.isNetworkHeadersCaptureEnabled())
        XCTAssertTrue(builder.isResponseBodyCaptureEnabled())
        XCTAssertEqual(builder.ignoredHeaders, ["Authorization", "Cookie"])

        _ = builder.captureNetworkHeaders(false).captureResponseBodies(false)
        XCTAssertFalse(builder.isNetworkHeadersCaptureEnabled())
        XCTAssertFalse(builder.isResponseBodyCaptureEnabled())
    }

    func testFlagsAreIndependent() {
        let headersOnly = MiddlewareRumBuilder().captureNetworkHeaders(true)
        XCTAssertTrue(headersOnly.isNetworkHeadersCaptureEnabled())
        XCTAssertFalse(headersOnly.isResponseBodyCaptureEnabled())

        let bodiesOnly = MiddlewareRumBuilder().captureResponseBodies(true)
        XCTAssertFalse(bodiesOnly.isNetworkHeadersCaptureEnabled())
        XCTAssertTrue(bodiesOnly.isResponseBodyCaptureEnabled())
    }

    // MARK: Header normalisation

    func testHeaderKeyNormalisation() {
        XCTAssertEqual(NetworkCapture.normalizeHeaderName("Content-Type"), "content_type")
        XCTAssertEqual(NetworkCapture.normalizeHeaderName("X-Request-ID"), "x_request_id")
        XCTAssertEqual(NetworkCapture.normalizeHeaderName("accept"), "accept")
    }

    func testRequestAndResponseHeaderKeys() {
        let capture = NetworkCapture(captureHeaders: true, captureResponseBodies: false)
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("abc", forHTTPHeaderField: "X-Request-Id")
        XCTAssertEqual(capture.requestHeaderAttributes(request), [
            "http.request.header.accept": "application/json",
            "http.request.header.x_request_id": "abc",
        ])

        let attrs = capture.responseHeaderAttributes(response(["Content-Type": "text/plain", "Cache-Control": "no-cache"]))
        XCTAssertEqual(attrs["http.response.header.content_type"], "text/plain")
        XCTAssertEqual(attrs["http.response.header.cache_control"], "no-cache")
    }

    func testCollidingNamesAreJoinedWithComma() {
        let capture = NetworkCapture(captureHeaders: true, captureResponseBodies: false)
        let attrs = capture.headerAttributes([(name: "X-Tag", value: "a"), (name: "x-tag", value: "b")],
                                             prefix: NetworkCapture.responseHeaderPrefix)
        XCTAssertEqual(attrs, ["http.response.header.x_tag": "a,b"])
    }

    func testIgnoreHeadersIsCaseInsensitive() {
        let capture = NetworkCapture(captureHeaders: true, captureResponseBodies: false,
                                     ignoredHeaders: ["AUTHORIZATION", "set-cookie"])
        var request = URLRequest(url: url)
        request.setValue("Bearer secret", forHTTPHeaderField: "Authorization")
        request.setValue("1", forHTTPHeaderField: "X-Keep")
        XCTAssertEqual(capture.requestHeaderAttributes(request), ["http.request.header.x_keep": "1"])

        let attrs = capture.responseHeaderAttributes(response(["Set-Cookie": "sid=1", "X-Keep": "1"]))
        XCTAssertNil(attrs["http.response.header.set_cookie"])
        XCTAssertEqual(attrs["http.response.header.x_keep"], "1")
    }

    func testAccessTokenIsMasked() {
        let capture = NetworkCapture(captureHeaders: true, captureResponseBodies: false)
        var request = URLRequest(url: url)
        request.setValue("super-secret", forHTTPHeaderField: "X-Access-Token")
        XCTAssertEqual(capture.requestHeaderAttributes(request)["http.request.header.x_access_token"], "********")

        let attrs = capture.responseHeaderAttributes(response(["x-access-token": "super-secret"]))
        XCTAssertEqual(attrs["http.response.header.x_access_token"], "********")
    }

    func testHeadersNotRecordedWhenDisabled() {
        let capture = NetworkCapture(captureHeaders: false, captureResponseBodies: true)
        var request = URLRequest(url: url)
        request.setValue("1", forHTTPHeaderField: "X-Keep")
        XCTAssertTrue(capture.requestHeaderAttributes(request).isEmpty)
        XCTAssertTrue(capture.responseHeaderAttributes(response(["X-Keep": "1"])).isEmpty)
    }

    // MARK: Content-type filter

    func testContentTypeFilter() {
        XCTAssertTrue(NetworkCapture.isCapturableContentType("application/json"))
        XCTAssertTrue(NetworkCapture.isCapturableContentType("Application/JSON; charset=utf-8"))
        XCTAssertTrue(NetworkCapture.isCapturableContentType(" application/problem+json "))
        XCTAssertTrue(NetworkCapture.isCapturableContentType("application/vnd.api+json;v=2"))
        XCTAssertTrue(NetworkCapture.isCapturableContentType("text/plain; charset=us-ascii"))

        XCTAssertFalse(NetworkCapture.isCapturableContentType(nil))
        XCTAssertFalse(NetworkCapture.isCapturableContentType(""))
        XCTAssertFalse(NetworkCapture.isCapturableContentType("text/html"))
        XCTAssertFalse(NetworkCapture.isCapturableContentType("image/png"))
        XCTAssertFalse(NetworkCapture.isCapturableContentType("application/octet-stream"))
        XCTAssertFalse(NetworkCapture.isCapturableContentType("application/jsonp"))
        XCTAssertFalse(NetworkCapture.isCapturableContentType("text/plain-ish"))
    }

    func testContentTypeHeaderLookupIsCaseInsensitive() {
        XCTAssertTrue(NetworkCapture.isCapturableResponse(response(["content-type": "application/json"])))
        XCTAssertFalse(NetworkCapture.isCapturableResponse(response([:])))
        XCTAssertFalse(NetworkCapture.isCapturableResponse(URLResponse(url: url, mimeType: "application/json",
                                                                      expectedContentLength: 2, textEncodingName: nil)))
    }

    // MARK: Body

    func testBodyCapturedForJsonOnly() {
        let capture = NetworkCapture(captureHeaders: false, captureResponseBodies: true)
        let body = Data("{\"ok\":true}".utf8)
        XCTAssertEqual(capture.responseBody(response: response(["Content-Type": "application/json"]), dataOrFile: body),
                       "{\"ok\":true}")
        XCTAssertNil(capture.responseBody(response: response(["Content-Type": "text/html"]), dataOrFile: body))
        XCTAssertNil(capture.responseBody(response: response([:]), dataOrFile: body))
    }

    func testBodySkippedWhenDisabledEmptyOrFile() {
        let json = response(["Content-Type": "application/json"])
        let off = NetworkCapture(captureHeaders: true, captureResponseBodies: false)
        XCTAssertNil(off.responseBody(response: json, dataOrFile: Data("{}".utf8)))

        let on = NetworkCapture(captureHeaders: false, captureResponseBodies: true)
        XCTAssertNil(on.responseBody(response: json, dataOrFile: Data()))
        XCTAssertNil(on.responseBody(response: json, dataOrFile: nil))
        XCTAssertNil(on.responseBody(response: json, dataOrFile: URL(fileURLWithPath: "/tmp/download.json")))
    }

    func testBodyCapAt64KiB() {
        XCTAssertEqual(NetworkCapture.maxResponseBodyBytes, 65536)

        let exact = Data(repeating: 0x61, count: 65536)
        XCTAssertEqual(NetworkCapture.truncatedBodyText(exact)?.utf8.count, 65536)

        let over = Data(repeating: 0x61, count: 100_000)
        XCTAssertEqual(NetworkCapture.truncatedBodyText(over)?.utf8.count, 65536)
    }

    func testBodyCapDoesNotSplitUtf8Scalar() {
        // 65535 ASCII bytes followed by a 3-byte "€": the cap falls inside the scalar, so it is
        // dropped whole rather than leaving a dangling lead byte.
        var data = Data(repeating: 0x61, count: 65535)
        data.append(contentsOf: Array("€".utf8))
        data.append(contentsOf: Array("tail".utf8))
        let text = NetworkCapture.truncatedBodyText(data)!
        XCTAssertEqual(text.utf8.count, 65535)
        XCTAssertFalse(text.contains("\u{FFFD}"))

        // 4-byte scalar straddling the cap.
        var emoji = Data(repeating: 0x61, count: 65534)
        emoji.append(contentsOf: Array("😀".utf8))
        let emojiText = NetworkCapture.truncatedBodyText(emoji)!
        XCTAssertEqual(emojiText.utf8.count, 65534)
        XCTAssertFalse(emojiText.contains("\u{FFFD}"))

        // A scalar that ends exactly at the cap is kept.
        var fits = Data(repeating: 0x61, count: 65533)
        fits.append(contentsOf: Array("€".utf8))
        fits.append(0x61)
        XCTAssertTrue(NetworkCapture.truncatedBodyText(fits)!.hasSuffix("€"))
    }

    func testInvalidUtf8IsDecodedLossily() {
        let text = NetworkCapture.truncatedBodyText(Data([0x6F, 0x6B, 0xFF, 0x21]))
        XCTAssertEqual(text, "ok\u{FFFD}!")
    }

    // MARK: Instrumentation wiring

    func testDefaultConfigurationHasNoCaptureHooks() {
        let config = MiddlewareRum.networkMonitoringConfiguration()
        XCTAssertNil(config.createdRequest)
        XCTAssertNil(config.receivedResponse)
        XCTAssertNil(config.shouldRecordPayload)
        XCTAssertNil(config.maxRecordedPayloadBytes)
        XCTAssertNil(config.shouldRecordPayloadForResponse)

        let bothOff = MiddlewareRum.networkMonitoringConfiguration(
            networkCapture: NetworkCapture(captureHeaders: false, captureResponseBodies: false, ignoredHeaders: ["a"]))
        XCTAssertNil(bothOff.createdRequest)
        XCTAssertNil(bothOff.receivedResponse)
        XCTAssertNil(bothOff.shouldRecordPayload)
    }

    func testHeadersOnlyDoesNotBufferPayloads() {
        let config = MiddlewareRum.networkMonitoringConfiguration(
            networkCapture: NetworkCapture(captureHeaders: true, captureResponseBodies: false))
        XCTAssertNotNil(config.createdRequest)
        XCTAssertNotNil(config.receivedResponse)
        XCTAssertNil(config.shouldRecordPayload)
        XCTAssertNil(config.maxRecordedPayloadBytes)
    }

    func testConfigurationHooksRecordAttributes() {
        let config = MiddlewareRum.networkMonitoringConfiguration(
            networkCapture: NetworkCapture(captureHeaders: true, captureResponseBodies: true, ignoredHeaders: ["cookie"]))
        let session = URLSession(configuration: .ephemeral)
        XCTAssertEqual(config.shouldRecordPayload?(session), true)
        XCTAssertEqual(config.maxRecordedPayloadBytes, NetworkCapture.maxResponseBodyBytes + 4)
        XCTAssertEqual(config.shouldRecordPayloadForResponse?(response(["Content-Type": "image/png"])), false)
        XCTAssertEqual(config.shouldRecordPayloadForResponse?(response(["Content-Type": "application/json"])), true)

        let exporter = InMemoryExporter()
        let provider = TracerProviderBuilder().add(spanProcessor: SimpleSpanProcessor(spanExporter: exporter)).build()
        let span = provider.get(instrumentationName: "test", instrumentationVersion: nil)
            .spanBuilder(spanName: "HTTP GET").startSpan()

        var request = URLRequest(url: url)
        request.setValue("Bearer x", forHTTPHeaderField: "Authorization")
        request.setValue("sid=1", forHTTPHeaderField: "Cookie")
        config.createdRequest?(request, span)
        config.receivedResponse?(response(["Content-Type": "application/json", "X-Access-Token": "t"]),
                                 Data("[1,2]".utf8), span)
        span.end()
        provider.forceFlush()

        let attributes = exporter.getFinishedSpanItems().first?.attributes ?? [:]
        XCTAssertEqual(attributes["http.request.header.authorization"], .string("Bearer x"))
        XCTAssertNil(attributes["http.request.header.cookie"])
        XCTAssertEqual(attributes["http.response.header.content_type"], .string("application/json"))
        XCTAssertEqual(attributes["http.response.header.x_access_token"], .string("********"))
        XCTAssertEqual(attributes["http.response.body"], .string("[1,2]"))
    }
}
