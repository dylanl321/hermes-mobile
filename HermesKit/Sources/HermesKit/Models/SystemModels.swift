import Foundation

// MARK: - Host stats

/// Host identity + resource sample from `GET /api/system/stats` (lenient).
public struct SystemStats: Equatable, Sendable, Decodable {
  public var os: String?
  public var osRelease: String?
  public var osVersion: String?
  public var platform: String?
  public var arch: String?
  public var hostname: String?
  public var pythonVersion: String?
  public var pythonImpl: String?
  public var hermesVersion: String?
  public var cpuCount: Int?
  public var psutil: Bool?
  public var cpuPercent: Double?
  public var loadAvg: [Double]?
  public var uptimeSeconds: Double?
  public var memory: SystemResourceSample?
  public var disk: SystemResourceSample?
  public var process: SystemProcessSample?

  public init(
    os: String? = nil,
    osRelease: String? = nil,
    osVersion: String? = nil,
    platform: String? = nil,
    arch: String? = nil,
    hostname: String? = nil,
    pythonVersion: String? = nil,
    pythonImpl: String? = nil,
    hermesVersion: String? = nil,
    cpuCount: Int? = nil,
    psutil: Bool? = nil,
    cpuPercent: Double? = nil,
    loadAvg: [Double]? = nil,
    uptimeSeconds: Double? = nil,
    memory: SystemResourceSample? = nil,
    disk: SystemResourceSample? = nil,
    process: SystemProcessSample? = nil
  ) {
    self.os = os
    self.osRelease = osRelease
    self.osVersion = osVersion
    self.platform = platform
    self.arch = arch
    self.hostname = hostname
    self.pythonVersion = pythonVersion
    self.pythonImpl = pythonImpl
    self.hermesVersion = hermesVersion
    self.cpuCount = cpuCount
    self.psutil = psutil
    self.cpuPercent = cpuPercent
    self.loadAvg = loadAvg
    self.uptimeSeconds = uptimeSeconds
    self.memory = memory
    self.disk = disk
    self.process = process
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    os = try? c.decodeIfPresent(String.self, forKey: .os)
    osRelease = try? c.decodeIfPresent(String.self, forKey: .osRelease)
    osVersion = try? c.decodeIfPresent(String.self, forKey: .osVersion)
    platform = try? c.decodeIfPresent(String.self, forKey: .platform)
    arch = try? c.decodeIfPresent(String.self, forKey: .arch)
    hostname = try? c.decodeIfPresent(String.self, forKey: .hostname)
    pythonVersion = try? c.decodeIfPresent(String.self, forKey: .pythonVersion)
    pythonImpl = try? c.decodeIfPresent(String.self, forKey: .pythonImpl)
    hermesVersion = try? c.decodeIfPresent(String.self, forKey: .hermesVersion)
    cpuCount = try? c.decodeIfPresent(Int.self, forKey: .cpuCount)
    psutil = try? c.decodeIfPresent(Bool.self, forKey: .psutil)
    cpuPercent = try? c.decodeIfPresent(Double.self, forKey: .cpuPercent)
    loadAvg = try? c.decodeIfPresent([Double].self, forKey: .loadAvg)
    uptimeSeconds = try? c.decodeIfPresent(Double.self, forKey: .uptimeSeconds)
    memory = try? c.decodeIfPresent(SystemResourceSample.self, forKey: .memory)
    disk = try? c.decodeIfPresent(SystemResourceSample.self, forKey: .disk)
    process = try? c.decodeIfPresent(SystemProcessSample.self, forKey: .process)
  }

  enum CodingKeys: String, CodingKey {
    case os, platform, arch, hostname, psutil, memory, disk, process
    case osRelease = "os_release"
    case osVersion = "os_version"
    case pythonVersion = "python_version"
    case pythonImpl = "python_impl"
    case hermesVersion = "hermes_version"
    case cpuCount = "cpu_count"
    case cpuPercent = "cpu_percent"
    case loadAvg = "load_avg"
    case uptimeSeconds = "uptime_seconds"
  }

  /// One-line OS identity for the Host section.
  public var osSummary: String {
    var parts: [String] = []
    if let os, !os.isEmpty { parts.append(os) }
    if let osRelease, !osRelease.isEmpty { parts.append(osRelease) }
    if let arch, !arch.isEmpty { parts.append(arch) }
    return parts.isEmpty ? "Unknown host" : parts.joined(separator: " · ")
  }

