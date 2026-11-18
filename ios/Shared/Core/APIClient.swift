import Foundation
import WidgetKit

// Talks to the server's /api/v1 JSON API. Authentication is the server's normal session cookie,
// kept in the App Group's cookie store (persisted across launches, since the server gives it an
// expiry, and shared with the share extension), so the app is signed out by the same idle/absolute
// limits as the web.

enum APIError: LocalizedError {
    case unauthorized
    case server(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized: "You've been signed out. Please sign in again."
        case .server(let message): message
        case .transport(let message): message
        }
    }
}

struct EmptyResponse: Decodable {}

final class APIClient {
    static let shared = APIClient()

    /// Posted when any request comes back 401, so the app can return to the sign-in screen
    static let unauthorizedNotification = Notification.Name("Obelo.unauthorized")

    private static let serverKey = "serverURL"
    /// A placeholder, not a real server: the sign-in screen starts with it, and you enter your own address there
    static let defaultServer = "https://your-server.example"

    /// The address the person saved, or "" until they sign in with one. The sign-in screens start from this, so a
    /// new install shows an empty field (the sign-in refuses an empty address).
    var storedServer: String {
        #if DEBUG
        if let arg = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)[Self.serverKey] as? String { return arg }
        #endif
        return AppGroup.defaults.string(forKey: Self.serverKey) ?? ""
    }

    var serverURL: URL {
        get {
            #if DEBUG
            // Simulator testing: a `-serverURL` launch argument wins
            if let arg = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)[Self.serverKey] as? String,
               let url = URL(string: arg) { return url }
            #endif
            let stored = AppGroup.defaults.string(forKey: Self.serverKey) ?? Self.defaultServer
            return URL(string: stored) ?? URL(string: Self.defaultServer)!
        }
        set { AppGroup.defaults.set(newValue.absoluteString, forKey: Self.serverKey) }
    }

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        // Cookies are handled by hand through AppGroup.session (see there), shared with the
        // share extension and widget
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 30
        // Always ask the server: a cached response would show the widget (or a screen) stale data
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        // userSessions.deviceName() on the server recognises this as "Obelo app on iPhone"
        config.httpAdditionalHeaders = ["User-Agent": "Obelo-iOS/\(version) (iPhone; iOS)"]
        return URLSession(configuration: config)
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        let withFraction = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        let plain = Date.ISO8601FormatStyle()
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            if let date = try? withFraction.parse(s) { return date }
            if let date = try? plain.parse(s) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad date \(s)"))
        }
        return d
    }()

    func url(_ path: String) -> URL {
        URL(string: path, relativeTo: serverURL)!.absoluteURL
    }

    // ── Requests ─────────────────────────────────────────────────────────────

    func get<T: Decodable>(_ path: String, query: [String: String?] = [:]) async throws -> T {
        var components = URLComponents(url: url("/api/v1" + path), resolvingAgainstBaseURL: true)!
        let items = query.compactMap { key, value in value.map { URLQueryItem(name: key, value: $0) } }
        if !items.isEmpty { components.queryItems = items }
        return try await send(URLRequest(url: components.url!))
    }

    @discardableResult
    func post<T: Decodable>(_ path: String, _ body: [String: Any] = [:], method: String = "POST") async throws -> T {
        var request = URLRequest(url: url("/api/v1" + path))
        request.httpMethod = method
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await send(request)
    }

    func post(_ path: String, _ body: [String: Any] = [:], method: String = "POST") async throws {
        let _: EmptyResponse = try await post(path, body, method: method)
    }

    func delete(_ path: String) async throws {
        try await post(path, [:], method: "DELETE")
    }

    private func send<T: Decodable>(_ request: URLRequest, contentTypeSet: Bool = false) async throws -> T {
        var request = request
        request.setValue("ios", forHTTPHeaderField: "X-Obelo-Client")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if request.httpBody != nil && !contentTypeSet { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }

        attachSession(&request)
        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.transport("Can't reach \(serverURL.host() ?? "the server"). Check your connection.")
        }
        rememberSession(from: response)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 {
            NotificationCenter.default.post(name: Self.unauthorizedNotification, object: nil)
            throw APIError.unauthorized
        }
        guard (200..<300).contains(status) else {
            let message = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
            throw APIError.server(message ?? "Something went wrong (HTTP \(status)).")
        }
        // Any successful change (from any screen, the share sheet or a widget button) refreshes
        // the home screen widget, so it never lags behind the app
        if request.httpMethod != nil && request.httpMethod != "GET" && !(request.url?.path.hasPrefix("/api/v1/auth") ?? false) {
            WidgetCenter.shared.reloadAllTimelines()
        }
        if T.self == EmptyResponse.self { return EmptyResponse() as! T }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.server("Unexpected response from the server. Is it running Obelo 3.18 or later?")
        }
    }

    struct UploadFile { let data: Data; let filename: String; let mimeType: String }

    /// multipart/form-data upload of one file
    func upload<T: Decodable>(_ path: String, field: String, data fileData: Data, filename: String, mimeType: String) async throws -> T {
        try await upload(path, field: field, files: [UploadFile(data: fileData, filename: filename, mimeType: mimeType)])
    }

    /// multipart/form-data upload of several files under the same field
    func upload<T: Decodable>(_ path: String, field: String, files: [UploadFile]) async throws -> T {
        let boundary = "vt-\(UUID().uuidString)"
        var body = Data()
        for file in files {
            let safeName = file.filename.replacingOccurrences(of: "\"", with: "")
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(field)\"; filename=\"\(safeName)\"\r\nContent-Type: \(file.mimeType)\r\n\r\n".data(using: .utf8)!)
            body.append(file.data)
            body.append("\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        var request = URLRequest(url: url("/api/v1" + path))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 120
        return try await send(request, contentTypeSet: true)
    }

    func clearCookies() {
        AppGroup.session = nil
        let storage = AppGroup.cookies
        storage.cookies(for: serverURL)?.forEach(storage.deleteCookie)
    }

    // ── Session cookie ───────────────────────────────────────────────────────

    private func attachSession(_ request: inout URLRequest) {
        guard let host = request.url?.host() else { return }
        var saved = AppGroup.session
        if saved == nil {
            // Sign-ins from before AppGroup.session: adopt the cookie from the old shared store
            let old = (AppGroup.cookies.cookies(for: serverURL) ?? []).filter { ($0.expiresDate ?? .distantFuture) > .now }
            if !old.isEmpty, let serverHost = serverURL.host() {
                saved = (serverHost, Dictionary(old.map { ($0.name, $0.value) }, uniquingKeysWith: { _, new in new }))
                AppGroup.session = saved
            }
        }
        guard let saved, saved.host == host else { return }
        request.setValue(saved.cookies.map { "\($0.key)=\($0.value)" }.joined(separator: "; "), forHTTPHeaderField: "Cookie")
    }

    private func rememberSession(from response: URLResponse) {
        guard let http = response as? HTTPURLResponse, let url = http.url, let host = url.host(),
              let fields = http.allHeaderFields as? [String: String] else { return }
        let set = HTTPCookie.cookies(withResponseHeaderFields: fields, for: url)
        guard !set.isEmpty else { return }
        var cookies = AppGroup.session.flatMap { $0.host == host ? $0.cookies : nil } ?? [:]
        for cookie in set {
            if let expires = cookie.expiresDate, expires <= .now { cookies[cookie.name] = nil }
            else { cookies[cookie.name] = cookie.value }
        }
        AppGroup.session = cookies.isEmpty ? nil : (host, cookies)
    }

    /// Bytes for an authenticated file (note attachments)
    func data(path: String) async throws -> Data {
        var request = URLRequest(url: url(path))
        request.setValue("ios", forHTTPHeaderField: "X-Obelo-Client")
        attachSession(&request)
        let (data, response) = try await session.data(for: request)
        rememberSession(from: response)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw APIError.server("Couldn't load the file.") }
        return data
    }
}
