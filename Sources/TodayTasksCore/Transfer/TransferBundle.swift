import Foundation

/// 换机转移的数据包。字段名与 Android 版 TransferBundle 一致，两端 JSON 可互读。
public struct TransferBundle: Codable, Equatable, Sendable {
  public var version: Int
  public var exportedAtMillis: Int64
  public var records: [LocalTaskRecord]

  public init(
    version: Int = 1,
    exportedAtMillis: Int64 = TaskItem.nowMillis(),
    records: [LocalTaskRecord] = []
  ) {
    self.version = version
    self.exportedAtMillis = exportedAtMillis
    self.records = records
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
    exportedAtMillis = try c.decodeIfPresent(Int64.self, forKey: .exportedAtMillis) ?? 0
    records = try c.decodeIfPresent([LocalTaskRecord].self, forKey: .records) ?? []
  }
}

public enum PairingCode {

  /// 6 位数字配对码，用系统 CSPRNG 生成（对应 Android 的 SecureRandom）。
  public static func generate() -> String {
    var random: UInt32 = 0
    let status = SecRandomCopyBytes(kSecRandomDefault, MemoryLayout<UInt32>.size, &random)
    let number = status == errSecSuccess ? Int(random % 1_000_000) : Int.random(in: 0..<1_000_000)
    return String(format: "%06d", number)
  }

  /// 只保留数字并截到 6 位。用户在输入框里带空格、横杠时都按这个规则清洗。
  public static func sanitize(_ raw: String) -> String {
    String(raw.filter(\.isNumber).prefix(6))
  }

  /// 123456 → "123 456"
  public static func formatSpaced(_ raw: String) -> String {
    let digits = sanitize(raw)
    guard digits.count == 6 else { return digits }
    let index = digits.index(digits.startIndex, offsetBy: 3)
    return "\(digits[digits.startIndex..<index]) \(digits[index...])"
  }

  public static func isValid(_ raw: String) -> Bool {
    sanitize(raw).count == 6
  }
}
