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
  /// Process still running (gateway/ops/update action poller).
  public var running: Bool?
  public var exitCode: Int?
  public var pid: Int?
  public var lines: [String]?
  /// Compact receipt summary when attached (hermes-update after dashboard restart).
  public var receiptOutcome: String?
  public var receiptExitCode: Int?

  public init(
    name: String? = nil,
    status: String? = nil,
    error: String? = nil,
    result: JSONValue? = nil,
    running: Bool? = nil,
    exitCode: Int? = nil,
    pid: Int? = nil,
    lines: [String]? = nil,
    receiptOutcome: String? = nil,
    receiptExitCode: Int? = nil
  ) {
    self.name = name
    self.status = status
    self.error = error
    self.result = result
    self.running = running
    self.exitCode = exitCode
    self.pid = pid
    self.lines = lines
    self.receiptOutcome = receiptOutcome
    self.receiptExitCode = receiptExitCode
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    name = try? c.decodeIfPresent(String.self, forKey: .name)
    status = try? c.decodeIfPresent(String.self, forKey: .status)
      ?? c.decodeIfPresent(String.self, forKey: .state)
    error = try? c.decodeIfPresent(String.self, forKey: .error)
      ?? c.decodeIfPresent(String.self, forKey: .detail)
    result = try? c.decodeIfPresent(JSONValue.self, forKey: .result)
    running = try? c.decodeIfPresent(Bool.self, forKey: .running)
    exitCode = try? c.decodeIfPresent(Int.self, forKey: .exitCode)
    pid = try? c.decodeIfPresent(Int.self, forKey: .pid)
    lines = try? c.decodeIfPresent([String].self, forKey: .lines)
    if let receipt = try? c.decodeIfPresent(ReceiptSummary.self, forKey: .receipt)
      ?? c.decodeIfPresent(ReceiptSummary.self, forKey: .receiptSummary)
    {
      receiptOutcome = receipt.outcome
      receiptExitCode = receipt.exitCode
    }
  }

  enum CodingKeys: String, CodingKey {
    case name, status, state, error, detail, result, running, pid, lines, receipt
    case exitCode = "exit_code"
    case receiptSummary = "receipt_summary"
  }

  private struct ReceiptSummary: Decodable {
    var outcome: String?
    var exitCode: Int?

    init(from decoder: Decoder) throws {
      let c = try decoder.container(keyedBy: CodingKeys.self)
      outcome = try? c.decodeIfPresent(String.self, forKey: .outcome)
      exitCode = try? c.decodeIfPresent(Int.self, forKey: .exitCode)
    }

    enum CodingKeys: String, CodingKey {
      case outcome
      case exitCode = "exit_code"
    }
  }

  public var isTerminal: Bool {
    if running == false { return true }
    if let exitCode { return true }
    if receiptExitCode != nil { return true }
    switch status?.lowercased() {
    case "done", "completed", "success", "failed", "error", "cancelled": true
    default: false
    }
  }

  public var isFailed: Bool {
    if let code = exitCode ?? receiptExitCode, code != 0 { return true }
    switch (receiptOutcome)?.lowercased() {
    case "failed", "error", "partial": return true
    default: break
    }
    switch status?.lowercased() {
    case "failed", "error": true
    default: error?.isEmpty == false
    }
  }

  /// Success for process-style polls (`running: false` + exit 0) or Skills status strings.
  public var isSuccessful: Bool {
    if isFailed { return false }
    if let code = exitCode ?? receiptExitCode { return code == 0 }
    switch (receiptOutcome ?? status)?.lowercased() {
    case "done", "completed", "success", "ok": true
    default: running == false && error == nil
    }
  }
}
