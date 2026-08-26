import ComposableArchitecture
import Foundation
import Testing

@testable import HermesKit

@MainActor
struct SessionListOpsStripTests {
  private let connection = ServerConnection(baseURL: URL(string: "http://mac.tailnet:9119")!, token: "tok")
  private let now = Date(timeIntervalSince1970: 1_749_600_000)

  @Test func refreshFetchesStatusAndAnalytics() async {
    let store = TestStore(initialState: SessionListFeature.State(connection: connection)) {
      SessionListFeature()
    } withDependencies: {
      $0.date = .constant(now)
      $0.continuousClock = TestClock()
      $0.hermesREST.sessions = { @Sendable _, _, _, _ in [] }
      $0.hermesREST.cronJobs = { @Sendable _, _ in throw RESTError.notFound }
      $0.hermesREST.status = { @Sendable _ in
        ServerStatus(version: "0.16.0", gatewayState: "running", memory: ResourcePressure(pressure: "elevated"))
      }
      $0.hermesREST.usageAnalytics = { @Sendable _, _ in
        UsageAnalytics(totalTokens: 1200, totalCost: 1.5, sessionCount: 2)
      }
    }

    await store.send(.pulledToRefresh) {
      $0.now = self.now
      $0.isLoading = true
    }
    await store.receive(\.sessionsResponse.success) {
      $0.isLoading = false
    }
    await store.receive(\.cronJobsResponse.failure) {
      $0.cronJobsSupported = false
    }
    await store.receive(\.serverStatusResponse.success) {
      $0.serverStatus = ServerStatus(
        version: "0.16.0", gatewayState: "running", memory: ResourcePressure(pressure: "elevated")
      )
    }
    await store.receive(\.usageAnalyticsResponse.success) {
      $0.usageAnalytics = UsageAnalytics(totalTokens: 1200, totalCost: 1.5, sessionCount: 2)
    }
    #expect(store.state.opsStripVisible)
    #expect(store.state.serverStatus?.worstPressure == "elevated")
  }

  @Test func analyticsNotFoundFlipsSupportSilently() async {
    let store = TestStore(initialState: SessionListFeature.State(connection: connection)) {
      SessionListFeature()
    } withDependencies: {
      $0.date = .constant(now)
      $0.continuousClock = TestClock()
      $0.hermesREST.sessions = { @Sendable _, _, _, _ in [] }
      $0.hermesREST.cronJobs = { @Sendable _, _ in throw RESTError.notFound }
      $0.hermesREST.usageAnalytics = { @Sendable _, _ in throw RESTError.notFound }
    }

    await store.send(.pulledToRefresh) {
      $0.now = self.now
      $0.isLoading = true
    }
    await store.receive(\.sessionsResponse.success) {
      $0.isLoading = false
    }
    await store.receive(\.cronJobsResponse.failure) {
      $0.cronJobsSupported = false
    }
    await store.receive(\.serverStatusResponse.success)
    await store.receive(\.usageAnalyticsResponse.failure) {
      $0.analyticsSupported = false
      $0.usageAnalytics = nil
    }
    #expect(store.state.loadError == nil)
  }
}
