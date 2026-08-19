import Foundation
import Synchronization

/// Intercepts requests inside a real `URLSession`, to test `URLSessionHTTPClient`
/// against the session's actual plumbing (status codes, transport errors, response
/// objects) without a single packet going out. Shared state uses `Mutex`, not
/// `nonisolated(unsafe)`, and the suites that use this are marked `.serialized` because
/// registering a `URLProtocol` affects the whole process.
final class StubURLProtocol: URLProtocol {
    struct Stub: Sendable {
        var statusCode: Int = 200
        var body = Data()
        // If set, the request fails in transport instead of answering.
        var error: URLError?
        var headers: [String: String] = ["Content-Type": "application/json"]

        static func ok(_ json: String) -> Stub { Stub(body: Data(json.utf8)) }
        static func status(_ code: Int, json: String = "{}") -> Stub {
            Stub(statusCode: code, body: Data(json.utf8))
        }
        static func transport(_ code: URLError.Code) -> Stub { Stub(error: URLError(code)) }
    }

    private static let stub = Mutex(Stub())
    private static let requests = Mutex<[URLRequest]>([])

    static func install(_ stub: Stub) {
        Self.stub.withLock { $0 = stub }
        requests.withLock { $0 = [] }
    }

    static var lastRequest: URLRequest? { requests.withLock { $0.last } }

    // Ephemeral, cache-free session, so one test can't read another's response.
    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        Self.requests.withLock { $0.append(request) }
        let stub = Self.stub.withLock { $0 }

        if let error = stub.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        guard let url = request.url,
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: stub.statusCode,
                  httpVersion: "HTTP/1.1",
                  headerFields: stub.headers
              )
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }
}
