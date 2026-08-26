import ComposableArchitecture
import DependenciesMacros
import Foundation
import Security

/// Stores the Hermes auth session (a bare token in `.token` mode, or the cookie payload +
/// username in `.cookie` mode). Live implementation backs onto the iOS Keychain; an
/// in-memory variant is used for previews and feature tests.
///
/// The session is persisted as a JSON-encoded `AuthSession` under a single Keychain item.
/// `loadSession`/`saveSession`/`deleteSession` are the full-session API; the `…Token`
/// closures are thin token-mode shims (kept as first-class dependency endpoints so the
/// existing token-mode call sites and their test overrides stay unchanged).
///
/// Per-server auth lives under account `"session-\(id)"` via `loadSessionForServer` /
/// `saveSessionForServer` / `deleteSessionForServer`. The legacy single-account API remains
/// the active session for launch backward compatibility.
@DependencyClient
public struct KeychainClient: Sendable {
  /// Load the full persisted session. For a `.cookie` session this also rehydrates the
  /// captured cookies into the supplied `HTTPCookieStorage` so the REST/WS transports pick
  /// them up on a fresh launch.
  public var loadSession: @Sendable (_ storage: HTTPCookieStorage) -> AuthSession? = { _ in nil }
  /// Persist the full session (token payload, or cookie jar + username).
  public var saveSession: @Sendable (_ session: AuthSession) throws -> Void
  /// Clear the persisted session. The live implementation also flushes any gated-session
  /// cookies rehydrated into `HTTPCookieStorage.shared` (used by the REST/WS transports) so
  /// no stale cookie outlives logout — call this, not `deleteToken`, on logout.
  public var deleteSession: @Sendable () throws -> Void
  /// Load auth for a saved server id (account `"session-\(id)"`).
  public var loadSessionForServer: @Sendable (_ id: String, _ storage: HTTPCookieStorage) -> AuthSession? = { _, _ in nil }
  /// Persist auth for a saved server id.
  public var saveSessionForServer: @Sendable (_ id: String, _ session: AuthSession) throws -> Void = { _, _ in }
  /// Delete auth for a saved server id (does not flush the shared cookie jar).
  public var deleteSessionForServer: @Sendable (_ id: String) throws -> Void = { _ in }
  /// Activate a freshly-captured `.cookie` session by rehydrating its cookies into
  /// `HTTPCookieStorage.shared` — the jar the live REST/WS transports read. Call this right
  /// after `passwordLogin` (BEFORE the first authenticated REST call): the login cookies are
  /// otherwise captured only in an isolated jar, so `.shared` stays empty and authenticated
  /// REST calls 401 until the next launch (when `loadSession` rehydrates). Flushes any prior
  /// shared cookies first so a user-switch / re-auth can't mix old and new jars.
  public var activateCookieSession: @Sendable (_ session: CookieSession) -> Void = { _ in }

  // Token-mode shims — retained as dependency endpoints for byte-identical token behaviour.
  public var loadToken: @Sendable () -> String? = { nil }
  public var saveToken: @Sendable (_ token: String) throws -> Void
  public var deleteToken: @Sendable () throws -> Void
}

public enum KeychainError: Error, Equatable, Sendable {
  case unhandled(OSStatus)
}

private func serverAccount(for id: String) -> String { "session-\(id)" }

