import Foundation

/// 单条任务的分享载荷。字段与 Android 版 SharedTaskPayload 完全一致。
public struct SharedTaskPayload: Codable, Equatable, Sendable {
  public var version: Int
  public var title: String
  public var notes: String
  public var deadlineMillis: Int64
  public var priority: TaskPriority
  public var category: String
  public var remindMinutesBefore: Int64

  public init(
    version: Int = 1,
    title: String,
    notes: String = "",
    deadlineMillis: Int64,
    priority: TaskPriority = .medium,
    category: String = "工作",
    remindMinutesBefore: Int64 = 15
  ) {
    self.version = version
    self.title = title
    self.notes = notes
    self.deadlineMillis = deadlineMillis
    self.priority = priority
    self.category = category
    self.remindMinutesBefore = remindMinutesBefore
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
    title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
    notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
    deadlineMillis = try c.decodeIfPresent(Int64.self, forKey: .deadlineMillis) ?? 0
    priority = (try? c.decodeIfPresent(TaskPriority.self, forKey: .priority)) ?? .medium
    category = try c.decodeIfPresent(String.self, forKey: .category) ?? "工作"
    remindMinutesBefore = try c.decodeIfPresent(Int64.self, forKey: .remindMinutesBefore) ?? 15
  }

  /// 落成本地记录：新 id、未完成、时间戳取当前；字段长度按建库规则截断。
  public func toNewLocalRecord() -> LocalTaskRecord {
    let now = TaskItem.nowMillis()
    let raw = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    return LocalTaskRecord(
      id: "local_" + raw.prefix(16),
      title: String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120)),
      notes: String(notes.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500)),
      deadlineMillis: deadlineMillis,
      isCompleted: false,
      completedAtMillis: 0,
      priority: priority,
      category: {
        let t = category.trimmingCharacters(in: .whitespacesAndNewlines)
        return String((t.isEmpty ? "工作" : t).prefix(20))
      }(),
      remindMinutesBefore: min(max(remindMinutesBefore, 0), 1440),
      createdAtMillis: now,
      updatedAtMillis: now
    )
  }
}

public enum ShareCodecError: Error, LocalizedError, Equatable {
  case empty
  case unrecognized
  case emptyTitle
  case corrupted

  public var errorDescription: String? {
    switch self {
    case .empty: return "分享内容为空"
    case .unrecognized: return "无法识别的分享码或二维码（需以 TT1: 开头或为 6 位数字配对码）"
    case .emptyTitle: return "分享的任务内容为空"
    case .corrupted: return "分享口令或二维码无效或已损坏"
    }
  }
}

/// 单条任务「口令码 / 二维码」编解码，与 Android 版 SingleTaskShareCodec 字节级兼容：
/// JSON → GZIP → Base64URL（去 padding），前面加 "TT1:"。
public enum SingleTaskShareCodec {

  public static let tokenPrefix = "TT1:"

  private static let encoder = JSONEncoder()
  private static let decoder = JSONDecoder()

  public static func payload(from task: TaskItem) -> SharedTaskPayload {
    SharedTaskPayload(
      title: task.title,
      notes: task.notes,
      deadlineMillis: task.deadlineMillis,
      priority: task.priority,
      category: task.category,
      remindMinutesBefore: task.remindMinutesBefore
    )
  }

  public static func fromTaskItem(_ task: TaskItem) -> LocalTaskRecord {
    var record = payload(from: task).toNewLocalRecord()
    record.id = task.id
    record.createdAtMillis = task.createdAtMillis
    record.updatedAtMillis = task.updatedAtMillis
    return record
  }

  public static func encodeToken(_ task: TaskItem) throws -> String {
    try encodePayload(payload(from: task))
  }

  public static func encodePayload(_ payload: SharedTaskPayload) throws -> String {
    let json = try encoder.encode(payload)
    let compressed = try Gzip.compress(json)
    return tokenPrefix + base64URLEncode(compressed)
  }

  public static func decodeToken(_ raw: String) -> Result<SharedTaskPayload, ShareCodecError> {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return .failure(.empty) }

    // 也接受直接的 JSON（用户从别处粘贴）
    if trimmed.hasPrefix("{") {
      guard let data = trimmed.data(using: .utf8),
            let payload = try? decoder.decode(SharedTaskPayload.self, from: data) else {
        return .failure(.corrupted)
      }
      guard !payload.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return .failure(.emptyTitle)
      }
      return .success(payload)
    }

    guard trimmed.hasPrefix(tokenPrefix) else { return .failure(.unrecognized) }

    let body = String(trimmed.dropFirst(tokenPrefix.count))
    guard let compressed = base64URLDecode(body) else { return .failure(.corrupted) }
    guard let json = try? Gzip.decompress(compressed),
          let payload = try? decoder.decode(SharedTaskPayload.self, from: json) else {
      return .failure(.corrupted)
    }
    guard !payload.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return .failure(.emptyTitle)
    }
    return .success(payload)
  }

  // MARK: - Base64URL

  static func base64URLEncode(_ data: Data) -> String {
    data.base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }

  static func base64URLDecode(_ string: String) -> Data? {
    var s = string
      .replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    let remainder = s.count % 4
    if remainder > 0 { s += String(repeating: "=", count: 4 - remainder) }
    return Data(base64Encoded: s)
  }
}
