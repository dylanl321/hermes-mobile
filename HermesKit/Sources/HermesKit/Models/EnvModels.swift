import Foundation

/// One catalog entry from `GET /api/env` (dashboard Keys / `.env` surface).
/// Decoded leniently — only the key name is required; unknown fields are ignored.
public struct EnvVarEntry: Equatable, Sendable, Identifiable {
  public var key: String
  public var isSet: Bool
  public var redactedValue: String?
  public var description: String
  public var url: String?
  public var category: String
  public var isPassword: Bool
  public var tools: [String]
  public var advanced: Bool

  public var id: String { key }

  public init(
    key: String,
    isSet: Bool = false,
    redactedValue: String? = nil,
    description: String = "",
    url: String? = nil,
    category: String = "",
    isPassword: Bool = false,
    tools: [String] = [],
    advanced: Bool = false
  ) {
    self.key = key
    self.isSet = isSet
    self.redactedValue = redactedValue
    self.description = description
    self.url = url
    self.category = category
    self.isPassword = isPassword
    self.tools = tools
    self.advanced = advanced
  }

  /// Display section title — blank / missing category → "Other".
  public var categoryTitle: String {
    let trimmed = category.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "Other" : trimmed
  }
}

/// Payload fields for a single env var inside the keyed `GET /api/env` object.
struct EnvVarPayload: Equatable, Sendable, Decodable {
  var isSet: Bool?
  var redactedValue: String?
  var description: String?
  var url: String?
  var category: String?
  var isPassword: Bool?
  var tools: [String]?
  var advanced: Bool?

  enum CodingKeys: String, CodingKey {
    case isSet = "is_set"
    case redactedValue = "redacted_value"
    case description
    case url
    case category
    case isPassword = "is_password"
    case password
    case tools
    case advanced
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    isSet = try? c.decodeIfPresent(Bool.self, forKey: .isSet)
    redactedValue = try? c.decodeIfPresent(String.self, forKey: .redactedValue)
    description = try? c.decodeIfPresent(String.self, forKey: .description)
    url = try? c.decodeIfPresent(String.self, forKey: .url)
    category = try? c.decodeIfPresent(String.self, forKey: .category)
    // Dashboard uses both `is_password` and legacy `password`.
    isPassword = (try? c.decodeIfPresent(Bool.self, forKey: .isPassword))
      ?? (try? c.decodeIfPresent(Bool.self, forKey: .password))
    tools = try? c.decodeIfPresent([String].self, forKey: .tools)
    advanced = try? c.decodeIfPresent(Bool.self, forKey: .advanced)
  }
}

/// `GET /api/env` returns a keyed object `{ "VAR_NAME": { is_set, redacted_value, … }, … }`.
struct EnvCatalogResponse: Equatable, Sendable, Decodable {
  var entries: [EnvVarEntry]

  init(entries: [EnvVarEntry]) {
    self.entries = entries
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let dict = try container.decode([String: EnvVarPayload].self)
    entries = dict.map { key, payload in
      EnvVarEntry(
        key: key,
        isSet: payload.isSet ?? false,
        redactedValue: payload.redactedValue,
        description: payload.description ?? "",
        url: payload.url,
        category: payload.category ?? "",
        isPassword: payload.isPassword ?? false,
        tools: payload.tools ?? [],
        advanced: payload.advanced ?? false
      )
    }
    .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
  }
}

/// `POST /api/env/reveal` → `{ "key", "value" }`.
struct EnvRevealResponse: Equatable, Sendable, Decodable {
  var key: String?
  var value: String

  enum CodingKeys: String, CodingKey {
    case key, value
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    key = try? c.decodeIfPresent(String.self, forKey: .key)
    // Prefer `value`; tolerate a missing field as empty rather than crashing decode.
    value = (try? c.decode(String.self, forKey: .value)) ?? ""
  }
}

extension RESTError {
  /// Reveal-specific soft-gate: agent refuses plaintext (SPA-only token, missing route).
  public var isRevealDeniedVerdict: Bool {
    switch self {
    case .unauthorized, .notFound: true
    case .server(status: 401, _), true
    case .server(status: 403, _), true
    case .server(status: 404, _), true
    case .server(status: 405, detail: _): true
    default: false
    }
  }
}
