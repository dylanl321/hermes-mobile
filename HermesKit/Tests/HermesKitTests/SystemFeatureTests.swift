import ComposableArchitecture
import Foundation
import Testing

@testable import HermesKit

@MainActor
struct SystemFeatureTests {
  private let connection = ServerConnection(
    baseURL: URL(string: "http://example.test")!,
    token: "tok"
  )

  @Test func taskLoadsStatsAndUpdateCheck() async {
    let store = TestStore(
      initialState: SystemFeature.State(connection: connection)
    ) {
      SystemFeature()
    } withDependencies: {
      $0.hermesREST.systemStats = { @Sendable _ in
        SystemStats(os: "Linux", hermesVersion: "0.20.0")
      }
      $0.hermesREST.status = { @Sendable _ in
        ServerStatus(version: "0.20.0", gatewayState: "running")
      }
      $0.hermesREST.hermesUpdateCheck = { @Sendable _, _ in
        HermesUpdateCheck(installMethod: "git", behind: 0, updateAvailable: false, canApply: true)
      }
    }

    store.exhaustivity = .off
    await store.send(.task) {
      $0.isLoading = true
      $0.isCheckingUpdate = true
    }
    await store.skipReceivedActions(strict: false)
    #expect(store.state.stats?.os == "Linux")
    #expect(store.state.serverStatus?.gatewayState == "running")
    #expect(store.state.updateCheck?.behind == 0)
    #expect(!store.state.isLoading)
    #expect(!store.state.isCheckingUpdate)
  }

  @Test func missingSystemStatsHidesFeature() async {
    let store = TestStore(
      initialState: SystemFeature.State(
        connection: connection,
        updateCheckSupported: false
      )
    ) {
      SystemFeature()
    } withDependencies: {
      $0.hermesREST.systemStats = { @Sendable _ in throw RESTError.notFound }
      $0.hermesREST.status = { @Sendable _ in ServerStatus() }
    }

    await store.send(.task) {
      $0.isLoading = true
      $0.isCheckingUpdate = false
    }
    await store.receive(\.loadFinished) {
      $0.isLoading = false
      $0.systemSupported = false
    }
    await store.receive(\.delegate.systemUnsupported)
  }

  @Test func applyUpdatePollsThenSucceeds() async {
    let clock = TestClock()
    let store = TestStore(
      initialState: SystemFeature.State(
        connection: connection,
        updateCheck: HermesUpdateCheck(
          installMethod: "git", behind: 2, updateAvailable: true, canApply: true
        )
      )
    ) {
      SystemFeature()
    } withDependencies: {
      $0.continuousClock = clock
      $0.hermesREST.hermesUpdate = { @Sendable _ in
        DashboardActionAccepted(ok: true, name: "hermes-update")
      }
      $0.hermesREST.actionStatus = { @Sendable _, _, _ in
        DashboardActionStatus(name: "hermes-update", running: false, exitCode: 0, lines: ["done"])
      }
      $0.hermesREST.hermesUpdateCheck = { @Sendable _, _ in
        HermesUpdateCheck(installMethod: "git", behind: 0, updateAvailable: false, canApply: true)
      }
    }

    store.exhaustivity = .off
    await store.send(.applyUpdateTapped)
    await store.send(.confirmationDialog(.presented(.confirmApplyUpdate))) {
      $0.confirmationDialog = nil
    }
    await store.receive(\.actionStarted) {
      $0.inFlightKind = .update
      $0.inFlightLabel = "Updating Hermes…"
      $0.actionLines = []
    }
    await clock.advance(by: SystemFeature.actionPollInterval)
    await store.receive(\.actionPolled) {
      $0.inFlightKind = nil
      $0.inFlightLabel = nil
      $0.actionLines = ["done"]
      $0.actionMessage = "Finished successfully."
    }
    await store.receive(\.updateCheckFinished.success) {
      $0.updateCheck = HermesUpdateCheck(
        installMethod: "git", behind: 0, updateAvailable: false, canApply: true
      )
    }
  }

