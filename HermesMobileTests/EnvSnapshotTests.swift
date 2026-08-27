import ComposableArchitecture
import HermesKit
import SnapshotTesting
import SwiftUI
import XCTest

@testable import HermesMobile

final class EnvSnapshotTests: SnapshotTestCase {
  /// Scrollable list — pin explicit height along the scroll axis so `sizeThatFits`
  /// does not record a blank sliver.
  func testEnvView_catalog() {
    let entries: [EnvVarEntry] = [
      EnvVarEntry(
        key: "OPENROUTER_API_KEY",
        isSet: true,
        redactedValue: "sk-…abcd",
        description: "OpenRouter API key",
        category: "LLM Providers",
        isPassword: true
      ),
      EnvVarEntry(
        key: "TAVILY_API_KEY",
        isSet: false,
        description: "Tavily search",
        category: "Tool API Keys",
        isPassword: true
      ),
      EnvVarEntry(
        key: "API_SERVER_ENABLED",
        isSet: true,
        redactedValue: "true",
        description: "Enable the API server",
        category: "Agent Settings",
        advanced: true
      ),
    ]
    let initial = EnvFeature.State(
      connection: connection,
      entries: IdentifiedArray(uniqueElements: entries),
      showAdvanced: false
    )
    let view = NavigationStack {
      EnvView(
        store: Store(initialState: initial) {
          EnvFeature().ignoring(\.task)
        }
      )
    }
    .frame(width: device.size?.width ?? 390, height: 700)
    .dynamicTypeSize(.large)

    assertSnapshot(of: view, as: componentImage())
  }

  func testEnvView_showAdvanced() {
    let entries: [EnvVarEntry] = [
      EnvVarEntry(
        key: "OPENROUTER_API_KEY",
        isSet: true,
        redactedValue: "sk-…abcd",
        description: "OpenRouter API key",
        category: "LLM Providers",
        isPassword: true
      ),
      EnvVarEntry(
        key: "API_SERVER_ENABLED",
        isSet: true,
        redactedValue: "true",
        description: "Enable the API server",
        category: "Agent Settings",
        advanced: true
      ),
    ]
    let initial = EnvFeature.State(
      connection: connection,
      entries: IdentifiedArray(uniqueElements: entries),
      showAdvanced: true
    )
    let view = NavigationStack {
      EnvView(
        store: Store(initialState: initial) {
          EnvFeature().ignoring(\.task)
        }
      )
    }
    .frame(width: device.size?.width ?? 390, height: 700)
    .dynamicTypeSize(.large)

    assertSnapshot(of: view, as: componentImage())
  }
}
