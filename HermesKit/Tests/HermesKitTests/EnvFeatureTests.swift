import ComposableArchitecture
import Foundation
import Testing

@testable import HermesKit

@MainActor
struct EnvFeatureTests {
  private let connection = ServerConnection(
    baseURL: URL(string: "http://test.local:9119")!,
    token: "tok"
  )

  private let sampleEntries = [
    EnvVarEntry(
      key: "OPENROUTER_API_KEY",
      isSet: true,
      redactedValue: "sk-…abcd",
      description: "OpenRouter",
      category: "LLM Providers",
      isPassword: true
    ),
    EnvVarEntry(
      key: "RARE_FLAG",
      isSet: false,
      description: "Advanced only",
      category: "Agent Settings",
      advanced: true
    ),
  ]

  @Test func taskLoadsCatalog() async {
    let store = TestStore(
      initialState: EnvFeature.State(connection: connection)
    ) {
      EnvFeature()
    } withDependencies: {
      $0.hermesREST.env = { @Sendable _, _ in
        [
          EnvVarEntry(key: "OPENROUTER_API_KEY", isSet: true, redactedValue: "sk-…abcd"),
          EnvVarEntry(key: "TAVILY_API_KEY", isSet: false),
        ]
      }
    }

    await store.send(.task) { $0.isLoading = true }
    await store.receive(\.envResponse.success) {
      $0.isLoading = false
      $0.envSupported = true
      $0.entries = [
        EnvVarEntry(key: "OPENROUTER_API_KEY", isSet: true, redactedValue: "sk-…abcd"),
        EnvVarEntry(key: "TAVILY_API_KEY", isSet: false),
      ]
    }
  }

  @Test func missingEndpointFlipsCapabilityOff() async {
    let store = TestStore(
      initialState: EnvFeature.State(connection: connection)
    ) {
      EnvFeature()
    } withDependencies: {
      $0.hermesREST.env = { @Sendable _, _ in throw RESTError.notFound }
    }

    await store.send(.task) { $0.isLoading = true }
    await store.receive(\.envResponse.failure) {
      $0.isLoading = false
      $0.envSupported = false
      $0.entries = []
    }
    await store.receive(\.delegate.envUnsupported)
  }

  @Test func emptySaveIsNoOp() async {
    let putCalled = LockIsolated(false)
    var state = EnvFeature.State(connection: connection, entries: IdentifiedArray(uniqueElements: sampleEntries))
    state.edit = EnvFeature.EditState(entry: sampleEntries[0], draftValue: "")
    let store = TestStore(initialState: state) {
      EnvFeature()
    } withDependencies: {
      $0.hermesREST.putEnv = { @Sendable _, _, _, _ in putCalled.setValue(true) }
    }

    await store.send(.saveTapped)
    #expect(putCalled.value == false)
  }

  @Test func savePutsValueThenReloadsAndClearsEdit() async {
    let put = LockIsolated<(String, String)?>(nil)
    var state = EnvFeature.State(connection: connection, entries: IdentifiedArray(uniqueElements: sampleEntries))
    state.edit = EnvFeature.EditState(entry: sampleEntries[0], draftValue: "secret-value")
    let store = TestStore(initialState: state) {
      EnvFeature()
    } withDependencies: {
      $0.hermesREST.putEnv = { @Sendable _, key, value, _ in
        put.setValue((key, value))
      }
      $0.hermesREST.env = { @Sendable _, _ in
        [EnvVarEntry(key: "OPENROUTER_API_KEY", isSet: true, redactedValue: "sk-…zzzz")]
      }
    }

    await store.send(.saveTapped) {
      $0.isSaving = true
    }
    await store.receive(\.saveFinished.success) {
      $0.isSaving = false
      $0.edit = nil
      $0.isLoading = true
    }
    await store.receive(\.envResponse.success) {
      $0.isLoading = false
      $0.entries = [
        EnvVarEntry(key: "OPENROUTER_API_KEY", isSet: true, redactedValue: "sk-…zzzz"),
      ]
    }
    #expect(put.value?.0 == "OPENROUTER_API_KEY")
    #expect(put.value?.1 == "secret-value")
  }

