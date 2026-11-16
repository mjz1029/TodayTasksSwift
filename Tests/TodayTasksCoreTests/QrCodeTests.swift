import CoreImage
import Foundation
import Testing
@testable import TodayTasksCore

@Suite("二维码：生成与识别端到端")
struct QrCodeTests {

  private func sampleTask() -> TaskItem {
    TaskItem(
      id: "local_qr1",
      title: "把经营分析汇总发给州公司",
      notes: "带上同比还原页",
      deadlineMillis: 1_794_820_000_000,
      priority: .high,
      category: "工作",
      remindMinutesBefore: 30
    )
  }

  @Test("生成的二维码能被识别回原始口令")
  func roundTripToken() throws {
    let token = try SingleTaskShareCodec.encodeToken(sampleTask())
    let image = try #require(QrCode.generate(token), "二维码生成失败")
    let decoded = try #require(QrCode.decode(image), "二维码识别失败")
    #expect(decoded == token)
  }

  @Test("识别回来的口令能还原任务字段")
  func decodedTokenStillParses() throws {
    var task = sampleTask()
    task.notes = "跨端验证：二维码 → 口令 → 任务"
    let token = try SingleTaskShareCodec.encodeToken(task)
    let image = try #require(QrCode.generate(token))
    let decoded = try #require(QrCode.decode(image))

    guard case .success(let payload) = SingleTaskShareCodec.decodeToken(decoded) else {
      Issue.record("还原失败")
      return
    }
    #expect(payload.title == task.title)
    #expect(payload.notes == task.notes)
    #expect(payload.deadlineMillis == task.deadlineMillis)
    #expect(payload.priority == .high)
    #expect(payload.category == "工作")
    #expect(payload.remindMinutesBefore == 30)
  }

  @Test("长内容（接近二维码容量）也能往返")
  func longContent() throws {
    var task = sampleTask()
    task.notes = String(repeating: "备注内容重复出现用于测试压缩与容量。", count: 20)
    let token = try SingleTaskShareCodec.encodeToken(task)
    let image = try #require(QrCode.generate(token))
    #expect(QrCode.decode(image) == token, "口令长度 \(token.count) 字")
  }

  @Test("空内容不生成、非二维码图片识别不出来")
  func negativeCases() {
    #expect(QrCode.generate("   ") == nil)
    #expect(QrCode.generate("x", scale: 0) == nil)

    // 一张纯色图，不应识别出任何内容
    let context = CIContext()
    let blank = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 200, height: 200))
    if let image = context.createCGImage(blank, from: blank.extent) {
      #expect(QrCode.decode(image) == nil)
    } else {
      Issue.record("构造空白图失败")
    }
  }

  @Test("缩放倍率影响尺寸")
  func scaleAffectsSize() throws {
    let small = try #require(QrCode.generate("TT1:abc", scale: 4))
    let large = try #require(QrCode.generate("TT1:abc", scale: 12))
    #expect(large.width > small.width)
    #expect(large.width % small.width < small.width)
  }
}
