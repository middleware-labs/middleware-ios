// Copyright © 2023 Middleware. Licensed under the Apache License, Version 2.0

import Foundation

/// Opt-in HTTP header and response body capture for URLSession spans.
///
/// Mirrors the browser SDK's `captureNetworkHeaders` / `captureResponseBodies` split. Both are
/// off by default; the attribute keys, masking, content-type filter and body cap are shared with
/// the other Middleware SDKs, so keep them in step.
struct NetworkCapture {
    static let requestHeaderPrefix = "http.request.header."
    static let responseHeaderPrefix = "http.response.header."
    static let responseBodyKey = "http.response.body"

    /// Response bodies are truncated to this many bytes before being recorded.
    static let maxResponseBodyBytes = 65536

    /// Headers whose value is recorded as `maskValue` rather than verbatim (lowercased).
    static let maskedHeaders: Set<String> = ["x-access-token"]
    static let maskValue = "********"

    let captureHeaders: Bool
    let captureResponseBodies: Bool
    /// Lowercased header names that are never recorded.
    let ignoredHeaders: Set<String>

    init(captureHeaders: Bool, captureResponseBodies: Bool, ignoredHeaders: [String] = []) {
        self.captureHeaders = captureHeaders
        self.captureResponseBodies = captureResponseBodies
        self.ignoredHeaders = Set(ignoredHeaders.map { Self.canonicalHeaderName($0) })
    }

    var isEnabled: Bool { captureHeaders || captureResponseBodies }

    // MARK: Headers

    /// `Content-Type` -> `content_type`.
    static func normalizeHeaderName(_ name: String) -> String {
        canonicalHeaderName(name).replacingOccurrences(of: "-", with: "_")
    }

    private static func canonicalHeaderName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// Builds `<prefix><normalized name>` attributes for the given headers, skipping ignored
    /// names and masking sensitive ones. Names that collide after normalization (e.g. the same
    /// header sent with different casing) are joined with `,`.
    func headerAttributes(_ headers: [(name: String, value: String)], prefix: String) -> [String: String] {
        var result = [String: String]()
        for header in headers.sorted(by: { $0.name < $1.name }) {
            let canonical = Self.canonicalHeaderName(header.name)
            guard !canonical.isEmpty, !ignoredHeaders.contains(canonical) else { continue }
            let value = Self.maskedHeaders.contains(canonical) ? Self.maskValue : header.value
            let key = prefix + Self.normalizeHeaderName(canonical)
            if let existing = result[key] {
                result[key] = existing + "," + value
            } else {
                result[key] = value
            }
        }
        return result
    }

    func requestHeaderAttributes(_ request: URLRequest) -> [String: String] {
        guard captureHeaders, let fields = request.allHTTPHeaderFields, !fields.isEmpty else { return [:] }
        return headerAttributes(fields.map { (name: $0.key, value: $0.value) }, prefix: Self.requestHeaderPrefix)
    }

    func responseHeaderAttributes(_ response: HTTPURLResponse) -> [String: String] {
        guard captureHeaders else { return [:] }
        return headerAttributes(Self.headerPairs(response.allHeaderFields), prefix: Self.responseHeaderPrefix)
    }

    static func headerPairs(_ fields: [AnyHashable: Any]) -> [(name: String, value: String)] {
        fields.map { key, value in
            let name = key.base as? String ?? String(describing: key.base)
            if let string = value as? String { return (name: name, value: string) }
            if let strings = value as? [String] { return (name: name, value: strings.joined(separator: ",")) }
            return (name: name, value: String(describing: value))
        }
    }

    /// Case-insensitive header lookup that works on every deployment target.
    static func headerValue(_ name: String, in fields: [AnyHashable: Any]) -> String? {
        let wanted = name.lowercased()
        return headerPairs(fields).first { $0.name.lowercased() == wanted }?.value
    }

    // MARK: Bodies

    /// `application/json`, `*+json` and `text/plain` (parameters such as charset are ignored).
    static func isCapturableContentType(_ contentType: String?) -> Bool {
        guard let contentType = contentType else { return false }
        let base = contentType.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        let type = base.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return type == "application/json" || type.hasSuffix("+json") || type == "text/plain"
    }

    static func isCapturableResponse(_ response: URLResponse?) -> Bool {
        guard let http = response as? HTTPURLResponse else { return false }
        return isCapturableContentType(headerValue("Content-Type", in: http.allHeaderFields))
    }

    /// Decodes at most `limit` bytes of `data` as UTF-8, backing off so a multi-byte scalar is not
    /// split at the cut. Invalid sequences are replaced (lossy). Returns nil for an empty body.
    static func truncatedBodyText(_ data: Data, limit: Int = maxResponseBodyBytes) -> String? {
        guard !data.isEmpty, limit > 0 else { return nil }
        let bytes = [UInt8](data.prefix(limit + 1))
        if bytes.count <= limit {
            return String(decoding: bytes, as: UTF8.self)
        }
        var cut = limit
        // bytes[cut] is the first byte we drop; if it's a continuation byte the scalar straddles
        // the cut, so move back to its lead byte (a UTF-8 scalar is at most 4 bytes).
        while cut > 0, limit - cut < 3, bytes[cut] & 0xC0 == 0x80 {
            cut -= 1
        }
        return String(decoding: bytes[0 ..< cut], as: UTF8.self)
    }

    /// The `http.response.body` value for a completed request, or nil when it shouldn't be
    /// recorded. Only in-memory `Data` is considered; download tasks hand over a file URL, which
    /// is never read.
    func responseBody(response: URLResponse, dataOrFile: Any?) -> String? {
        guard captureResponseBodies,
              Self.isCapturableResponse(response),
              let data = dataOrFile as? Data
        else { return nil }
        return Self.truncatedBodyText(data)
    }
}
