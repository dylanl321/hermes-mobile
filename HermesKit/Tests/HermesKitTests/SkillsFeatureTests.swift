import ComposableArchitecture
import Foundation
import Testing

@testable import HermesKit

@MainActor
struct SkillsFeatureTests {
  private let connection = ServerConnection(
    baseURL: URL(string: "http://test.local:9119")!,
    token: "tok"
  )

  @Test func taskLoadsSkills() async {
    let store = TestStore(
      initialState: SkillsFeature.State(connection: connection)
    ) {
      SkillsFeature()
    } withDependencies: {
      $0.hermesREST.skills = { @Sendable _, _ in
        [
          Skill(name: "web", description: "Browse", enabled: true),
          Skill(name: "code", enabled: false),
        ]
      }
    }

    await store.send(.task) { $0.isLoading = true }
    await store.receive(\.skillsResponse.success) {
      $0.isLoading = false
      $0.skillsSupported = true
      $0.skills = [
        Skill(name: "web", description: "Browse", enabled: true),
        Skill(name: "code", enabled: false),
      ]
    }
  }

  @Test func missingEndpointFlipsCapabilityOff() async {
    let store = TestStore(
      initialState: SkillsFeature.State(connection: connection)
    ) {
      SkillsFeature()
    } withDependencies: {
      $0.hermesREST.skills = { @Sendable _, _ in throw RESTError.notFound }
    }

    await store.send(.task) { $0.isLoading = true }
    await store.receive(\.skillsResponse.failure) {
      $0.isLoading = false
      $0.skillsSupported = false
      $0.skills = []
    }
    await store.receive(\.delegate.skillsUnsupported)
  }

  @Test func toggleSkillOptimisticThenRollbackOnError() async {
    let store = TestStore(
      initialState: SkillsFeature.State(
        connection: connection,
        skills: [Skill(name: "web", enabled: true)]
      )
    ) {
      SkillsFeature()
    } withDependencies: {
      $0.hermesREST.toggleSkill = { @Sendable _, _, _, _ in
        throw RESTError.server(status: 500, detail: "boom")
      }
    }

    await store.send(.toggleSkill(name: "web", enabled: false)) {
      $0.togglingNames = ["web"]
      $0.skills[id: "web"]?.enabled = false
    }
    await store.receive(\.toggleFinished) {
      $0.togglingNames = []
      $0.skills[id: "web"]?.enabled = true
      $0.errorBanner = RESTError.server(status: 500, detail: "boom").message
    }
  }

  @Test func toggleSkillSucceeds() async {
    let toggled = LockIsolated<(String, Bool)?>(nil)
    let store = TestStore(
      initialState: SkillsFeature.State(
        connection: connection,
        skills: [Skill(name: "web", enabled: true)]
      )
    ) {
      SkillsFeature()
    } withDependencies: {
      $0.hermesREST.toggleSkill = { @Sendable _, name, enabled, _ in
        toggled.setValue((name, enabled))
      }
    }

    await store.send(.toggleSkill(name: "web", enabled: false)) {
      $0.togglingNames = ["web"]
      $0.skills[id: "web"]?.enabled = false
    }
    await store.receive(\.toggleFinished) {
      $0.togglingNames = []
    }
    #expect(toggled.value?.0 == "web")
    #expect(toggled.value?.1 == false)
  }
}

struct SkillModelTests {
  @Test func skillDecodesLeniently() throws {
    let json = Data(#"{"name":"web","description":"Browse","enabled":true,"extra":1}"#.utf8)
    let skill = try JSONDecoder().decode(Skill.self, from: json)
    #expect(skill.name == "web")
    #expect(skill.description == "Browse")
    #expect(skill.isEnabled)
  }

  @Test func configQuickEditPaths() {
    var root: JSONValue = .object([
      "model": .object(["default": .string("gpt-4o")]),
      "display": .object(["show_cost": .bool(true)]),
    ])
    #expect(AgentConfigDocument.value(at: "model.default", in: root)?.stringValue == "gpt-4o")
    AgentConfigDocument.set("display.show_reasoning", value: .bool(false), on: &root)
    #expect(AgentConfigDocument.value(at: "display.show_reasoning", in: root)?.boolValue == false)
    let keys = AgentConfigDocument.availableQuickEditKeys(in: root)
    #expect(keys.contains(.modelDefault))
    #expect(keys.contains(.displayShowCost))
  }

  @Test func doneTappedEmitsDismiss() async {
    let store = TestStore(
      initialState: SkillsFeature.State(connection: connection)
    ) {
      SkillsFeature()
    }

    await store.send(.doneTapped)
    await store.receive(\.delegate.dismiss)
  }
}
