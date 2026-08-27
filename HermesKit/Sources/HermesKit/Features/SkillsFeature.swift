import ComposableArchitecture
import Foundation

/// Skills management (dashboard REST): installed list + enable toggles + hub search/install.
/// Presented as a sheet from the session list (More menu / Settings → Skills) when the
/// agent exposes `/api/skills`.
@Reducer
public struct SkillsFeature {
  @ObservableState
  public struct State: Equatable {
    public var connection: ServerConnection
    /// Non-default profile name for `?profile=` scoping; `nil` omits the param.
    public var profile: String?
    public var skillsSupported: Bool
    public var skills: IdentifiedArrayOf<Skill>
    public var isLoading: Bool
    public var errorBanner: String?
    public var hubQuery: String
    public var hubResults: IdentifiedArrayOf<SkillHubHit>
    public var isSearchingHub: Bool
    public var hubActionInFlight: String?
    public var hubActionMessage: String?
    /// Names currently mid-toggle (optimistic UI lock).
    public var togglingNames: Set<String>

    public init(
      connection: ServerConnection,
      profile: String? = nil,
      skillsSupported: Bool = true,
      skills: IdentifiedArrayOf<Skill> = [],
      isLoading: Bool = false,
      errorBanner: String? = nil,
      hubQuery: String = "",
      hubResults: IdentifiedArrayOf<SkillHubHit> = [],
      isSearchingHub: Bool = false,
      hubActionInFlight: String? = nil,
      hubActionMessage: String? = nil,
      togglingNames: Set<String> = []
    ) {
      self.connection = connection
      self.profile = profile
      self.skillsSupported = skillsSupported
      self.skills = skills
      self.isLoading = isLoading
      self.errorBanner = errorBanner
      self.hubQuery = hubQuery
      self.hubResults = hubResults
      self.isSearchingHub = isSearchingHub
      self.hubActionInFlight = hubActionInFlight
      self.hubActionMessage = hubActionMessage
      self.togglingNames = togglingNames
    }
  }

  public enum Action: BindableAction {
    case binding(BindingAction<State>)
    case task
    case refreshTapped
    case skillsResponse(Result<[Skill], RESTError>)
    case toggleSkill(name: String, enabled: Bool)
    case toggleFinished(name: String, enabled: Bool, error: RESTError?)
    case hubSearchSubmitted
    case hubSearchResponse(Result<[SkillHubHit], RESTError>)
    case hubInstall(name: String)
    case hubUninstall(name: String)
    case hubUpdate(name: String)
    case hubActionStarted(name: String, actionName: String?)
    case hubActionPolled(DashboardActionStatus)
    case hubActionFailed(String)
    case dismissError
    case dismissHubMessage
    case doneTapped
    case delegate(Delegate)

    @CasePathable
    public enum Delegate {
      case skillsUnsupported
      /// Sheet Done — parent dismisses the presented Skills sheet.
      case dismiss
    }
  }

  private enum CancelID { case load, hubSearch, hubPoll }

  @Dependency(\.hermesREST) var rest
  @Dependency(\.continuousClock) var clock

  public init() {}

