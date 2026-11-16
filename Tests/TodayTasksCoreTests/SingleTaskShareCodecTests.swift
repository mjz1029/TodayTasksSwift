import Foundation
import Testing
@testable import TodayTasksCore

@Suite("单条任务分享码 TT1:")
struct SingleTaskShareCodecTests {

  private func sampleTask() -> TaskItem {
    TaskItem(
      id: "local_abc123",
      title: "把季度汇总表发给王总",
      notes: "带上现金流那页，抄送财务",
      deadlineMillis: 1_794_820_000_000,
      priority: .high,
      category: "沟通",
      remindMinutesBefore: 30,
      createdAtMillis: 1_794_700_000_000,
      updatedAtMillis: 1_794_700_000_000
    )
  }

  @Test("编码-解码往返，字段一个不差")
  func roundTrip() throws {
    let task = sampleTask()
    let token = try SingleTaskShareCodec.encodeToken(task)
    #expect(token.hasPrefix("TT1:"))

    let result = SingleTaskShareCodec.decodeToken(token)
    guard case .success(let payload) = result else {
      Issue.record("解码失败：\(result)")
      return
    }
    #expect(payload.title == task.title)
    #expect(payload.notes == task.notes)
    #expect(payload.deadlineMillis == task.deadlineMillis)
    #expect(payload.priority == .high)
    #expect(payload.category == "沟通")
    #expect(payload.remindMinutesBefore == 30)
  }

  @Test("token 里只有 URL 安全字符，能塞进二维码")
  func tokenIsUrlSafe() throws {
    let token = try SingleTaskShareCodec.encodeToken(sampleTask())
    let body = token.dropFirst(SingleTaskShareCodec.tokenPrefix.count)
    let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
    #expect(body.unicodeScalars.allSatisfy { allowed.contains($0) })
    #expect(!body.contains("="), "不能有 padding")
  }

  @Test("直接粘 JSON 也认")
  func acceptsRawJson() {
    let json = #"{"title":"直接粘贴的任务","deadlineMillis":1794820000000}"#
    let result = SingleTaskShareCodec.decodeToken(json)
    guard case .success(let payload) = result else {
      Issue.record("应接受裸 JSON")
      return
    }
    #expect(payload.title == "直接粘贴的任务")
  }

  @Test("无法识别的前缀给出明确提示")
  func rejectsUnknownPrefix() {
    let result = SingleTaskShareCodec.decodeToken("HELLO123")
    #expect(result == .failure(.unrecognized))
    #expect(ShareCodecError.unrecognized.errorDescription?.contains("TT1:") == true)
  }

  @Test("空内容与损坏内容分别报错")
  func rejectsEmptyAndCorrupted() {
    #expect(SingleTaskShareCodec.decodeToken("   ") == .failure(.empty))
    #expect(SingleTaskShareCodec.decodeToken("TT1:!!!!not-base64!!!!") == .failure(.corrupted))
    // 合法 base64 但不是 gzip
    let notGzip = Data("这不是压缩数据".utf8).base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
    #expect(SingleTaskShareCodec.decodeToken("TT1:" + notGzip) == .failure(.corrupted))
  }

  @Test("长内容也能压得进二维码")
  func longContentCompresses() throws {
    var task = sampleTask()
    task.notes = String(repeating: "备注内容重复出现用于测试压缩率。", count: 40)
    let token = try SingleTaskShareCodec.encodeToken(task)
    #expect(token.count < task.notes.utf8.count, "压缩后应明显短于原始备注体积")

    guard case .success(let payload) = SingleTaskShareCodec.decodeToken(token) else {
      Issue.record("长内容解码失败")
      return
    }
    #expect(payload.notes == task.notes)
  }

  @Test("解码成新记录：新 id、未完成、完成时间清零")
  func toNewLocalRecord() {
    let payload = SharedTaskPayload(
      title: "  新任务  ",
      notes: "  备注  ",
      deadlineMillis: 1_794_820_000_000,
      priority: .low,
      category: "  ",
      remindMinutesBefore: 99_999
    )
    let record = payload.toNewLocalRecord()
    #expect(record.id.hasPrefix("local_"))
    #expect(record.title == "新任务")
    #expect(record.notes == "备注")
    #expect(!record.isCompleted)
    #expect(record.completedAtMillis == 0)
    #expect(record.category == "工作", "空分类回落工作")
    #expect(record.remindMinutesBefore == 1440, "提醒上限收紧到 1440")
  }
}
