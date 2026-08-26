import Foundation
import Testing

@testable import HermesKit

struct UsageAnalyticsTests {
  private func decode<T: Decodable>(_ json: String) throws -> T {
    try JSONDecoder().decode(T.self, from: Data(json.utf8))
  }

  @Test func decodesUsageAnalyticsPayload() throws {
    let analytics: UsageAnalytics = try decode(
      """
      {
        "days": 30,
        "total_tokens": 1250000,
        "total_cost": 12.34,
        "session_count": 42,
        "daily": [
          {"date": "2026-08-01", "tokens": 1000, "cost": 0.5}
        ]
      }
      """
    )

    #expect(analytics.days == 30)
    #expect(analytics.totalTokens == 1_250_000)
    #expect(analytics.totalCost == 12.34)
    #expect(analytics.sessionCount == 42)
    #expect(analytics.daily.count == 1)
    #expect(analytics.daily[0].date == "2026-08-01")
    #expect(analytics.summaryLabel.contains("1.2M tokens"))
    #expect(analytics.summaryLabel.contains("$12.34"))
    #expect(analytics.summaryLabel.contains("42 sessions"))
  }

  @Test func decodesUsageAnalyticsAlternateKeys() throws {
    let analytics: UsageAnalytics = try decode(
      """
      {"tokens": 500, "cost": 1.0, "sessions": 3, "daily": [{"day": "2026-08-02", "tokens": 100}]}
      """
    )

    #expect(analytics.totalTokens == 500)
    #expect(analytics.totalCost == 1.0)
    #expect(analytics.sessionCount == 3)
    #expect(analytics.daily[0].date == "2026-08-02")
  }

  @Test func summaryLabelWhenEmpty() {
    #expect(UsageAnalytics().summaryLabel == "No usage data")
  }

  @Test func decodesResourcePressure() throws {
    let pressure: ResourcePressure = try decode(
      """
      {"pressure": "elevated", "free_mb": 512, "total_mb": 8192, "system_available_mb": 2048}
      """
    )

    #expect(pressure.pressure == "elevated")
    #expect(pressure.freeMb == 512)
    #expect(pressure.isElevatedOrWorse)
  }

  @Test func decodesServerStatusWithPressure() throws {
    let status: ServerStatus = try decode(
      """
      {
        "version": "0.16.0",
        "gateway_state": "running",
        "memory": {"pressure": "critical"},
        "disk": {"pressure": "elevated"}
      }
      """
    )

    #expect(status.version == "0.16.0")
    #expect(status.gatewayState == "running")
    #expect(status.worstPressure == "critical")
    #expect(status.memory?.isElevatedOrWorse == true)
  }
}
