import Foundation
import TodayTasksCore

/// 本机偏好：模型配置、布局模式。对应 Android 版 LlmConfigStore（Preferences DataStore）。
/// Swift 侧用 UserDefaults；API Key 也存这里——见 README 的「已知偏差」，后续换成 Keychain。
@MainActor
public final class AppSettings {

  public static let shared = AppSettings()

  private enum Keys {
    static let llmConfig = "todaytasks.llmConfig"
    static let layoutMode = "todaytasks.layoutMode"
    static let remindersEnabled = "todaytasks.remindersEnabled"
  }

  private let defaults: UserDefaults

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  public var llmConfig: LlmConfig {
    get {
      guard let data = defaults.data(forKey: Keys.llmConfig),
            let config = try? JSONDecoder().decode(LlmConfig.self, from: data) else {
        return LlmConfig()
      }
      return config
    }
    set {
      if let data = try? JSONEncoder().encode(newValue) {
        defaults.set(data, forKey: Keys.llmConfig)
      }
    }
  }

  public var layoutMode: String {
    get { defaults.string(forKey: Keys.layoutMode) ?? "adaptive" }
    set { defaults.set(newValue, forKey: Keys.layoutMode) }
  }

  public var remindersEnabled: Bool {
    get { defaults.object(forKey: Keys.remindersEnabled) as? Bool ?? true }
    set { defaults.set(newValue, forKey: Keys.remindersEnabled) }
  }
}

/// 任务变化后需要重排提醒。核心库/UI 层不直接依赖 UserNotifications，
/// 由平台入口注入真实实现（macOS/iOS 各一份），保证 UI 层可编译可测。
@MainActor
public final class ReminderBridge {
  public static let shared = ReminderBridge()
  public var onSync: (@MainActor () async -> Void)?

  public func sync() async {
    await onSync?()
  }
}
