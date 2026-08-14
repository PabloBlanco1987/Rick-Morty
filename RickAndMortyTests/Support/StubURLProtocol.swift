import Foundation
import Synchronization

// Intercepta las peticiones dentro de una URLSession de verdad, para poder probar
// URLSessionHTTPClient contra la fontanería real de la sesión (códigos de estado,
// errores de transporte, objetos de respuesta) sin que salga un solo paquete.
// El estado compartido va con Mutex y no con nonisolated(unsafe), y las suites que
// lo usan están marcadas .serialized porque registrar un URLProtocol afecta a todo
// el proceso.
final class StubURLProtocol: URLProtocol {
    struct Stub: Sendable {
        var statusCode: Int = 200
        var body = Data()
        // Si está puesto, la petición falla en transporte en vez de contestar
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

    // Sesión efímera y sin caché, para que un test no lea la respuesta de otro
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
