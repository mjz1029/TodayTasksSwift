import Foundation
import Testing
@testable import TodayTasksCore

private struct StubHttpClient: TransferHttpClient {
  final class Log: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var urls: [URL] = []
    func append(_ url: URL) {
      lock.lock(); defer { lock.unlock() }
      urls.append(url)
    }
  }

  let log = Log()
  let replies: [(status: Int, body: String)]

  func get(_ url: URL) async throws -> (status: Int, body: Data) {
    log.append(url)
    let index = min(log.urls.count - 1, replies.count - 1)
    let reply = replies[max(index, 0)]
    return (reply.status, Data(reply.body.utf8))
  }
}

private struct StubDiscovery: PeerDiscovery {
  let peers: [String]
  func discoverPeers(timeoutMillis: Int) async -> [String] { peers }
}

@Suite("换机转移：配对码 / 离线口令 / 局域网协议")
struct TransferTests {

  private func records() -> [LocalTaskRecord] {
    [
      LocalTaskRecord(id: "local_a", title: "整理月度经营分析", notes: "带上同比数据",
                      deadlineMillis: 1_794_820_000_000, priority: .high, category: "工作",
                      remindMinutesBefore: 30, createdAtMillis: 1_794_700_000_000,
                      updatedAtMillis: 1_794_700_000_000),
      LocalTaskRecord(id: "local_b", title: "和王总确认口径", deadlineMillis: 1_794_830_000_000,
                      priority: .medium, category: "沟通", remindMinutesBefore: 15),
      LocalTaskRecord(id: "local_c", title: "已完成的旧任务", deadlineMillis: 1_794_000_000_000,
                      isCompleted: true, completedAtMillis: 1_794_100_000_000,
                      priority: .low, category: "个人", remindMinutesBefore: 0),
    ]
  }

  // MARK: 配对码

  @Test("生成的配对码永远是 6 位数字")
  func generatesSixDigits() {
    for _ in 0..<500 {
      let code = PairingCode.generate()
      #expect(code.count == 6)
      #expect(code.allSatisfy { $0.isNumber })
      #expect(code == String(format: "%06d", Int(code) ?? -1))
    }
  }

  @Test("清洗与分组显示")
  func sanitizesCode() {
    #expect(PairingCode.sanitize("123 456") == "123456")
    #expect(PairingCode.sanitize("12-34-56-78") == "123456")
    #expect(PairingCode.sanitize("abc") == "")
    #expect(PairingCode.formatSpaced("123456") == "123 456")
    #expect(PairingCode.formatSpaced("12345") == "12345")
    #expect(PairingCode.isValid("482 913"))
    #expect(!PairingCode.isValid("48291"))
  }

  // MARK: 密钥派生（用 Python hashlib 算出的标准向量核对）