  @Test func revealUnauthorizedDisablesReveal() async {
    var state = EnvFeature.State(connection: connection, entries: IdentifiedArray(uniqueElements: sampleEntries))
    state.edit = EnvFeature.EditState(entry: sampleEntries[0])
    let store = TestStore(initialState: state) {
      EnvFeature()
    } withDependencies: {
      $0.hermesREST.revealEnv = { @Sendable _, _, _ in throw RESTError.unauthorized }
    }

    await store.send(.revealTapped) { $0.isRevealing = true }
    await store.receive(\.revealFinished.failure) {
      $0.isRevealing = false
      $0.revealSupported = false
    }
    // Revealed plaintext must not linger.
    #expect(store.state.edit?.revealedValue == nil)
  }

  @Test func revealSuccessStoresValueUntilDismiss() async {
    let clock = TestClock()
    var state = EnvFeature.State(connection: connection, entries: IdentifiedArray(uniqueElements: sampleEntries))
    state.edit = EnvFeature.EditState(entry: sampleEntries[0])
    let store = TestStore(initialState: state) {
      EnvFeature()
    } withDependencies: {
      $0.hermesREST.revealEnv = { @Sendable _, _, _ in "plaintext-secret" }
      $0.continuousClock = clock
    }

    await store.send(.revealTapped) { $0.isRevealing = true }
    await store.receive(\.revealFinished.success) {
      $0.isRevealing = false
      $0.edit?.revealedValue = "plaintext-secret"
    }
    await store.send(.dismissEdit) {
      $0.edit = nil
      $0.isRevealing = false
      $0.isSaving = false
    }
    #expect(store.state.edit == nil)
  }

  @Test func revealAutoClearsAfterDwell() async {
    let clock = TestClock()
    var state = EnvFeature.State(connection: connection, entries: IdentifiedArray(uniqueElements: sampleEntries))
    state.edit = EnvFeature.EditState(entry: sampleEntries[0])
    let store = TestStore(initialState: state) {
      EnvFeature()
    } withDependencies: {
      $0.hermesREST.revealEnv = { @Sendable _, _, _ in "plaintext-secret" }
      $0.continuousClock = clock
    }

    await store.send(.revealTapped) { $0.isRevealing = true }
    await store.receive(\.revealFinished.success) {
      $0.isRevealing = false
      $0.edit?.revealedValue = "plaintext-secret"
    }
    await clock.advance(by: EnvFeature.revealDwellDuration)
    await store.receive(\.clearRevealedValue) {
      $0.edit?.revealedValue = nil
    }
  }

  @Test func revealRateLimitedSurfacesBanner() async {
    var state = EnvFeature.State(connection: connection, entries: IdentifiedArray(uniqueElements: sampleEntries))
    state.edit = EnvFeature.EditState(entry: sampleEntries[0])
    let store = TestStore(initialState: state) {
      EnvFeature()
    } withDependencies: {
      $0.hermesREST.revealEnv = { @Sendable _, _, _ in
        throw RESTError.server(status: 429, detail: "Too many")
      }
    }

    await store.send(.revealTapped) { $0.isRevealing = true }
    await store.receive(\.revealFinished.failure) {
      $0.isRevealing = false
      $0.errorBanner = "Too many reveal requests. Try again shortly."
    }
  }

