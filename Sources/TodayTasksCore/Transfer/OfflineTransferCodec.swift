import CommonCrypto
import CryptoKit
import Foundation

public enum OfflineTransferError: Error, LocalizedError, Equatable {
  case invalidCode
  case badPrefix
  case truncated
  case decryptFailed

  public var errorDescription: String? {
    switch self {
    case .invalidCode: return "请输入 6 位数字配对码"
    case .badPrefix: return "迁移口令格式无效（应以 TD1: 开头）"
    case .truncated: return "迁移口令内容不完整"
    case .decryptFailed: return "配对码不正确或迁移口令已损坏"
    }
  }
}

/// 离线迁移口令：`TD1:` + base64URL( salt[16] ‖ iv[12] ‖ AES-GCM密文+tag )。
/// 密钥 = PBKDF2-HMAC-SHA256(配对码, salt, 10000 轮, 32 字节)，
/// 与 Android 版 encodeOfflineEncryptedPackage / decodeOfflineEncryptedPackage 同构。
public enum OfflineTransferCodec {

  public static let prefix = "TD1:"
  public static let pbkdf2Iterations: UInt32 = 10_000
  static let saltLength = 16
  static let ivLength = 12

  private static let encoder = JSONEncoder()
  private static let decoder = JSONDecoder()

  public static func encode(
    records: [LocalTaskRecord],
    pairingCode: String,
    exportedAtMillis: Int64 = TaskItem.nowMillis()
  ) throws -> String {
    let code = PairingCode.sanitize(pairingCode)
    guard code.count == 6 else { throw OfflineTransferError.invalidCode }

    let bundle = TransferBundle(exportedAtMillis: exportedAtMillis, records: records)
    let json = try encoder.encode(bundle)
    let compressed = try Gzip.compress(json)

    let salt = randomBytes(saltLength)
    let iv = randomBytes(ivLength)
    let key = try deriveKey(code: code, salt: salt)
    let nonce = try AES.GCM.Nonce(data: iv)
    let sealed = try AES.GCM.seal(compressed, using: key, nonce: nonce)

    var combined = Data()
    combined.append(salt)
    combined.append(iv)
    combined.append(sealed.ciphertext)
    combined.append(sealed.tag)

    return prefix + SingleTaskShareCodec.base64URLEncode(combined)
  }

  public static func decode(_ packageText: String, pairingCode: String) throws -> TransferBundle {
    let code = PairingCode.sanitize(pairingCode)
    guard code.count == 6 else { throw OfflineTransferError.invalidCode }

    let trimmed = packageText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.hasPrefix(prefix) else { throw OfflineTransferError.badPrefix }

    guard let raw = SingleTaskShareCodec.base64URLDecode(String(trimmed.dropFirst(prefix.count))) else {
      throw OfflineTransferError.decryptFailed
    }
    guard raw.count >= saltLength + ivLength + 16 else { throw OfflineTransferError.truncated }

    let salt = raw.prefix(saltLength)
    let iv = raw.dropFirst(saltLength).prefix(ivLength)
    let ciphertext = raw.dropFirst(saltLength + ivLength).dropLast(16)
    let tag = raw.suffix(16)

    do {
      let key = try deriveKey(code: code, salt: Data(salt))
      let nonce = try AES.GCM.Nonce(data: Data(iv))
      let box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: Data(ciphertext), tag: Data(tag))
      let compressed = try AES.GCM.open(box, using: key)
      let json = try Gzip.decompress(compressed)
      return try decoder.decode(TransferBundle.self, from: json)
    } catch {
      throw OfflineTransferError.decryptFailed
    }
  }

  /// PBKDF2-HMAC-SHA256，参数与 Java 的 PBKDF2WithHmacSHA256 一致（10000 轮 / 256 位）。
  static func deriveKey(code: String, salt: Data) throws -> SymmetricKey {
    var derived = [UInt8](repeating: 0, count: 32)
    let result = code.withCString { password in
      salt.withUnsafeBytes { saltBytes in
        CCKeyDerivationPBKDF(
          CCPBKDFAlgorithm(kCCPBKDF2),
          password, strlen(password),
          saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
          CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
          pbkdf2Iterations,
          &derived, derived.count
        )
      }
    }
    guard result == kCCSuccess else { throw OfflineTransferError.decryptFailed }
    return SymmetricKey(data: Data(derived))
  }

  static func pbkdf2Hex(password: String, salt: String, rounds: UInt32) -> String {
    var derived = [UInt8](repeating: 0, count: 32)
    let saltData = Data(salt.utf8)
    _ = password.withCString { pw in
      saltData.withUnsafeBytes { saltBytes in
        CCKeyDerivationPBKDF(
          CCPBKDFAlgorithm(kCCPBKDF2),
          pw, strlen(pw),
          saltBytes.bindMemory(to: UInt8.self).baseAddress, saltData.count,
          CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
          rounds,
          &derived, derived.count
        )
      }
    }
    return derived.map { String(format: "%02x", $0) }.joined()
  }

  private static func randomBytes(_ count: Int) -> Data {
    var bytes = [UInt8](repeating: 0, count: count)
    let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
    if status != errSecSuccess {
      bytes = (0..<count).map { _ in UInt8.random(in: 0...255) }
    }
    return Data(bytes)
  }
}
