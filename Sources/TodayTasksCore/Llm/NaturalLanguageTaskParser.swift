import Foundation

/// 大模型解析出来的一条待办草稿。
public struct ParsedTaskDraft: Equatable, Sendable {
  public var title: String
  public var notes: String
  public var deadlineMillis: Int64
  public var priority: TaskPriority
  public var category: String
  public var remindMinutesBefore: Int64

  public init(
    title: String,
    notes: String = "",
    deadlineMillis: Int64,
    priority: TaskPriority = .medium,
    category: String = "工作",
    remindMinutesBefore: Int64 = 15
  ) {
    self.title = title
    self.notes = notes
    self.deadlineMillis = deadlineMillis
    self.priority = priority
    self.category = category
    self.remindMinutesBefore = remindMinutesBefore
  }

  public var toNewTaskInput: LocalTasksStore.NewTaskInput {
    LocalTasksStore.NewTaskInput(
      title: title,
      notes: notes,
      deadlineMillis: deadlineMillis,
      priority: priority,
      category: category,
      remindMinutesBefore: remindMinutesBefore
    )
  }
}

public enum LlmParseError: Error, LocalizedError, Equatable {
  case emptyInput
  case missingApiKey(String)
  case timedOut
  case transport(String)
  case noTasks

  public var errorDescription: String? {
    switch self {
    case .emptyInput:
      return "请输入要记录的工作内容与时间"
    case .missingApiKey(let providerName):
      return "当前选择了 \(providerName)，请先在设置中填写 API Key"
    case .timedOut:
      return "大模型解析超时，请检查网络或重试"
    case .transport(let message):
      return message
    case .noTasks:
      return "未识别出有效的待办事项，请换个说法重试"
    }
  }
}

/// 自然语言建任务解析器。行为、提示词、JSON 容错规则、错误文案全部对齐 Android 版
/// NaturalLanguageTaskParser 的 OpenAI 兼容分支。
public final class NaturalLanguageTaskParser: @unchecked Sendable {

  public static let systemPrompt =
    "You extract one OR multiple structured work tasks from a Chinese or English user sentence. "
    + "If the user mentions several independent actions or deadlines in one sentence, split them into separate task objects inside the 'tasks' array. "
    + #"Return ONLY valid JSON of the form {"tasks": [{title, notes, deadlineLocal (yyyy-MM-dd HH:mm), priority (high|medium|low), category (工作|会议|沟通|开发|个人), remindMinutesBefore (0|5|15|30|60)}]}."#

  public static let allowedCategories = ["工作", "会议", "沟通", "开发", "个人"]
  public static let allowedReminders: [Int64] = [0, 5, 15, 30, 60]

  private let transport: LlmTransport
  private let timeout: TimeInterval

  public init(transport: LlmTransport = URLSessionLlmTransport(), timeout: TimeInterval = 45) {
    self.transport = transport
    self.timeout = timeout
  }

  // MARK: - 主流程

  /// 解析一句自然语言，返回 1 条或多条待办草稿。
  public func parse(
    sentence: String,
    config: LlmConfig,
    nowMillis: Int64 = TaskItem.nowMillis()
  ) async throws -> [ParsedTaskDraft] {
    let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw LlmParseError.emptyInput }
    guard config.isConfigured else {
      throw LlmParseError.missingApiKey(config.provider.displayName)
    }

