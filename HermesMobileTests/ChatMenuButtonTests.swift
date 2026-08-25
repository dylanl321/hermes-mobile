import ComposableArchitecture
import HermesKit
import SwiftUI
import UIKit
import XCTest

@testable import HermesMobile

/// The #82 invariant: streaming churn in `ChatView` must never reach the nav-bar menu.
///
/// Every tool start/complete re-runs `ChatView.body` (it reads `visibleRows`), and while
/// the `Menu` was built inline in the toolbar that rebuilt the button each time — the
/// flicker loop the tester saw under back-to-back Bash calls. A snapshot can't capture a
/// re-animation, so this pins the mechanism instead: host the real screen, stream a burst
/// of tool events through the store, and assert `ChatMenuButton`'s body was not evaluated
/// again. The probe is the debug-only `bodyEvaluations` counter.
final class ChatMenuButtonTests: XCTestCase {
  private var window: UIWindow?

  override func tearDown() {
    window?.isHidden = true
    window?.rootViewController = nil
    window = nil
    super.tearDown()
  }

  @MainActor
  func testStreamingToolEventsDoNotReevaluateTheMenu() {
    let state = ChatFeature.State(
      connection: ServerConnection(baseURL: URL(string: "http://mac.tailnet:9119")!, token: "t"),
      resumeStoredID: "menu-session",
      title: "Chat",
      status: .ready
    )
    let store = Store(initialState: state) {
      ChatFeature()
    } withDependencies: {
      // Don't open a real socket; streaming rows are minted through `uuid`.
      $0.hermesGateway.connect = { _, _ in AsyncStream { _ in } }
      $0.continuousClock = ImmediateClock()
      $0.uuid = .incrementing
      // `message.start` stamps the elapsed-timer anchor.
      $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
    }

    let controller = UIHostingController(rootView: NavigationStack { ChatView(store: store) })
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    window.rootViewController = controller
    window.makeKeyAndVisible()
    self.window = window
    controller.view.layoutIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.3))

    let settled = ChatMenuButton.bodyEvaluations.value
    XCTAssertGreaterThan(settled, 0, "The menu must have rendered once the screen is hosted")

    // A turn with back-to-back tool calls — the reported reproduction. Each event appends
    // or mutates a transcript row, so `ChatView.body` re-evaluates on every one.
    store.send(.gatewayEvent(.messageStart))
    for index in 0..<20 {
      store.send(.gatewayEvent(.toolStart(
        toolID: "t\(index)", name: "bash", title: "Running command", argsText: nil
      )))
      store.send(.gatewayEvent(.toolComplete(
        toolID: "t\(index)", name: "bash", title: nil,
        args: nil, resultText: "ok", inlineDiff: nil, durationS: 0.1
      )))
      RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }
    RunLoop.main.run(until: Date().addingTimeInterval(0.3))

    XCTAssertTrue(store.isSending, "The turn must be running — otherwise nothing churned")
    XCTAssertGreaterThanOrEqual(
      store.transcript.count, 21,
      "Every tool event must have landed in the transcript the parent body reads"
    )
    XCTAssertEqual(
      ChatMenuButton.bodyEvaluations.value, settled,
      "Streaming churn re-ran the nav-bar menu's body — the #82 flicker loop is back"
    )
  }
}