public extension KeychainClient {
  /// Keychain-backed implementation (generic password item).
  static func live(
    service: String = "dev.honcharenko.HermesMobile",
    account: String = "session-token"
  ) -> KeychainClient {
    // Capture only the Sendable strings; build the (non-Sendable) query dicts inside
    // each closure so nothing non-Sendable crosses the @Sendable boundary.
    @Sendable func loadAccount(_ account: String, _ storage: HTTPCookieStorage) -> AuthSession? {
      let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account,
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne,
      ]
      var item: CFTypeRef?
      guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
            let data = item as? Data
      else { return nil }
      guard let session = decodeSession(data) else { return nil }
      rehydrate(session, into: storage)
      return session
    }
    @Sendable func saveAccount(_ account: String, _ session: AuthSession) throws {
      let data = try JSONEncoder().encode(session)
      let identity: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account,
      ]
      SecItemDelete(identity as CFDictionary) // upsert: clear any existing item first
      var add = identity
      add[kSecValueData as String] = data
      add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
      let status = SecItemAdd(add as CFDictionary, nil)
      guard status == errSecSuccess else { throw KeychainError.unhandled(status) }
    }
    @Sendable func deleteAccount(_ account: String) throws {
      let identity: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account,
      ]
      let status = SecItemDelete(identity as CFDictionary)
      guard status == errSecSuccess || status == errSecItemNotFound else {
        throw KeychainError.unhandled(status)
      }
    }
    @Sendable func load(_ storage: HTTPCookieStorage) -> AuthSession? {
      loadAccount(account, storage)
    }
    @Sendable func save(_ session: AuthSession) throws {
      try saveAccount(account, session)
    }
    @Sendable func delete() throws {
      try deleteAccount(account)
      // Flush gated-session cookies rehydrated into the shared jar (where the REST/WS live
      // transports read them) so logout leaves nothing behind for the next user.
      clearSharedCookies()
    }
    return KeychainClient(
      loadSession: { load($0) },
      saveSession: { try save($0) },
      deleteSession: { try delete() },
      loadSessionForServer: { id, storage in loadAccount(serverAccount(for: id), storage) },
      saveSessionForServer: { id, session in try saveAccount(serverAccount(for: id), session) },
      deleteSessionForServer: { id in try deleteAccount(serverAccount(for: id)) },
      activateCookieSession: { activateSharedCookieSession($0) },
      loadToken: { load(.shared)?.token },
      saveToken: { try save(.token($0)) },
      deleteToken: { try delete() }
    )
  }

  /// Deterministic in-memory store for previews and tests.
  static func inMemory() -> KeychainClient {
    let box = SessionBox()
    @Sendable func load(_ storage: HTTPCookieStorage) -> AuthSession? {
      guard let session = box.getLegacy() else { return nil }
      rehydrate(session, into: storage)
      return session
    }
    @Sendable func loadForServer(_ id: String, _ storage: HTTPCookieStorage) -> AuthSession? {
      guard let session = box.getServer(id) else { return nil }
      rehydrate(session, into: storage)
      return session
    }
    return KeychainClient(
      loadSession: { load($0) },
      saveSession: { box.setLegacy($0) },
      deleteSession: { box.setLegacy(nil) },
      loadSessionForServer: { id, storage in loadForServer(id, storage) },
      saveSessionForServer: { id, session in box.setServer(id, session) },
      deleteSessionForServer: { id in box.setServer(id, nil) },
      // No-op for the in-memory variant: feature tests don't drive the live `.shared` jar, and
      // mutating the process-global jar here would race across parallel suites. Tests that
      // need to assert activation override this endpoint with a spy.
      activateCookieSession: { _ in },
      loadToken: { box.getLegacy()?.token },
      saveToken: { box.setLegacy(.token($0)) },
      deleteToken: { box.setLegacy(nil) }
    )
  }
}

/// Rehydrate a freshly-captured `.cookie` session into `HTTPCookieStorage.shared` (flushing
/// any prior cookies first) so the live REST/WS transports authenticate immediately after an
/// in-app login — not just on the next launch.
func activateSharedCookieSession(_ session: CookieSession) {
  clearSharedCookies()
  rehydrate(.cookie(session), into: .shared)
}

/// Remove every cookie from `HTTPCookieStorage.shared` — the jar the live REST/WS transports
/// read (and into which a `.cookie` session is rehydrated). Called on session deletion so a
/// gated logout leaves no cookie behind. (We own the shared jar in this app — no third-party
/// cookies share it — so clearing all of them is safe and avoids domain-matching guesswork.)
func clearSharedCookies() {
  let storage = HTTPCookieStorage.shared
  for cookie in storage.cookies ?? [] { storage.deleteCookie(cookie) }
}

/// Decode a persisted `AuthSession`. Falls back to treating a legacy raw-string payload
/// (a bare token written by older builds) as `.token` so existing installs keep working.
private func decodeSession(_ data: Data) -> AuthSession? {
  if let session = try? JSONDecoder().decode(AuthSession.self, from: data) {
    return session
  }
  if let token = String(data: data, encoding: .utf8), !token.isEmpty {
    return .token(token)
  }
  return nil
}

/// Rehydrate a `.cookie` session's cookies into the cookie storage so the transports
/// authenticate on a fresh launch. `.token` sessions need no cookie work.
private func rehydrate(_ session: AuthSession, into storage: HTTPCookieStorage) {
  guard case let .cookie(cookieSession) = session else { return }
  for cookie in cookieSession.cookies.compactMap(\.httpCookie) {
    storage.setCookie(cookie)
  }
}

extension KeychainClient: DependencyKey {
  public static var liveValue: KeychainClient { .live() }
  // Feature tests get a working in-memory store by default (deterministic, isolated).
  public static var testValue: KeychainClient { .inMemory() }
}

public extension DependencyValues {
  var keychain: KeychainClient {
    get { self[KeychainClient.self] }
    set { self[KeychainClient.self] = newValue }
  }
}

/// Lock-guarded box backing the in-memory keychain.
private final class SessionBox: @unchecked Sendable {
  private let lock = NSLock()
  private var legacy: AuthSession?
  private var perServer: [String: AuthSession] = [:]
  func getLegacy() -> AuthSession? { lock.withLock { legacy } }
  func setLegacy(_ newValue: AuthSession?) { lock.withLock { legacy = newValue } }
  func getServer(_ id: String) -> AuthSession? { lock.withLock { perServer[id] } }
  func setServer(_ id: String, _ newValue: AuthSession?) {
    lock.withLock {
      if let newValue { perServer[id] = newValue } else { perServer.removeValue(forKey: id) }
    }
  }
}
