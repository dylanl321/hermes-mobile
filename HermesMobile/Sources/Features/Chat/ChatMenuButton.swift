import ComposableArchitecture
import HermesKit
import SwiftUI

/// The chat screen's nav-bar ellipsis menu (Rename / Copy ID / Open workspace).
///
/// #82: streaming must not re-animate this control. Two layers keep it stable:
/// 1. `ChatView` is a chrome shell — its body does not read transcript / `isSending` /
///    thinking state, so stream deltas never recreate the `ToolbarItem` that hosts us.
/// 2. This view itself observes ONLY `canRename` / `sessionKey` / `canOpenWorkspace`, so
///    even a rare chrome re-render (title rename, sheet) does not rebuild the `Menu`
///    unless those fields change.
///
/// Deliberately takes the STORE rather than `canRename:` / `onRename:` parameters: closure
/// fields are not comparable, so SwiftUI would have to re-run the body on every parent
/// update anyway and the fix would evaporate.
struct ChatMenuButton: View {
  let store: StoreOf<ChatFeature>

  var body: some View {
    Menu {
      // Icons on every item — a `Menu` reserves the glyph gutter as soon as one item has
      // an image, so a bare "Rename" would sit in a blank column.
      Button("Rename", systemImage: "pencil") { store.send(.renameButtonTapped) }
        .disabled(!store.canRename)
      // `sessionKey` is `storedSessionID ?? liveSessionID` — nil only before a session
      // exists at all (a brand-new chat that hasn't been created yet).
      Button("Copy ID", systemImage: "doc.on.doc") { store.send(.copySessionIDTapped) }
        .disabled(store.sessionKey == nil)
      if store.canOpenWorkspace {
        Button("Open workspace", systemImage: "folder") {
          store.send(.openWorkspaceTapped)
        }
      }
    } label: {
      Image(systemName: "ellipsis.circle")
    }
  }
}
