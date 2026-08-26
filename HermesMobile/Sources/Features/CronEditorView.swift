import ComposableArchitecture
import HermesKit
import SwiftUI

/// Create/edit cron job sheet — binds to `SessionListFeature.State.cronEditor`.
struct CronEditorView: View {
  @Bindable var store: StoreOf<SessionListFeature>

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("Name (optional)", text: nameBinding)
          TextField("Prompt", text: promptBinding, axis: .vertical)
            .lineLimit(3...8)
          TextField("Schedule", text: scheduleBinding)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
          TextField("Deliver (optional)", text: deliverBinding)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        } footer: {
          Text("Schedule uses cron syntax (e.g. \"0 9 * * *\" for 9:00 daily).")
        }

        if let error = store.cronEditor?.error {
          Section {
            Label(error, systemImage: "exclamationmark.triangle.fill")
              .font(.footnote)
              .foregroundStyle(.red)
          }
        }

        Section {
          Button {
            store.send(.cronEditorSaveTapped)
          } label: {
            HStack {
              Spacer()
              if store.cronEditor?.isSaving == true {
                ProgressView()
              } else {
                Text(store.cronEditor?.isEdit == true ? "Save changes" : "Create job")
              }
              Spacer()
            }
          }
          .disabled(store.cronEditor?.canSave != true)
        }
      }
      .navigationTitle(store.cronEditor?.navigationTitle ?? "Cron job")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { store.send(.cronEditorDismissed) }
        }
      }
    }
  }

  private var nameBinding: Binding<String> {
    Binding(
      get: { store.cronEditor?.name ?? "" },
      set: { store.send(.cronEditorBinding(.name($0))) }
    )
  }

  private var promptBinding: Binding<String> {
    Binding(
      get: { store.cronEditor?.prompt ?? "" },
      set: { store.send(.cronEditorBinding(.prompt($0))) }
    )
  }

  private var scheduleBinding: Binding<String> {
    Binding(
      get: { store.cronEditor?.schedule ?? "" },
      set: { store.send(.cronEditorBinding(.schedule($0))) }
    )
  }

  private var deliverBinding: Binding<String> {
    Binding(
      get: { store.cronEditor?.deliver ?? "" },
      set: { store.send(.cronEditorBinding(.deliver($0))) }
    )
  }
}
