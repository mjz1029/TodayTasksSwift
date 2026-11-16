import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import Vision

/// 二维码生成与识别。对应 Android 版 QrCodeHelper（ZXing）。
/// 生成走 CoreImage 内置滤镜，识别走 Vision，两端都是系统框架，不引第三方。
public enum QrCode {

  public static let defaultScale: CGFloat = 10

  /// 生成二维码位图。内容为空返回 nil。
  public static func generate(_ content: String, scale: CGFloat = defaultScale) -> CGImage? {
    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, scale > 0 else { return nil }
    guard let data = trimmed.data(using: .utf8) else { return nil }

    let filter = CIFilter.qrCodeGenerator()
    filter.message = data
    filter.correctionLevel = "M"   // 与 Android 版 ErrorCorrectionLevel.M 一致
    guard let output = filter.outputImage else { return nil }

    let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    let context = CIContext(options: nil)
    return context.createCGImage(scaled, from: scaled.extent)
  }

  /// 从图片里识别二维码文本（用于相册选图、桌面端文件、以及自动化验证）。
  public static func decode(_ image: CGImage) -> String? {
    let request = VNDetectBarcodesRequest()
    request.symbologies = [.qr]
    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    do {
      try handler.perform([request])
    } catch {
      return nil
    }
    guard let results = request.results, let first = results.first else { return nil }
    let payload = first.payloadStringValue
    return (payload?.isEmpty ?? true) ? nil : payload
  }
}