    let prompt = Self.buildParsingPrompt(sentence: trimmed, nowMillis: nowMillis)
    let rawJSON = try await call(config: config, userPrompt: prompt)
    let drafts = Self.parseDraftsJSON(rawJson: rawJSON, fallbackSentence: trimmed, nowMillis: nowMillis)
    guard !drafts.isEmpty else { throw LlmParseError.noTasks }
    return drafts
  }

  /// 只取第一条草稿（Android 版 parseSentence）。
  public func parseSingle(
    sentence: String,
    config: LlmConfig,
    nowMillis: Int64 = TaskItem.nowMillis()
  ) async throws -> ParsedTaskDraft {
    let drafts = try await parse(sentence: sentence, config: config, nowMillis: nowMillis)
    guard let first = drafts.first else { throw LlmParseError.noTasks }
    return first
  }

  /// 设置页的「测试连接」。返回给用户看的成功文案。
  public func testConnection(config: LlmConfig) async throws -> String {
    guard config.isConfigured else {
      throw LlmParseError.missingApiKey(config.provider.displayName)
    }
    let testPrompt = #"Reply with strictly this JSON: {"tasks":[{"title":"测试","notes":"","deadlineLocal":"2026-12-31 18:00","priority":"medium","category":"工作","remindMinutesBefore":15}]}"#
    let raw = try await call(config: config, userPrompt: testPrompt)
    guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw LlmParseError.transport("模型返回内容为空")
    }
    return "连接成功：\(config.provider.displayName) (\(config.model)) 响应正常"
  }

  // MARK: - 网络

  private func call(config: LlmConfig, userPrompt: String) async throws -> String {
    let payload: [String: Any] = [
      "model": config.model.trimmingCharacters(in: .whitespacesAndNewlines),
      "temperature": 0.2,
      "messages": [
        ["role": "system", "content": Self.systemPrompt],
        ["role": "user", "content": userPrompt],
      ],
      "response_format": ["type": "json_object"],
    ]

    do {
      return try await Self.withTimeout(seconds: timeout) { [transport] in
        let firstBody = try Self.encodeJSON(payload)
        let first = try await transport.postJSON(
          url: config.endpoint,
          headers: ["Authorization": "Bearer " + config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)],
          body: firstBody
        )

        var result = first
        if !(200...299).contains(first.status), first.status == 400 {
          // 有些兼容接口不认 response_format，去掉重试一次（与 Android 版一致）
          var retryPayload = payload
          retryPayload.removeValue(forKey: "response_format")
          let retryBody = try Self.encodeJSON(retryPayload)
          result = try await transport.postJSON(
            url: config.endpoint,
            headers: ["Authorization": "Bearer " + config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)],
            body: retryBody
          )
        }

        guard (200...299).contains(result.status) else {
          throw LlmParseError.transport(Self.errorMessage(status: result.status, body: result.body))
        }

        guard
          let root = try? JSONSerialization.jsonObject(with: result.body) as? [String: Any],
          let choices = root["choices"] as? [[String: Any]]
        else {
          throw LlmParseError.transport("接口未返回 choices 字段")
        }
        guard let first = choices.first else {
          throw LlmParseError.transport("模型未返回候选结果")
        }
        let message = first["message"] as? [String: Any]
        let content = (message?["content"] as? String) ?? ""
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
          throw LlmParseError.transport("模型返回内容为空")
        }
        return content
      }
    } catch let error as LlmParseError {
      throw error
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw LlmParseError.transport(error.localizedDescription)
    }
  }

  static func errorMessage(status: Int, body: Data) -> String {
    let text = String(data: body, encoding: .utf8) ?? ""
    var apiMessage: String?
    if let root = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
       let err = root["error"] as? [String: Any],
       let msg = err["message"] as? String,
       !msg.isEmpty {
      apiMessage = msg
    }
    let detail = apiMessage ?? String(text.prefix(180))
    return "HTTP \(status): \(detail)"
  }

  static func encodeJSON(_ object: [String: Any]) throws -> Data {
    try JSONSerialization.data(withJSONObject: object, options: [])
  }

  static func withTimeout<T>(seconds: TimeInterval, _ work: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
      group.addTask { try await work() }
      group.addTask {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        throw LlmParseError.timedOut
      }
      defer { group.cancelAll() }
      guard let result = try await group.next() else {
        throw LlmParseError.timedOut
      }
      return result
    }
  }

  // MARK: - 提示词

  public static func buildParsingPrompt(sentence: String, nowMillis: Int64) -> String {
    let fmt = DateFormatter()
    fmt.locale = Locale(identifier: "zh_CN")
    fmt.timeZone = .current
    fmt.dateFormat = "yyyy-MM-dd HH:mm EEEE"
    let nowFormatted = fmt.string(from: Date(timeIntervalSince1970: Double(nowMillis) / 1000))
    let tzID = TimeZone.current.identifier
    return """
    当前本地时间：\(nowFormatted) (时区: \(tzID))
    请分析下面这句用户输入，识别其中包含的 1 个或多个独立工作待办事项（如果一句话里有多个时间或多项不同工作，请拆分为多条），严格只返回 JSON 对象 `{"tasks": [...]}`（不要额外解释）：
    用户输入：「\(sentence)」

    每条待办对象字段要求：
    - title: 提炼后的清晰工作标题（简明扼要，不超过60字）
    - notes: 补充说明、交付物或关联人物；如果没有则为空字符串 ""
    - deadlineLocal: 格式必须为 "yyyy-MM-dd HH:mm"。若用户只说了"上午10点/下班前/今天下午/今晚/3点"，请按当前时间合理推算；若某项未单独提时间，可继承句中主时间或默认为当前时间 1 小时后
    - priority: 仅限 "high"、"medium"、"low"（含"急/马上/立刻/重要/必须"取 "high"）
    - category: 仅限 "工作"、"会议"、"沟通"、"开发"、"个人"
    - remindMinutesBefore: 仅限整数 0、5、15、30、60（默认 15）
    """
  }

  // MARK: - 响应解析（纯函数，单独测）

  public static func extractJsonString(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let arrStart = trimmed.firstIndex(of: "["),
          let objStart = trimmed.firstIndex(of: "{") else {
      if let objStart = trimmed.firstIndex(of: "{"), let objEnd = trimmed.lastIndex(of: "}"), objEnd > objStart {
        return String(trimmed[objStart...objEnd])
      }
      return trimmed
    }
    if arrStart < objStart {
      if let arrEnd = trimmed.lastIndex(of: "]"), arrEnd > arrStart {
        return String(trimmed[arrStart...arrEnd])
      }
      return trimmed
    }
    if let objEnd = trimmed.lastIndex(of: "}"), objEnd > objStart {
      return String(trimmed[objStart...objEnd])
    }
    return trimmed
  }

  public static func extractJsonObjectString(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if let start = trimmed.firstIndex(of: "{"),
       let end = trimmed.lastIndex(of: "}"),
       end > start {
      return String(trimmed[start...end])
    }
    return trimmed
  }

  public static func parseDraftsJSON(
    rawJson: String,
    fallbackSentence: String,
    nowMillis: Int64
  ) -> [ParsedTaskDraft] {
    let cleaned = extractJsonString(rawJson)
    guard let data = cleaned.data(using: .utf8),
          let root = try? JSONSerialization.jsonObject(with: data) else {
      return []
    }

    if let arr = root as? [[String: Any]] {
      return arr.map { parseSingleObject($0, fallbackSentence: fallbackSentence, nowMillis: nowMillis) }
    }
    guard let dict = root as? [String: Any] else { return [] }
    for key in ["tasks", "items", "todos"] {
      if let arr = dict[key] as? [[String: Any]], !arr.isEmpty {
        return arr.map { parseSingleObject($0, fallbackSentence: fallbackSentence, nowMillis: nowMillis) }
      }
    }
    return [parseSingleObject(dict, fallbackSentence: fallbackSentence, nowMillis: nowMillis)]
  }

  public static func parseSingleObject(
    _ json: [String: Any],
    fallbackSentence: String,
    nowMillis: Int64
  ) -> ParsedTaskDraft {
    let rawTitle = (json["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let fallback = String(fallbackSentence.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
    let title = String((rawTitle.isEmpty ? fallback : rawTitle).prefix(120))
    let notes = String((json["notes"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
    let deadlineLocal = (json["deadlineLocal"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let deadlineMillis = parseDeadlineLocalToMillis(deadlineLocal, nowMillis: nowMillis)

    let priorityWire = (json["priority"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let priority = TaskPriority.fromWire(priorityWire)

    let rawCategory = (json["category"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let category = allowedCategories.contains(rawCategory) ? rawCategory : "工作"

    let rawRemind = json["remindMinutesBefore"] as? Int64
      ?? (json["remindMinutesBefore"] as? Int).map(Int64.init)
      ?? (json["remindMinutesBefore"] as? Double).map { Int64($0) }
      ?? 15
    let remind = allowedReminders.min(by: { abs($0 - rawRemind) < abs($1 - rawRemind) }) ?? 15

    return ParsedTaskDraft(
      title: title,
      notes: notes,
      deadlineMillis: deadlineMillis,
      priority: priority,
      category: category,
      remindMinutesBefore: remind
    )
  }

  /// 支持 yyyy-MM-dd HH:mm / yyyy/MM/dd HH:mm / yyyy-MM-dd'T'HH:mm；
  /// 解析不出来就落到「当前时间 + 1 小时（秒归零）」，与 Android 版一致。
  public static func parseDeadlineLocalToMillis(_ deadlineLocal: String, nowMillis: Int64) -> Int64 {
    if !deadlineLocal.isEmpty {
      let patterns = ["yyyy-MM-dd HH:mm", "yyyy/MM/dd HH:mm", "yyyy-MM-dd'T'HH:mm"]
      for pattern in patterns {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "zh_CN")
        fmt.timeZone = .current
        fmt.dateFormat = pattern
        fmt.isLenient = false
        let candidate = String(deadlineLocal.prefix(16))
        if let date = fmt.date(from: candidate), date.timeIntervalSince1970 > 0 {
          return Int64((date.timeIntervalSince1970 * 1000).rounded())
        }
      }
    }
    let calendar = Calendar.current
    var comps = calendar.dateComponents([.year, .month, .day, .hour, .minute],
                                        from: Date(timeIntervalSince1970: Double(nowMillis) / 1000 + 3600))
    comps.second = 0
    let date = calendar.date(from: comps) ?? Date()
    return Int64((date.timeIntervalSince1970 * 1000).rounded())
  }
}
