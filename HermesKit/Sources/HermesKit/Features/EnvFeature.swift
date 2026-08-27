import ComposableArchitecture
import Foundation

/// API Keys / `.env` management (dashboard REST): catalog list + set/delete + optional reveal.
/// Presented from Settings when the agent exposes `GET /api/env`.
@Reducer
public struct EnvFeature {
  @ObservableState
  public struct State: Equatable {
    public var connection: ServerConnection
    /// Non-default profile name for `?profile=` scoping; `nil` omits the param.
    public var profile: String?
    public var envSupported: Bool
    /// Soft-gate for `POST /api/env/reveal` — flipped off on 401/403/404/405.
    public var revealSupported: Bool
    public var entries: IdentifiedArrayOf<EnvVarEntry>
    public var isLoading: Bool
    public var errorBanner: String?
    public var showAdvanced: Bool
    public var edit: EditState?
    public var isSaving: Bool
    public var isDeleting: Bool
    public var isRevealing: Bool
    @Presents public var confirmationDialog: ConfirmationDialogState<Action.Dialog>?

    public init(
      connection: ServerConnection,
      profile: String? = nil,
      envSupported: Bool = true,
      revealSupported: Bool = true,
      entries: IdentifiedArrayOf<EnvVarEntry> = [],
      isLoading: Bool = false,
      errorBanner: String? = nil,
      showAdvanced: Bool = false,
      edit: EditState? = nil,
      isSaving: Bool = false,
      isDeleting: Bool = false,
      isRevealing: Bool = false,
      confirmationDialog: ConfirmationDialogState<Action.Dialog>? = nil
    ) {
      self.connection = connection
      self.profile = profile
      self.envSupported = envSupported
      self.revealSupported = revealSupported
      self.entries = entries
      self.isLoading = isLoading
      self.errorBanner = errorBanner
      self.showAdvanced = showAdvanced
      self.edit = edit
      self.isSaving = isSaving
      self.isDeleting = isDeleting
      self.isRevealing = isRevealing
      self.confirmationDialog = confirmationDialog
    }

    /// Entries visible given the Advanced toggle.
    public var visibleEntries: [EnvVarEntry] {
      entries.filter { showAdvanced || !$0.advanced }
    }

    /// Category titles in stable alphabetical order for sectioning the list.
    public var categoryTitles: [String] {
      var seen = Set<String>()
      var titles: [String] = []
      for entry in visibleEntries {
        let title = entry.categoryTitle
        if seen.insert(title).inserted {
          titles.append(title)
        }
      }
      return titles.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    public func entries(in categoryTitle: String) -> [EnvVarEntry] {
      visibleEntries.filter { $0.categoryTitle == categoryTitle }
    }
  }

  /// In-flight edit sheet for one key. Plaintext `revealedValue` is never persisted — cleared
  /// on dismiss.
  public struct EditState: Equatable, Identifiable, Sendable {
    public var key: String
    public var draftValue: String
    public var revealedValue: String?
    /// Snapshot of the catalog row for UI chrome (set badge, description).
    public var entry: EnvVarEntry

    public var id: String { key }

    public init(entry: EnvVarEntry, draftValue: String = "", revealedValue: String? = nil) {
      self.key = entry.key
      self.draftValue = draftValue
      self.revealedValue = revealedValue
      self.entry = entry
    }
  }

  public enum Action: BindableAction {
    case binding(BindingAction<State>)
    case task
    case refreshTapped
    case envResponse(Result<[EnvVarEntry], RESTError>)
    case rowTapped(String)
    case draftValueChanged(String)
    case saveTapped
    case saveFinished(Result<Void, RESTError>)
    case revealTapped
    case revealFinished(Result<String, RESTError>)
    case deleteTapped
    case confirmationDialog(PresentationAction<Dialog>)
    case deleteFinished(Result<Void, RESTError>)
    case dismissEdit
    case dismissError
    case delegate(Delegate)

    public enum Dialog: Equatable {
      case confirmDelete(key: String)
    }

    @CasePathable
    public enum Delegate {
      case envUnsupported
    }
  }

  private enum CancelID { case load, save, delete, reveal }

  @Dependency(\.hermesREST) var rest

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
        return loadEnv(state)

      case let .envResponse(.success(entries)):
        state.isLoading = false
        state.envSupported = true
        state.entries = IdentifiedArray(
          entries.filter { !$0.key.isEmpty },
          uniquingIDsWith: { a, _ in a }
        )
        // Keep the edit sheet's entry snapshot in sync after a reload.
        if var edit = state.edit, let refreshed = state.entries[id: edit.key] {
          edit.entry = refreshed
          state.edit = edit
        }
        return .none

