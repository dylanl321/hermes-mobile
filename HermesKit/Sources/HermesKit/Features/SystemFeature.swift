import ComposableArchitecture
import Foundation

/// System / Host / Update / Gateway / Operations (dashboard REST).
/// Presented as a sheet from the session list (More / Settings → System) when the
/// agent exposes `GET /api/system/stats`.
@Reducer
public struct SystemFeature {
  public static let actionPollInterval: Duration = .seconds(1)
  public static let actionPollMaxAttempts = 180
  public static let updateReceiptPollMaxAttempts = 60
  public static let copiedFeedbackDuration: Duration = .seconds(1.5)
  public static let actionLogLineLimit = 200

  @ObservableState
  public struct State: Equatable {
    public var connection: ServerConnection
    public var systemSupported: Bool
    public var updateCheckSupported: Bool
    public var gatewaySupported: Bool
    public var opsSupported: Bool
    public var stats: SystemStats?
    public var serverStatus: ServerStatus?
    public var updateCheck: HermesUpdateCheck?
    public var isLoading: Bool
    public var isCheckingUpdate: Bool
    public var errorBanner: String?
    public var statusBanner: String?
    public var dismissedBootId: String?
    public var inFlightKind: InFlightKind?
    public var inFlightLabel: String?
    public var actionLines: [String]
    public var actionMessage: String?
    public var copyToken: Int?
    @Presents public var confirmationDialog: ConfirmationDialogState<Action.Dialog>?

    public init(
      connection: ServerConnection,
      systemSupported: Bool = true,
      updateCheckSupported: Bool = true,
      gatewaySupported: Bool = true,
      opsSupported: Bool = true,
      stats: SystemStats? = nil,
      serverStatus: ServerStatus? = nil,
      updateCheck: HermesUpdateCheck? = nil,
      isLoading: Bool = false,
      isCheckingUpdate: Bool = false,
      errorBanner: String? = nil,
      statusBanner: String? = nil,
      dismissedBootId: String? = nil,
      inFlightKind: InFlightKind? = nil,
      inFlightLabel: String? = nil,
      actionLines: [String] = [],
      actionMessage: String? = nil,
      copyToken: Int? = nil,
      confirmationDialog: ConfirmationDialogState<Action.Dialog>? = nil
    ) {
      self.connection = connection
      self.systemSupported = systemSupported
      self.updateCheckSupported = updateCheckSupported
      self.gatewaySupported = gatewaySupported
      self.opsSupported = opsSupported
      self.stats = stats
      self.serverStatus = serverStatus
      self.updateCheck = updateCheck
      self.isLoading = isLoading
      self.isCheckingUpdate = isCheckingUpdate
      self.errorBanner = errorBanner
      self.statusBanner = statusBanner
      self.dismissedBootId = dismissedBootId
      self.inFlightKind = inFlightKind
      self.inFlightLabel = inFlightLabel
      self.actionLines = actionLines
      self.actionMessage = actionMessage
      self.copyToken = copyToken
      self.confirmationDialog = confirmationDialog
    }

    public var hasInFlightAction: Bool { inFlightKind != nil }

    public var bootWarningText: String? {
      guard let warning = serverStatus?.bootWarning else { return nil }
      if let bootId = serverStatus?.bootId, bootId == dismissedBootId { return nil }
      return warning
    }

    public var gatewayStateLabel: String {
      if let state = serverStatus?.gatewayState, !state.isEmpty { return state }
      if serverStatus?.gatewayRunning == true { return "running" }
      if serverStatus?.gatewayRunning == false { return "stopped" }
      return "unknown"
    }
  }

  public enum InFlightKind: Equatable, Sendable {
    case update
    case gateway(GatewayLifecycleAction)
    case ops(OpsAction)
  }

