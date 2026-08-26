import ComposableArchitecture
import Foundation

@testable import HermesKit

/// Shared assertions for session-list load side effects (ops probes at end of `load()`).
@MainActor
enum SessionListLoadTestSupport {
  /// Default ops probes: empty status + analytics 404 (disables `analyticsSupported`).
  static func receiveOpsProbes<State, Action>(
    _ store: TestStore<State, Action>,
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    line: UInt = #line,
    column: UInt = #column
  ) async where State == SessionListFeature.State, Action == SessionListFeature.Action {
    await store.receive(\.serverStatusResponse.success, fileID: fileID, filePath: filePath, line: line, column: column)
    await store.receive(\.usageAnalyticsResponse.failure, fileID: fileID, filePath: filePath, line: line, column: column) {
      $0.analyticsSupported = false
    }
  }
}