  @Test func updatePollInterruptedFallsBackToReceipt() async {
    let clock = TestClock()
    let store = TestStore(
      initialState: SystemFeature.State(
        connection: connection,
        updateCheck: HermesUpdateCheck(
          installMethod: "git", behind: 1, updateAvailable: true, canApply: true
        ),
        inFlightKind: .update,
        inFlightLabel: "Updating Hermes…"
      )
    ) {
      SystemFeature()
    } withDependencies: {
      $0.continuousClock = clock
      $0.hermesREST.hermesUpdateReceipt = { @Sendable _ in
        HermesUpdateReceipt(outcome: "success", exitCode: 0, message: "ok")
      }
      $0.hermesREST.hermesUpdateCheck = { @Sendable _, _ in
        HermesUpdateCheck(installMethod: "git", behind: 0, updateAvailable: false, canApply: true)
      }
    }

    await store.send(.updatePollInterrupted) {
      $0.actionMessage = "Reconnecting to read update receipt…"
    }
    await clock.advance(by: SystemFeature.actionPollInterval)
    await store.receive(\.receiptPolled.success) {
      $0.inFlightKind = nil
      $0.inFlightLabel = nil
      $0.actionMessage = "ok"
      $0.errorBanner = nil
    }
    await store.receive(\.updateCheckFinished.success) {
      $0.updateCheck = HermesUpdateCheck(
        installMethod: "git", behind: 0, updateAvailable: false, canApply: true
      )
    }
  }

  @Test func gatewayRestartMissingEndpointFlipsFlag() async {
    let store = TestStore(
      initialState: SystemFeature.State(connection: connection)
    ) {
      SystemFeature()
    } withDependencies: {
      $0.hermesREST.gatewayLifecycle = { @Sendable _, _ in throw RESTError.notFound }
    }

    await store.send(.confirmationDialog(.presented(.confirmGatewayRestart))) {
      $0.confirmationDialog = nil
    }
    await store.receive(\.delegate.gatewayUnsupported) {
      $0.gatewaySupported = false
    }
  }

  @Test func opsDoctorPollsToCompletion() async {
    let clock = TestClock()
    let store = TestStore(
      initialState: SystemFeature.State(connection: connection)
    ) {
      SystemFeature()
    } withDependencies: {
      $0.continuousClock = clock
      $0.hermesREST.opsAction = { @Sendable _, action in
        #expect(action == .doctor)
        return DashboardActionAccepted(ok: true, name: "doctor")
      }
      $0.hermesREST.actionStatus = { @Sendable _, name, lines in
        #expect(name == "doctor")
        #expect(lines == SystemFeature.actionLogLineLimit)
        return DashboardActionStatus(running: false, exitCode: 0, lines: ["all good"])
      }
    }

    await store.send(.opsTapped(.doctor))
    await store.receive(\.actionStarted) {
      $0.inFlightKind = .ops(.doctor)
      $0.inFlightLabel = "Doctor…"
    }
    await clock.advance(by: SystemFeature.actionPollInterval)
    await store.receive(\.actionPolled) {
      $0.inFlightKind = nil
      $0.inFlightLabel = nil
      $0.actionLines = ["all good"]
      $0.actionMessage = "Finished successfully."
    }
  }

  @Test func dismissBootWarningKeysOnBootId() async {
    let store = TestStore(
      initialState: SystemFeature.State(
        connection: connection,
        serverStatus: ServerStatus(
          memory: ResourcePressure(bootId: "boot-9", lastBootSuspectedOom: true)
        )
      )
    ) {
      SystemFeature()
    }

    #expect(store.state.bootWarningText != nil)
    await store.send(.dismissBootWarning) {
      $0.dismissedBootId = "boot-9"
    }
    #expect(store.state.bootWarningText == nil)
  }
}
