import ComposableArchitecture
import HermesKit
import SwiftUI
import UIKit

/// Agent workspace browser: roots picker → directory list → text/image preview.
struct WorkspaceBrowserView: View {
  @Bindable var store: StoreOf<WorkspaceBrowserFeature>

  var body: some View {
    Group {
      if store.isShowingRoots {
        rootsList
      } else {
        directoryList
      }
    }
    .navigationTitle(store.browseTitle)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        Button("Done") { store.send(.doneTapped) }
      }
      if !store.isShowingRoots {
        ToolbarItem(placement: .topBarLeading) {
          Button {
            store.send(.openParent)
          } label: {
            Label(
              store.parentPath == nil ? "Workspaces" : "Up",
              systemImage: "chevron.backward"
            )
          }
        }
      }
    }
    .task { store.send(.task) }
    .refreshable { store.send(.refreshTapped) }
    .sheet(
      isPresented: Binding(
        get: { store.preview != nil || store.isLoadingPreview },
        set: { presented in if !presented { store.send(.dismissPreview) } }
      )
    ) {
      previewSheet
    }
  }

  @ViewBuilder
  private var rootsList: some View {
    List {
      bannerSection
      if store.isLoading && store.roots.isEmpty {
        ProgressView("Loading workspaces…")
      } else if store.roots.isEmpty {
        ContentUnavailableView(
          "No workspaces yet",
          systemImage: "folder",
          description: Text("Session working directories appear here once chats have a project path.")
        )
      } else {
        Section {
          ForEach(store.roots) { root in
            Button {
              store.send(.openRoot(root))
            } label: {
              Label {
                VStack(alignment: .leading, spacing: 2) {
                  Text(root.label)
                  Text(root.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                }
              } icon: {
                Image(systemName: "folder.fill")
              }
            }
            .foregroundStyle(.primary)
          }
        } footer: {
          Text("Project folders Hermes has opened, derived from session working directories on the agent.")
        }
      }
    }
  }

  @ViewBuilder
  private var directoryList: some View {
    List {
      bannerSection
      if let path = store.currentPath {
        Section {
          Text(path)
            .font(.caption)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
        }
      }
      Section {
        if store.isLoading && store.entries.isEmpty {
          ProgressView("Loading…")
        } else if store.entries.isEmpty {
          Text("Empty folder")
            .foregroundStyle(.secondary)
        } else {
          ForEach(store.entries) { entry in
            Button {
              store.send(.openEntry(entry))
            } label: {
              Label {
                Text(entry.name)
                  .lineLimit(1)
              } icon: {
                Image(systemName: entry.isDirectory ? "folder.fill" : "doc")
              }
            }
            .foregroundStyle(.primary)
          }
        }
      }
    }
  }

  @ViewBuilder
  private var bannerSection: some View {
    if let banner = store.errorBanner {
      Section {
        Label(banner, systemImage: "exclamationmark.triangle")
          .foregroundStyle(.orange)
          .font(.footnote)
        Button("Dismiss") { store.send(.dismissError) }
          .font(.footnote)
      }
    }
  }

  @ViewBuilder
  private var previewSheet: some View {
    NavigationStack {
      Group {
        if store.isLoadingPreview {
          ProgressView("Loading preview…")
        } else if let preview = store.preview {
          previewBody(preview)
        } else {
          ProgressView()
        }
      }
      .navigationTitle(store.preview?.name ?? "Preview")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Close") { store.send(.dismissPreview) }
        }
      }
    }
  }

  @ViewBuilder
  private func previewBody(_ preview: WorkspaceBrowserFeature.Preview) -> some View {
    switch preview.kind {
    case let .text(text):
      ScrollView {
        VStack(alignment: .leading, spacing: 8) {
          if preview.truncated {
            Text("Preview truncated")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Text(text)
            .font(.system(.body, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
      }
    case let .imageDataURL(dataURL):
      if let data = Data(dataURLContents: dataURL), let image = UIImage(data: data) {
        ScrollView {
          Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .padding()
        }
      } else {
        ContentUnavailableView("Couldn’t decode image", systemImage: "photo")
      }
    case let .binaryUnavailable(reason):
      ContentUnavailableView {
        Label("No preview", systemImage: "doc")
      } description: {
        Text(reason)
      }
    }
  }
}

private extension Data {
  /// Decode a `data:[mime];base64,…` URL into raw bytes. Returns `nil` when the prefix
  /// or base64 payload is malformed.
  init?(dataURLContents dataURL: String) {
    guard let comma = dataURL.firstIndex(of: ",") else { return nil }
    let encoded = String(dataURL[dataURL.index(after: comma)...])
    guard let data = Data(base64Encoded: encoded) else { return nil }
    self = data
  }
}
