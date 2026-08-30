import Foundation
import Testing

@testable import HermesKit

struct SystemModelsTests {
  private func decode<T: Decodable>(_ json: String) throws -> T {
    try JSONDecoder().decode(T.self, from: Data(json.utf8))
  }

  @Test func decodesSystemStats() throws {
    let stats: SystemStats = try decode(
      """
      {
        "os": "Linux",
        "os_release": "6.12.0",
        "arch": "x86_64",
        "hostname": "agent",
        "python_version": "3.12.0",
        "hermes_version": "0.20.0",
        "cpu_count": 4,
        "cpu_percent": 12.5,
        "uptime_seconds": 90061,
        "memory": {"total": 16, "available": 8, "used": 8, "percent": 50},
        "disk": {"total": 100, "used": 40, "free": 60, "percent": 40}
      }
      """
    )

    #expect(stats.os == "Linux")
    #expect(stats.hermesVersion == "0.20.0")
    #expect(stats.osSummary.contains("Linux"))
    #expect(stats.uptimeLabel == "1d 1h")
    #expect(stats.memory?.percentLabel == "50%")
  }

  @Test func decodesUpdateCheck() throws {
    let check: HermesUpdateCheck = try decode(
      """
      {
        "install_method": "git",
        "current_version": "abc123",
        "behind": 3,
        "update_available": true,
        "can_apply": true,
        "update_command": "hermes update",
        "commits": [{"sha": "def", "summary": "Fix thing", "author": "a"}]
      }
      """
    )

    #expect(check.behind == 3)
    #expect(check.showsApplyButton)
    #expect(check.statusLabel == "3 commits behind")
    #expect(check.commits.count == 1)
    #expect(check.commits[0].sha == "def")
  }

  @Test func nonGitUpdateCheckHidesApply() throws {
    let check: HermesUpdateCheck = try decode(
      """
      {
        "install_method": "docker",
        "behind": 1,
        "update_available": true,
        "can_apply": false,
        "update_command": "docker pull …"
      }
      """
    )
    #expect(!check.showsApplyButton)
    #expect(check.updateCommand == "docker pull …")
  }

  @Test func decodesUpdateReceiptSuccess() throws {
    let receipt: HermesUpdateReceipt = try decode(
      """
      {
        "outcome": "success",
        "exit_code": 0,
        "stop_reason": "completed at command boundary",
        "started_at": "2026-08-30T12:00:00Z",
        "summary": {"outcome": "success", "exit_code": 0}
      }
      """
    )
    #expect(receipt.isSuccessful)
    #expect(receipt.isFinished)
    #expect(!receipt.isFailed)
  }

  @Test func decodesActionAccepted() throws {
    let accepted: DashboardActionAccepted = try decode(
      #"{"ok":true,"name":"hermes-update","pid":42}"#
    )
    #expect(accepted.actionName == "hermes-update")
    #expect(accepted.pid == 42)
  }

  @Test func dashboardActionStatusProcessStyle() throws {
    let status: DashboardActionStatus = try decode(
      """
      {"name":"doctor","running":false,"exit_code":0,"pid":1,"lines":["ok"]}
      """
    )
    #expect(status.isTerminal)
    #expect(status.isSuccessful)
    #expect(status.lines == ["ok"])
  }

  @Test func dashboardActionStatusSkillsStyleStillWorks() throws {
    let status: DashboardActionStatus = try decode(
      #"{"name":"hub","status":"completed"}"#
    )
    #expect(status.isTerminal)
    #expect(!status.isFailed)
  }

  @Test func resourcePressureDecodesOomFields() throws {
    let pressure: ResourcePressure = try decode(
      """
      {
        "pressure": "ok",
        "boot_id": "boot-1",
        "last_boot_unclean": true,
        "last_boot_suspected_oom": true,
        "used_percent": 88.5
      }
      """
    )
    #expect(pressure.bootId == "boot-1")
    #expect(pressure.lastBootSuspectedOom == true)
    #expect(pressure.usedPercent == 88.5)

    let status = ServerStatus(memory: pressure)
    #expect(status.bootWarning?.contains("memory") == true)
    #expect(status.bootId == "boot-1")
  }
}
