import ComposableArchitecture
import HermesKit
import SnapshotTesting
import SwiftUI
import XCTest

@testable import HermesMobile

final class SettingsSnapshotTests: SnapshotTestCase {
  /// Pin `envSupported = false` so existing Settings baselines stay stable; API Keys
  /// chrome is covered by `EnvSnapshotTests`.
  private func settingsState(
    connection: ServerConnection? = nil,
    pushAvailable: Bool = true,
    notificationsEnabled: Bool = false,
    notificationsDenied: Bool = false,
    testPushStatus: SettingsFeature.State.TestPushStatus = .idle,
    pushPlugin: PushPluginInfo? = nil,
    pluginUpdate: SettingsFeature.State.PluginUpdateStatus = .idle,
    deleteSupported: Bool = true
  ) -> SettingsFeature.State {
    var state = SettingsFeature.State(
      connection: connection ?? self.connection,
      pushAvailable: pushAvailable,
      notificationsEnabled: notificationsEnabled,
      notificationsDenied: notificationsDenied,
      testPushStatus: testPushStatus,
      pushPlugin: pushPlugin,
      pluginUpdate: pluginUpdate,
      deleteSupported: deleteSupported,
      envSupported: false
    )
    return state
  }

  func testSettingsView() {
    var initial = settingsState()
    initial.log = [
      GatewayLogEntry(id: 0, type: "gateway.ready", summary: ""),
      GatewayLogEntry(id: 1, type: "message.delta", summary: "Here's the gist"),
    ]
    let view = NavigationStack {
      SettingsView(
        store: Store(initialState: initial) { SettingsFeature().ignoring(\.task) } withDependencies: {
          $0.debugLog = .testValue // inert stream for a deterministic render
        }
      )
    }
    assertSnapshot(of: view, as: deviceImage())
  }

  /// Older agent without `DELETE /api/sessions/{id}` — the "Default swipe action" picker
  /// section must be hidden entirely (Archive is the only destructive action, so the
  /// choice would be meaningless). The default-state snapshot above shows it.
  func testSettingsView_deleteUnsupported() {
    var initial = settingsState(deleteSupported: false)
    initial.log = [
      GatewayLogEntry(id: 0, type: "gateway.ready", summary: ""),
      GatewayLogEntry(id: 1, type: "message.delta", summary: "Here's the gist"),
    ]
    let view = NavigationStack {
      SettingsView(
        store: Store(initialState: initial) { SettingsFeature().ignoring(\.task) } withDependencies: {
          $0.debugLog = .testValue // inert stream for a deterministic render
        }
      )
    }
    assertSnapshot(of: view, as: deviceImage())
  }

  /// Notifications enabled: toggle on, push available, no test sent yet.
  ///
  /// The three Notifications-focused fixtures hide the (unrelated) "Session list" swipe
  /// section: it sits above Notifications, and with it present the rows these snapshots
  /// exist to prove — the test-sent label especially — fall below the device fold.
  func testSettingsNotificationsEnabled() {
    let initial = settingsState(
      pushAvailable: true,
      notificationsEnabled: true,
      deleteSupported: false
    )
    let view = NavigationStack {
      SettingsView(
        store: Store(initialState: initial) { SettingsFeature().ignoring(\.task) } withDependencies: {
          $0.debugLog = .testValue
          $0.push = PushClient.inMemory(granted: true, status: .authorized).client
        }
      )
    }
    assertSnapshot(of: view, as: deviceImage())
  }

  /// Push not available on this server (plugin missing) → "not available" note, no controls.
  func testSettingsNotificationsUnavailable() {
    let initial = settingsState(
      pushAvailable: false,
      deleteSupported: false
    )
    let view = NavigationStack {
      SettingsView(
        store: Store(initialState: initial) { SettingsFeature().ignoring(\.task) } withDependencies: {
          $0.debugLog = .testValue
          $0.push = PushClient.inMemory(granted: false, status: .notDetermined).client
        }
      )
    }
    assertSnapshot(of: view, as: deviceImage())
  }

