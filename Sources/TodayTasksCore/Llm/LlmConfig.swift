import Foundation

/// 大模型服务商预设。与 Android 版 LlmProvider 对齐（Firebase 内置 Gemini 在 iOS/macOS 侧不实现，
/// 按约定只走 OpenAI 兼容接口）。
public enum LlmProvider: String, CaseIterable, Codable, Sendable {
  case deepseek
  case openai
  case qwen
  case kimi
  case glm
  case custom

  public var displayName: String {
    switch self {
    case .deepseek: return "DeepSeek"
    case .openai: return "OpenAI (GPT)"
    case .qwen: return "通义千问 (Qwen)"
    case .kimi: return "Kimi (Moonshot)"
    case .glm: return "智谱 GLM"
    case .custom: return "自定义接口"
    }
  }

  public var defaultBaseURL: String {
    switch self {
    case .deepseek: return "https://api.deepseek.com/v1"
    case .openai: return "https://api.openai.com/v1"
    case .qwen: return "https://dashscope.aliyuncs.com/compatible-mode/v1"
    case .kimi: return "https://api.moonshot.cn/v1"
    case .glm: return "https://open.bigmodel.cn/api/paas/v4"
    case .custom: return ""
    }
  }

  public var defaultModel: String {
    switch self {
    case .deepseek: return "deepseek-chat"
    case .openai: return "gpt-4o-mini"
    case .qwen: return "qwen-plus"
    case .kimi: return "moonshot-v1-8k"
    case .glm: return "glm-4-flash"
    case .custom: return ""
    }
  }

  public var hint: String {
    switch self {
    case .deepseek: return "高性价比中文语义理解，支持 deepseek-chat"
    case .openai: return "OpenAI 官方接口（gpt-4o-mini / gpt-4o）"
    case .qwen: return "阿里云百炼 OpenAI 兼容接口"
    case .kimi: return "月之暗面开放平台接口"
    case .glm: return "智谱 AI 开放平台接口"
    case .custom: return "任何兼容 /chat/completions 的接口"
    }
  }
}

/// 模型调用配置。baseURL 填到 /v1 为止即可，代码会自动补 /chat/completions。
public struct LlmConfig: Codable, Equatable, Sendable {
  public var provider: LlmProvider
  public var baseURL: String
  public var model: String
  public var apiKey: String

  public init(
    provider: LlmProvider = .deepseek,
    baseURL: String = LlmProvider.deepseek.defaultBaseURL,
    model: String = LlmProvider.deepseek.defaultModel,
    apiKey: String = ""
  ) {
    self.provider = provider
    self.baseURL = baseURL
    self.model = model
    self.apiKey = apiKey
  }

  public var isConfigured: Bool {
    !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  /// 切服务商时把 baseURL/model 换成该服务商默认值（保留已填的 key）
  public mutating func applyProviderDefaults() {
    baseURL = provider.defaultBaseURL
    model = provider.defaultModel
  }

  public var endpoint: String {
    let clean = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmed = clean.hasSuffix("/") ? String(clean.dropLast()) : clean
    if trimmed.hasSuffix("/chat/completions") { return trimmed }
    return trimmed + "/chat/completions"
  }
}
