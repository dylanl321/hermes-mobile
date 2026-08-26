import ComposableArchitecture
import Foundation

/// Agent workspace browser over the desktop remote `/api/fs/*` rail.
///
/// Roots come from session `cwd`s (+ optional `default-cwd`); browsing lists/previews
/// paths on the agent host. Presented as a sheet from the session list (Organize →
/// Workspaces) or pushed from Settings. Capability-gated: first definitive 404/405
/// flips `fsSupported` off and notifies the parent via `delegate.fsUnsupported`.
@Reducer
public struct WorkspaceBrowserFeature {
  /// In-sheet file preview (text or image data-URL).
  public struct Preview: Equatable, Sendable {
    public var path: String
    public var name: String
    public var kind: Kind
    public var truncated: Bool
    public var byteSize: Int?

    public enum Kind: Equatable, Sendable {
      case text(String)
      case imageDataURL(String)
      case binaryUnavailable(reason: String)
    }

    public init(
      path: String,
      name: String,
      kind: Kind,
      truncated: Bool = false,
      byteSize: Int? = nil
    ) {
      self.path = path
      self.name = name
      self.kind = kind
      self.truncated = truncated
      self.byteSize = byteSize
    }

    public var id: String { path }
  }

  @ObservableState
  public struct State: Equatable {
    public var connection: ServerConnection
    /// Non-default profile for `?profile=` scoping; `nil` omits.
    public var profile: String?
    public var fsSupported: Bool
    /// Session-derived roots (+ default-cwd after probe).
    public var roots: [WorkspaceRoot]
    /// `nil` = roots picker; otherwise the absolute path being listed.
    public var currentPath: String?
    public var entries: IdentifiedArrayOf<FsEntry>
    public var isLoading: Bool
    public var errorBanner: String?
    public var preview: Preview?
    public var isLoadingPreview: Bool
    /// Jump straight into this path on `.task` (session “Open workspace”).
    public var initialPath: String?
    /// Seed cwds from the parent session list (before default-cwd merge).
    public var seedSessions: [Session]
    public var lastWorkspacePath: String?

    public init(
      connection: ServerConnection,
      profile: String? = nil,
      fsSupported: Bool = true,
      roots: [WorkspaceRoot] = [],
      currentPath: String? = nil,
      entries: IdentifiedArrayOf<FsEntry> = [],
      isLoading: Bool = false,
      errorBanner: String? = nil,
      preview: Preview? = nil,
      isLoadingPreview: Bool = false,
      initialPath: String? = nil,
      seedSessions: [Session] = [],
      lastWorkspacePath: String? = nil
    ) {
      self.connection = connection
      self.profile = profile
      self.fsSupported = fsSupported
      self.roots = roots
      self.currentPath = currentPath
      self.entries = entries
      self.isLoading = isLoading
      self.errorBanner = errorBanner
      self.preview = preview
      self.isLoadingPreview = isLoadingPreview
      self.initialPath = initialPath
      self.seedSessions = seedSessions
      self.lastWorkspacePath = lastWorkspacePath
    }

    /// Basename for the navigation title while browsing.
    public var browseTitle: String {
      guard let currentPath else { return "Workspaces" }
      return SessionGroup.label(forPath: currentPath)
    }

    /// Parent directory of `currentPath`, or `nil` at filesystem root.
    public var parentPath: String? {
      guard let currentPath, currentPath != "/" else { return nil }
      let trimmed = currentPath.hasSuffix("/") ? String(currentPath.dropLast()) : currentPath
      guard let slash = trimmed.lastIndex(of: "/") else { return nil }
      if slash == trimmed.startIndex { return "/" }
      return String(trimmed[..<slash])
    }

    public var isShowingRoots: Bool { currentPath == nil }
  }

  public enum Action {
    case task
    case refreshTapped
    case bootstrapFinished(defaultCwd: FsDefaultCwd?, error: RESTError?)
    case openRoot(WorkspaceRoot)
    case openEntry(FsEntry)
    case openPath(String)
    case openParent
    case showRoots
    case listResponse(path: String, Result<FsDirectoryListing, RESTError>)
    case previewEntry(FsEntry)
    case previewTextResponse(path: String, name: String, Result<FsTextPreview, RESTError>)
    case previewDataURLResponse(path: String, name: String, Result<FsDataURL, RESTError>)
    case dismissPreview
    case dismissError
    case doneTapped
    case delegate(Delegate)

    @CasePathable
    public enum Delegate {
      case fsUnsupported
      case dismiss
    }
  }