      case let .envResponse(.failure(error)):
        state.isLoading = false
        if error.isMissingEndpointVerdict {
          state.envSupported = false
          state.entries = []
          state.edit = nil
          return .send(.delegate(.envUnsupported))
        }
        state.errorBanner = error.message
        return .none

      case let .rowTapped(key):
        guard let entry = state.entries[id: key] else { return .none }
        state.edit = EditState(entry: entry)
        state.errorBanner = nil
        return .none

      case let .draftValueChanged(text):
        state.edit?.draftValue = text
        return .none

      case .saveTapped:
        guard var edit = state.edit else { return .none }
        let value = edit.draftValue
        // Empty submit is a deliberate no-op — never wipe a secret by accident.
        guard !value.isEmpty else { return .none }
        guard !state.isSaving else { return .none }
        state.isSaving = true
        state.errorBanner = nil
        let key = edit.key
        let conn = state.connection
        let profile = state.profile
        _ = edit
        return .run { [rest] send in
          do {
            try await rest.putEnv(conn, key, value, profile)
            await send(.saveFinished(.success(())))
          } catch {
            await send(.saveFinished(.failure(asRESTError(error))))
          }
        }
        .cancellable(id: CancelID.save, cancelInFlight: true)

      case .saveFinished(.success):
        state.isSaving = false
        // Clear plaintext from the sheet before dismissing.
        state.edit = nil
        state.isLoading = true
        return loadEnv(state)

      case let .saveFinished(.failure(error)):
        state.isSaving = false
        state.errorBanner = error.message
        return .none

      case .revealTapped:
        guard state.revealSupported, let edit = state.edit, edit.entry.isSet else {
          return .none
        }
        guard !state.isRevealing else { return .none }
        state.isRevealing = true
        state.errorBanner = nil
        let key = edit.key
        let conn = state.connection
        let profile = state.profile
        return .run { [rest] send in
          do {
            let value = try await rest.revealEnv(conn, key, profile)
            await send(.revealFinished(.success(value)))
          } catch {
            await send(.revealFinished(.failure(asRESTError(error))))
          }
        }
        .cancellable(id: CancelID.reveal, cancelInFlight: true)

      case let .revealFinished(.success(value)):
        state.isRevealing = false
        state.edit?.revealedValue = value
        return .none

      case let .revealFinished(.failure(error)):
        state.isRevealing = false
        if error.isRevealDeniedVerdict {
          state.revealSupported = false
          return .none
        }
        state.errorBanner = error.message
        return .none

      case .deleteTapped:
        guard let key = state.edit?.key else { return .none }
        state.confirmationDialog = ConfirmationDialogState {
          TextState("Delete \(key)?")
        } actions: {
          ButtonState(role: .destructive, action: .confirmDelete(key: key)) {
            TextState("Delete")
          }
          ButtonState(role: .cancel) {
            TextState("Cancel")
          }
        } message: {
          TextState("Removes this variable from the agent’s .env. Running sessions may need a reload or restart to pick up the change.")
        }
        return .none

      case let .confirmationDialog(.presented(.confirmDelete(key))):
        guard !state.isDeleting else { return .none }
        state.isDeleting = true
        state.errorBanner = nil
        let conn = state.connection
        let profile = state.profile
        return .run { [rest] send in
          do {
            try await rest.deleteEnv(conn, key, profile)
            await send(.deleteFinished(.success(())))
          } catch {
            await send(.deleteFinished(.failure(asRESTError(error))))
          }
        }
        .cancellable(id: CancelID.delete, cancelInFlight: true)

      case .confirmationDialog:
        return .none

      case .deleteFinished(.success):
        state.isDeleting = false
        state.edit = nil
        state.isLoading = true
        return loadEnv(state)

      case let .deleteFinished(.failure(error)):
        state.isDeleting = false
        state.errorBanner = error.message
        return .none

      case .dismissEdit:
        // Drop any revealed plaintext — never retain it after the sheet closes.
        state.edit = nil
        state.isRevealing = false
        state.isSaving = false
        return .merge(
          .cancel(id: CancelID.reveal),
          .cancel(id: CancelID.save)
        )

      case .dismissError:
        state.errorBanner = nil
        return .none

      case .delegate:
        return .none
      }
    }
    .ifLet(\.$confirmationDialog, action: \.confirmationDialog)
  }

  private func loadEnv(_ state: State) -> Effect<Action> {
    let conn = state.connection
    let profile = state.profile
    return .run { [rest] send in
      do {
        let entries = try await rest.env(conn, profile)
        await send(.envResponse(.success(entries)))
      } catch {
        await send(.envResponse(.failure(asRESTError(error))))
      }
    }
    .cancellable(id: CancelID.load, cancelInFlight: true)
  }
}