  public var body: some ReducerOf<Self> {
    BindingReducer()
    Reduce { state, action in
      switch action {
      case .binding:
        return .none

      case .task, .refreshTapped:
        state.isLoading = true
        state.errorBanner = nil
        return loadSkills(state)

      case let .skillsResponse(.success(skills)):
        state.isLoading = false
        state.skillsSupported = true
        state.skills = IdentifiedArray(skills.filter { !$0.name.isEmpty }, uniquingIDsWith: { a, _ in a })
        return .none

      case let .skillsResponse(.failure(error)):
        state.isLoading = false
        if error.isMissingEndpointVerdict {
          state.skillsSupported = false
          state.skills = []
          return .send(.delegate(.skillsUnsupported))
        }
        state.errorBanner = error.message
        return .none

      case let .toggleSkill(name, enabled):
        state.togglingNames.insert(name)
        if var skill = state.skills[id: name] {
          skill.enabled = enabled
          state.skills[id: name] = skill
        }
        let conn = state.connection
        let profile = state.profile
        return .run { [rest] send in
          do {
            try await rest.toggleSkill(conn, name, enabled, profile)
            await send(.toggleFinished(name: name, enabled: enabled, error: nil))
          } catch {
            await send(.toggleFinished(name: name, enabled: enabled, error: asRESTError(error)))
          }
        }

      case let .toggleFinished(name, enabled, error):
        state.togglingNames.remove(name)
        if let error {
          // Roll back optimistic toggle.
          if var skill = state.skills[id: name] {
            skill.enabled = !enabled
            state.skills[id: name] = skill
          }
          state.errorBanner = error.message
        }
        return .none

      case .hubSearchSubmitted:
        let query = state.hubQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
          state.hubResults = []
          return .none
        }
        state.isSearchingHub = true
        state.hubActionMessage = nil
        let conn = state.connection
        let profile = state.profile
        return .run { [rest] send in
          do {
            let hits = try await rest.searchSkillHub(conn, query, profile)
            await send(.hubSearchResponse(.success(hits)))
          } catch {
            await send(.hubSearchResponse(.failure(asRESTError(error))))
          }
        }
        .cancellable(id: CancelID.hubSearch, cancelInFlight: true)

      case let .hubSearchResponse(.success(hits)):
        state.isSearchingHub = false
        state.hubResults = IdentifiedArray(
          hits.filter { !$0.name.isEmpty },
          uniquingIDsWith: { a, _ in a }
        )
        return .none

      case let .hubSearchResponse(.failure(error)):
        state.isSearchingHub = false
        if error.isMissingEndpointVerdict {
          state.hubResults = []
          state.hubActionMessage = "Skill hub isn’t available on this server."
          return .none
        }
        state.errorBanner = error.message
        return .none

      case let .hubInstall(name):
        return hubAction(state, action: "install", name: name)
      case let .hubUninstall(name):
        return hubAction(state, action: "uninstall", name: name)
      case let .hubUpdate(name):
        return hubAction(state, action: "update", name: name)

      case let .hubActionStarted(name, actionName):
        state.hubActionInFlight = name
        if let actionName, !actionName.isEmpty {
          return pollAction(state, actionName: actionName)
        }
        // No action handle — treat as fire-and-forget success, then refresh.
        state.hubActionInFlight = nil
        state.hubActionMessage = "Requested \(name)."
        state.isLoading = true
        return loadSkills(state)

      case let .hubActionPolled(status):
        if status.isFailed {
          state.hubActionInFlight = nil
          state.errorBanner = status.error ?? "Skill hub action failed."
          return .cancel(id: CancelID.hubPoll)
        }
        if status.isTerminal {
          state.hubActionInFlight = nil
          state.hubActionMessage = "Done."
          state.isLoading = true
          return .merge(
            .cancel(id: CancelID.hubPoll),
            loadSkills(state)
          )
        }
        return .none

      case let .hubActionFailed(message):
        state.hubActionInFlight = nil
        state.errorBanner = message
        return .cancel(id: CancelID.hubPoll)

      case .dismissError:
        state.errorBanner = nil
        return .none

      case .dismissHubMessage:
        state.hubActionMessage = nil
        return .none

      case .doneTapped:
        return .send(.delegate(.dismiss))

      case .delegate:
        return .none
      }
    }
  }

  private func loadSkills(_ state: State) -> Effect<Action> {
    let conn = state.connection
    let profile = state.profile
    return .run { [rest] send in
      do {
        let skills = try await rest.skills(conn, profile)
        await send(.skillsResponse(.success(skills)))
      } catch {
        await send(.skillsResponse(.failure(asRESTError(error))))
      }
    }
    .cancellable(id: CancelID.load, cancelInFlight: true)
  }

  private func hubAction(_ state: State, action: String, name: String) -> Effect<Action> {
    let conn = state.connection
    let profile = state.profile
    return .run { [rest] send in
      do {
        let actionName = try await rest.skillHubAction(conn, action, name, profile)
        await send(.hubActionStarted(name: name, actionName: actionName))
      } catch {
        await send(.hubActionFailed(asRESTError(error).message))
      }
    }
  }

  private func pollAction(_ state: State, actionName: String) -> Effect<Action> {
    let conn = state.connection
    return .run { [rest, clock] send in
      for _ in 0..<60 {
        try await clock.sleep(for: .seconds(1))
        do {
          let status = try await rest.actionStatus(conn, actionName)
          await send(.hubActionPolled(status))
          if status.isTerminal || status.isFailed { return }
        } catch {
          await send(.hubActionFailed(asRESTError(error).message))
          return
        }
      }
      await send(.hubActionFailed("Skill hub action timed out."))
    }
    .cancellable(id: CancelID.hubPoll, cancelInFlight: true)
  }
}
