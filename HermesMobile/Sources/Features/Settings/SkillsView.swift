import ComposableArchitecture
import HermesKit
import SwiftUI

struct SkillsView: View {
  @Bindable var store: StoreOf<SkillsFeature>

  var body: some View {
    List {
      if let banner = store.errorBanner {
        Section {
          Label(banner, systemImage: "exclamationmark.triangle")
            .foregroundStyle(.orange)
            .font(.footnote)
          Button("Dismiss") { store.send(.dismissError) }
            .font(.footnote)
        }
      }

      Section {
        if store.isLoading && store.skills.isEmpty {
          ProgressView("Loading skills…")
        } else if store.skills.isEmpty {
          Text("No installed skills.")
            .foregroundStyle(.secondary)
        } else {
          ForEach(store.skills) { skill in
            Toggle(
              isOn: Binding(
                get: { skill.isEnabled },
                set: { store.send(.toggleSkill(name: skill.name, enabled: $0)) }
              )
            ) {
              VStack(alignment: .leading, spacing: 2) {
                Text(skill.name)
                if let description = skill.description, !description.isEmpty {
                  Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                }
              }
            }
            .disabled(store.togglingNames.contains(skill.name))
          }
        }
      } header: {
        Text("Installed")
      }

      Section {
        HStack {
          TextField("Search hub", text: $store.hubQuery)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .onSubmit { store.send(.hubSearchSubmitted) }
          Button("Search") { store.send(.hubSearchSubmitted) }
            .disabled(store.hubQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        if store.isSearchingHub {
          ProgressView()
        }
        if let message = store.hubActionMessage {
          Text(message)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .onTapGesture { store.send(.dismissHubMessage) }
        }
        if let inFlight = store.hubActionInFlight {
          Label("Working on \(inFlight)…", systemImage: "arrow.triangle.2.circlepath")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        ForEach(store.hubResults) { hit in
          VStack(alignment: .leading, spacing: 6) {
            Text(hit.name).fontWeight(.medium)
            if let description = hit.description, !description.isEmpty {
              Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            }
            HStack {
              if hit.installed == true {
                Button("Update") { store.send(.hubUpdate(name: hit.name)) }
                Button("Uninstall", role: .destructive) {
                  store.send(.hubUninstall(name: hit.name))
                }
              } else {
                Button("Install") { store.send(.hubInstall(name: hit.name)) }
              }
            }
            .font(.footnote)
            .disabled(store.hubActionInFlight != nil)
          }
        }
      } header: {
        Text("Skill hub")
      } footer: {
        Text("Install and update skills from the agent’s hub. Older agents without hub routes hide these actions after the first miss.")
      }
    }
    .navigationTitle("Skills")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button("Refresh") { store.send(.refreshTapped) }
          .disabled(store.isLoading)
      }
    }
    .task { store.send(.task) }
  }
}
