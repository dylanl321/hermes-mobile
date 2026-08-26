import Foundation
import Testing

@testable import HermesKit

struct WorkspaceRootTests {
  private func session(_ id: String, cwd: String?) -> Session {
    Session(id: id, cwd: cwd)
  }

  @Test func uniqueCwdsInFirstSeenOrder() {
    let roots = WorkspaceRoot.roots(from: [
      session("a", cwd: "/Users/me/dev/hermes-mobile"),
      session("b", cwd: "/Users/me/dev/hermes-agent"),
      session("c", cwd: "/Users/me/dev/hermes-mobile"),
    ])
    #expect(roots.map(\.path) == [
      "/Users/me/dev/hermes-mobile",
      "/Users/me/dev/hermes-agent",
    ])
    #expect(roots.map(\.label) == ["hermes-mobile", "hermes-agent"])
  }

  @Test func skipsEmptyAndWhitespaceCwds() {
    let roots = WorkspaceRoot.roots(from: [
      session("a", cwd: nil),
      session("b", cwd: "   "),
      session("c", cwd: "/w"),
    ])
    #expect(roots.map(\.path) == ["/w"])
  }

  @Test func appendsDefaultCwdWhenMissing() {
    let roots = WorkspaceRoot.roots(
      from: [session("a", cwd: "/proj")],
      defaultCwd: "/home/agent"
    )
    #expect(roots.map(\.path) == ["/proj", "/home/agent"])
  }

  @Test func doesNotDuplicateDefaultCwd() {
    let roots = WorkspaceRoot.roots(
      from: [session("a", cwd: "/home/agent")],
      defaultCwd: "/home/agent"
    )
    #expect(roots.map(\.path) == ["/home/agent"])
  }

  @Test func defaultCwdAloneWhenNoSessions() {
    let roots = WorkspaceRoot.roots(from: [Session](), defaultCwd: "/opt/data")
    #expect(roots.map(\.path) == ["/opt/data"])
  }
}
