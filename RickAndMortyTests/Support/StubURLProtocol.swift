import Foundation
import Synchronization

/// Intercepts requests inside a real `URLSession` so `URLSessionHTTPClient` can be
/// tested against actual session plumbing — status codes, transport errors, response
/// objects — without a single packet leaving the machine.
///
/// Shared state is guarded by `Mutex` rather than `nonisolated(unsafe)`; suites that
/// use it are marked `.serialized`, since `URLProtocol` registration is process-wide.
final class StubURLProtocol: URLProtocol {
    struct Stub: Sendable {
        var statusCode: Int = 200
        var body: Data = Data()
        /// When set, the transport fails instead of answering.
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

    /// An ephemeral session with caching off, so a test never reads another test's answer.
    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
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