  public enum Action: BindableAction {
    case binding(BindingAction<State>)
    case task
    case refreshTapped
    case loadFinished(stats: Result<SystemStats, RESTError>, status: Result<ServerStatus, RESTError>)
    case statusRefreshed(ServerStatus)
    case checkUpdateTapped
    case updateCheckFinished(Result<HermesUpdateCheck, RESTError>)
    case applyUpdateTapped
    case copyUpdateCommandTapped
    case gatewayStartTapped
    case gatewayStopTapped
    case gatewayRestartTapped
    case opsTapped(OpsAction)
    case confirmationDialog(PresentationAction<Dialog>)
    case actionStarted(kind: InFlightKind, accepted: DashboardActionAccepted)
    case actionPolled(DashboardActionStatus)
    case actionFailed(String)
    /// Update poll lost the socket (dashboard restart) — fall back to receipt.
    case updatePollInterrupted
    case opsUnsupported
    case receiptPolled(Result<HermesUpdateReceipt, RESTError>)
    case copyFinished
    case dismissError
    case dismissStatusBanner
    case dismissBootWarning
    case dismissActionMessage
    case doneTapped
    case delegate(Delegate)

    public enum Dialog: Equatable, Sendable {
      case confirmApplyUpdate
      case confirmGatewayStop
      case confirmGatewayRestart
      case confirmConfigMigrate
    }

    @CasePathable
    public enum Delegate: Equatable, Sendable {
      case systemUnsupported
      case gatewayUnsupported
      case dismiss
      /// Parent should refresh session-list status after a gateway lifecycle change.
      case gatewayLifecycleCompleted
    }
  }

  private enum CancelID {
    case load, updateCheck, actionPoll, receiptPoll, copyFeedback
  }

  @Dependency(\.hermesREST) var rest
  @Dependency(\.continuousClock) var clock
  @Dependency(\.pasteboard) var pasteboard

  public init() {}

