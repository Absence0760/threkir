import XCTest
@testable import WatchApp

/// The wrist's own sign-in.
///
/// Everything here is the part that can be decided without a server: which
/// request goes out, how a refusal is named, when a stored session is stale,
/// and — the one that has to hold in a Release build nobody has configured —
/// that an unconfigured watch makes no request at all.
final class WatchAuthTests: XCTestCase {

    private let env = SupabaseEnvironment(baseURL: "https://example.supabase.co", anonKey: "anon-key")

    // MARK: - Environment resolution

    func testEnvironmentPrefersTheProcessEnvironment() {
        let resolved = SupabaseEnvironment.resolve(
            processEnvironment: ["SUPABASE_URL": "http://127.0.0.1:54321", "SUPABASE_ANON_KEY": "local"],
            infoDictionary: ["SupabaseURL": "https://prod.example", "SupabaseAnonKey": "prod"]
        )
        XCTAssertEqual(resolved?.baseURL, "http://127.0.0.1:54321")
        XCTAssertEqual(resolved?.anonKey, "local")
    }

    func testEnvironmentFallsBackToTheBundle() {
        let resolved = SupabaseEnvironment.resolve(
            processEnvironment: [:],
            infoDictionary: ["SupabaseURL": "https://prod.example", "SupabaseAnonKey": "prod"]
        )
        XCTAssertEqual(resolved, SupabaseEnvironment(baseURL: "https://prod.example", anonKey: "prod"))
    }

    /// The whole fail-closed rule: a build that configures nothing cannot
    /// reach any Supabase project, rather than reaching a default one.
    func testEnvironmentIsNilWhenNothingIsConfigured() {
        XCTAssertNil(SupabaseEnvironment.resolve(processEnvironment: [:], infoDictionary: [:]))
    }

    /// `Info.plist` is processed with the build settings expanded; a setting
    /// nobody defined leaves an empty value or the literal placeholder, and
    /// both mean unconfigured.
    func testEnvironmentRejectsEmptyAndUnexpandedValues() {
        XCTAssertNil(SupabaseEnvironment.resolve(
            processEnvironment: [:],
            infoDictionary: ["SupabaseURL": "$(SUPABASE_URL)", "SupabaseAnonKey": "$(SUPABASE_ANON_KEY)"]
        ))
        XCTAssertNil(SupabaseEnvironment.resolve(
            processEnvironment: ["SUPABASE_URL": "  ", "SUPABASE_ANON_KEY": ""],
            infoDictionary: [:]
        ))
    }

    /// Half a configuration is not a configuration: GoTrue answers 401 to an
    /// empty `apikey`, which would surface as "email or password is wrong".
    func testEnvironmentNeedsBothHalves() {
        XCTAssertNil(SupabaseEnvironment.resolve(
            processEnvironment: ["SUPABASE_URL": "https://example.supabase.co"],
            infoDictionary: [:]
        ))
        XCTAssertNil(SupabaseEnvironment.resolve(
            processEnvironment: ["SUPABASE_ANON_KEY": "anon"],
            infoDictionary: [:]
        ))
    }

    // MARK: - Request shape

