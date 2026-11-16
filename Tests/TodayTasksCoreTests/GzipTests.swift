import Foundation
import Testing
@testable import TodayTasksCore

@Suite("gzip 容器与 CLI 互通")
struct GzipTests {

  @Test("往返一致")
  func roundTrip() throws {
    let samples: [Data] = [
      Data(),
      Data("a".utf8),
      Data("提交 Q4 进度报告，今晚 8 点前完成合同审阅".utf8),
      Data(repeating: 0x41, count: 10_000),
      Data((0..<4096).map { UInt8($0 % 256) }),
    ]
    for sample in samples {
      let packed = try Gzip.compress(sample)
      let unpacked = try Gzip.decompress(packed)
      #expect(unpacked == sample, "长度 \(sample.count) 往返不一致")
      #expect(packed[packed.startIndex] == 0x1F && packed[packed.startIndex + 1] == 0x8B, "必须是 gzip 魔数")
    }
  }

  @Test("系统 gzip 能解开我们打的包（证明格式真的兼容）")
  func systemGunzipAcceptsOutput() throws {
    let text = "今日待办：下午三点前把汇总表发出去，晚上八点开会"
    let packed = try Gzip.compress(Data(text.utf8))
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let gz = dir.appendingPathComponent("payload.gz")
    try packed.write(to: gz)

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
    process.arguments = ["-dc", gz.path]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()
    try process.run()
    let out = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    #expect(process.terminationStatus == 0)
    #expect(String(data: out, encoding: .utf8) == text, "gunzip -dc 解出来的内容应与原文一致")
  }

  @Test("系统 gzip 打的包我们能解开")
  func weAcceptSystemGzipOutput() throws {
    let text = "跨端兼容验证：Android GZIPOutputStream 产出的字节流，Swift 侧必须能读"
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let raw = dir.appendingPathComponent("raw.txt")
    try Data(text.utf8).write(to: raw)

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
    process.arguments = ["-c", raw.path]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()
    try process.run()
    let gzBytes = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    let unpacked = try Gzip.decompress(gzBytes)
    #expect(String(data: unpacked, encoding: .utf8) == text)
  }

  @Test("坏数据抛错而不崩溃")
  func rejectsGarbage() {
    #expect(throws: Gzip.GzipError.self) {
      _ = try Gzip.decompress(Data([0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
                                    0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F,
                                    0x10, 0x11, 0x12]))
    }
  }
}