  public var body: some ReducerOf<Self> {
    BindingReducer()
    Reduce { state, action in
      switch action {
      case .binding:
        return .none

      case .task, .refreshTapped:
        state.isLoading = true
        state.isCheckingUpdate = state.updateCheckSupported
        state.errorBanner = nil
        return .merge(loadAll(state), loadUpdateCheck(state, force: false))

      case let .loadFinished(statsResult, statusResult):
        state.isLoading = false
        if case let .success(stats) = statsResult {
          state.systemSupported = true
          state.stats = stats
        } else if case let .failure(error) = statsResult {
          if error.isMissingEndpointVerdict {
            state.systemSupported = false
            state.stats = nil
            return .send(.delegate(.systemUnsupported))
          }
          state.errorBanner = error.message
        }
        if case let .success(status) = statusResult {
          state.serverStatus = status
        }
        return .none

      case let .statusRefreshed(status):
        state.serverStatus = status
        return .none

      case .checkUpdateTapped:
        guard state.updateCheckSupported else { return .none }
        state.isCheckingUpdate = true
        return loadUpdateCheck(state, force: true)

      case let .updateCheckFinished(.success(check)):
        state.isCheckingUpdate = false
        state.updateCheckSupported = true
        state.updateCheck = check
        return .none

      case let .updateCheckFinished(.failure(error)):
        state.isCheckingUpdate = false
        if error.isMissingEndpointVerdict {
          state.updateCheckSupported = false
          state.updateCheck = nil
          return .none
        }
        state.errorBanner = error.message
        return .none

      case .applyUpdateTapped:
        guard state.updateCheck?.showsApplyButton == true, !state.hasInFlightAction else {
          return .none
        }
        state.confirmationDialog = ConfirmationDialogState {
          TextState("Update Hermes?")
        } actions: {
          ButtonState(action: .confirmApplyUpdate) { TextState("Update now") }
          ButtonState(role: .cancel) { TextState("Cancel") }
        } message: {
          let behind = state.updateCheck?.behind
          if let behind, behind > 0 {
            TextState("Pull \(behind) commit\(behind == 1 ? "" : "s") and restart services on the host.")
          } else {
            TextState("Run hermes update on the host. The dashboard may restart briefly.")
          }
        }
        return .none

      case .copyUpdateCommandTapped:
        guard let command = state.updateCheck?.updateCommand, !command.isEmpty else {
          return .none
        }
        state.actionMessage = "Copied update command."
        return .run { [pasteboard] _ in pasteboard.copy(command) }

      case .copyFinished:
        return .none

      case .gatewayStartTapped:
        guard state.gatewaySupported, !state.hasInFlightAction else { return .none }
        return startGateway(state, .start)

      case .gatewayStopTapped:
        guard state.gatewaySupported, !state.hasInFlightAction else { return .none }
        state.confirmationDialog = ConfirmationDialogState {
          TextState("Stop gateway?")
        } actions: {
          ButtonState(role: .destructive, action: .confirmGatewayStop) {
            TextState("Stop")
          }
          ButtonState(role: .cancel) { TextState("Cancel") }
        } message: {
          TextState("Messaging channels will disconnect until the gateway is started again.")
        }
        return .none

      case .gatewayRestartTapped:
        guard state.gatewaySupported, !state.hasInFlightAction else { return .none }
        state.confirmationDialog = Self.restartConfirmation(dialog: .confirmGatewayRestart)
        return .none

      case let .opsTapped(ops):
        guard state.opsSupported, !state.hasInFlightAction else { return .none }
        if ops.requiresConfirmation {
          state.confirmationDialog = ConfirmationDialogState {
            TextState("Migrate config?")
          } actions: {
            ButtonState(action: .confirmConfigMigrate) { TextState("Migrate") }
            ButtonState(role: .cancel) { TextState("Cancel") }
          } message: {
            TextState("Apply retired config migrations on the host.")
          }
          return .none
        }
        return startOps(state, ops)

      case .confirmationDialog(.presented(.confirmApplyUpdate)):
        state.confirmationDialog = nil
        return startUpdate(state)

      case .confirmationDialog(.presented(.confirmGatewayStop)):
        state.confirmationDialog = nil
        return startGateway(state, .stop)

      case .confirmationDialog(.presented(.confirmGatewayRestart)):
        state.confirmationDialog = nil
        return startGateway(state, .restart)

      case .confirmationDialog(.presented(.confirmConfigMigrate)):
        state.confirmationDialog = nil
        return startOps(state, .configMigrate)

      case .confirmationDialog(.dismiss):
        state.confirmationDialog = nil
        return .none

      case let .actionStarted(kind, accepted):
        if accepted.ok == false {
          state.inFlightKind = nil
          state.inFlightLabel = nil
          state.errorBanner = accepted.error ?? accepted.message ?? "Action failed."
          if kind.isGateway, let error = accepted.error,
            error.lowercased().contains("not found")
          {
            state.gatewaySupported = false
            return .send(.delegate(.gatewayUnsupported))
          }
          return .none
        }
        state.inFlightKind = kind
        state.inFlightLabel = kind.label
        state.actionMessage = accepted.message
        state.actionLines = []
        state.errorBanner = nil
        let actionName = accepted.actionName ?? kind.defaultActionName
        return pollAction(state, actionName: actionName, allowReceiptFallback: kind == .update)

      case let .actionPolled(status):
        if let lines = status.lines, !lines.isEmpty {
          state.actionLines = lines
        }
        if status.isTerminal {
          let kind = state.inFlightKind
          state.inFlightKind = nil
          state.inFlightLabel = nil
          if status.isFailed {
            state.actionMessage = status.error ?? "Action failed."
            state.errorBanner = state.actionMessage
          } else {
            state.actionMessage = status.isSuccessful
              ? "Finished successfully."
              : "Finished."
          }
          if kind?.isGateway == true {
            return .merge(
              refreshStatus(state),
              .send(.delegate(.gatewayLifecycleCompleted))
            )
          }
          if kind == .update {
            return loadUpdateCheck(state, force: true)
          }
          return .none
        }
        return .none

      case let .actionFailed(message):
        state.inFlightKind = nil
        state.inFlightLabel = nil
        state.errorBanner = message
        state.actionMessage = message
        return .none

      case .updatePollInterrupted:
        state.actionMessage = "Reconnecting to read update receipt…"
        return pollReceipt(state.connection)

      case .opsUnsupported:
        state.opsSupported = false
        state.inFlightKind = nil
        state.inFlightLabel = nil
        state.errorBanner = "Operations aren’t available on this agent."
        return .none

      case let .receiptPolled(.success(receipt)):
        if receipt.isFinished {
          state.inFlightKind = nil
          state.inFlightLabel = nil
          if receipt.isSuccessful {
            state.actionMessage = receipt.message ?? "Update completed."
            state.errorBanner = nil
            return loadUpdateCheck(state, force: true)
          }
          if receipt.isFailed {
            state.actionMessage = receipt.message ?? receipt.stopReason ?? "Update failed."
            state.errorBanner = state.actionMessage
            return .none
          }
        }
        return .none

      case let .receiptPolled(.failure(error)):
        if error.isMissingEndpointVerdict {
          state.inFlightKind = nil
          state.inFlightLabel = nil
          state.errorBanner = "Update status lost after restart — check the host."
          return .none
        }
        // Keep waiting through transient blips.
        return .none

      case .dismissError:
        state.errorBanner = nil
        return .none

      case .dismissStatusBanner:
        state.statusBanner = nil
        return .none

      case .dismissBootWarning:
        state.dismissedBootId = state.serverStatus?.bootId ?? "dismissed"
        return .none

      case .dismissActionMessage:
        state.actionMessage = nil
        return .none

      case .doneTapped:
        return .send(.delegate(.dismiss))

      case .delegate(.gatewayUnsupported):
        state.gatewaySupported = false
        return .none

      case .delegate:
        return .none
      }
    }
    .ifLet(\.$confirmationDialog, action: \.confirmationDialog)
  }

