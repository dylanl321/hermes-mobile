import Foundation
import Testing

@testable import HermesKit

struct FsModelsDecodingTests {
  @Test func listDecodesEntriesAndSoftError() throws {
    let data = Data("""
    {"entries":[{"name":"src","path":"/w/src","isDirectory":true},{"name":"a.swift","path":"/w/a.swift","isDirectory":false}],"error":"ENOENT"}
    """.utf8)
    let listing = try JSONDecoder().decode(FsDirectoryListing.self, from: data)
    #expect(listing.entries.count == 2)
    #expect(listing.entries[0].isDirectory)
    #expect(listing.entries[1].name == "a.swift")
    #expect(listing.error == "ENOENT")
    #expect(listing.errorBanner?.contains("no longer exists") == true)
  }

  @Test func listAcceptsSnakeCaseIsDirectory() throws {
    let data = Data(#"{"entries":[{"name":"d","path":"/d","is_directory":true}]}"#.utf8)
    let listing = try JSONDecoder().decode(FsDirectoryListing.self, from: data)
    #expect(listing.entries[0].isDirectory)
  }

  @Test func readTextDecodesCamelAndSnake() throws {
    let data = Data("""
    {"path":"/w/a.swift","text":"hi","binary":false,"truncated":true,"byteSize":2,"mimeType":"text/plain","language":"swift"}
    """.utf8)
    let preview = try JSONDecoder().decode(FsTextPreview.self, from: data)
    #expect(preview.text == "hi")
    #expect(preview.truncated)
    #expect(preview.byteSize == 2)
    #expect(preview.mimeType == "text/plain")
  }

  @Test func dataURLAcceptsEitherKey() throws {
    let camel = try JSONDecoder().decode(
      FsDataURL.self,
      from: Data(#"{"dataUrl":"data:image/png;base64,abc"}"#.utf8)
    )
    #expect(camel.dataUrl.hasPrefix("data:image/png"))
    let snake = try JSONDecoder().decode(
      FsDataURL.self,
      from: Data(#"{"data_url":"data:text/plain;base64,YQ=="}"#.utf8)
    )
    #expect(snake.dataUrl.contains("base64"))
  }

  @Test func defaultCwdDecodes() throws {
    let cwd = try JSONDecoder().decode(
      FsDefaultCwd.self,
      from: Data(#"{"cwd":"/Users/me","branch":"main"}"#.utf8)
    )
    #expect(cwd.cwd == "/Users/me")
    #expect(cwd.branch == "main")
  }
}