  public var uptimeLabel: String? {
    guard let seconds = uptimeSeconds, seconds >= 0 else { return nil }
    let total = Int(seconds)
    let days = total / 86_400
    let hours = (total % 86_400) / 3_600
    let minutes = (total % 3_600) / 60
    if days > 0 { return "\(days)d \(hours)h" }
    if hours > 0 { return "\(hours)h \(minutes)m" }
    return "\(minutes)m"
  }
}

public struct SystemResourceSample: Equatable, Sendable, Decodable {
  public var total: Double?
  public var available: Double?
  public var used: Double?
  public var free: Double?
  public var percent: Double?

  public init(
    total: Double? = nil,
    available: Double? = nil,
    used: Double? = nil,
    free: Double? = nil,
    percent: Double? = nil
  ) {
    self.total = total
    self.available = available
    self.used = used
    self.free = free
    self.percent = percent
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    total = try? c.decodeIfPresent(Double.self, forKey: .total)
    available = try? c.decodeIfPresent(Double.self, forKey: .available)
    used = try? c.decodeIfPresent(Double.self, forKey: .used)
    free = try? c.decodeIfPresent(Double.self, forKey: .free)
    percent = try? c.decodeIfPresent(Double.self, forKey: .percent)
  }

  enum CodingKeys: String, CodingKey {
    case total, available, used, free, percent
  }

  public var percentLabel: String? {
    guard let percent else { return nil }
    return String(format: "%.0f%%", percent)
  }
}

public struct SystemProcessSample: Equatable, Sendable, Decodable {
  public var pid: Int?
  public var rss: Double?
  public var createTime: Double?
  public var numThreads: Int?

  public init(
    pid: Int? = nil,
    rss: Double? = nil,
    createTime: Double? = nil,
    numThreads: Int? = nil
  ) {
    self.pid = pid
    self.rss = rss
    self.createTime = createTime
    self.numThreads = numThreads
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    pid = try? c.decodeIfPresent(Int.self, forKey: .pid)
    rss = try? c.decodeIfPresent(Double.self, forKey: .rss)
    createTime = try? c.decodeIfPresent(Double.self, forKey: .createTime)
    numThreads = try? c.decodeIfPresent(Int.self, forKey: .numThreads)
  }

  enum CodingKeys: String, CodingKey {
    case pid, rss
    case createTime = "create_time"
    case numThreads = "num_threads"
  }
}

// MARK: - Hermes update

/// Result of `GET /api/hermes/update/check`.
public struct HermesUpdateCheck: Equatable, Sendable, Decodable {
  public var installMethod: String?
  public var currentVersion: String?
  /// Commits behind: ≥1 known count, 0 up to date, −1 behind by unknown count, nil if check failed.
  public var behind: Int?
  public var updateAvailable: Bool?
  public var canApply: Bool?
  public var updateCommand: String?
  public var message: String?
  public var commits: [HermesUpdateCommit]

  public init(
    installMethod: String? = nil,
    currentVersion: String? = nil,
    behind: Int? = nil,
    updateAvailable: Bool? = nil,
    canApply: Bool? = nil,
    updateCommand: String? = nil,
    message: String? = nil,
    commits: [HermesUpdateCommit] = []
  ) {
    self.installMethod = installMethod
    self.currentVersion = currentVersion
    self.behind = behind
    self.updateAvailable = updateAvailable
    self.canApply = canApply
    self.updateCommand = updateCommand
    self.message = message
    self.commits = commits
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    installMethod = try? c.decodeIfPresent(String.self, forKey: .installMethod)
    currentVersion = try? c.decodeIfPresent(String.self, forKey: .currentVersion)
    behind = try? c.decodeIfPresent(Int.self, forKey: .behind)
    updateAvailable = try? c.decodeIfPresent(Bool.self, forKey: .updateAvailable)
    canApply = try? c.decodeIfPresent(Bool.self, forKey: .canApply)
      ?? c.decodeIfPresent(Bool.self, forKey: .canUpdate)
    updateCommand = try? c.decodeIfPresent(String.self, forKey: .updateCommand)
      ?? c.decodeIfPresent(String.self, forKey: .command)
    message = try? c.decodeIfPresent(String.self, forKey: .message)
    commits = (try? c.decodeIfPresent([HermesUpdateCommit].self, forKey: .commits)) ?? []
  }

