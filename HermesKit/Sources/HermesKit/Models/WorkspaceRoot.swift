import Foundation

/// A browsable project root derived from session `cwd`s (and optionally the agent’s
/// `default-cwd`). There is no server workspace catalog — the inventory is client-side,
/// matching how the session list groups by workspace.
public struct WorkspaceRoot: Equatable, Sendable, Identifiable {
  /// Absolute path on the agent host (= `id`).
  public var path: String
  /// Folder basename (or the path itself for `/`).
  public var label: String

  public var id: String { path }

  public init(path: String, label: String) {
    self.path = path
    self.label = label
  }

  public init(path: String) {
    let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
    self.path = trimmed
    self.label = SessionGroup.label(forPath: trimmed)
  }

  /// Unique non-empty `cwd`s from `sessions`, in first-seen order, then optionally append
  /// `defaultCwd` when it isn’t already present. Empty / whitespace cwds are skipped
  /// (same rule as the “No workspace” session-list bucket).
  public static func roots(
    from sessions: some Sequence<Session>,
    defaultCwd: String? = nil
  ) -> [WorkspaceRoot] {
    var order: [String] = []
    var seen = Set<String>()

    for session in sessions {
      let path = session.cwd?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      guard !path.isEmpty, !seen.contains(path) else { continue }
      seen.insert(path)
      order.append(path)
    }

    if let raw = defaultCwd?.trimmingCharacters(in: .whitespacesAndNewlines),
      !raw.isEmpty,
      !seen.contains(raw)
    {
      order.append(raw)
    }

    return order.map(WorkspaceRoot.init(path:))
  }
}
