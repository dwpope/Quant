import XCTest
import simd
@testable import PostureLogic

/// The client for the Jev proxy. There is no networking anywhere else in this project, so the
/// error taxonomy and the backoff are both established here rather than copied.
///
/// The proxy's status codes carry meaning and the client must act on them differently: 429 and
/// 529 are passed through from TypeSafe and are worth retrying; 400 and 413 mean our own payload
/// is wrong and retrying would just fail again; 503 means the proxy has no key, which no amount
/// of waiting fixes. Getting that wrong turns a misconfiguration into a retry storm against a
/// paid API.
final class JevClientTests: XCTestCase {

    private let endpoint = URL(string: "https://jev-proxy.example/classify")!

    /// Records what it was asked and replays a scripted sequence of responses.
    private final class StubTransport: JevTransport, @unchecked Sendable {
        var script: [(status: Int, body: Data)]
        private(set) var calls: [(url: URL, body: Data)] = []
        init(_ script: [(status: Int, body: Data)]) { self.script = script }
        func post(_ body: Data, to url: URL) async throws -> (Data, Int) {
            calls.append((url, body))
            let next = script.isEmpty ? (status: 200, body: Data()) : script.removeFirst()
            return (next.body, next.status)
        }
    }

    private final class RecordingSleeper: JevSleeper, @unchecked Sendable {
        private(set) var slept: [Double] = []
        func sleep(seconds: Double) async { slept.append(seconds) }
    }

    private var verdictBody: Data {
        Data("""
        {"posture":"slouch","confidence":0.72,"probabilities":{"slouch":0.72},"model":"jev-1.13.0"}
        """.utf8)
    }

    private func features() -> JevFeatures {
        JevFeatures.make(
            sample: PoseSample(
                timestamp: 0, depthMode: .twoDOnly,
                headPosition: SIMD3<Float>(0.5, 0.8, 0), shoulderMidpoint: SIMD3<Float>(0.5, 0.6, 0),
                leftShoulder: SIMD3<Float>(0.4, 0.6, 0), rightShoulder: SIMD3<Float>(0.6, 0.6, 0),
                torsoAngle: 5, headForwardOffset: 0, shoulderTwist: 0,
                shoulderWidthRaw: 0.3, trackingQuality: .good),
            metrics: RawMetrics(
                timestamp: 0, forwardCreep: 0.1, headDrop: 0, shoulderRounding: 0,
                lateralLean: 0, twist: 0, movementLevel: 0, headMovementPattern: .still),
            baseline: Baseline(
                timestamp: Date(timeIntervalSince1970: 0),
                shoulderMidpoint: SIMD3<Float>(0.5, 0.6, 0), headPosition: SIMD3<Float>(0.5, 0.8, 0),
                torsoAngle: 0, shoulderTwist: 0, shoulderWidth: 0.2, depthAvailable: false)
        )!
    }

    private func client(_ transport: StubTransport, _ sleeper: RecordingSleeper = RecordingSleeper(),
                        maxRetries: Int = 3) -> JevClient {
        JevClient(endpoint: endpoint, transport: transport, sleeper: sleeper, maxRetries: maxRetries)
    }

    // MARK: - The happy path

    func test_classify_returnsTheVerdictAndPostsToTheEndpoint() async throws {
        let transport = StubTransport([(200, verdictBody)])
        let verdict = try await client(transport).classify(features())

        XCTAssertEqual(verdict.posture, "slouch")
        XCTAssertEqual(verdict.confidence, 0.72, accuracy: 1e-9)
        XCTAssertEqual(transport.calls.count, 1)
        XCTAssertEqual(transport.calls[0].url, endpoint)
    }

