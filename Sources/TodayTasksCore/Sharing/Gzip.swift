import Compression
import Foundation

/// 最小 gzip 实现：只做「RAW DEFLATE + gzip 容器」。
///
/// 为什么要自己封 gzip 容器：Apple 的 Compression 框架里 COMPRESSION_ZLIB 输出的是裸 deflate 流，
/// 而 Android 端用的是 java.util.zip.GZIPOutputStream（真正的 gzip 格式）。
/// 不补上那 10 字节头和 8 字节尾，两端分享码互不认。
public enum Gzip {

  public enum GzipError: Error {
    case encodeFailed
    case decodeFailed
  }

  // MARK: - 对外

  public static func compress(_ data: Data) throws -> Data {
    let deflated = try rawDeflate(data)
    var out = Data([0x1F, 0x8B, 0x08, 0x00,  // 魔数 + DEFLATE
                    0x00, 0x00, 0x00, 0x00,  // MTIME = 0
                    0x00,                    // XFL
                    0xFF])                   // OS = unknown
    out.append(deflated)
    var crc = CRC32.checksum(data).littleEndian
    withUnsafeBytes(of: &crc) { out.append(contentsOf: $0) }
    var isize = UInt32(truncatingIfNeeded: data.count).littleEndian
    withUnsafeBytes(of: &isize) { out.append(contentsOf: $0) }
    return out
  }

  public static func decompress(_ data: Data) throws -> Data {
    guard data.count > 18,
          data[data.startIndex] == 0x1F,
          data[data.startIndex + 1] == 0x8B,
          data[data.startIndex + 2] == 0x08 else {
      throw GzipError.decodeFailed
    }
    let bytes = [UInt8](data)
    let flags = bytes[3]
    var cursor = 10
    if flags & 0x04 != 0 { // FEXTRA
      guard cursor + 2 <= bytes.count else { throw GzipError.decodeFailed }
      let xlen = Int(bytes[cursor]) | (Int(bytes[cursor + 1]) << 8)
      cursor += 2 + xlen
    }
    if flags & 0x08 != 0 { // FNAME
      while cursor < bytes.count, bytes[cursor] != 0 { cursor += 1 }
      cursor += 1
    }
    if flags & 0x10 != 0 { // FCOMMENT
      while cursor < bytes.count, bytes[cursor] != 0 { cursor += 1 }
      cursor += 1
    }
    if flags & 0x02 != 0 { cursor += 2 } // FHCRC
    guard cursor < bytes.count - 8 else { throw GzipError.decodeFailed }

    let deflated = Data(bytes[cursor..<(bytes.count - 8)])
    let expectedSize = UInt32(bytes[bytes.count - 4])
      | (UInt32(bytes[bytes.count - 3]) << 8)
      | (UInt32(bytes[bytes.count - 2]) << 16)
      | (UInt32(bytes[bytes.count - 1]) << 24)
    let result = try rawInflate(deflated, expectedSize: Int(expectedSize))
    return result
  }

  // MARK: - 裸 deflate

  private static func rawDeflate(_ data: Data) throws -> Data {
    if data.isEmpty { return Data([0x03, 0x00]) } // 空输入的固定最小 deflate 块
    var capacity = max(data.count * 2, 1024)
    for _ in 0..<6 {
      var dst = Data(count: capacity)
      let written = dst.withUnsafeMutableBytes { dstPtr -> Int in
        data.withUnsafeBytes { srcPtr -> Int in
          compression_encode_buffer(
            dstPtr.bindMemory(to: UInt8.self).baseAddress!, capacity,
            srcPtr.bindMemory(to: UInt8.self).baseAddress!, data.count,
            nil, COMPRESSION_ZLIB
          )
        }
      }
      if written > 0 {
        dst.removeSubrange(written..<dst.count)
        return dst
      }
      capacity *= 4
    }
    throw GzipError.encodeFailed
  }

  private static func rawInflate(_ data: Data, expectedSize: Int) throws -> Data {
    // 空内容的合法 gzip 解出来就是 0 字节，而 compression_decode_buffer 对 0 字节输出
    // 同样返回 0，会被误判成失败，这里先按 ISIZE 短路。
    if expectedSize == 0 { return Data() }
    let hint = expectedSize > 0 ? expectedSize : max(data.count * 4, 1024)
    var capacity = max(hint, 1024)
    for _ in 0..<8 {
      var dst = Data(count: capacity)
      let written = dst.withUnsafeMutableBytes { dstPtr -> Int in
        data.withUnsafeBytes { srcPtr -> Int in
          compression_decode_buffer(
            dstPtr.bindMemory(to: UInt8.self).baseAddress!, capacity,
            srcPtr.bindMemory(to: UInt8.self).baseAddress!, data.count,
            nil, COMPRESSION_ZLIB
          )
        }
      }
      if written > 0 {
        dst.removeSubrange(written..<dst.count)
        return dst
      }
      capacity *= 4
    }
    throw GzipError.decodeFailed
  }
}

/// gzip 尾部校验用的 CRC32（IEEE 多项式，标准实现）。
enum CRC32 {
  private static let table: [UInt32] = (0..<256).map { index in
    var c = UInt32(index)
    for _ in 0..<8 {
      c = (c & 1) != 0 ? (0xEDB8_8320 ^ (c >> 1)) : (c >> 1)
    }
    return c
  }

  static func checksum(_ data: Data) -> UInt32 {
    var crc: UInt32 = 0xFFFF_FFFF
    for byte in data {
      crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
    }
    return crc ^ 0xFFFF_FFFF
  }
}
