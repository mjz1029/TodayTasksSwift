import Foundation

public enum LanTransferError: Error, LocalizedError, Equatable {
  case invalidCode
  case badAddress
  case httpError(String)
  case connectionFailed(String)
  case noPeers

  public var errorDescription: String? {
    switch self {
    case .invalidCode: return "请输入完整的 6 位数字配对码"
    case .badAddress: return "地址格式应为 IP:端口，例如 192.168.1.8:49321"
    case .httpError(let message): return message
    case .connectionFailed(let detail): return "无法连接发送端 (\(detail))"
    case .noPeers:
      return "同一 Wi-Fi 下未发现发送端设备。请确认两台设备在同一 Wi-Fi 并已打开「生成配对码」，"
        + "或手动填写局域网地址（如 192.168.x.x:端口），也可使用「离线迁移口令」。"
    }
  }
}

/// 发送端应答逻辑（不碰 socket，纯状态机，方便测试）。
/// 对应 Android PairingServer.handleClient 里的判定顺序：
/// 先查失败次数上限（429），再比对配对码（403），最后吐数据包（200）。
public actor LanPairingResponder {
  public static let path = "/transfer"
  public static let maxFailedAttempts = 12

  private let pairingCode: String
  private let recordsProvider: @Sendable () async -> [LocalTaskRecord]
  private var failedAttempts = 0
  private let encoder = JSONEncoder()

  public init(
    pairingCode: String,
    recordsProvider: @escaping @Sendable () async -> [LocalTaskRecord]
  ) {
    self.pairingCode = PairingCode.sanitize(pairingCode)
    self.recordsProvider = recordsProvider
  }

  public var attemptsUsed: Int { failedAttempts }

  public struct Response: Equatable, Sendable {
    public let status: Int
    public let reason: String
    public let body: String
  }

  /// requestLine 形如 "GET /transfer?code=482913 HTTP/1.1"
  public func respond(requestLine: String) async -> Response {
    let pathPart = requestLine.split(separator: " ").dropFirst().first.map(String.init) ?? ""
    let requested = PairingCode.sanitize(Self.queryParam(pathPart, key: "code") ?? "")

    if failedAttempts >= Self.maxFailedAttempts {
      return Response(status: 429, reason: "Too Many Requests",
                      body: #"{"error":"错误尝试次数过多，请重新生成配对码"}"#)
    }

    guard requested.count == 6, constantTimeEquals(requested, pairingCode) else {
      failedAttempts += 1
      return Response(status: 403, reason: "Forbidden",
                      body: #"{"error":"配对码不正确，请核对旧手机上的 6 位数字"}"#)
    }

    let records = await recordsProvider()
    let bundle = TransferBundle(records: records)
    let body = (try? encoder.encode(bundle)).flatMap { String(data: $0, encoding: .utf8) } ?? #"{"version":1,"records":[]}"#
    return Response(status: 200, reason: "OK", body: body)
  }

  public func resetAttempts() { failedAttempts = 0 }

  static func queryParam(_ path: String, key: String) -> String? {
    guard let questionMark = path.firstIndex(of: "?") else { return nil }
    let query = path[path.index(after: questionMark)...]
    for part in query.split(separator: "&") {
      let kv = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
      if kv.count == 2, kv[0] == key { return String(kv[1]) }
    }
    return nil
  }

  /// 定长比较，避免按字节提前返回（对应 Android 的 MessageDigest.isEqual）
  private func constantTimeEquals(_ lhs: String, _ rhs: String) -> Bool {
    let a = Array(lhs.utf8)
    let b = Array(rhs.utf8)
    guard a.count == b.count else { return false }
    var diff: UInt8 = 0
    for index in 0..<a.count { diff |= a[index] ^ b[index] }
    return diff == 0
  }
}

// MARK: - 接收端

public protocol TransferHttpClient: Sendable {
  func get(_ url: URL) async throws -> (status: Int, body: Data)
}

public struct URLSessionTransferClient: TransferHttpClient {
  private let session: URLSession

  public init(connectTimeout: TimeInterval = 4, readTimeout: TimeInterval = 8) {
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = readTimeout
    config.timeoutIntervalForResource = connectTimeout + readTimeout
    config.waitsForConnectivity = false
    self.session = URLSession(configuration: config)
  }

  public func get(_ url: URL) async throws -> (status: Int, body: Data) {
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    let (data, response) = try await session.data(for: request)
    return ((response as? HTTPURLResponse)?.statusCode ?? -1, data)
  }
}

/// 局域网发现。iOS/macOS 用 Bonjour（NWBrowser），实现在平台壳里；核心库只依赖这个协议。
public protocol PeerDiscovery: Sendable {
  func discoverPeers(timeoutMillis: Int) async -> [String]
}

public enum LanTransferClient {

  public static func fetch(
    hostAndPort: String,
    pairingCode: String,
    client: TransferHttpClient = URLSessionTransferClient()
  ) async throws -> TransferBundle {
    let code = PairingCode.sanitize(pairingCode)
    guard code.count == 6 else { throw LanTransferError.invalidCode }

    var normalized = hostAndPort.trimmingCharacters(in: .whitespacesAndNewlines)
    for scheme in ["http://", "https://"] where normalized.hasPrefix(scheme) {
      normalized.removeFirst(scheme.count)
    }
    while normalized.hasSuffix("/") { normalized.removeLast() }
    guard normalized.contains(":") else { throw LanTransferError.badAddress }
    guard let url = URL(string: "http://\(normalized)/transfer?code=\(code)") else {
      throw LanTransferError.badAddress
    }

    do {
      let (status, body) = try await client.get(url)
      guard (200...299).contains(status) else {
        let message = errorMessage(from: body) ?? "配对码校验失败（HTTP \(status)）"
        throw LanTransferError.httpError(message)
      }
      return try JSONDecoder().decode(TransferBundle.self, from: body)
    } catch let error as LanTransferError {
      throw error
    } catch let error as URLError {
      throw LanTransferError.connectionFailed(error.localizedDescription)
    } catch {
      throw LanTransferError.connectionFailed(error.localizedDescription)
    }
  }

  public static func receive(
    pairingCode: String,
    manualAddress: String? = nil,
    discovery: PeerDiscovery? = nil,
    client: TransferHttpClient = URLSessionTransferClient(),
    discoveryTimeoutMillis: Int = 4_000
  ) async throws -> TransferBundle {
    let code = PairingCode.sanitize(pairingCode)
    guard code.count == 6 else { throw LanTransferError.invalidCode }

    let manual = manualAddress?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !manual.isEmpty {
      return try await fetch(hostAndPort: manual, pairingCode: code, client: client)
    }

    guard let discovery else { throw LanTransferError.noPeers }
    let peers = await discovery.discoverPeers(timeoutMillis: discoveryTimeoutMillis)
    guard !peers.isEmpty else { throw LanTransferError.noPeers }

    var lastError: Error = LanTransferError.httpError("配对码不匹配或连接失败")
    for address in peers {
      do {
        return try await fetch(hostAndPort: address, pairingCode: code, client: client)
      } catch {
        lastError = error
      }
    }
    throw lastError
  }

  static func errorMessage(from body: Data) -> String? {
    guard let root = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
          let message = root["error"] as? String,
          !message.isEmpty else { return nil }
    return message
  }
}
