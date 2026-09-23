import XCTest
@testable import PostureLogic

/// The one place this project makes an HTTP request, so the request's shape is pinned rather
/// than assumed. Driven through a `URLProtocol` stub on an ephemeral session — no network.
final class URLSessionJevTransportTests: XCTestCase {

    private final class StubProtocol: URLProtocol {
        nonisolated(unsafe) static var status = 200
        nonisolated(unsafe) static var body = Data("{}".utf8)
        nonisolated(unsafe) static var seen: URLRequest?
        nonisolated(unsafe) static var seenBody: Data?

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            Self.seen = request
            Self.seenBody = request.httpBody ?? request.httpBodyStream.flatMap { stream in
                stream.open()
                var data = Data()
                var buffer = [UInt8](repeating: 0, count: 1024)
                while stream.hasBytesAvailable {
                    let read = stream.read(&buffer, maxLength: buffer.count)
                    if read <= 0 { break }
                    data.append(contentsOf: buffer[0..<read])
                }
                stream.close()
                return data
            }
            let response = HTTPURLResponse(
                url: request.url!, statusCode: Self.status, httpVersion: nil,
                headerFields: ["content-type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Self.body)
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    private func makeTransport() -> URLSessionJevTransport {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return URLSessionJevTransport(session: URLSession(configuration: config))
    }

    override func setUp() {
        StubProtocol.status = 200
        StubProtocol.body = Data("{}".utf8)
        StubProtocol.seen = nil
        StubProtocol.seenBody = nil
    }

    func test_post_sendsAJsonPostWithTheBody() async throws {
        let url = URL(string: "https://jev-proxy.example/classify")!
        let payload = Data(#"{"a":1}"#.utf8)

        _ = try await makeTransport().post(payload, to: url)

        let request = try XCTUnwrap(StubProtocol.seen)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url, url)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(StubProtocol.seenBody, payload)
    }

    func test_post_returnsTheStatusAndBody() async throws {
        StubProtocol.status = 429
        StubProtocol.body = Data(#"{"error":"upstream busy"}"#.utf8)

        let (body, status) = try await makeTransport()
            .post(Data("{}".utf8), to: URL(string: "https://jev-proxy.example/classify")!)

        XCTAssertEqual(status, 429)
        XCTAssertEqual(body, StubProtocol.body)
    }

    /// No credential is ever attached: the proxy owns the bearer token, and that is the whole
    /// reason the app holds none. A future edit adding an Authorization header here should fail.
    func test_post_attachesNoAuthorizationHeader() async throws {
        _ = try await makeTransport()
            .post(Data("{}".utf8), to: URL(string: "https://jev-proxy.example/classify")!)
        XCTAssertNil(try XCTUnwrap(StubProtocol.seen).value(forHTTPHeaderField: "Authorization"))
    }
}
