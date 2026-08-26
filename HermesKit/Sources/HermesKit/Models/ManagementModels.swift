import Foundation

/// Device-local saved dashboard server (non-secret). Auth lives in Keychain keyed by `id`.
public struct SavedServer: Equatable, Sendable, Identifiable, Codable {
  public var id: String
  public var label: String
  public var baseURL: String

  public init(id: String = UUID().uuidString, label: String, baseURL: String) {
    self.id = id
    self.label = label
    self.baseURL = baseURL
  }

  public var displayLabel: String {
    let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? baseURL : trimmed
  }
}

/// Curated config keys editable from Settings “Quick edits”.
public enum ConfigQuickEditKey: String, CaseIterable, Sendable, Equatable {
  case modelDefault = "model.default"
  case modelProvider = "model.provider"
  case approvalsMode = "approvals.mode"
  case agentApprovalMode = "agent.approval_mode"
  case displayShowCost = "display.show_cost"
  case displayShowReasoning = "display.show_reasoning"
  case displayStreaming = "display.streaming"
  case agentMaxTurns = "agent.max_turns"
  case agentMaxIterations = "agent.max_iterations"

  public var section: String {
    switch self {
    case .modelDefault, .modelProvider: "Model"
    case .approvalsMode, .agentApprovalMode: "Approvals"
    case .displayShowCost, .displayShowReasoning, .displayStreaming: "Display"
    case .agentMaxTurns, .agentMaxIterations: "Agent"
    }
  }

  public var title: String {
    switch self {
    case .modelDefault: "Default model"
    case .modelProvider: "Provider"
    case .approvalsMode, .agentApprovalMode: "Approval mode"
    case .displayShowCost: "Show cost"
    case .displayShowReasoning: "Show reasoning"
    case .displayStreaming: "Streaming"
    case .agentMaxTurns: "Max turns"
    case .agentMaxIterations: "Max iterations"
    }
  }

  public var isBoolean: Bool {
    switch self {
    case .displayShowCost, .displayShowReasoning, .displayStreaming: true
    default: false
    }
  }
}

/// Helpers for reading/writing nested dashboard config JSON without a YAML editor.
public enum AgentConfigDocument {
  /// Walk a dotted path (`model.default`) into a nested `JSONValue` object tree.
  public static func value(at path: String, in root: JSONValue) -> JSONValue? {
    let parts = path.split(separator: ".").map(String.init)
    var current: JSONValue? = root
    for part in parts {
      guard let next = current?[part] else { return nil }
      current = next
    }
    return current
  }

  /// Set a dotted path on a mutable object tree; creates intermediate objects as needed.
  public static func set(_ path: String, value: JSONValue, on root: inout JSONValue) {
    let parts = path.split(separator: ".").map(String.init)
    guard !parts.isEmpty else { return }
    set(parts, value: value, on: &root)
  }

  private static func set(_ parts: [String], value: JSONValue, on node: inout JSONValue) {
    guard let head = parts.first else { return }
    if parts.count == 1 {
      var obj = node.objectDictionary ?? [:]
      obj[head] = value
      node = .object(obj)
      return
    }
    var obj = node.objectDictionary ?? [:]
    var child = obj[head] ?? .object([:])
    set(Array(parts.dropFirst()), value: value, on: &child)
    obj[head] = child
    node = .object(obj)
  }

  /// Keys from `ConfigQuickEditKey` that are present (or have a parent object) in `root`.
  public static func availableQuickEditKeys(in root: JSONValue) -> [ConfigQuickEditKey] {
    ConfigQuickEditKey.allCases.filter { key in
      if value(at: key.rawValue, in: root) != nil { return true }
      // Parent section exists (e.g. `display` object) — offer the curated key.
      let parent = key.rawValue.split(separator: ".").first.map(String.init) ?? ""
      return root[parent] != nil
    }
  }
}

private extension JSONValue {
  var objectDictionary: [String: JSONValue]? {
    if case .object(let o) = self { return o }
    return nil
  }
}
