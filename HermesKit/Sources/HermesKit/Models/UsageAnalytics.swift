import Foundation

/// Token / cost analytics from `GET /api/analytics/usage?days=`.
public struct UsageAnalytics: Equatable, Sendable, Decodable {
  public var days: Int?
  public var totalTokens: Int?
  public var totalCost: Double?
  public var sessionCount: Int?
  public var daily: [DailyUsage]

  public init(
    days: Int? = nil,
    totalTokens: Int? = nil,
    totalCost: Double? = nil,
    sessionCount: Int? = nil,
    daily: [DailyUsage] = []
  ) {
    self.days = days
    self.totalTokens = totalTokens
    self.totalCost = totalCost
    self.sessionCount = sessionCount
    self.daily = daily
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    days = try? c.decodeIfPresent(Int.self, forKey: .days)
    totalTokens = try? c.decodeIfPresent(Int.self, forKey: .totalTokens)
      ?? c.decodeIfPresent(Int.self, forKey: .tokens)
    totalCost = try? c.decodeIfPresent(Double.self, forKey: .totalCost)
      ?? c.decodeIfPresent(Double.self, forKey: .cost)
    sessionCount = try? c.decodeIfPresent(Int.self, forKey: .sessionCount)
      ?? c.decodeIfPresent(Int.self, forKey: .sessions)
    daily = (try? c.decodeIfPresent([DailyUsage].self, forKey: .daily)) ?? []
  }

  enum CodingKeys: String, CodingKey {
    case days, daily, tokens, cost, sessions
    case totalTokens = "total_tokens"
    case totalCost = "total_cost"
    case sessionCount = "session_count"
  }

  public struct DailyUsage: Equatable, Sendable, Decodable {
    public var date: String?
    public var tokens: Int?
    public var cost: Double?

    public init(date: String? = nil, tokens: Int? = nil, cost: Double? = nil) {
      self.date = date
      self.tokens = tokens
      self.cost = cost
    }

    public init(from decoder: Decoder) throws {
      let c = try decoder.container(keyedBy: CodingKeys.self)
      date = try? c.decodeIfPresent(String.self, forKey: .date)
        ?? c.decodeIfPresent(String.self, forKey: .day)
      tokens = try? c.decodeIfPresent(Int.self, forKey: .tokens)
      cost = try? c.decodeIfPresent(Double.self, forKey: .cost)
    }

    enum CodingKeys: String, CodingKey { case date, day, tokens, cost }
  }

  /// Compact label for the home ops strip.
  public var summaryLabel: String {
    var parts: [String] = []
    if let tokens = totalTokens {
      parts.append("\(Self.formatTokens(tokens)) tokens")
    }
    if let cost = totalCost {
      parts.append(String(format: "$%.2f", cost))
    }
    if let sessions = sessionCount {
      parts.append("\(sessions) sessions")
    }
    return parts.isEmpty ? "No usage data" : parts.joined(separator: " · ")
  }

  private static func formatTokens(_ n: Int) -> String {
    if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
    if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
    return "\(n)"
  }
}

/// Resource pressure block from `GET /api/status` (`memory` / `disk`).
public struct ResourcePressure: Equatable, Sendable, Decodable {
  public var pressure: String?
  public var freeMb: Int?
  public var totalMb: Int?
  public var systemAvailableMb: Int?

  public init(
    pressure: String? = nil,
    freeMb: Int? = nil,
    totalMb: Int? = nil,
    systemAvailableMb: Int? = nil
  ) {
    self.pressure = pressure
    self.freeMb = freeMb
    self.totalMb = totalMb
    self.systemAvailableMb = systemAvailableMb
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    pressure = try? c.decodeIfPresent(String.self, forKey: .pressure)
    freeMb = try? c.decodeIfPresent(Int.self, forKey: .freeMb)
    totalMb = try? c.decodeIfPresent(Int.self, forKey: .totalMb)
    systemAvailableMb = try? c.decodeIfPresent(Int.self, forKey: .systemAvailableMb)
  }

  enum CodingKeys: String, CodingKey {
    case pressure
    case freeMb = "free_mb"
    case totalMb = "total_mb"
    case systemAvailableMb = "system_available_mb"
  }

  public var isElevatedOrWorse: Bool {
    switch pressure?.lowercased() {
    case "elevated", "critical": true
    default: false
    }
  }
}
