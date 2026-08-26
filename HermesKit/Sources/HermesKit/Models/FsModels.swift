import Foundation

/// One directory entry from `GET /api/fs/list` (desktop remote FS rail).
public struct FsEntry: Equatable, Sendable, Identifiable, Decodable {
  public var name: String
  public var path: String
  public var isDirectory: Bool

  public var id: String { path }

  public init(name: String, path: String, isDirectory: Bool) {
    self.name = name
    self.path = path
    self.isDirectory = isDirectory
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    name = (try? c.decode(String.self, forKey: .name)) ?? ""
    path = (try? c.decode(String.self, forKey: .path)) ?? ""
    // Wire uses camelCase `isDirectory`; accept snake_case too.
    if let value = try? c.decode(Bool.self, forKey: .isDirectory) {
      isDirectory = value
    } else if let value = try? c.decode(Bool.self, forKey: .is_directory) {
      isDirectory = value
    } else {
      isDirectory = false
    }
  }

  enum CodingKeys: String, CodingKey {
    case name, path, isDirectory
    case is_directory
  }
}

/// Listing payload from `GET /api/fs/list?path=`. Soft errors arrive as `error` with empty entries
/// (ENOENT / ENOTDIR / EACCES) rather than HTTP failure — mirrors the desktop remote bridge.
public struct FsDirectoryListing: Equatable, Sendable, Decodable {
  public var entries: [FsEntry]
  public var error: String?

  public init(entries: [FsEntry] = [], error: String? = nil) {
    self.entries = entries
    self.error = error
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    entries = (try? c.decode([FsEntry].self, forKey: .entries)) ?? []
    error = try? c.decodeIfPresent(String.self, forKey: .error)
  }

  enum CodingKeys: String, CodingKey {
    case entries, error
  }

  /// Human-readable banner for a soft list error code.
  public var errorBanner: String? {
    guard let error, !error.isEmpty else { return nil }
    switch error {
    case "ENOENT": return "This folder no longer exists on the agent."
    case "ENOTDIR": return "That path isn’t a folder."
    case "EACCES": return "The agent can’t read that folder."
    default: return "Couldn’t read this folder (\(error))."
    }
  }
}

/// Text preview from `GET /api/fs/read-text?path=`.
public struct FsTextPreview: Equatable, Sendable, Decodable {
  public var path: String
  public var text: String
  public var binary: Bool
  public var truncated: Bool
  public var byteSize: Int?
  public var mimeType: String?
  public var language: String?

  public init(
    path: String,
    text: String,
    binary: Bool = false,
    truncated: Bool = false,
    byteSize: Int? = nil,
    mimeType: String? = nil,
    language: String? = nil
  ) {
    self.path = path
    self.text = text
    self.binary = binary
    self.truncated = truncated
    self.byteSize = byteSize
    self.mimeType = mimeType
    self.language = language
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    path = (try? c.decode(String.self, forKey: .path)) ?? ""
    text = (try? c.decode(String.self, forKey: .text)) ?? ""
    binary = (try? c.decode(Bool.self, forKey: .binary)) ?? false
    truncated = (try? c.decode(Bool.self, forKey: .truncated)) ?? false
    if let size = try? c.decodeIfPresent(Int.self, forKey: .byteSize) {
      byteSize = size
    } else {
      byteSize = try? c.decodeIfPresent(Int.self, forKey: .byte_size)
    }
    if let mime = try? c.decodeIfPresent(String.self, forKey: .mimeType) {
      mimeType = mime
    } else {
      mimeType = try? c.decodeIfPresent(String.self, forKey: .mime_type)
    }
    language = try? c.decodeIfPresent(String.self, forKey: .language)
  }

  enum CodingKeys: String, CodingKey {
    case path, text, binary, truncated, language
    case byteSize, byte_size
    case mimeType, mime_type
  }
}

/// Binary/image payload from `GET /api/fs/read-data-url?path=`.
public struct FsDataURL: Equatable, Sendable, Decodable {
  public var dataUrl: String

  public init(dataUrl: String) {
    self.dataUrl = dataUrl
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    if let value = try? c.decode(String.self, forKey: .dataUrl) {
      dataUrl = value
    } else if let value = try? c.decode(String.self, forKey: .data_url) {
      dataUrl = value
    } else {
      dataUrl = ""
    }
  }

  enum CodingKeys: String, CodingKey {
    case dataUrl, data_url
  }
}

/// Seed path from `GET /api/fs/default-cwd`.
public struct FsDefaultCwd: Equatable, Sendable, Decodable {
  public var cwd: String
  public var branch: String?

  public init(cwd: String, branch: String? = nil) {
    self.cwd = cwd
    self.branch = branch
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    cwd = (try? c.decode(String.self, forKey: .cwd)) ?? ""
    branch = try? c.decodeIfPresent(String.self, forKey: .branch)
  }

  enum CodingKeys: String, CodingKey {
    case cwd, branch
  }
}
