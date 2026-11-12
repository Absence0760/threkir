import Foundation
import Security

/// The wrist's own account session — email + password straight to GoTrue's
/// password grant, the way Wear OS's `SupabaseClient.signIn` has done since it
/// shipped.
///
/// The paired iPhone remains the durable sync target
/// (`docs/architecture/decisions.md` — WCSession owns the run hand-off, and
/// this file deliberately does NOT grow a second upload path). What the phone
/// handover never gave the watch is an identity of its own: a watch separated
/// from its phone could not authenticate at all, which is the same hole Wear
/// OS's `SignInScreen` exists to close.
///
/// Narrow on purpose: two grants and nothing else. Per
/// `apps/watch_ios/CLAUDE.md` the wrist is not where the Supabase surface
/// grows.

/// A session minted by GoTrue and held on this watch.
///
/// `expiresAt` is optional because the server is the one that says when — a
/// response without `expires_in` is an UNKNOWN expiry, not an immediate one,
/// which is the same short-circuit Wear OS's `StoredSession.isExpired` makes
/// on `expiresAtMs > 0`.
struct WatchSession: Equatable, Codable {
    let accessToken: String
    let refreshToken: String
    let userId: String
    let email: String
    let expiresAt: Date?

    /// One minute of margin, matching Wear OS's, so a request is never sent
    /// with a token that expires while it is in flight.
    static let refreshMargin: TimeInterval = 60

    func isExpired(now: Date = Date()) -> Bool {
        guard let expiresAt else { return false }
        return now >= expiresAt.addingTimeInterval(-Self.refreshMargin)
    }
}

/// Why the watch could not authenticate, as something the wrist can say in the
/// runner's own language.
///
/// A port of Wear OS's `AuthFault` (`apps/watch_wear/.../AuthFault.kt`) and its
/// reasoning: GoTrue's error bodies are English prose, so surfacing
/// `error.localizedDescription` puts half a sentence in the runner's language
/// and the half carrying the meaning in ours. The vocabulary is the runner's
/// next move — `invalidCredentials` is something they retype, `rateLimited` is
/// something they wait out, `sessionExpired` is a sign-in they owe through no
/// fault of their own.
enum WatchAuthFault: Equatable {
    /// The email and password were not accepted.
    case invalidCredentials
    /// GoTrue is rate-limiting this watch. Waiting is the whole remedy.
    case rateLimited
    /// The auth server answered 5xx.
    case serverBusy
    /// The request never reached the auth server.
    case offline
    /// A cached session could not be renewed. Distinct from
    /// `invalidCredentials` because the runner typed nothing wrong.
    case sessionExpired
    /// No Supabase environment is configured in this build, so no request was
    /// made. The fail-closed default — see `SupabaseEnvironment`.
    case notConfigured
    /// Something failed that none of the above describes.
    case unknown

    var message: String {
        switch self {
        case .invalidCredentials: return String(localized: "Email or password is wrong")
        case .rateLimited: return String(localized: "Too many tries — wait a minute")
        case .serverBusy: return String(localized: "Server busy — try again")
        case .offline: return String(localized: "No connection")
        case .sessionExpired: return String(localized: "Session expired — sign in again")
        case .notConfigured:
            return String(localized: "Sign-in isn't set up on this watch — sign in on your iPhone")
        case .unknown: return String(localized: "Sign-in failed")
        }
    }

    /// The half both grants answer the same way: everything that is not the
    /// grant itself being refused.
    private static func shared(status: Int?, error: Error?) -> WatchAuthFault? {
        guard let status else { return isTransientTransportFailure(error) ? .offline : .unknown }
        if status == 429 { return .rateLimited }
        if (500...599).contains(status) { return .serverBusy }
        return nil
    }

    /// Classify a failure of the password grant. A 4xx here is the credentials
    /// being refused — this endpoint has no token to be stale, so
    /// `sessionExpired` is not reachable from it.
    static func signIn(status: Int?, error: Error? = nil) -> WatchAuthFault {
        if let shared = shared(status: status, error: error) { return shared }
        guard let status, (400...499).contains(status) else { return .unknown }
        return .invalidCredentials
    }

    /// Classify a failure of the refresh grant. The same status codes mean
    /// something else here: a 400 on the password grant is a typo, and a 400
    /// on the refresh grant is a session the server will not renew.
    static func refresh(status: Int?, error: Error? = nil) -> WatchAuthFault {
        if let shared = shared(status: status, error: error) { return shared }
        guard let status, (400...499).contains(status) else { return .unknown }
        return .sessionExpired
    }

    /// Whether a transport failure is the network being absent rather than
    /// something the runner should read as a defect. Anything not on this list
    /// reads as `unknown`, which is the honest direction: telling a runner
    /// they are offline when they are not sends them to fix the wrong thing.
    static func isTransientTransportFailure(_ error: Error?) -> Bool {
        guard let error = error as? URLError else { return false }
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .timedOut,
             .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
             .internationalRoamingOff, .dataNotAllowed, .secureConnectionFailed:
            return true
        default:
            return false
        }
    }
}