  private enum CancelID { case bootstrap, list, preview }

  @Dependency(\.hermesREST) var rest
  @Dependency(\.preferences) var preferences

  public init() {}

  public var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .task:
        state.isLoading = true
        state.errorBanner = nil
        state.lastWorkspacePath = preferences.loadLastWorkspacePath()
        // Seed roots from sessions immediately so the picker isn’t empty while default-cwd loads.
        state.roots = WorkspaceRoot.roots(from: state.seedSessions)
        let conn = state.connection
        let profile = state.profile
        return .run { [rest] send in
          do {
            let cwd = try await rest.fsDefaultCwd(conn, profile)
            await send(.bootstrapFinished(defaultCwd: cwd, error: nil))
          } catch {
            await send(.bootstrapFinished(defaultCwd: nil, error: asRESTError(error)))
          }
        }
        .cancellable(id: CancelID.bootstrap, cancelInFlight: true)

      case let .bootstrapFinished(defaultCwd, error):
        if let error {
          if error.isMissingEndpointVerdict {
            state.isLoading = false
            state.fsSupported = false
            state.roots = []
            return .send(.delegate(.fsUnsupported))
          }
          // Soft: keep session-derived roots; surface the banner only when we have nowhere to go.
          if state.roots.isEmpty {
            state.isLoading = false
            state.errorBanner = error.message
            return .none
          }
        }

        state.fsSupported = true
        state.roots = WorkspaceRoot.roots(
          from: state.seedSessions,
          defaultCwd: defaultCwd?.cwd
        )
        // Prefer last-opened root at the top when it still exists in the inventory.
        if let last = state.lastWorkspacePath,
          let index = state.roots.firstIndex(where: { $0.path == last }),
          index > 0
        {
          let item = state.roots.remove(at: index)
          state.roots.insert(item, at: 0)
        }

        let jump = state.initialPath?.trimmingCharacters(in: .whitespacesAndNewlines)
        state.initialPath = nil
        if let jump, !jump.isEmpty {
          return openDirectory(&state, path: jump)
        }
        state.isLoading = false
        return .none

      case .refreshTapped:
        if let path = state.currentPath {
          return openDirectory(&state, path: path)
        }
        // Re-probe default-cwd + rebuild roots.
        state.isLoading = true
        state.errorBanner = nil
        let conn = state.connection
        let profile = state.profile
        return .run { [rest] send in
          do {
            let cwd = try await rest.fsDefaultCwd(conn, profile)
            await send(.bootstrapFinished(defaultCwd: cwd, error: nil))
          } catch {
            await send(.bootstrapFinished(defaultCwd: nil, error: asRESTError(error)))
          }
        }
        .cancellable(id: CancelID.bootstrap, cancelInFlight: true)

      case let .openRoot(root):
        return openDirectory(&state, path: root.path)

      case let .openEntry(entry):
        guard !entry.path.isEmpty else { return .none }
        if entry.isDirectory {
          return openDirectory(&state, path: entry.path)
        }
        return .send(.previewEntry(entry))