  public static func restartConfirmation(
    dialog: Action.Dialog = .confirmGatewayRestart
  ) -> ConfirmationDialogState<Action.Dialog> {
    ConfirmationDialogState {
      TextState("Restart gateway?")
    } actions: {
      ButtonState(action: dialog) { TextState("Restart") }
      ButtonState(role: .cancel) { TextState("Cancel") }
    } message: {
      TextState("Restart the messaging gateway so config and API key changes take effect.")
    }
  }

  private func loadAll(_ state: State) -> Effect<Action> {
    let conn = state.connection
    return .run { [rest] send in
      let statsResult: Result<SystemStats, RESTError>
      do {
        statsResult = .success(try await rest.systemStats(conn))
      } catch {
        statsResult = .failure(asRESTError(error))
      }
      let statusResult: Result<ServerStatus, RESTError>
      do {
        statusResult = .success(try await rest.status(conn.baseURL))
      } catch {
        statusResult = .failure(asRESTError(error))
      }
      await send(.loadFinished(stats: statsResult, status: statusResult))
    }
    .cancellable(id: CancelID.load, cancelInFlight: true)
  }

  private func refreshStatus(_ state: State) -> Effect<Action> {
    let conn = state.connection
    return .run { [rest] send in
      do {
        let status = try await rest.status(conn.baseURL)
        await send(.statusRefreshed(status))
      } catch {
        // Ignore — UI keeps last known state.
      }
    }
  }

  private func loadUpdateCheck(_ state: State, force: Bool) -> Effect<Action> {
    guard state.updateCheckSupported else { return .none }
    let conn = state.connection
    return .run { [rest] send in
      do {
        let check = try await rest.hermesUpdateCheck(conn, force)
        await send(.updateCheckFinished(.success(check)))
      } catch {
        await send(.updateCheckFinished(.failure(asRESTError(error))))
      }
    }
    .cancellable(id: CancelID.updateCheck, cancelInFlight: true)
  }

