import ComposableArchitecture
import Foundation
import Testing

@testable import HermesKit

/// Cron job create/edit/delete reducers on the session list.
@MainActor
struct SessionListCronCRUDTests {
  private let connection = ServerConnection(baseURL: URL(string: "http://mac.tailnet:9119")!, token: "tok")

  private func job(_ id: String = "job1") -> CronJob {
    CronJob(id: id, name: "Digest", prompt: "Summarize inbox", scheduleDisplay: "0 9 * * *")
  }

  @Test func createSuccessRefetchesJobsAndDismissesEditor() async {
    let created = LockIsolated<CronJobWrite?>(nil)
    let profile = LockIsolated<String?>("unset")
    let store = TestStore(
      initialState: SessionListFeature.State(
        connection: connection,
        selectedProfileName: "work",
        profilesSupported: true,
        cronJobs: [job()],
        cronEditor: CronEditorState(
          mode: .create,
          name: "Morning",
          prompt: "Check mail",
          schedule: "0 8 * * *"
        )
      )
    ) {
      SessionListFeature()
    } withDependencies: {
      $0.hermesREST.createCronJob = { @Sendable _, write, prof in
        created.setValue(write)
        profile.setValue(prof)
        return CronJob(id: "new", name: write.name)
      }
      $0.hermesREST.cronJobs = { @Sendable _, _ in [job(), CronJob(id: "new", name: "Morning")] }
    }

    await store.send(.cronEditorSaveTapped) {
      $0.cronEditor?.isSaving = true
      $0.cronEditor?.error = nil
    }
    await store.receive(\.cronMutationFinished.success) {
      $0.cronEditor = nil
    }
    await store.receive(\.cronJobsResponse.success) {
      $0.cronJobs = [self.job(), CronJob(id: "new", name: "Morning")]
    }

    #expect(created.value?.prompt == "Check mail")
    #expect(created.value?.schedule == "0 8 * * *")
    #expect(created.value?.name == "Morning")
    #expect(profile.value == "work")
  }

  @Test func editSuccessRefetchesJobs() async {
    let updated = LockIsolated<(String, CronJobWrite)?>(nil)
    let store = TestStore(
      initialState: SessionListFeature.State(
        connection: connection,
        cronJobs: [job()],
        cronEditor: CronEditorState(
          mode: .edit(id: "job1"),
          name: "Digest",
          prompt: "Summarize everything",
          schedule: "0 10 * * *"
        )
      )
    ) {
      SessionListFeature()
    } withDependencies: {
      $0.hermesREST.updateCronJob = { @Sendable _, id, write, _ in
        updated.setValue((id, write))
        return CronJob(id: id, name: write.name, prompt: write.prompt)
      }
      $0.hermesREST.cronJobs = { @Sendable _, _ in
        [CronJob(id: "job1", name: "Digest", prompt: "Summarize everything")]
      }
    }

    await store.send(.cronEditorSaveTapped) {
      $0.cronEditor?.isSaving = true
    }
    await store.receive(\.cronMutationFinished.success) {
      $0.cronEditor = nil
    }
    await store.receive(\.cronJobsResponse.success) {
      $0.cronJobs = [CronJob(id: "job1", name: "Digest", prompt: "Summarize everything")]
    }
    #expect(updated.value?.0 == "job1")
    #expect(updated.value?.1.prompt == "Summarize everything")
  }

  @Test func saveFailureSurfacesEditorError() async {
    let store = TestStore(
      initialState: SessionListFeature.State(
        connection: connection,
        cronJobs: [job()],
        cronEditor: CronEditorState(
          mode: .create,
          prompt: "Go",
          schedule: "0 9 * * *"
        )
      )
    ) {
      SessionListFeature()
    } withDependencies: {
      $0.hermesREST.createCronJob = { @Sendable _, _, _ in
        throw RESTError.server(status: 400, detail: "invalid schedule")
      }
    }

    await store.send(.cronEditorSaveTapped) {
      $0.cronEditor?.isSaving = true
    }
    await store.receive(\.cronMutationFinished.failure) {
      $0.cronEditor?.isSaving = false
      $0.cronEditor?.error = "invalid schedule"
    }
  }

  @Test func deletePresentsConfirmationThenRefetches() async {
    let deletedID = LockIsolated<String?>(nil)
    let profileUsed = LockIsolated<String?>(nil)
    let store = TestStore(
      initialState: SessionListFeature.State(
        connection: connection,
        selectedProfileName: "default",
        profilesSupported: true,
        cronJobs: [job()],
        expandedCronJobID: "job1"
      )
    ) {
      SessionListFeature()
    } withDependencies: {
      $0.hermesREST.deleteCronJob = { @Sendable _, id, profile in
        deletedID.setValue(id)
        profileUsed.setValue(profile)
      }
      $0.hermesREST.cronJobs = { @Sendable _, _ in [] }
    }

    await store.send(.deleteCronTapped(id: "job1")) {
      $0.confirmationDialog = ConfirmationDialogState {
        TextState("Delete cron job?")
      } actions: {
        ButtonState(role: .destructive, action: .confirmDeleteCron(id: "job1")) {
          TextState("Delete")
        }
        ButtonState(role: .cancel) {
          TextState("Cancel")
        }
      } message: {
        TextState("This permanently deletes the job and stops future runs.")
      }
    }
    await store.send(.confirmationDialog(.presented(.confirmDeleteCron(id: "job1")))) {
      $0.expandedCronJobID = nil
    }
    await store.receive(\.cronMutationFinished.success)
    await store.receive(\.cronJobsResponse.success) {
      $0.cronJobs = []
    }
    #expect(deletedID.value == "job1")
    #expect(profileUsed.value == "default")
  }

  @Test func deleteFailureSurfacesLoadError() async {
    let store = TestStore(
      initialState: SessionListFeature.State(
        connection: connection,
        cronJobs: [job()]
      )
    ) {
      SessionListFeature()
    } withDependencies: {
      $0.hermesREST.deleteCronJob = { @Sendable _, _, _ in
        throw RESTError.server(status: 500, detail: "db locked")
      }
    }

    await store.send(.deleteCronTapped(id: "job1")) {
      $0.confirmationDialog = ConfirmationDialogState {
        TextState("Delete cron job?")
      } actions: {
        ButtonState(role: .destructive, action: .confirmDeleteCron(id: "job1")) {
          TextState("Delete")
        }
        ButtonState(role: .cancel) {
          TextState("Cancel")
        }
      } message: {
        TextState("This permanently deletes the job and stops future runs.")
      }
    }
    await store.send(.confirmationDialog(.presented(.confirmDeleteCron(id: "job1"))))
    await store.receive(\.cronMutationFinished.failure) {
      $0.loadError = "db locked"
    }
  }

  @Test func createTappedOpensEmptyEditor() async {
    let store = TestStore(initialState: SessionListFeature.State(connection: connection)) {
      SessionListFeature()
    }

    await store.send(.createCronTapped) {
      $0.cronEditor = CronEditorState(mode: .create)
    }
  }

  @Test func editTappedPrefillsFromJob() async {
    let store = TestStore(
      initialState: SessionListFeature.State(
        connection: connection,
        cronJobs: [job()]
      )
    ) {
      SessionListFeature()
    }

    await store.send(.editCronTapped(id: "job1")) {
      $0.cronEditor = CronEditorState(
        mode: .edit(id: "job1"),
        name: "Digest",
        prompt: "Summarize inbox",
        schedule: "0 9 * * *"
      )
    }
  }
}