      case let .openPath(path):
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .none }
        return openDirectory(&state, path: trimmed)

      case .openParent:
        guard let parent = state.parentPath else {
          return .send(.showRoots)
        }
        return openDirectory(&state, path: parent)

      case .showRoots:
        state.currentPath = nil
        state.entries = []
        state.preview = nil
        state.errorBanner = nil
        state.isLoading = false
        return .none

      case let .listResponse(path, .success(listing)):
        guard state.currentPath == path else { return .none }
        state.isLoading = false
        let sorted = listing.entries
          .filter { !$0.name.isEmpty && !$0.path.isEmpty }
          .sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory && !$1.isDirectory }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
          }
        state.entries = IdentifiedArray(uniqueElements: sorted)
        state.errorBanner = listing.errorBanner
        preferences.saveLastWorkspacePath(path)
        state.lastWorkspacePath = path
        return .none

      case let .listResponse(path, .failure(error)):
        guard state.currentPath == path else { return .none }
        state.isLoading = false
        state.entries = []
        if error.isMissingEndpointVerdict {
          state.fsSupported = false
          return .send(.delegate(.fsUnsupported))
        }
        if error.statusCode == 403 {
          state.errorBanner = "Access to that path isn’t allowed on this agent."
          return .none
        }
        state.errorBanner = error.message
        return .none

      case let .previewEntry(entry):
        state.isLoadingPreview = true
        state.errorBanner = nil
        let conn = state.connection
        let profile = state.profile
        let path = entry.path
        let name = entry.name
        if Self.isLikelyImage(name: name) {
          return .run { [rest] send in
            do {
              let data = try await rest.fsReadDataURL(conn, path, profile)
              await send(.previewDataURLResponse(path: path, name: name, .success(data)))
            } catch {
              await send(.previewDataURLResponse(path: path, name: name, .failure(asRESTError(error))))
            }
          }
          .cancellable(id: CancelID.preview, cancelInFlight: true)
        }
        return .run { [rest] send in
          do {
            let preview = try await rest.fsReadText(conn, path, profile)
            await send(.previewTextResponse(path: path, name: name, .success(preview)))
          } catch {
            await send(.previewTextResponse(path: path, name: name, .failure(asRESTError(error))))
          }
        }
        .cancellable(id: CancelID.preview, cancelInFlight: true)

      case let .previewTextResponse(path, name, .success(preview)):
        state.isLoadingPreview = false
        if preview.binary {
          // Fall through to data-URL for binary sniff.
          let conn = state.connection
          let profile = state.profile
          return .run { [rest] send in
            do {
              let data = try await rest.fsReadDataURL(conn, path, profile)
              await send(.previewDataURLResponse(path: path, name: name, .success(data)))
            } catch {
              await send(.previewDataURLResponse(path: path, name: name, .failure(asRESTError(error))))
            }
          }
          .cancellable(id: CancelID.preview, cancelInFlight: true)
        }
        state.preview = Preview(
          path: path,
          name: name,
          kind: .text(preview.text),
          truncated: preview.truncated,
          byteSize: preview.byteSize
        )
        return .none

      case let .previewTextResponse(path, name, .failure(error)):
        state.isLoadingPreview = false
        if error.isMissingEndpointVerdict {
          state.fsSupported = false
          return .send(.delegate(.fsUnsupported))
        }
        if error.statusCode == 413 {
          state.preview = Preview(
            path: path,
            name: name,
            kind: .binaryUnavailable(reason: "File is too large to preview.")
          )
          return .none
        }
        state.errorBanner = error.message
        return .none

      case let .previewDataURLResponse(path, name, .success(payload)):
        state.isLoadingPreview = false
        let url = payload.dataUrl
        if url.isEmpty {
          state.preview = Preview(
            path: path,
            name: name,
            kind: .binaryUnavailable(reason: "No preview available for this file.")
          )
        } else if Self.isLikelyImage(name: name) || url.hasPrefix("data:image/") {
          state.preview = Preview(path: path, name: name, kind: .imageDataURL(url))
        } else {
          state.preview = Preview(
            path: path,
            name: name,
            kind: .binaryUnavailable(reason: "Binary file — preview isn’t available on mobile.")
          )
        }
        return .none

      case let .previewDataURLResponse(_, _, .failure(error)):
        state.isLoadingPreview = false
        if error.isMissingEndpointVerdict {
          state.fsSupported = false
          return .send(.delegate(.fsUnsupported))
        }
        state.errorBanner = error.message
        return .none

      case .dismissPreview:
        state.preview = nil
        state.isLoadingPreview = false
        return .cancel(id: CancelID.preview)

      case .dismissError:
        state.errorBanner = nil
        return .none

      case .doneTapped:
        return .send(.delegate(.dismiss))

      case .delegate:
        return .none
      }
    }
  }

  private func openDirectory(_ state: inout State, path: String) -> Effect<Action> {
    state.currentPath = path
    state.preview = nil
    state.isLoading = true
    state.errorBanner = nil
    state.entries = []
    let conn = state.connection
    let profile = state.profile
    return .run { [rest] send in
      do {
        let listing = try await rest.fsList(conn, path, profile)
        await send(.listResponse(path: path, .success(listing)))
      } catch {
        await send(.listResponse(path: path, .failure(asRESTError(error))))
      }
    }
    .cancellable(id: CancelID.list, cancelInFlight: true)
  }

  static func isLikelyImage(name: String) -> Bool {
    let ext = (name as NSString).pathExtension.lowercased()
    return ["png", "jpg", "jpeg", "gif", "webp", "heic", "bmp", "tif", "tiff"].contains(ext)
  }
}

extension RESTError {
  /// HTTP status when this is a `.server` / `.notFound` / `.unauthorized` verdict; else `nil`.
  fileprivate var statusCode: Int? {
    switch self {
    case .notFound: return 404
    case .unauthorized: return 401
    case let .server(status, _): return status
    default: return nil
    }
  }
}