  private func startUpdate(_ state: State) -> Effect<Action> {
    let conn = state.connection
    return .run { [rest] send in
      do {
        let accepted = try await rest.hermesUpdate(conn)
        await send(.actionStarted(kind: .update, accepted: accepted))
      } catch {
        let err = asRESTError(error)
        if err.isMissingEndpointVerdict {
          await send(.updateCheckFinished(.failure(err)))
        } else {
          await send(.actionFailed(err.message))
        }
      }
    }
  }

  private func startGateway(_ state: State, _ action: GatewayLifecycleAction) -> Effect<Action> {
    let conn = state.connection
    return .run { [rest] send in
      do {
        let accepted = try await rest.gatewayLifecycle(conn, action)
        await send(.actionStarted(kind: .gateway(action), accepted: accepted))
      } catch {
        let err = asRESTError(error)
        if err.isMissingEndpointVerdict {
          await send(.delegate(.gatewayUnsupported))
        } else {
          await send(.actionFailed(err.message))
        }
      }
    }
  }

  private func startOps(_ state: State, _ action: OpsAction) -> Effect<Action> {
    let conn = state.connection
    return .run { [rest] send in
      do {
        let accepted = try await rest.opsAction(conn, action)
        await send(.actionStarted(kind: .ops(action), accepted: accepted))
      } catch {
        let err = asRESTError(error)
        if err.isMissingEndpointVerdict {
          await send(.opsUnsupported)
        } else {
          await send(.actionFailed(err.message))
        }
      }
    }
  }

  private func pollAction(
    _ state: State,
    actionName: String,
    allowReceiptFallback: Bool
  ) -> Effect<Action> {
    let conn = state.connection
    return .run { [rest, clock] send in
      for _ in 0..<Self.actionPollMaxAttempts {
        try await clock.sleep(for: Self.actionPollInterval)
        do {
          let status = try await rest.actionStatus(conn, actionName, Self.actionLogLineLimit)
          await send(.actionPolled(status))
          if status.isTerminal { return }
        } catch {
          if allowReceiptFallback {
            await send(.updatePollInterrupted)
          } else {
            await send(.actionFailed(asRESTError(error).message))
          }
          return
        }
      }
      if allowReceiptFallback {
        await send(.updatePollInterrupted)
      } else {
        await send(.actionFailed("Action timed out."))
      }
    }
    .cancellable(id: CancelID.actionPoll, cancelInFlight: true)
  }

  private func pollReceipt(_ connection: ServerConnection) -> Effect<Action> {
    .run { [rest, clock] send in
      for _ in 0..<Self.updateReceiptPollMaxAttempts {
        try await clock.sleep(for: Self.actionPollInterval)
        do {
          let receipt = try await rest.hermesUpdateReceipt(connection)
          await send(.receiptPolled(.success(receipt)))
          if receipt.isFinished { return }
        } catch {
          let err = asRESTError(error)
          await send(.receiptPolled(.failure(err)))
          if err.isMissingEndpointVerdict { return }
        }
      }
      await send(.actionFailed("Update status timed out — check the host."))
    }
    .cancellable(id: CancelID.receiptPoll, cancelInFlight: true)
  }
}

extension SystemFeature.InFlightKind {
  var label: String {
    switch self {
    case .update: "Updating Hermes…"
    case let .gateway(action): "\(action.title)ing gateway…"
    case let .ops(action): "\(action.title)…"
    }
  }

  var defaultActionName: String {
    switch self {
    case .update: "hermes-update"
    case let .gateway(action): "gateway-\(action.rawValue)"
    case let .ops(action): action.rawValue
    }
  }

  var isGateway: Bool {
    if case .gateway = self { return true }
    return false
  }
}