  /// Test notification just sent → confirmation label.
  func testSettingsNotificationsTestSent() {
    let initial = settingsState(
      pushAvailable: true,
      notificationsEnabled: true,
      testPushStatus: .sent,
      deleteSupported: false
    )
    let view = NavigationStack {
      SettingsView(
        store: Store(initialState: initial) { SettingsFeature().ignoring(\.task) } withDependencies: {
          $0.debugLog = .testValue
          $0.push = PushClient.inMemory(granted: true, status: .authorized).client
        }
      )
    }
    assertSnapshot(of: view, as: deviceImage())
  }

  /// An outdated, git-updatable plugin → the update row with the one-tap button.
  func testSettingsPluginUpdateAvailable() {
    let initial = settingsState(
      pushAvailable: true,
      notificationsEnabled: true,
      pushPlugin: PushPluginInfo(status: .ready, version: "0.1.0", canUpdateGit: true)
    )
    let view = NavigationStack {
      SettingsView(
        store: Store(initialState: initial) { SettingsFeature().ignoring(\.task) } withDependencies: {
          $0.debugLog = .testValue
          $0.push = PushClient.inMemory(granted: true, status: .authorized).client
        }
      )
    }
    assertSnapshot(of: view, as: deviceImage())
  }

  /// After a successful pull — the RESTART notice, which is the whole point of that state.
  func testSettingsPluginUpdatedNeedsRestart() {
    let initial = settingsState(
      pushAvailable: true,
      notificationsEnabled: true,
      pushPlugin: PushPluginInfo(status: .ready, version: "0.1.0", canUpdateGit: true),
      pluginUpdate: .updated
    )
    let view = NavigationStack {
      SettingsView(
        store: Store(initialState: initial) { SettingsFeature().ignoring(\.task) } withDependencies: {
          $0.debugLog = .testValue
          $0.push = PushClient.inMemory(granted: true, status: .authorized).client
        }
      )
    }
    assertSnapshot(of: view, as: deviceImage())
  }

  /// Outdated but not a git checkout → no button, pointer to the guide instead.
  func testSettingsPluginUpdateNeedsManualSteps() {
    let initial = settingsState(
      pushAvailable: true,
      notificationsEnabled: true,
      pushPlugin: PushPluginInfo(status: .ready, version: "0.1.0", canUpdateGit: false)
    )
    let view = NavigationStack {
      SettingsView(
        store: Store(initialState: initial) { SettingsFeature().ignoring(\.task) } withDependencies: {
          $0.debugLog = .testValue
          $0.push = PushClient.inMemory(granted: true, status: .authorized).client
        }
      )
    }
    assertSnapshot(of: view, as: deviceImage())
  }

  /// The "how push works" info sheet, plugin NOT installed — install action + Later snooze.
  func testPushSetupGuideView() {
    let view = PushSetupGuideView(pluginInstalled: false, onAskAgent: {}, onLater: {})
    assertSnapshot(of: view, as: deviceImage())
  }

  /// Plugin already installed — the action becomes "update" and the Later snooze drops away
  /// (there is no nag to snooze; the sheet was opened deliberately from Settings).
  func testPushSetupGuideView_installed() {
    let view = PushSetupGuideView(pluginInstalled: true, onAskAgent: {}, onLater: {})
    assertSnapshot(of: view, as: deviceImage())
  }

  func testConnectionDebugView() {
    let view = NavigationStack {
      ConnectionDebugView(entries: [
        GatewayLogEntry(id: 0, type: "gateway.ready", summary: ""),
        GatewayLogEntry(id: 1, type: "tool.start", summary: "read_file"),
        GatewayLogEntry(id: 2, type: "message.delta", summary: "WebSocket JSON-RPC at /api/ws"),
        GatewayLogEntry(id: 3, type: "status.update", summary: "[lifecycle] thinking…"),
      ])
    }
    assertSnapshot(of: view, as: deviceImage())
  }
}