  enum CodingKeys: String, CodingKey {
    case behind, message, commits, command
    case installMethod = "install_method"
    case currentVersion = "current_version"
    case updateAvailable = "update_available"
    case canApply = "can_apply"
    case canUpdate = "can_update"
    case updateCommand = "update_command"
  }

  /// Show the in-app Apply button (git installs that can update in place).
  public var showsApplyButton: Bool {
    canApply == true && (updateAvailable == true || (behind ?? 0) > 0)
  }

  public var statusLabel: String {
    if let message, !message.isEmpty { return message }
    if behind == 0 || updateAvailable == false { return "Up to date" }
    if let behind, behind > 0 {
      return behind == 1 ? "1 commit behind" : "\(behind) commits behind"
    }
    if behind == -1 || updateAvailable == true { return "Update available" }
    return "Couldn’t check for updates"
  }
}

public struct HermesUpdateCommit: Equatable, Sendable, Identifiable, Decodable {
  public var sha: String?
  public var summary: String?
  public var author: String?
  public var at: String?

  public var id: String {
    if let sha, !sha.isEmpty { return sha }
    return [summary, author, at].compactMap { $0 }.joined(separator: "|")
  }

  public init(sha: String? = nil, summary: String? = nil, author: String? = nil, at: String? = nil) {
    self.sha = sha
    self.summary = summary
    self.author = author
    self.at = at
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    sha = try? c.decodeIfPresent(String.self, forKey: .sha)
      ?? c.decodeIfPresent(String.self, forKey: .id)
    summary = try? c.decodeIfPresent(String.self, forKey: .summary)
      ?? c.decodeIfPresent(String.self, forKey: .message)
      ?? c.decodeIfPresent(String.self, forKey: .title)
    author = try? c.decodeIfPresent(String.self, forKey: .author)
    at = try? c.decodeIfPresent(String.self, forKey: .at)
      ?? c.decodeIfPresent(String.self, forKey: .date)
  }

  enum CodingKeys: String, CodingKey {
    case sha, id, summary, message, title, author, at, date
  }
}

/// Durable update outcome from `GET /api/hermes/update/receipt` (lenient).
public struct HermesUpdateReceipt: Equatable, Sendable, Decodable {
  public var outcome: String?
  public var exitCode: Int?
  public var stopReason: String?
  public var startedAt: String?
  public var finishedAt: String?
  public var message: String?
  /// Nested `summary` object when the endpoint wraps the receipt.
  public var summaryOutcome: String?
  public var summaryExitCode: Int?

  public init(
    outcome: String? = nil,
    exitCode: Int? = nil,
    stopReason: String? = nil,
    startedAt: String? = nil,
    finishedAt: String? = nil,
    message: String? = nil,
    summaryOutcome: String? = nil,
    summaryExitCode: Int? = nil
  ) {
    self.outcome = outcome
    self.exitCode = exitCode
    self.stopReason = stopReason
    self.startedAt = startedAt
    self.finishedAt = finishedAt
    self.message = message
    self.summaryOutcome = summaryOutcome
    self.summaryExitCode = summaryExitCode
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    outcome = try? c.decodeIfPresent(String.self, forKey: .outcome)
    exitCode = try? c.decodeIfPresent(Int.self, forKey: .exitCode)
    stopReason = try? c.decodeIfPresent(String.self, forKey: .stopReason)
    startedAt = try? c.decodeIfPresent(String.self, forKey: .startedAt)
      ?? c.decodeIfPresent(String.self, forKey: .startedAtAlt)
    finishedAt = try? c.decodeIfPresent(String.self, forKey: .finishedAt)
      ?? c.decodeIfPresent(String.self, forKey: .finishedAtAlt)
    message = try? c.decodeIfPresent(String.self, forKey: .message)
    if let summary = try? c.decodeIfPresent(Summary.self, forKey: .summary) {
      summaryOutcome = summary.outcome
      summaryExitCode = summary.exitCode
      if outcome == nil { outcome = summary.outcome }
      if exitCode == nil { exitCode = summary.exitCode }
      if startedAt == nil { startedAt = summary.startedAt }
    }
  }