  @Test("PBKDF2-HMAC-SHA256 与标准实现逐字节一致")
  func pbkdf2MatchesStandard() {
    #expect(OfflineTransferCodec.pbkdf2Hex(password: "password", salt: "salt", rounds: 1)
            == "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b")
    #expect(OfflineTransferCodec.pbkdf2Hex(password: "password", salt: "salt", rounds: 2)
            == "ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43")
    #expect(OfflineTransferCodec.pbkdf2Hex(password: "password", salt: "salt", rounds: 4096)
            == "c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a")
  }

  // MARK: 离线迁移口令

  @Test("口令往返：三条任务一条不差")
  func offlineRoundTrip() throws {
    let code = "482913"
    let token = try OfflineTransferCodec.encode(records: records(), pairingCode: code,
                                                exportedAtMillis: 1_794_900_000_000)
    #expect(token.hasPrefix("TD1:"))

    let bundle = try OfflineTransferCodec.decode(token, pairingCode: code)
    #expect(bundle.version == 1)
    #expect(bundle.exportedAtMillis == 1_794_900_000_000)
    #expect(bundle.records.count == 3)
    #expect(bundle.records[0].title == "整理月度经营分析")
    #expect(bundle.records[0].priority == .high)
    #expect(bundle.records[2].isCompleted, "已完成状态要带过去")
    #expect(bundle.records[2].completedAtMillis == 1_794_100_000_000)
  }

  @Test("口令每次加密结果都不同（盐和 IV 是随机的）")
  func offlineTokenIsRandomized() throws {
    let a = try OfflineTransferCodec.encode(records: records(), pairingCode: "482913")
    let b = try OfflineTransferCodec.encode(records: records(), pairingCode: "482913")
    #expect(a != b)
    #expect(try OfflineTransferCodec.decode(a, pairingCode: "482913").records.count == 3)
    #expect(try OfflineTransferCodec.decode(b, pairingCode: "482913").records.count == 3)
  }

  @Test("配对码不对、口令损坏、前缀不对分别报错")
  func offlineErrorPaths() throws {
    let token = try OfflineTransferCodec.encode(records: records(), pairingCode: "482913")

    #expect(throws: OfflineTransferError.decryptFailed) {
      _ = try OfflineTransferCodec.decode(token, pairingCode: "111111")
    }
    #expect(throws: OfflineTransferError.invalidCode) {
      _ = try OfflineTransferCodec.decode(token, pairingCode: "123")
    }
    #expect(throws: OfflineTransferError.badPrefix) {
      _ = try OfflineTransferCodec.decode("TT1:abcdef", pairingCode: "482913")
    }
    #expect(throws: OfflineTransferError.truncated) {
      _ = try OfflineTransferCodec.decode("TD1:" + SingleTaskShareCodec.base64URLEncode(Data([1, 2, 3, 4])),
                                          pairingCode: "482913")
    }
    #expect(OfflineTransferError.decryptFailed.errorDescription == "配对码不正确或迁移口令已损坏")
  }

  @Test("空任务表也能编码解码")
  func offlineEmptyBundle() throws {
    let token = try OfflineTransferCodec.encode(records: [], pairingCode: "000000")
    let bundle = try OfflineTransferCodec.decode(token, pairingCode: "000000")
    #expect(bundle.records.isEmpty)
  }

  // MARK: 发送端应答

  @Test("配对码正确吐数据包，错误返回 403 并计数")
  func responderMatchesCode() async throws {
    let responder = LanPairingResponder(pairingCode: "482913") { self.records() }

    let ok = await responder.respond(requestLine: "GET /transfer?code=482913 HTTP/1.1")
    #expect(ok.status == 200)
    let bundle = try JSONDecoder().decode(TransferBundle.self, from: Data(ok.body.utf8))
    #expect(bundle.records.count == 3)

    let wrong = await responder.respond(requestLine: "GET /transfer?code=111111 HTTP/1.1")
    #expect(wrong.status == 403)
    #expect(wrong.body.contains("配对码不正确，请核对旧手机上的 6 位数字"))
    #expect(await responder.attemptsUsed == 1)
  }

  @Test("带空格和前缀的请求行也能取到 code")
  func responderParsesQuery() async {
    let responder = LanPairingResponder(pairingCode: "482913") { [] }
    let response = await responder.respond(requestLine: "GET /transfer?foo=1&code=482913&bar=2 HTTP/1.1")
    #expect(response.status == 200)
  }

  @Test("连错 12 次后返回 429")
  func responderRateLimits() async {
    let responder = LanPairingResponder(pairingCode: "482913") { [] }
    for _ in 0..<12 {
      _ = await responder.respond(requestLine: "GET /transfer?code=000000 HTTP/1.1")
    }
    let limited = await responder.respond(requestLine: "GET /transfer?code=482913 HTTP/1.1")
    #expect(limited.status == 429)
    #expect(limited.body.contains("错误尝试次数过多，请重新生成配对码"))

    await responder.resetAttempts()
    let afterReset = await responder.respond(requestLine: "GET /transfer?code=482913 HTTP/1.1")
    #expect(afterReset.status == 200)
  }

  // MARK: 接收端

  @Test("按 IP:端口 拉取数据包，URL 与清洗后的配对码都对")
  func clientFetchesBundle() async throws {
    let body = #"{"version":1,"exportedAtMillis":1794900000000,"records":[{"id":"local_x","title":"转移过来的任务","deadlineMillis":1794820000000,"priority":"high","category":"工作","remindMinutesBefore":15,"isCompleted":false,"completedAtMillis":0,"createdAtMillis":0,"updatedAtMillis":0}]}"#
    let client = StubHttpClient(replies: [(200, body)])
    let bundle = try await LanTransferClient.fetch(hostAndPort: "http://192.168.1.8:49321/",
                                                  pairingCode: "48 29 13", client: client)
    #expect(bundle.records.first?.title == "转移过来的任务")
    #expect(bundle.records.first?.priority == .high)
    #expect(client.log.urls.first?.absoluteString == "http://192.168.1.8:49321/transfer?code=482913")
  }

  @Test("服务端 403 时把中文错误原样抛给用户")
  func clientSurfacesServerError() async {
    let client = StubHttpClient(replies: [(403, #"{"error":"配对码不正确，请核对旧手机上的 6 位数字"}"#)])
    do {
      _ = try await LanTransferClient.fetch(hostAndPort: "192.168.1.8:49321", pairingCode: "111111", client: client)
      Issue.record("应当抛错")
    } catch let error as LanTransferError {
      #expect(error == .httpError("配对码不正确，请核对旧手机上的 6 位数字"))
    } catch {
      Issue.record("错误类型不对：\(error)")
    }
  }

  @Test("地址没端口、配对码不完整分别拦下")
  func clientValidatesInput() async {
    let client = StubHttpClient(replies: [(200, "{}")])
    do {
      _ = try await LanTransferClient.fetch(hostAndPort: "192.168.1.8", pairingCode: "482913", client: client)
      Issue.record("缺端口应报错")
    } catch let error as LanTransferError {
      #expect(error == .badAddress)
    } catch { Issue.record("错误类型不对") }

    do {
      _ = try await LanTransferClient.fetch(hostAndPort: "192.168.1.8:8080", pairingCode: "4829", client: client)
      Issue.record("配对码不足 6 位应报错")
    } catch let error as LanTransferError {
      #expect(error == .invalidCode)
    } catch { Issue.record("错误类型不对") }
  }

  @Test("自动发现：没发现设备时给明确提示")
  func receiveWithoutPeers() async {
    do {
      _ = try await LanTransferClient.receive(pairingCode: "482913", discovery: StubDiscovery(peers: []),
                                              client: StubHttpClient(replies: [(200, "{}")]))
      Issue.record("应当抛错")
    } catch let error as LanTransferError {
      #expect(error == .noPeers)
      #expect(error.errorDescription?.contains("未发现发送端设备") == true)
    } catch { Issue.record("错误类型不对") }
  }

  @Test("自动发现：逐个尝试，第一台失败第二台成功")
  func receiveFallsThroughPeers() async throws {
    let okBody = #"{"records":[{"id":"local_z","title":"第二台给的","deadlineMillis":0}]}"#
    let client = StubHttpClient(replies: [(403, #"{"error":"配对码不正确"}"#), (200, okBody)])
    let bundle = try await LanTransferClient.receive(
      pairingCode: "482913",
      discovery: StubDiscovery(peers: ["10.0.0.2:1111", "10.0.0.3:2222"]),
      client: client
    )
    #expect(bundle.records.first?.title == "第二台给的")
    #expect(client.log.urls.count == 2)
  }
}
