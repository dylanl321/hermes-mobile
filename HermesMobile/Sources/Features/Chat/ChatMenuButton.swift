import ComposableArchitecture
import HermesKit
import SwiftUI

/// The chat screen's nav-bar ellipsis menu (Rename / Copy ID), split out of `ChatView` so
/// it observes ONLY the two fields it renders (#82).
///
/// `ChatView.body` re-evaluates on every streaming change — each `message.delta`, tool
/// start/complete, status update, and thinking tick — because it reads `visibleRows`,
/// `isSending`, and friends. While this menu lived inline in `ChatView`'s `.toolbar { }`,
/// every one of those re-evaluations rebuilt the `Menu` and its label, and the toolbar
/// button replayed its appearance each time; with back-to-back tool calls that is the
/// visible flicker loop the tester reported on the icon.
///
/// As a child view holding the store — a reference, which SwiftUI diffs by identity, so the
/// parent's re-render alone does not re-run this body — Observation re-evaluates it only
/// when `canRename` / `sessionKey` change, i.e. at session creation and never mid-turn.
/// Pinned by `ChatMenuButtonTests` through the `bodyEvaluations` probe.
///
/// Deliberately takes the STORE rather than `canRename:` / `onRename:` parameters: closure
/// fields are not comparable, so SwiftUI would have to re-run the body on every parent
/// update anyway and the fix would evaporate.
struct ChatMenuButton: View {
  let store: StoreOf<ChatFeature>

  var body: some View {
    #if DEBUG
    Self.bodyEvaluations.withValue { $0 += 1 }
    #endif
    return Menu {
      // Icons on every item — a `Menu` reserves the glyph gutter as soon as one item has
      // an image, so a bare "Rename" would sit in a blank column.
      Button("Rename", systemImage: "pencil") { store.send(.renameButtonTapped) }
        .disabled(!store.canRename)
      // `sessionKey` is `storedSessionID ?? liveSessionID` — nil only before a session
      // exists at all (a brand-new chat that hasn't been created yet).
      Button("Copy ID", systemImage: "doc.on.doc") { store.send(.copySessionIDTapped) }
        .disabled(store.sessionKey == nil)
    } label: {
      Image(systemName: "ellipsis.circle")
    }
  }

  #if DEBUG
  /// Test probe (#82): counts body evaluations so a hosted test can assert that streaming
  /// churn in the parent never reaches this view. Debug-only; the release body has no
  /// side effects.
  static let bodyEvaluations = LockIsolated(0)
  #endif
}
