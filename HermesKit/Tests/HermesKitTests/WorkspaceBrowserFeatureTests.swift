import ComposableArchitecture
import Foundation
import Testing

@testable import HermesKit

@MainActor
struct WorkspaceBrowserFeatureTests {
  private let connection = ServerConnection(
    baseURL: URL(string: "http://test.local:9119")!,
    token: "tok"
  )

  @Test func bootstrapBuildsRootsAndStaysOnPicker() async {
    let sessions = [
      Session(id: "a", cwd: "/Users/me/dev/hermes-mobile"),
      Session(id: "b", cwd: "/Users/me/dev/hermes-agent"),
    ]
    let store = TestStore(
      initialState: WorkspaceBrowserFeature.State(
        connection: connection,
        seedSessions: sessions
      )
    ) {
      WorkspaceBrowserFeature()
    } withDependencies: {
      $0.hermesREST.fsDefaultCwd = { @Sendable _, _ in
        FsDefaultCwd(cwd: "/Users/me", branch: "main")
      }
      $0.preferences = .inMemory()
    }

    await store.send(.task) {
      $0.isLoading = true
      $0.roots = WorkspaceRoot.roots(from: sessions)
    }
    await store.receive(\.bootstrapFinished) {
      $0.isLoading = false
      $0.fsSupported = true
      $0.roots = WorkspaceRoot.roots(from: sessions, defaultCwd: "/Users/me")
    }
  }

  @Test func missingDefaultCwdFlipsCapabilityOff() async {
    let store = TestStore(
      initialState: WorkspaceBrowserFeature.State(connection: connection)
    ) {
      WorkspaceBrowserFeature()
    } withDependencies: {
      $0.hermesREST.fsDefaultCwd = { @Sendable _, _ in throw RESTError.notFound }
      $0.preferences = .inMemory()
    }

    await store.send(.task) {
      $0.isLoading = true
      $0.roots = []
    }
    await store.receive(\.bootstrapFinished) {
      $0.isLoading = false
      $0.fsSupported = false
      $0.roots = []
    }
    await store.receive(\.delegate.fsUnsupported)
  }

  @Test func openRootListsDirectory() async {
    let store = TestStore(
      initialState: WorkspaceBrowserFeature.State(
        connection: connection,
        roots: [WorkspaceRoot(path: "/w")],
        seedSessions: [Session(id: "a", cwd: "/w")]
      )
    ) {
      WorkspaceBrowserFeature()
    } withDependencies: {
      $0.hermesREST.fsList = { @Sendable _, path, _ in
        #expect(path == "/w")
        return FsDirectoryListing(entries: [
          FsEntry(name: "src", path: "/w/src", isDirectory: true),
          FsEntry(name: "README.md", path: "/w/README.md", isDirectory: false),
        ])
      }
      $0.preferences = .inMemory()
    }

    await store.send(.openRoot(WorkspaceRoot(path: "/w"))) {
      $0.currentPath = "/w"
      $0.isLoading = true
      $0.entries = []
      $0.errorBanner = nil
      $0.preview = nil
    }
    await store.receive(\.listResponse) {
      $0.isLoading = false
      $0.entries = [
        FsEntry(name: "src", path: "/w/src", isDirectory: true),
        FsEntry(name: "README.md", path: "/w/README.md", isDirectory: false),
      ]
      $0.lastWorkspacePath = "/w"
    }
  }

  @Test func softEnoentSurfacesBanner() async {
    let store = TestStore(
      initialState: WorkspaceBrowserFeature.State(
        connection: connection,
        currentPath: "/gone"
      )
    ) {
      WorkspaceBrowserFeature()
    } withDependencies: {
      $0.hermesREST.fsList = { @Sendable _, _, _ in
        FsDirectoryListing(entries: [], error: "ENOENT")
      }
      $0.preferences = .inMemory()
    }

    await store.send(.refreshTapped) {
      $0.isLoading = true
      $0.errorBanner = nil
      $0.entries = []
      $0.preview = nil
    }
    await store.receive(\.listResponse) {
      $0.isLoading = false
      $0.entries = []
      $0.errorBanner = FsDirectoryListing(error: "ENOENT").errorBanner
      $0.lastWorkspacePath = "/gone"
    }
  }

  @Test func initialPathJumpsIntoBrowse() async {
    let store = TestStore(
      initialState: WorkspaceBrowserFeature.State(
        connection: connection,
        initialPath: "/w",
        seedSessions: [Session(id: "a", cwd: "/w")]
      )
    ) {
      WorkspaceBrowserFeature()
    } withDependencies: {
      $0.hermesREST.fsDefaultCwd = { @Sendable _, _ in
        FsDefaultCwd(cwd: "/w")
      }
      $0.hermesREST.fsList = { @Sendable _, path, _ in
        #expect(path == "/w")
        return FsDirectoryListing(entries: [
          FsEntry(name: "a.txt", path: "/w/a.txt", isDirectory: false),
        ])
      }
      $0.preferences = .inMemory()
    }

    await store.send(.task) {
      $0.isLoading = true
      $0.roots = [WorkspaceRoot(path: "/w")]
    }
    await store.receive(\.bootstrapFinished) {
      $0.fsSupported = true
      $0.roots = [WorkspaceRoot(path: "/w")]
      $0.initialPath = nil
      $0.currentPath = "/w"
      $0.isLoading = true
      $0.entries = []
      $0.preview = nil
      $0.errorBanner = nil
    }
    await store.receive(\.listResponse) {
      $0.isLoading = false
      $0.entries = [FsEntry(name: "a.txt", path: "/w/a.txt", isDirectory: false)]
      $0.lastWorkspacePath = "/w"
    }
  }

  @Test func previewTextFile() async {
    let store = TestStore(
      initialState: WorkspaceBrowserFeature.State(
        connection: connection,
        currentPath: "/w"
      )
    ) {
      WorkspaceBrowserFeature()
    } withDependencies: {
      $0.hermesREST.fsReadText = { @Sendable _, path, _ in
        #expect(path == "/w/a.swift")
        return FsTextPreview(path: path, text: "let x = 1", truncated: false)
      }
      $0.preferences = .inMemory()
    }

    let entry = FsEntry(name: "a.swift", path: "/w/a.swift", isDirectory: false)
    await store.send(.previewEntry(entry)) {
      $0.isLoadingPreview = true
      $0.errorBanner = nil
    }
    await store.receive(\.previewTextResponse) {
      $0.isLoadingPreview = false
      $0.preview = WorkspaceBrowserFeature.Preview(
        path: "/w/a.swift",
        name: "a.swift",
        kind: .text("let x = 1")
      )
    }
  }

  @Test func parentPathComputation() {
    var state = WorkspaceBrowserFeature.State(connection: connection, currentPath: "/a/b/c")
    #expect(state.parentPath == "/a/b")
    state.currentPath = "/a"
    #expect(state.parentPath == "/")
    state.currentPath = "/"
    #expect(state.parentPath == nil)
  }
}
