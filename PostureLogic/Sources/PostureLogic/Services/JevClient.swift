import Foundation

/// How a `JevClient` reaches the proxy. Abstracted so the client's status-code handling and
/// backoff are testable without a network — there is no other networking in this project to
/// borrow a test seam from.
public protocol JevTransport: Sendable {
    /// Returns the response body and HTTP status. Throwing means "did not reach the proxy".
    func post(_ body: Data, to url: URL) async throws -> (Data, Int)
}

/// Injected so backoff tests assert the schedule instead of waiting for it.
public protocol JevSleeper: Sendable {
    func sleep(seconds: Double) async
}

public struct TaskSleeper: JevSleeper {
    public init() {}
    public func sleep(seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}

/// What went wrong, in terms the caller can act on.
///
/// The distinction between these cases is the point. `busy` means try again later; `rejected`
/// means this payload will never work; `proxyUnconfigured` means a human must set a secret. A
/// client that collapsed them into one error would either retry a misconfiguration forever or
/// give up on transient rate limiting.
public enum JevClientError: Error, Equatable {
    /// 400 or 413 — our own payload is wrong. Retrying cannot help.
    case rejected(status: Int)
    /// 503 — the proxy has no TypeSafe key. Waiting cannot help.
    case proxyUnconfigured
    /// 429/529 passed through from TypeSafe, still failing after every retry.
    case busy(afterAttempts: Int)
    /// 502 — the proxy reached TypeSafe and TypeSafe failed. Includes a rejected key (401
    /// upstream), which is why this is not retried: it is almost always a configuration fault.
    case upstream(status: Int)
    /// The proxy answered 200 with something that is not a verdict.
    case malformedResponse
    /// The proxy was not reachable at all.
    case unreachable
}

/// Classifies posture via the Jev proxy.
///
/// An `actor` so an interval-driven caller cannot accidentally run overlapping requests, and so
/// the retry state is never shared across tasks. The app holds no credential: the proxy adds the
/// bearer token, which is why this type has no notion of one.
public actor JevClient {
    private let endpoint: URL
    private let transport: JevTransport
    private let sleeper: JevSleeper
    private let maxRetries: Int
    private let firstBackoff: Double

    public init(
        endpoint: URL,
        transport: JevTransport,
        sleeper: JevSleeper = TaskSleeper(),
        maxRetries: Int = 3,
        firstBackoff: Double = 0.5
    ) {
        self.endpoint = endpoint
        self.transport = transport
        self.sleeper = sleeper
        self.maxRetries = maxRetries
        self.firstBackoff = firstBackoff
    }

    public func classify(_ features: JevFeatures) async throws -> JevVerdict {
        let body = try JSONEncoder().encode(features)
        var backoff = firstBackoff

        for attempt in 0...maxRetries {
            let status: Int
            let data: Data
            do {
                (data, status) = try await transport.post(body, to: endpoint)
            } catch {
                throw JevClientError.unreachable
            }

            switch status {
            case 200:
                guard let verdict = try? JSONDecoder().decode(JevVerdict.self, from: data) else {
                    throw JevClientError.malformedResponse
                }
                return verdict

            case 429, 529:
                // Retryable. Sleep only when another attempt remains, so the last failure is
                // not preceded by a pointless wait.
                guard attempt < maxRetries else { break }
                await sleeper.sleep(seconds: backoff)
                backoff *= 2
                continue

            case 400, 413:
                throw JevClientError.rejected(status: status)

            case 503:
                throw JevClientError.proxyUnconfigured

            default:
                throw JevClientError.upstream(status: status)
            }
        }

        throw JevClientError.busy(afterAttempts: maxRetries + 1)
    }
}

/// The real transport: one `POST` with a JSON body and no credential.
///
/// It deliberately attaches no `Authorization` header. The proxy owns the TypeSafe bearer token,
/// which is the entire reason the app holds none — a key in an iOS binary is extractable, and
/// TypeSafe documents no ephemeral-token scheme. If a future change adds a header here, the app
/// has started carrying a secret again and a test fails.
public struct URLSessionJevTransport: JevTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func post(_ body: Data, to url: URL) async throws -> (Data, Int) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw JevClientError.unreachable
        }
        return (data, http.statusCode)
    }
}
