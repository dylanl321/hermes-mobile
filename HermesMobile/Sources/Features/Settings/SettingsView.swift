import ComposableArchitecture
import HermesKit
import SwiftUI
import UIKit

/// Settings sheet: server info, token re-paste/clear, manual reconnect, and a link to
/// the live connection debug log.
struct SettingsView: View {
  @Bindable var store: StoreOf<SettingsFeature>
  /// Presentation-only: the "how push works / install the plugin" info sheet. Pure view
  /// state — there's no reducer behavior behind it.
  @State private var showingPushGuide = false

  var body: some View {
    Form {
      serverSection
      managementSection
      quickEditsSection
      modelSection
      tokenSection
      connectionSection
      swipeActionSection
      notificationsSection
      disconnectSection
    }
    .navigationTitle("Settings")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        Button("Done") { store.send(.doneTapped) }
      }
    }
    .sheet(isPresented: $showingPushGuide) {
      PushSetupGuideView(
        // Installed → the sheet drops the "Later" snooze and asks the agent to UPDATE rather
        // than install. It is never purely informational: an installed-but-outdated plugin is
        // exactly the case that needs an action here.
        pluginInstalled: store.pushAvailable,
        onAskAgent: {
          showingPushGuide = false
          store.send(.askAgentToInstallTapped)
        },
        onLater: { showingPushGuide = false }
      )
    }
    .task { store.send(.task) }
    .navigationDestination(
      item: $store.scope(state: \.skills, action: \.skills)
    ) { skillsStore in
      SkillsView(store: skillsStore)
    }
    .navigationDestination(
      item: $store.scope(state: \.env, action: \.env)
    ) { envStore in
      EnvView(store: envStore)
    }
  }

  // MARK: - Sections (split so the type checker stays under budget)

  private var serverSection: some View {
    Section("Server") {
      LabeledContent("URL", value: store.serverURLString)
    }
  }

  @ViewBuilder
  private var managementSection: some View {
    if store.skillsSupported || store.envSupported || store.fsSupported {
      Section("Management") {
        if store.skillsSupported {
          Button {
            store.send(.openSkillsTapped)
          } label: {
            Label("Skills", systemImage: "puzzlepiece.extension")
          }
        }
        if store.envSupported {
          Button {
            store.send(.openEnvTapped)
          } label: {
            Label("API Keys", systemImage: "key.fill")
          }
        }
        if store.fsSupported {
          Button {
            store.send(.openWorkspacesTapped)
          } label: {
            Label("Workspaces", systemImage: "folder")
          }
        }
      }
    }
  }

  @ViewBuilder
  private var quickEditsSection: some View {
    if store.configSupported {
      Section {
        if store.isLoadingConfig && store.configDocument == nil {
          ProgressView("Loading config…")
        } else {
          ForEach(store.availableQuickEditKeys, id: \.rawValue) { key in
            quickEditRow(key)
          }
        }
        if let error = store.configError {
          Label(error, systemImage: "exclamationmark.triangle")
            .foregroundStyle(.orange)
            .font(.footnote)
        }
      } header: {
        Text("Quick edits")
      } footer: {
        Text("Curated config.yaml keys. Changes apply on the next agent session.")
      }
    }
  }

  @ViewBuilder
  private var modelSection: some View {
    if store.modelRESTSupported {
      Section {
        modelSectionContent
        if let error = store.modelError {
          Label(error, systemImage: "exclamationmark.triangle")
            .foregroundStyle(.orange)
            .font(.footnote)
        }
      } header: {
        Text("Default model")
      }
    }
  }

  @ViewBuilder
  private var modelSectionContent: some View {
    if store.isLoadingModels && store.modelOptions == nil {
      ProgressView("Loading models…")
    } else if let options = store.modelOptions {
      ForEach(options.orderedProviders) { provider in
        modelProviderRows(provider: provider, currentModel: options.currentModel)
      }
    }
  }

  @ViewBuilder
  private func modelProviderRows(
    provider: ModelOptions.Provider,
    currentModel: String?
  ) -> some View {
    if provider.isConfigured {
      ForEach(provider.models, id: \.self) { model in
        Button {
          store.send(.selectModel(model: model, provider: provider.slug ?? provider.name))
        } label: {
          HStack {
            Text(model)
            Spacer()
            if currentModel == model {
              Image(systemName: "checkmark")
                .foregroundStyle(Color.hermesAccent)
            }
          }
        }
        .disabled(store.isSettingModel)
      }
    }
  }

  private var tokenSection: some View {
    Section {
      SecureField("Session token", text: $store.token)
        .textContentType(.password)
      Button("Save token") { store.send(.saveTokenTapped) }
        .disabled(!store.canSaveToken)
      if store.savedConfirmation {
        Label("Token saved", systemImage: "checkmark.circle")
          .foregroundStyle(.green).font(.footnote)
      }
    } header: {
      Text("Token")
    } footer: {
      Text("Re-paste the stable token if it changed on the server.")
    }
  }

  private var connectionSection: some View {
    Section("Connection") {
      Button("Switch server") { store.send(.switchServerTapped) }
      Button("Reconnect") { store.send(.reconnectTapped) }
      NavigationLink {
        ConnectionDebugView(entries: store.log)
      } label: {
        LabeledContent("Debug log", value: "\(store.log.count)")
      }
    }
  }

  @ViewBuilder
  private var swipeActionSection: some View {
    // Only offered when the agent supports session deletion — otherwise Archive is the
    // only destructive action and the choice would be meaningless.
    if store.deleteSupported {
      Section {
        Picker(
          "Default swipe action",
          selection: Binding(
            get: { store.defaultSwipeAction },
            set: { store.send(.defaultSwipeActionChanged($0)) }
          )
        ) {
          Text("Archive").tag(SessionSwipeAction.archive)
          Text("Delete").tag(SessionSwipeAction.delete)
        }
      } header: {
        Text("Session list")
      } footer: {
        Text("The action a full swipe on a session row triggers. The long-press menu always offers both.")
      }
    }
  }

  private var notificationsSection: some View {
    Section {
      pluginUpdateRows
      pushToggleRows
    } header: {
      Text("Notifications")
    } footer: {
      if store.pushAvailable {
        Text("Get a push when Hermes needs your approval, even while the app is closed.")
      } else {
        Text("Needs the hermes-push plugin running on your agent.")
      }
    }
  }

  @ViewBuilder
  private var pluginUpdateRows: some View {
    // Plugin update, offered above the toggle because an out-of-date plugin sends pushes
    // the user is actively complaining about. Shown whether or not push is currently
    // available — an installed-but-disabled plugin is still worth updating.
    if store.pluginUpdateAvailable {
      VStack(alignment: .leading, spacing: 4) {
        Label("Plugin update available", systemImage: "arrow.down.circle")
          .font(.subheadline.weight(.semibold))
        Text(pluginUpdateExplanation)
          .font(.footnote).foregroundStyle(.secondary)
      }
      Button("Update plugin") { store.send(.updatePluginTapped) }
        .disabled(store.pluginUpdate == .updating)
    } else if store.pluginUpdateNeedsManualSteps {
      // Out of date but the agent can't pull it (pip install / hand-copied directory), so
      // a button here would only 400. Route to the guide, which offers the chat prompt.
      VStack(alignment: .leading, spacing: 4) {
        Label("Plugin update available", systemImage: "arrow.down.circle")
          .font(.subheadline.weight(.semibold))
        Text("\(pluginUpdateExplanation) This copy can't be updated from the app — ask your agent to update it.")
          .font(.footnote).foregroundStyle(.secondary)
      }
      Button("How to update the plugin") { showingPushGuide = true }
        .font(.footnote)
    }
    switch store.pluginUpdate {
    case .idle:
      EmptyView()
    case .updating:
      Label("Updating…", systemImage: "arrow.triangle.2.circlepath")
        .foregroundStyle(.secondary).font(.footnote)
    case .updated:
      // A pull only changes files on disk — the running agent keeps the old code loaded.
      // This restart notice is the whole point of the success state; don't soften it.
      Label(
        "Plugin updated. Restart your Hermes agent to apply it.",
        systemImage: "exclamationmark.arrow.triangle.2.circlepath"
      )
      .foregroundStyle(.orange).font(.footnote)
    case .alreadyCurrent:
      Label("Plugin is already up to date", systemImage: "checkmark.circle")
        .foregroundStyle(.green).font(.footnote)
    case let .failed(reason):
      Label(reason, systemImage: "exclamationmark.triangle")
        .foregroundStyle(.orange).font(.footnote)
    }
  }

  @ViewBuilder
  private var pushToggleRows: some View {
    if store.pushAvailable {
      Toggle(
        "Notify me about approvals",
        isOn: Binding(
          get: { store.notificationsEnabled },
          set: { store.send(.notificationsToggled($0)) }
        )
      )
      if store.notificationsDenied {
        VStack(alignment: .leading, spacing: 4) {
          Label("Notifications are turned off", systemImage: "bell.slash")
            .foregroundStyle(.orange).font(.footnote)
          if let url = URL(string: UIApplication.openSettingsURLString) {
            Link("Enable in iOS Settings", destination: url)
              .font(.footnote)
          }
        }
      }
      Button("Send test notification") { store.send(.sendTestPushTapped) }
        .disabled(store.testPushStatus == .sending)
      switch store.testPushStatus {
      case .idle:
        EmptyView()
      case .sending:
        Label("Sending…", systemImage: "paperplane")
          .foregroundStyle(.secondary).font(.footnote)
      case .sent:
        Label("Test notification sent", systemImage: "checkmark.circle")
          .foregroundStyle(.green).font(.footnote)
      case .failed:
        Label("Couldn't send test notification", systemImage: "exclamationmark.triangle")
          .foregroundStyle(.orange).font(.footnote)
      }
      Button("How push notifications work") { showingPushGuide = true }
        .font(.footnote)
    } else {
      Label("Notifications aren't available on this server", systemImage: "bell.slash")
        .foregroundStyle(.secondary).font(.footnote)
      Button("How to enable push notifications") { showingPushGuide = true }
    }
  }

  private var disconnectSection: some View {
    Section {
      Button("Clear token & disconnect", role: .destructive) {
        store.send(.clearTokenTapped)
      }
    } footer: {
      Text("Removes the token from the Keychain and returns to the connection screen.")
    }
  }

  @ViewBuilder
  private func quickEditRow(_ key: ConfigQuickEditKey) -> some View {
    let current = store.configDocument.flatMap { AgentConfigDocument.value(at: key.rawValue, in: $0) }
    if key.isBoolean {
      Toggle(
        key.title,
        isOn: Binding(
          get: { current?.boolValue ?? false },
          set: { store.send(.setConfigBool(key, $0)) }
        )
      )
      .disabled(store.configSavingKey == key.rawValue)
    } else {
      LabeledContent(key.title) {
        TextField(
          key.title,
          text: Binding(
            get: { quickEditText(from: current) },
            set: { store.send(.setConfigString(key, $0)) }
          )
        )
        .multilineTextAlignment(.trailing)
        .disabled(store.configSavingKey == key.rawValue)
      }
    }
  }

  private func quickEditText(from value: JSONValue?) -> String {
    if let string = value?.stringValue { return string }
    if let number = value?.doubleValue {
      return number == number.rounded() ? String(Int(number)) : String(number)
    }
    return ""
  }

  /// Why the update matters, naming both versions when the agent reported one. Kept in the
  /// view because it is pure display copy — the decision to show it lives in the reducer.
  private var pluginUpdateExplanation: String {
    let latest = PushSetup.minimumPluginVersion
    let reason = "Older versions send a “Turn complete” push each time a delegated subagent finishes."
    guard let installed = store.pushPlugin?.version else {
      return "Update to \(latest). \(reason)"
    }
    return "Installed \(installed), latest \(latest). \(reason)"
  }
}
