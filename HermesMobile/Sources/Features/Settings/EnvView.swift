import ComposableArchitecture
import HermesKit
import SwiftUI

struct EnvView: View {
  @Bindable var store: StoreOf<EnvFeature>

  var body: some View {
    List {
      errorBannerSection
      advancedToggleSection
      catalogSection
    }
    .navigationTitle("API Keys")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button("Refresh") { store.send(.refreshTapped) }
          .disabled(store.isLoading)
      }
    }
    .safeAreaInset(edge: .bottom) {
      footerNote
    }
    .sheet(item: editSheetBinding) { edit in
      EnvEditSheet(store: store, edit: edit)
    }
    .bottomActionSheet(
      $store.scope(state: \.confirmationDialog, action: \.confirmationDialog)
    )
    .task { store.send(.task) }
  }

  // MARK: - Sections (split so the type checker stays under budget)

  @ViewBuilder
  private var errorBannerSection: some View {
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

  private var advancedToggleSection: some View {
    Section {
      Toggle("Show advanced keys", isOn: $store.showAdvanced)
    }
  }

  @ViewBuilder
  private var catalogSection: some View {
    if store.isLoading && store.entries.isEmpty {
      Section {
        ProgressView("Loading keys…")
      }
    } else if store.visibleEntries.isEmpty {
      Section {
        Text(emptyCatalogMessage)
          .foregroundStyle(.secondary)
      }
    } else {
      ForEach(store.categoryTitles, id: \.self) { category in
        EnvCategorySection(
          category: category,
          entries: store.state.entriesInCategory(category),
          onRowTapped: { store.send(.rowTapped($0)) }
        )
      }
    }
  }

  private var emptyCatalogMessage: String {
    store.showAdvanced
      ? "No environment variables in the catalog."
      : "No keys to show. Turn on advanced to see rarely-used variables."
  }

  private var footerNote: some View {
    Text("Edits write to the agent’s .env. New sessions pick them up; a running CLI may need /reload.")
      .font(.caption)
      .foregroundStyle(.secondary)
      .padding(.horizontal)
      .padding(.vertical, 8)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.bar)
  }

  private var editSheetBinding: Binding<EnvFeature.EditState?> {
    Binding(
      get: { store.edit },
      set: { if $0 == nil { store.send(.dismissEdit) } }
    )
  }
}

private struct EnvCategorySection: View {
  let category: String
  let entries: [EnvVarEntry]
  let onRowTapped: (String) -> Void

  var body: some View {
    Section(category) {
      ForEach(entries) { entry in
        Button {
          onRowTapped(entry.key)
        } label: {
          EnvRowLabel(entry: entry)
        }
      }
    }
  }
}

private struct EnvRowLabel: View {
  let entry: EnvVarEntry

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text(entry.key)
          .font(.body.monospaced())
          .foregroundStyle(.primary)
        Spacer(minLength: 8)
        Text(entry.isSet ? "Set" : "Unset")
          .font(.caption.weight(.semibold))
          .foregroundStyle(entry.isSet ? .green : .secondary)
      }
      if let preview = entry.redactedValue, !preview.isEmpty {
        Text(preview)
          .font(.caption.monospaced())
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      if !entry.description.isEmpty {
        Text(entry.description)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
          .multilineTextAlignment(.leading)
      }
    }
  }
}

private struct EnvEditSheet: View {
  @Bindable var store: StoreOf<EnvFeature>
  let edit: EnvFeature.EditState

  var body: some View {
    NavigationStack {
      Form {
        keySection
        valueSection
        revealSection
        deleteSection
      }
      .navigationTitle(edit.key)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Close") { store.send(.dismissEdit) }
        }
      }
    }
    .presentationDetents([.medium, .large])
  }

  @ViewBuilder
  private var keySection: some View {
    Section {
      LabeledContent("Key", value: edit.key)
      LabeledContent("Status", value: edit.entry.isSet ? "Set" : "Unset")
      if let preview = edit.entry.redactedValue, !preview.isEmpty {
        LabeledContent("Preview", value: preview)
      }
    } footer: {
      if !edit.entry.description.isEmpty {
        Text(edit.entry.description)
      }
    }
  }

  private var valueSection: some View {
    Section {
      SecureField("New value", text: draftValueBinding)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .disabled(store.isSaving || store.isDeleting)

      Button {
        store.send(.saveTapped)
      } label: {
        if store.isSaving {
          ProgressView()
        } else {
          Text("Save")
        }
      }
      .disabled(store.isSaving || store.isDeleting || draftIsEmpty)
    } footer: {
      Text("Leave blank and dismiss to keep the current value. Saving overwrites the stored secret.")
    }
  }

  @ViewBuilder
  private var revealSection: some View {
    if let revealed = store.edit?.revealedValue ?? edit.revealedValue {
      Section("Revealed value") {
        Text(revealed)
          .font(.body.monospaced())
          .textSelection(.enabled)
      }
    } else if store.revealSupported, edit.entry.isSet {
      Section {
        Button {
          store.send(.revealTapped)
        } label: {
          if store.isRevealing {
            ProgressView()
          } else {
            Label("Reveal current value", systemImage: "eye")
          }
        }
        .disabled(store.isRevealing || store.isSaving || store.isDeleting)
      } footer: {
        Text("Some agents only allow reveal from the web dashboard. If reveal fails, overwrite with a new value instead.")
      }
    }
  }

  @ViewBuilder
  private var deleteSection: some View {
    if edit.entry.isSet {
      Section {
        Button("Delete", role: .destructive) {
          store.send(.deleteTapped)
        }
        .disabled(store.isSaving || store.isDeleting || store.isRevealing)
      }
    }
  }

  private var draftValueBinding: Binding<String> {
    Binding(
      get: { store.edit?.draftValue ?? "" },
      set: { store.send(.draftValueChanged($0)) }
    )
  }

  private var draftIsEmpty: Bool {
    store.edit?.draftValue.isEmpty ?? true
  }
}
