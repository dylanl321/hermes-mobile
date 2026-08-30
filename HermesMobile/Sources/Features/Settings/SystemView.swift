import ComposableArchitecture
import HermesKit
import SwiftUI

struct SystemView: View {
  @Bindable var store: StoreOf<SystemFeature>

  var body: some View {
    Form {
      if let banner = store.errorBanner {
        Section {
          Label(banner, systemImage: "exclamationmark.triangle")
            .foregroundStyle(.orange)
            .font(.footnote)
          Button("Dismiss") { store.send(.dismissError) }
            .font(.footnote)
        }
      }

      if let boot = store.bootWarningText {
        Section {
          Label(boot, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
            .font(.footnote)
          Button("Dismiss") { store.send(.dismissBootWarning) }
            .font(.footnote)
        }
      }

      hostSection
      updateSection
      gatewaySection
      operationsSection
      actionLogSection
    }
    .navigationTitle("System")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Done") { store.send(.doneTapped) }
      }
      ToolbarItem(placement: .primaryAction) {
        Button {
          store.send(.refreshTapped)
        } label: {
          Image(systemName: "arrow.clockwise")
        }
        .disabled(store.isLoading || store.hasInFlightAction)
      }
    }
    .task { store.send(.task) }
    .bottomActionSheet(
      $store.scope(state: \.confirmationDialog, action: \.confirmationDialog)
    )
  }

  @ViewBuilder
  private var hostSection: some View {
    Section("Host") {
      if store.isLoading && store.stats == nil {
        ProgressView("Loading host…")
      } else if let stats = store.stats {
        LabeledContent("OS", value: stats.osSummary)
        if let hostname = stats.hostname, !hostname.isEmpty {
          LabeledContent("Hostname", value: hostname)
        }
        if let version = stats.hermesVersion, !version.isEmpty {
          LabeledContent("Hermes", value: version)
        }
        if let python = stats.pythonVersion, !python.isEmpty {
          LabeledContent("Python", value: python)
        }
        if let uptime = stats.uptimeLabel {
          LabeledContent("Uptime", value: uptime)
        }
        if let cpu = stats.cpuPercent {
          LabeledContent("CPU", value: String(format: "%.0f%%", cpu))
        }
        if let mem = stats.memory?.percentLabel {
          LabeledContent("Memory", value: mem)
        }
        if let disk = stats.disk?.percentLabel {
          LabeledContent("Disk", value: disk)
        }
      } else {
        Text("Host stats unavailable.")
          .foregroundStyle(.secondary)
      }
    }
  }

  @ViewBuilder
  private var updateSection: some View {
    if store.updateCheckSupported {
      Section {
        if store.isCheckingUpdate && store.updateCheck == nil {
          ProgressView("Checking for updates…")
        } else if let check = store.updateCheck {
          LabeledContent("Status", value: check.statusLabel)
          if let method = check.installMethod, !method.isEmpty {
            LabeledContent("Install", value: method)
          }
          if let version = check.currentVersion, !version.isEmpty {
            LabeledContent("Version", value: version)
          }
          if check.showsApplyButton {
            Button("Update now") { store.send(.applyUpdateTapped) }
              .disabled(store.hasInFlightAction)
          } else if let command = check.updateCommand, !command.isEmpty {
            Text(command)
              .font(.footnote.monospaced())
              .textSelection(.enabled)
            Button("Copy update command") { store.send(.copyUpdateCommandTapped) }
          }
          ForEach(check.commits.prefix(8)) { commit in
            VStack(alignment: .leading, spacing: 2) {
              Text(commit.summary ?? commit.sha ?? "Commit")
                .font(.footnote)
              if let author = commit.author {
                Text(author)
                  .font(.caption2)
                  .foregroundStyle(.secondary)
              }
            }
          }
        }
        Button("Check again") { store.send(.checkUpdateTapped) }
          .disabled(store.isCheckingUpdate || store.hasInFlightAction)
      } header: {
        Text("Hermes update")
      } footer: {
        Text("Apply runs hermes update on the host. The dashboard may restart briefly.")
      }
    }
  }

  @ViewBuilder
  private var gatewaySection: some View {
    if store.gatewaySupported {
      Section {
        LabeledContent("State", value: store.gatewayStateLabel)
        Button("Start") { store.send(.gatewayStartTapped) }
          .disabled(store.hasInFlightAction)
        Button("Restart…") { store.send(.gatewayRestartTapped) }
          .disabled(store.hasInFlightAction)
        Button("Stop…", role: .destructive) { store.send(.gatewayStopTapped) }
          .disabled(store.hasInFlightAction)
      } header: {
        Text("Gateway")
      } footer: {
        Text("Restart after config.yaml or API key changes so running services pick them up.")
      }
    }
  }

  @ViewBuilder
  private var operationsSection: some View {
    if store.opsSupported {
      Section("Operations") {
        ForEach(OpsAction.allCases, id: \.rawValue) { action in
          Button(action.title) { store.send(.opsTapped(action)) }
            .disabled(store.hasInFlightAction)
        }
      }
    }
  }

  @ViewBuilder
  private var actionLogSection: some View {
    if store.hasInFlightAction || store.actionMessage != nil || !store.actionLines.isEmpty {
      Section {
        if let label = store.inFlightLabel {
          Label(label, systemImage: "arrow.triangle.2.circlepath")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        if let message = store.actionMessage {
          Text(message)
            .font(.footnote)
            .onTapGesture { store.send(.dismissActionMessage) }
        }
        if !store.actionLines.isEmpty {
          ScrollView {
            Text(store.actionLines.suffix(80).joined(separator: "\n"))
              .font(.caption.monospaced())
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          .frame(maxHeight: 220)
        }
      } header: {
        Text("Activity")
      }
    }
  }
}