    func test_classify_sendsTheWireKeys() async throws {
        let transport = StubTransport([(200, verdictBody)])
        _ = try await client(transport).classify(features())

        let json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: transport.calls[0].body) as? [String: Any])
        XCTAssertNotNil(json["lateral_lean_in_shoulder_widths"])
        XCTAssertNotNil(json["shoulder_tilt_signed_degrees"])
        XCTAssertEqual(json["tracking_quality"] as? String, "good")
    }

    // MARK: - Retryable: the proxy passes these through from TypeSafe

    func test_classify_retriesOn429AndSucceeds() async throws {
        let transport = StubTransport([(429, Data()), (200, verdictBody)])
        let sleeper = RecordingSleeper()

        let verdict = try await client(transport, sleeper).classify(features())

        XCTAssertEqual(verdict.posture, "slouch")
        XCTAssertEqual(transport.calls.count, 2)
        XCTAssertEqual(sleeper.slept.count, 1, "must wait before retrying")
    }

    func test_classify_retriesOn529() async throws {
        let transport = StubTransport([(529, Data()), (200, verdictBody)])
        _ = try await client(transport).classify(features())
        XCTAssertEqual(transport.calls.count, 2)
    }

    func test_classify_backsOffExponentiallyAndGivesUp() async {
        let transport = StubTransport(Array(repeating: (429, Data()), count: 10))
        let sleeper = RecordingSleeper()

        do {
            _ = try await client(transport, sleeper, maxRetries: 3).classify(features())
            XCTFail("expected to give up")
        } catch let error as JevClientError {
            XCTAssertEqual(error, .busy(afterAttempts: 4))
        } catch {
            XCTFail("unexpected error \(error)")
        }

        XCTAssertEqual(transport.calls.count, 4, "one initial attempt plus three retries")
        XCTAssertEqual(sleeper.slept, [0.5, 1.0, 2.0], "each wait doubles")
    }

    // MARK: - Not retryable

    func test_classify_doesNotRetryOurOwnBadPayload() async {
        for status in [400, 413] {
            let transport = StubTransport([(status, Data())])
            do {
                _ = try await client(transport).classify(features())
                XCTFail("expected a rejection for \(status)")
            } catch let error as JevClientError {
                XCTAssertEqual(error, .rejected(status: status))
            } catch { XCTFail("unexpected error \(error)") }
            XCTAssertEqual(transport.calls.count, 1, "status \(status) must not be retried")
        }
    }

    func test_classify_doesNotRetryAnUnconfiguredProxy() async {
        let transport = StubTransport([(503, Data())])
        do {
            _ = try await client(transport).classify(features())
            XCTFail("expected proxyUnconfigured")
        } catch let error as JevClientError {
            XCTAssertEqual(error, .proxyUnconfigured)
        } catch { XCTFail("unexpected error \(error)") }
        XCTAssertEqual(transport.calls.count, 1)
    }

    func test_classify_reportsAnUpstreamFailureWithoutRetrying() async {
        let transport = StubTransport([(502, Data())])
        do {
            _ = try await client(transport).classify(features())
            XCTFail("expected upstream")
        } catch let error as JevClientError {
            XCTAssertEqual(error, .upstream(status: 502))
        } catch { XCTFail("unexpected error \(error)") }
        XCTAssertEqual(transport.calls.count, 1)
    }

    func test_classify_reportsMalformedJson() async {
        let transport = StubTransport([(200, Data("{ not json".utf8))])
        do {
            _ = try await client(transport).classify(features())
            XCTFail("expected malformedResponse")
        } catch let error as JevClientError {
            XCTAssertEqual(error, .malformedResponse)
        } catch { XCTFail("unexpected error \(error)") }
    }

    func test_classify_surfacesATransportFailure() async {
        struct Boom: Error {}
        final class Failing: JevTransport, @unchecked Sendable {
            func post(_ body: Data, to url: URL) async throws -> (Data, Int) { throw Boom() }
        }
        do {
            _ = try await JevClient(endpoint: endpoint, transport: Failing(),
                                    sleeper: RecordingSleeper(), maxRetries: 3)
                .classify(features())
            XCTFail("expected unreachable")
        } catch let error as JevClientError {
            XCTAssertEqual(error, .unreachable)
        } catch { XCTFail("unexpected error \(error)") }
    }
}