/// Where the watch's Supabase project lives, and the key it presents.
///
/// Fail-closed: neither value is baked in. A build that configures neither
/// cannot reach GoTrue at all and the sign-in screen says so, which is the
/// same posture Wear OS's `build.gradle.kts` takes by defaulting its anon key
/// to `""` — a watch that could mint a session against a default project is
/// worse than one that cannot sign in.
///
/// Two sources, in order: the process environment (set in the WatchApp run
/// scheme for watch-simulator-alone dev, the same pair `SupabaseService` reads)
/// and then the bundle's `SupabaseURL` / `SupabaseAnonKey` keys, which
/// `Info.plist` fills from the build settings of the same name. Undefined
/// settings expand to empty, so an unconfigured release is unconfigured rather
/// than pointed somewhere.
struct SupabaseEnvironment: Equatable {
    let baseURL: String
    let anonKey: String

    static let urlKey = "SUPABASE_URL"
    static let anonKeyKey = "SUPABASE_ANON_KEY"
    static let urlInfoKey = "SupabaseURL"
    static let anonKeyInfoKey = "SupabaseAnonKey"

    /// Pure so the precedence and the fail-closed rule are testable without a
    /// bundle. An unexpanded `$(…)` placeholder counts as absent — an
    /// Info.plist processed without the build setting defined leaves either an
    /// empty string or the literal, and both mean "not configured".
    static func resolve(
        processEnvironment: [String: String],
        infoDictionary: [String: Any]
    ) -> SupabaseEnvironment? {
        func pick(_ envKey: String, _ infoKey: String) -> String? {
            for candidate in [processEnvironment[envKey], infoDictionary[infoKey] as? String] {
                guard let value = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !value.isEmpty, !value.contains("$(") else { continue }
                return value
            }
            return nil
        }
        guard let url = pick(urlKey, urlInfoKey), let key = pick(anonKeyKey, anonKeyInfoKey) else {
            return nil
        }
        return SupabaseEnvironment(baseURL: url, anonKey: key)
    }

    static func current(bundle: Bundle = .main) -> SupabaseEnvironment? {
        resolve(
            processEnvironment: ProcessInfo.processInfo.environment,
            infoDictionary: bundle.infoDictionary ?? [:]
        )
    }
}

/// The two requests, built without sending them, so their shape is pinned by
/// tests rather than by a run against a live project.
enum WatchAuthRequest {
    static func passwordGrant(
        email: String,
        password: String,
        environment: SupabaseEnvironment
    ) -> URLRequest? {
        // Each endpoint spelled out rather than interpolated from a grant
        // name: `scripts/check_watch_ios_source.mjs` claim (14) finds the
        // password grant by reading for it, and a guard that cannot see the
        // thing it governs is worse than none.
        post(
            path: "/auth/v1/token?grant_type=password",
            payload: ["email": normalize(email: email), "password": password],
            environment: environment
        )
    }

    static func refreshGrant(
        refreshToken: String,
        environment: SupabaseEnvironment
    ) -> URLRequest? {
        post(
            path: "/auth/v1/token?grant_type=refresh_token",
            payload: ["refresh_token": refreshToken],
            environment: environment
        )
    }

    /// Trimmed and lowercased, the same belt-and-braces Wear OS applies on
    /// every keystroke: watch text entry auto-shifts after `@` often enough
    /// that a typed address arrives capitalised, and GoTrue compares exactly.
    static func normalize(email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func post(
        path: String,
        payload: [String: String],
        environment: SupabaseEnvironment
    ) -> URLRequest? {
        guard let url = URL(string: environment.baseURL + path),
              let encoded = try? JSONEncoder().encode(payload) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(environment.anonKey, forHTTPHeaderField: "apikey")
        request.httpBody = encoded
        return request
    }
}

/// GoTrue's token response, and the only part of it this watch keeps.
struct WatchTokenResponse: Decodable {
    struct User: Decodable {
        let id: String
        let email: String?
    }

    let access_token: String
    let refresh_token: String
    let expires_in: Int?
    let user: User

