import Foundation

/// A skill as returned by `GET /api/skills` (dashboard management API).
/// Decoded leniently — only `name` is required.
public struct Skill: Equatable, Sendable, Identifiable, Decodable {
  public var name: String
  public var description: String?
  public var category: String?
  public var enabled: Bool?

  public var id: String { name }

  public init(
    name: String,
    description: String? = nil,
    category: String? = nil,
    enabled: Bool? = nil
  ) {
    self.name = name
    self.description = description
    self.category = category
    self.enabled = enabled
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    name = (try? c.decode(String.self, forKey: .name)) ?? ""
    description = try? c.decodeIfPresent(String.self, forKey: .description)
    category = try? c.decodeIfPresent(String.self, forKey: .category)
    enabled = try? c.decodeIfPresent(Bool.self, forKey: .enabled)
  }

  enum CodingKeys: String, CodingKey {
    case name, description, category, enabled
  }

  public var isEnabled: Bool { enabled ?? true }
}

/// A hub search hit from `GET /api/skills/hub/search`.
public struct SkillHubHit: Equatable, Sendable, Identifiable, Decodable {
  public var name: String
  public var description: String?
  public var source: String?
  public var installed: Bool?

  public var id: String { [source, name].compactMap { $0 }.joined(separator: "/") }

  public init(
    name: String,
    description: String? = nil,
    source: String? = nil,
    installed: Bool? = nil
  ) {
    self.name = name
    self.description = description
    self.source = source
    self.installed = installed
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    name = (try? c.decode(String.self, forKey: .name))
      ?? (try? c.decode(String.self, forKey: .id))
      ?? ""
    description = try? c.decodeIfPresent(String.self, forKey: .description)
    source = try? c.decodeIfPresent(String.self, forKey: .source)
    installed = try? c.decodeIfPresent(Bool.self, forKey: .installed)
  }

  enum CodingKeys: String, CodingKey {
    case name, description, source, installed, id
  }
}

/// Background action status from `GET /api/actions/{name}/status`.
public struct DashboardActionStatus: Equatable, Sendable, Decodable {
  public var name: String?
  public var status: String?
  public var error: String?
  public var result: JSONValue?

  public init(
    name: String? = nil,
    status: String? = nil,
    error: String? = nil,
    result: JSONValue? = nil
  ) {
    self.name = name
    self.status = status
    self.error = error
    self.result = result
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    name = try? c.decodeIfPresent(String.self, forKey: .name)
    status = try? c.decodeIfPresent(String.self, forKey: .status)
      ?? c.decodeIfPresent(String.self, forKey: .state)
    error = try? c.decodeIfPresent(String.self, forKey: .error)
      ?? c.decodeIfPresent(String.self, forKey: .detail)
    result = try? c.decodeIfPresent(JSONValue.self, forKey: .result)
  }

  enum CodingKeys: String, CodingKey {
    case name, status, state, error, detail, result
  }

  public var isTerminal: Bool {
    switch status?.lowercased() {
    case "done", "completed", "success", "failed", "error", "cancelled": true
    default: false
    }
  }

  public var isFailed: Bool {
    switch status?.lowercased() {
    case "failed", "error": true
    default: error?.isEmpty == false
    }
  }
}