  enum CodingKeys: String, CodingKey {
    case outcome, message, summary
    case exitCode = "exit_code"
    case stopReason = "stop_reason"
    case startedAt = "started_at"
    case startedAtAlt = "startedAt"
    case finishedAt = "finished_at"
    case finishedAtAlt = "finishedAt"
  }

  private struct Summary: Decodable {
    var outcome: String?
    var exitCode: Int?
    var startedAt: String?

    init(from decoder: Decoder) throws {
      let c = try decoder.container(keyedBy: CodingKeys.self)
      outcome = try? c.decodeIfPresent(String.self, forKey: .outcome)
      exitCode = try? c.decodeIfPresent(Int.self, forKey: .exitCode)
      startedAt = try? c.decodeIfPresent(String.self, forKey: .startedAt)
        ?? c.decodeIfPresent(String.self, forKey: .startedAtAlt)
    }

    enum CodingKeys: String, CodingKey {
      case outcome
      case exitCode = "exit_code"
      case startedAt = "started_at"
      case startedAtAlt = "startedAt"
    }
  }

  /// Authoritative success across a dashboard restart gap.
  public var isSuccessful: Bool {
    let code = exitCode ?? summaryExitCode
    if code == 0 { return true }
    switch (outcome ?? summaryOutcome)?.lowercased() {
    case "success", "ok", "completed": return true
    default: return false
    }
  }

  public var isFailed: Bool {
    if isSuccessful { return false }
    let code = exitCode ?? summaryExitCode
    if let code, code != 0 { return true }
    switch (outcome ?? summaryOutcome)?.lowercased() {
    case "failed", "error", "partial": return true
    default: return false
    }
  }

  public var isFinished: Bool {
    isSuccessful || isFailed || finishedAt != nil
  }
}

// MARK: - Gateway / ops actions

public enum GatewayLifecycleAction: String, Equatable, Sendable, CaseIterable {
  case start
  case stop
  case restart

  public var pathSegment: String { rawValue }

  public var title: String {
    switch self {
    case .start: "Start"
    case .stop: "Stop"
    case .restart: "Restart"
    }
  }
}

public enum OpsAction: String, Equatable, Sendable, CaseIterable {
  case doctor
  case securityAudit = "security-audit"
  case backup
  case promptSize = "prompt-size"
  case dump
  case configMigrate = "config-migrate"

  public var pathSegment: String { rawValue }

  public var title: String {
    switch self {
    case .doctor: "Doctor"
    case .securityAudit: "Security audit"
    case .backup: "Backup"
    case .promptSize: "Prompt size"
    case .dump: "Support dump"
    case .configMigrate: "Config migrate"
    }
  }

  public var requiresConfirmation: Bool {
    self == .configMigrate
  }
}

/// Accepted background action from `POST /api/hermes/update`, gateway, or ops.
public struct DashboardActionAccepted: Equatable, Sendable, Decodable {
  public var ok: Bool?
  public var name: String?
  public var pid: Int?
  public var message: String?
  public var error: String?
  public var archive: String?
  public var updateCommand: String?

  public init(
    ok: Bool? = nil,
    name: String? = nil,
    pid: Int? = nil,
    message: String? = nil,
    error: String? = nil,
    archive: String? = nil,
    updateCommand: String? = nil
  ) {
    self.ok = ok
    self.name = name
    self.pid = pid
    self.message = message
    self.error = error
    self.archive = archive
    self.updateCommand = updateCommand
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    ok = try? c.decodeIfPresent(Bool.self, forKey: .ok)
    name = try? c.decodeIfPresent(String.self, forKey: .name)
      ?? c.decodeIfPresent(String.self, forKey: .action)
    pid = try? c.decodeIfPresent(Int.self, forKey: .pid)
    message = try? c.decodeIfPresent(String.self, forKey: .message)
    error = try? c.decodeIfPresent(String.self, forKey: .error)
      ?? c.decodeIfPresent(String.self, forKey: .detail)
    archive = try? c.decodeIfPresent(String.self, forKey: .archive)
    updateCommand = try? c.decodeIfPresent(String.self, forKey: .updateCommand)
  }

  enum CodingKeys: String, CodingKey {
    case ok, name, action, pid, message, error, detail, archive
    case updateCommand = "update_command"
  }

  /// Action name to poll via `actionStatus`, when present.
  public var actionName: String? {
    guard let name, !name.isEmpty else { return nil }
    return name
  }
}