  @Test func deleteConfirmsThenReloads() async {
    let deleted = LockIsolated<String?>(nil)
    var state = EnvFeature.State(connection: connection, entries: IdentifiedArray(uniqueElements: sampleEntries))
    state.edit = EnvFeature.EditState(entry: sampleEntries[0])
    let store = TestStore(initialState: state) {
      EnvFeature()
    } withDependencies: {
      $0.hermesREST.deleteEnv = { @Sendable _, key, _ in deleted.setValue(key) }
      $0.hermesREST.env = { @Sendable _, _ in
        [EnvVarEntry(key: "RARE_FLAG", isSet: false, advanced: true)]
      }
    }

    await store.send(.deleteTapped) {
      $0.confirmationDialog = ConfirmationDialogState {
        TextState("Delete OPENROUTER_API_KEY?")
      } actions: {
        ButtonState(role: .destructive, action: .confirmDelete(key: "OPENROUTER_API_KEY")) {
          TextState("Delete")
        }
        ButtonState(role: .cancel) {
          TextState("Cancel")
        }
      } message: {
        TextState("Removes this variable from the agent’s .env. Running sessions may need a reload or restart to pick up the change.")
      }
    }
    await store.send(.confirmationDialog(.presented(.confirmDelete(key: "OPENROUTER_API_KEY")))) {
      $0.confirmationDialog = nil
      $0.isDeleting = true
    }
    await store.receive(\.deleteFinished.success) {
      $0.isDeleting = false
      $0.edit = nil
      $0.isLoading = true
    }
    await store.receive(\.envResponse.success) {
      $0.isLoading = false
      $0.entries = [
        EnvVarEntry(key: "RARE_FLAG", isSet: false, advanced: true),
      ]
    }
    #expect(deleted.value == "OPENROUTER_API_KEY")
  }

  @Test func visibleEntriesHidesAdvancedUntilToggled() {
    let state = EnvFeature.State(
      connection: connection,
      entries: IdentifiedArray(uniqueElements: sampleEntries),
      showAdvanced: false
    )
    #expect(state.visibleEntries.map(\.key) == ["OPENROUTER_API_KEY"])
    var shown = state
    shown.showAdvanced = true
    #expect(shown.visibleEntries.map(\.key) == ["OPENROUTER_API_KEY", "RARE_FLAG"])
  }

  @Test func visibleEntriesSetOnlyAndSearch() {
    let entries = sampleEntries + [
      EnvVarEntry(key: "TAVILY_API_KEY", isSet: false, category: "Tool API Keys"),
    ]
    var state = EnvFeature.State(
      connection: connection,
      entries: IdentifiedArray(uniqueElements: entries),
      showAdvanced: true,
      showSetOnly: true
    )
    #expect(state.visibleEntries.map(\.key) == ["OPENROUTER_API_KEY"])
    state.showSetOnly = false
    state.searchQuery = "tavily"
    #expect(state.visibleEntries.map(\.key) == ["TAVILY_API_KEY"])
  }
}

struct EnvModelTests {
  @Test func catalogDecodesKeyedObject() throws {
    let json = Data(
      #"""
      {
        "OPENROUTER_API_KEY": {
          "is_set": true,
          "redacted_value": "sk-…abcd",
          "description": "OpenRouter key",
          "url": "https://openrouter.ai",
          "category": "LLM Providers",
          "is_password": true,
          "tools": ["chat"],
          "advanced": false,
          "extra": 1
        },
        "API_SERVER_ENABLED": {
          "is_set": false,
          "description": "Enable API",
          "category": "Agent Settings",
          "password": false,
          "advanced": true
        }
      }
      """#.utf8
    )
    let catalog = try JSONDecoder().decode(EnvCatalogResponse.self, from: json)
    #expect(catalog.entries.map(\.key) == ["API_SERVER_ENABLED", "OPENROUTER_API_KEY"])
    let openrouter = try #require(catalog.entries.first { $0.key == "OPENROUTER_API_KEY" })
    #expect(openrouter.isSet)
    #expect(openrouter.redactedValue == "sk-…abcd")
    #expect(openrouter.isPassword)
    #expect(openrouter.categoryTitle == "LLM Providers")
    let flag = try #require(catalog.entries.first { $0.key == "API_SERVER_ENABLED" })
    #expect(!flag.isSet)
    #expect(flag.advanced)
    #expect(!flag.isPassword)
  }

  @Test func revealDeniedVerdicts() {
    #expect(RESTError.unauthorized.isRevealDeniedVerdict)
    #expect(RESTError.notFound.isRevealDeniedVerdict)
    #expect(RESTError.server(status: 403, detail: nil).isRevealDeniedVerdict)
    #expect(RESTError.server(status: 405, detail: nil).isRevealDeniedVerdict)
    #expect(!RESTError.server(status: 500, detail: "boom").isRevealDeniedVerdict)
    #expect(!RESTError.unreachable.isRevealDeniedVerdict)
  }
}
