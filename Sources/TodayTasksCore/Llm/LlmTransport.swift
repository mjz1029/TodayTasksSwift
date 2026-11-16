import Foundation

/// HTTP 传输层抽象。抽出来是为了让解析逻辑可以在没有网络、没有真实 key 的情况下被测试。
public protocol LlmTransport: Sendable {
  /// 返回 HTTP 状态码和响应体。**非 2xx 不抛错**，由调用方按 Android 版同样的规则组装错误文案。
  func postJSON(url: String, headers: [String: String], body: Data) async throws -> (status: Int, body: Data)
}

/// 默认实现：URLSession，超时参数对齐 Android 版 OkHttp（连接 20s / 读取 45s）。
public struct URLSessionLlmTransport: LlmTransport {
  private let session: URLSession

  public init(timeoutIntervalForRequest: TimeInterval = 45) {
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = timeoutIntervalForRequest
    config.timeoutIntervalForResource = timeoutIntervalForRequest
    config.waitsForConnectivity = false
    self.session = URLSession(configuration: config)
  }

  public func postJSON(
    url: String,
    headers: [String: String],
    body: Data
  ) async throws -> (status: Int, body: Data) {
    guard let url = URL(string: url) else {
      throw URLError(.badURL)
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.httpBody = body
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    for (key, value) in headers {
      request.setValue(value, forHTTPHeaderField: key)
    }
    let (data, response) = try await session.data(for: request)
    let status = (response as? HTTPURLResponse)?.statusCode ?? -1
    return (status, data)
  }
}