    func testPasswordGrantRequest() throws {
        let request = try XCTUnwrap(
            WatchAuthRequest.passwordGrant(email: "runner@test.com", password: "testtest", environment: env)
        )
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://example.supabase.co/auth/v1/token?grant_type=password"
        )
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "apikey"), "anon-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try JSONDecoder().decode(
            [String: String].self, from: try XCTUnwrap(request.httpBody)
        )
        XCTAssertEqual(body, ["email": "runner@test.com", "password": "testtest"])
    }

    /// Watch text entry capitalises after `@` often enough that the typed
    /// address arrives shifted, and GoTrue compares exactly — the same
    /// belt-and-braces Wear OS applies on every keystroke.
    func testPasswordGrantNormalisesTheEmailButNotThePassword() throws {
        let request = try XCTUnwrap(
            WatchAuthRequest.passwordGrant(email: "  Runner@Test.COM ", password: " PaSsWoRd ", environment: env)
        )
        let body = try JSONDecoder().decode(
            [String: String].self, from: try XCTUnwrap(request.httpBody)
        )
        XCTAssertEqual(body["email"], "runner@test.com")
        XCTAssertEqual(body["password"], " PaSsWoRd ", "a password is bytes, not a display string")
    }

    func testRefreshGrantRequest() throws {
        let request = try XCTUnwrap(
            WatchAuthRequest.refreshGrant(refreshToken: "refresh-1", environment: env)
        )
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://example.supabase.co/auth/v1/token?grant_type=refresh_token"
        )
        let body = try JSONDecoder().decode(
            [String: String].self, from: try XCTUnwrap(request.httpBody)
        )
        XCTAssertEqual(body, ["refresh_token": "refresh-1"])
    }

    func testRequestIsNilWhenTheBaseUrlCannotBeAUrl() {
        let broken = SupabaseEnvironment(baseURL: "http://exa mple", anonKey: "k")
        XCTAssertNil(WatchAuthRequest.passwordGrant(email: "a@b.c", password: "p", environment: broken))
    }

    // MARK: - Fault classification

    /// A 4xx on the password grant is the credentials being refused. This
    /// endpoint has no token to be stale, so `sessionExpired` is unreachable
    /// from it — the distinction Wear OS's two entry points exist for.
    func testSignInFaultsByStatus() {
        XCTAssertEqual(WatchAuthFault.signIn(status: 400), .invalidCredentials)
        XCTAssertEqual(WatchAuthFault.signIn(status: 401), .invalidCredentials)
        XCTAssertEqual(WatchAuthFault.signIn(status: 429), .rateLimited)
        XCTAssertEqual(WatchAuthFault.signIn(status: 500), .serverBusy)
        XCTAssertEqual(WatchAuthFault.signIn(status: 503), .serverBusy)
        XCTAssertEqual(WatchAuthFault.signIn(status: 302), .unknown)
    }

    /// The same statuses mean something else on the refresh grant: a 400
    /// there is a session the server will not renew, and telling a runner
    /// their password is wrong when they have not typed one is worse than
    /// saying nothing.
    func testRefreshFaultsByStatus() {
        XCTAssertEqual(WatchAuthFault.refresh(status: 400), .sessionExpired)
        XCTAssertEqual(WatchAuthFault.refresh(status: 403), .sessionExpired)
        XCTAssertEqual(WatchAuthFault.refresh(status: 429), .rateLimited)
        XCTAssertEqual(WatchAuthFault.refresh(status: 500), .serverBusy)
    }

    func testTransportFailuresAreOfflineOnlyWhenTheyAre() {
        XCTAssertEqual(
            WatchAuthFault.signIn(status: nil, error: URLError(.notConnectedToInternet)), .offline
        )
        XCTAssertEqual(WatchAuthFault.signIn(status: nil, error: URLError(.timedOut)), .offline)
        XCTAssertEqual(
            WatchAuthFault.refresh(status: nil, error: URLError(.networkConnectionLost)), .offline
        )
        XCTAssertEqual(
            WatchAuthFault.signIn(status: nil, error: URLError(.badURL)), .unknown,
            "a malformed request is a defect, not a runner standing in a tunnel"
        )
        XCTAssertEqual(WatchAuthFault.signIn(status: nil, error: nil), .unknown)
    }

    /// Every case says something; none falls through to a key or to GoTrue's
    /// English prose, which is the defect the enum exists to prevent.
    func testEveryFaultHasAMessage() {
        let all: [WatchAuthFault] = [
            .invalidCredentials, .rateLimited, .serverBusy, .offline,
            .sessionExpired, .notConfigured, .unknown,
        ]
        XCTAssertEqual(Set(all.map(\.message)).count, all.count)
        for fault in all {
            XCTAssertFalse(fault.message.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    // MARK: - Session

    func testSessionExpiryCarriesAMinuteOfMargin() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let session = WatchSession(
            accessToken: "a", refreshToken: "r", userId: "u", email: "e@x.y",
            expiresAt: now.addingTimeInterval(90)
        )
        XCTAssertFalse(session.isExpired(now: now))
        XCTAssertTrue(
            session.isExpired(now: now.addingTimeInterval(31)),
            "a token 59 s from expiry must be renewed before a request is sent with it"
        )
    }

    /// An expiry the server never gave is UNKNOWN, not immediate — the same
    /// short-circuit Wear OS's `StoredSession.isExpired` makes on `> 0`.
    func testSessionWithNoExpiryIsNotTreatedAsExpired() {
        let session = WatchSession(
            accessToken: "a", refreshToken: "r", userId: "u", email: "e@x.y", expiresAt: nil
        )
        XCTAssertFalse(session.isExpired(now: Date(timeIntervalSince1970: 9_999_999_999)))
    }

    func testTokenResponseBecomesASession() throws {
        let json = """
        {"access_token":"at","refresh_token":"rt","expires_in":3600,
         "user":{"id":"user-1","email":"Runner@Test.com"}}
        """
        let decoded = try JSONDecoder().decode(WatchTokenResponse.self, from: Data(json.utf8))
        let now = Date(timeIntervalSince1970: 1_000_000)
        let session = try XCTUnwrap(decoded.session(now: now, fallbackEmail: "typed@x.y"))
        XCTAssertEqual(session.accessToken, "at")
        XCTAssertEqual(session.refreshToken, "rt")
        XCTAssertEqual(session.userId, "user-1")
        XCTAssertEqual(session.email, "Runner@Test.com", "the server's spelling wins over the typed one")
        XCTAssertEqual(session.expiresAt, now.addingTimeInterval(3600))
    }

    func testTokenResponseFallsBackToTheTypedEmailAndAnUnknownExpiry() throws {
        let json = """
        {"access_token":"at","refresh_token":"rt","user":{"id":"user-1"}}
        """
        let decoded = try JSONDecoder().decode(WatchTokenResponse.self, from: Data(json.utf8))
        let session = try XCTUnwrap(decoded.session(fallbackEmail: "typed@x.y"))
        XCTAssertEqual(session.email, "typed@x.y")
        XCTAssertNil(session.expiresAt)
    }

    /// A session with a blank user id writes rows nobody owns, so the
    /// response is refused rather than half-adopted.
    func testTokenResponseWithoutAUserIdIsRefused() throws {
        let json = """
        {"access_token":"at","refresh_token":"rt","user":{"id":""}}
        """
        let decoded = try JSONDecoder().decode(WatchTokenResponse.self, from: Data(json.utf8))
        XCTAssertNil(decoded.session(fallbackEmail: "typed@x.y"))
    }

    // MARK: - Keychain store

    /// The refresh token mints access tokens indefinitely, so it lives in the
    /// Keychain and not in `UserDefaults` — which on watchOS is a plist in the
    /// app container that travels in the watch's backup.
    func testKeychainRoundTrip() throws {
        WatchSessionStore.clear()
        defer { WatchSessionStore.clear() }
        let session = WatchSession(
            accessToken: "at", refreshToken: "rt", userId: "u-1", email: "e@x.y",
            expiresAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        XCTAssertTrue(WatchSessionStore.save(session))
        XCTAssertEqual(WatchSessionStore.load(), session)

        let replacement = WatchSession(
            accessToken: "at2", refreshToken: "rt2", userId: "u-1", email: "e@x.y", expiresAt: nil
        )
        XCTAssertTrue(WatchSessionStore.save(replacement), "a second sign-in replaces, never duplicates")
        XCTAssertEqual(WatchSessionStore.load(), replacement)

        WatchSessionStore.clear()
        XCTAssertNil(WatchSessionStore.load())
    }

    // MARK: - The observable

    /// The fail-closed gate, from the outside: an unconfigured build reports
    /// itself and sends nothing. Anything else would be a watch signing in
    /// against whatever project a default pointed at.
    @MainActor
    func testUnconfiguredSignInMakesNoRequest() async {
        let auth = WatchAuth(environment: nil, session: nil)
        XCTAssertFalse(auth.isConfigured)
        await auth.signIn(email: "runner@test.com", password: "testtest")
        XCTAssertEqual(auth.fault, .notConfigured)
        XCTAssertNil(auth.session)
        XCTAssertFalse(auth.isBusy)
    }

    @MainActor
    func testSignOutDropsTheSessionAndTheStoredCopy() {
        let session = WatchSession(
            accessToken: "at", refreshToken: "rt", userId: "u-1", email: "e@x.y", expiresAt: nil
        )
        XCTAssertTrue(WatchSessionStore.save(session))
        let auth = WatchAuth(environment: env, session: session)
        XCTAssertEqual(auth.session, session)

        auth.signOut()

        XCTAssertNil(auth.session)
        XCTAssertNil(auth.fault)
        XCTAssertNil(WatchSessionStore.load(), "a signed-out watch keeps no credential on disk")
    }

    /// A refresh is attempted only when the margin says so — an unexpired
    /// session hands its token straight back rather than spending a round
    /// trip on every read.
    @MainActor
    func testRefreshIsSkippedForAFreshSession() async {
        let session = WatchSession(
            accessToken: "at", refreshToken: "rt", userId: "u-1", email: "e@x.y",
            expiresAt: Date().addingTimeInterval(3600)
        )
        let auth = WatchAuth(environment: env, session: session)
        let token = await auth.refreshIfNeeded()
        XCTAssertEqual(token, "at")
        XCTAssertNil(auth.fault)
    }

    @MainActor
    func testRefreshWithNoSessionIsNil() async {
        let auth = WatchAuth(environment: env, session: nil)
        let token = await auth.refreshIfNeeded()
        XCTAssertNil(token)
    }
}