    /// A session, or nil when the response is missing something a session
    /// cannot be without. Refusing is the honest answer: a session with a
    /// blank user id writes rows nobody owns.
    func session(now: Date = Date(), fallbackEmail: String) -> WatchSession? {
        guard !access_token.isEmpty, !refresh_token.isEmpty, !user.id.isEmpty else { return nil }
        let email = user.email.flatMap { $0.isEmpty ? nil : $0 } ?? fallbackEmail
        return WatchSession(
            accessToken: access_token,
            refreshToken: refresh_token,
            userId: user.id,
            email: email,
            expiresAt: expires_in.map { now.addingTimeInterval(TimeInterval($0)) }
        )
    }
}

/// The session's home on disk.
///
/// The Keychain, not `UserDefaults`, and for the reason Wear OS keeps its
/// `StoredSession` in `EncryptedSharedPreferences`: the refresh token is a
/// bearer credential that mints fresh access tokens indefinitely, so anyone
/// who can read it can act as the runner until it is revoked. `UserDefaults`
/// on watchOS is a plist in the app container, which is carried in the watch's
/// backup to its paired phone; a Keychain item marked
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` is readable after the
/// first unlock (a background relaunch needs that) and never leaves the
/// device.
enum WatchSessionStore {
    static let service = "com.threkir.watch.supabase-session"
    static let account = "session"

    private static func query() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    @discardableResult
    static func save(_ session: WatchSession) -> Bool {
        guard let data = try? JSONEncoder().encode(session) else { return false }
        var attributes = query()
        SecItemDelete(attributes as CFDictionary)
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    static func load() -> WatchSession? {
        var attributes = query()
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(attributes as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(WatchSession.self, from: data)
    }

    static func clear() {
        SecItemDelete(query() as CFDictionary)
    }
}

/// What the sign-in screen and the pre-run account row observe.
///
/// The class is not `@MainActor` so the shared instance can be read from a
/// `View`'s stored-property initializer; every method that touches a
/// `@Published` value is, which is where the isolation actually matters.
final class WatchAuth: ObservableObject {
    static let shared = WatchAuth()

    @Published private(set) var session: WatchSession?
    @Published private(set) var fault: WatchAuthFault?
    @Published private(set) var isBusy = false

    let environment: SupabaseEnvironment?

    var isConfigured: Bool { environment != nil }

    init(environment: SupabaseEnvironment? = SupabaseEnvironment.current(),
         session: WatchSession? = WatchSessionStore.load()) {
        self.environment = environment
        self.session = session
        applyToDirectSyncPath()
    }

    @MainActor
    func clearFault() {
        fault = nil
    }

    @MainActor
    func signIn(email: String, password: String) async {
        guard let environment else {
            fault = .notConfigured
            return
        }
        guard let request = WatchAuthRequest.passwordGrant(
            email: email, password: password, environment: environment
        ) else {
            fault = .unknown
            return
        }
        isBusy = true
        fault = nil
        defer { isBusy = false }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode
            guard status == 200 else {
                fault = .signIn(status: status)
                return
            }
            guard let decoded = try? JSONDecoder().decode(WatchTokenResponse.self, from: data),
                  let session = decoded.session(fallbackEmail: WatchAuthRequest.normalize(email: email))
            else {
                fault = .unknown
                return
            }
            adopt(session)
        } catch {
            fault = .signIn(status: nil, error: error)
        }
    }

    /// Renew a session that is at or past its margin. Returns the usable
    /// access token, or nil — in which case `fault` says why and `session` has
    /// been dropped, because a session the server will not renew is not one
    /// the wrist should keep claiming to hold.
    @discardableResult
    @MainActor
    func refreshIfNeeded() async -> String? {
        guard let session else { return nil }
        guard session.isExpired() else { return session.accessToken }
        guard let environment else {
            fault = .notConfigured
            return nil
        }
        guard let request = WatchAuthRequest.refreshGrant(
            refreshToken: session.refreshToken, environment: environment
        ) else {
            fault = .unknown
            return nil
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode
            guard status == 200,
                  let decoded = try? JSONDecoder().decode(WatchTokenResponse.self, from: data),
                  let renewed = decoded.session(fallbackEmail: session.email)
            else {
                fault = .refresh(status: status)
                discard()
                return nil
            }
            adopt(renewed)
            return renewed.accessToken
        } catch {
            // A transport failure is not a revoked session — keep it and let
            // the next attempt try again, rather than making a runner retype a
            // password on a wrist because a tunnel dropped.
            fault = .refresh(status: nil, error: error)
            return nil
        }
    }

    @MainActor
    func signOut() {
        discard()
        fault = nil
    }

    @MainActor
    private func adopt(_ session: WatchSession) {
        WatchSessionStore.save(session)
        self.session = session
        fault = nil
        applyToDirectSyncPath()
    }

    @MainActor
    private func discard() {
        WatchSessionStore.clear()
        session = nil
    }

    /// The one consumer that exists today. `SupabaseService` is the DEBUG-only
    /// watch-simulator-alone writer and its sign-in fallback hands GoTrue the
    /// seed account; handing it the runner's real session instead means a
    /// developer's direct upload lands on their own rows, and the seed
    /// credential is reached only when nobody has signed in.
    ///
    /// Release has no consumer yet and this is deliberately not one: the
    /// paired iPhone owns the Supabase write (`docs/architecture/decisions.md`
    /// — WCSession is the durable sync target), and growing a second upload
    /// path here would re-litigate that ADR rather than implement this row.
    private func applyToDirectSyncPath() {
        #if DEBUG
        guard let session, let environment else { return }
        Task {
            await SupabaseService.shared.applyCredentials(
                accessToken: session.accessToken,
                userId: session.userId,
                baseURL: environment.baseURL,
                anonKey: environment.anonKey
            )
        }
        #endif
    }
}
