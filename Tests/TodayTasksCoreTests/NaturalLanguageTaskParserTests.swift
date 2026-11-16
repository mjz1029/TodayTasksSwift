import Foundation
import Testing
@testable import TodayTasksCore

/// 可编排的假传输层：按顺序吐出预设响应，并记下每次请求，便于断言「重试时到底发了什么」。
final class StubTransport: LlmTransport, @unchecked Sendable {
  struct Reply {
    let status: Int
    let body: Data
    init(status: Int, body: String) {
      self.status = status
      self.body = Data(body.utf8)
    }
  }

  struct Captured {
    let url: String
    let headers: [String: String]
    let body: Data
  }

  private let lock = NSLock()
  private var pending: [Reply]
  private var captured: [Captured] = []

  init(_ replies: [Reply]) {
    self.pending = replies
  }

  var requests: [Captured] {
    lock.lock(); defer { lock.unlock() }
    return captured
  }

  func postJSON(url: String, headers: [String: String], body: Data) async throws -> (status: Int, body: Data) {
    lock.lock()
    captured.append(Captured(url: url, headers: headers, body: body))
    let reply = pending.isEmpty ? Reply(status: 500, body: "stub exhausted") : pending.removeFirst()
    lock.unlock()
    return (reply.status, reply.body)
  }
}

@Suite("自然语言建任务解析")
struct NaturalLanguageTaskParserTests {

  private func millis(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Int64 {
    var comps = DateComponents()
    comps.year = y; comps.month = mo; comps.day = d
    comps.hour = h; comps.minute = mi; comps.second = 0
    return Int64((Calendar.current.date(from: comps)!.timeIntervalSince1970 * 1000).rounded())
  }

  private func config() -> LlmConfig {
    LlmConfig(provider: .deepseek, baseURL: "https://api.deepseek.com/v1",
              model: "deepseek-chat", apiKey: "sk-test-123")
  }

  private func chatCompletion(_ content: String) -> String {
    let escaped = content
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
      .replacingOccurrences(of: "\n", with: "\\n")
    return #"{"choices":[{"message":{"role":"assistant","content":"\#(escaped)"}}]}"#
  }

  @Test("一句话拆成多条待办")
  func parsesMultipleTasks() async throws {
    let content = #"""
    ```json
    {"tasks":[
      {"title":"提交 Q4 进度报告","notes":"带上季度数据","deadlineLocal":"2026-11-16 18:00","priority":"high","category":"工作","remindMinutesBefore":30},
      {"title":"和王总确认预算口径","notes":"","deadlineLocal":"2026-11-17 10:30","priority":"medium","category":"沟通","remindMinutesBefore":15}
    ]}
    ```
    """#
    let stub = StubTransport([.init(status: 200, body: chatCompletion(content))])
    let parser = NaturalLanguageTaskParser(transport: stub)
    let now = millis(2026, 11, 16, 9, 0)

    let drafts = try await parser.parse(sentence: "今晚八点前交季报，明早十点半和王总确认预算口径", config: config(), nowMillis: now)
    #expect(drafts.count == 2)
    #expect(drafts[0].title == "提交 Q4 进度报告")
    #expect(drafts[0].priority == .high)
    #expect(drafts[0].remindMinutesBefore == 30)
    #expect(drafts[0].deadlineMillis == millis(2026, 11, 16, 18, 0))
    #expect(drafts[1].category == "沟通")

    // 请求本身也要对：endpoint、鉴权头、model、response_format
    let request = try #require(stub.requests.first)
    #expect(request.url == "https://api.deepseek.com/v1/chat/completions")
    #expect(request.headers["Authorization"] == "Bearer sk-test-123")
    let json = try #require(try JSONSerialization.jsonObject(with: request.body) as? [String: Any])
    #expect(json["model"] as? String == "deepseek-chat")
    #expect((json["response_format"] as? [String: Any])?["type"] as? String == "json_object")
    let messages = try #require(json["messages"] as? [[String: String]])
    #expect(messages.count == 2)
    #expect(messages[0]["role"] == "system")
    #expect(messages[1]["content"]?.contains("今晚八点前交季报") == true, "提示词里必须带用户原句")
    #expect(messages[1]["content"]?.contains("2026-11-16") == true, "提示词里必须带当前时间")
  }

  @Test("接口不认 response_format 时自动去掉重试")
  func retriesWithoutResponseFormatOn400() async throws {
    let content = #"{"tasks":[{"title":"重试成功","deadlineLocal":"2026-11-16 18:00","priority":"medium","category":"工作","remindMinutesBefore":15}]}"#
    let stub = StubTransport([
      .init(status: 400, body: #"{"error":{"message":"response_format is not supported"}}"#),
      .init(status: 200, body: chatCompletion(content)),
    ])
    let parser = NaturalLanguageTaskParser(transport: stub)
    let drafts = try await parser.parse(sentence: "重试测试", config: config(), nowMillis: millis(2026, 11, 16, 9, 0))
    #expect(drafts.first?.title == "重试成功")

    #expect(stub.requests.count == 2, "400 后应重试一次")
    let retryJSON = try #require(try JSONSerialization.jsonObject(with: stub.requests[1].body) as? [String: Any])
    #expect(retryJSON["response_format"] == nil, "重试请求不能再带 response_format")
  }

  @Test("鉴权失败把服务端错误文案带出来")
  func surfacesApiErrorMessage() async {
    let stub = StubTransport([.init(status: 401, body: #"{"error":{"message":"Invalid API key"}}"#)])
    let parser = NaturalLanguageTaskParser(transport: stub)
    do {
      _ = try await parser.parse(sentence: "测试", config: config(), nowMillis: millis(2026, 11, 16, 9, 0))
      Issue.record("应该抛错")
    } catch let error as LlmParseError {
      #expect(error == .transport("HTTP 401: Invalid API key"))
    } catch {
      Issue.record("错误类型不对：\(error)")
    }
  }

  @Test("没填 key、空输入分别报错")
  func validatesInput() async {
    let parser = NaturalLanguageTaskParser(transport: StubTransport([]))
    var noKey = config()
    noKey.apiKey = "   "
    do {
      _ = try await parser.parse(sentence: "有内容", config: noKey, nowMillis: 0)
      Issue.record("缺 key 应该抛错")
    } catch let error as LlmParseError {
      #expect(error == .missingApiKey("DeepSeek"))
      #expect(error.errorDescription?.contains("API Key") == true)
    } catch { Issue.record("错误类型不对") }

    do {
      _ = try await parser.parse(sentence: "   ", config: config(), nowMillis: 0)
      Issue.record("空输入应该抛错")
    } catch let error as LlmParseError {
      #expect(error == .emptyInput)
    } catch { Issue.record("错误类型不对") }
  }

  @Test("模型返回非 JSON 时给「没识别出待办」而不是崩")
  func handlesGarbageContent() async {
    let stub = StubTransport([.init(status: 200, body: chatCompletion("抱歉，我无法理解这句话"))])
    let parser = NaturalLanguageTaskParser(transport: stub)
    do {
      _ = try await parser.parse(sentence: "随便说点什么", config: config(), nowMillis: 0)
      Issue.record("应该抛错")
    } catch let error as LlmParseError {
      #expect(error == .noTasks)
      #expect(error.errorDescription == "未识别出有效的工作事项，请换个说法重试" || error.errorDescription == "未识别出有效的待办事项，请换个说法重试")
    } catch { Issue.record("错误类型不对：\(error)") }
  }

  @Test("字段清洗：标题回退、分类白名单、提醒就近取整")
  func sanitizesDraftFields() {
    let now = millis(2026, 11, 16, 9, 0)
    let draft = NaturalLanguageTaskParser.parseSingleObject(
      ["title": "   ", "notes": "", "deadlineLocal": "", "priority": "URGENT", "category": "杂事", "remindMinutesBefore": 20],
      fallbackSentence: "标题为空时用用户原句兜底，这句挺长的所以要被截断到六十个字以内才行啊真的挺长的一句话",
      nowMillis: now
    )
    #expect(draft.title.hasPrefix("标题为空时用用户原句兜底"))
    #expect(draft.title.count <= 60)
    #expect(draft.priority == .medium, "未知优先级回落常规")
    #expect(draft.category == "工作", "白名单外分类回落工作")
    #expect(draft.remindMinutesBefore == 15, "20 就近取 15")
    #expect(draft.deadlineMillis == millis(2026, 11, 16, 10, 0), "没给时间就落到一小时后且秒归零")
  }

  @Test("截止时间三种格式都认")
  func parsesDeadlineFormats() {
    let now = millis(2026, 11, 16, 9, 0)
    #expect(NaturalLanguageTaskParser.parseDeadlineLocalToMillis("2026-11-16 18:30", nowMillis: now) == millis(2026, 11, 16, 18, 30))
    #expect(NaturalLanguageTaskParser.parseDeadlineLocalToMillis("2026/11/17 08:05", nowMillis: now) == millis(2026, 11, 17, 8, 5))
    #expect(NaturalLanguageTaskParser.parseDeadlineLocalToMillis("2026-11-18T14:00", nowMillis: now) == millis(2026, 11, 18, 14, 0))
    #expect(NaturalLanguageTaskParser.parseDeadlineLocalToMillis("明天下午", nowMillis: now) == millis(2026, 11, 16, 10, 0))
  }

  @Test("裸数组与 items/todos 两种包裹都能解析")
  func acceptsAlternativeShapes() {
    let now = millis(2026, 11, 16, 9, 0)
    let array = NaturalLanguageTaskParser.parseDraftsJSON(
      rawJson: #"[{"title":"数组直接给","deadlineLocal":"2026-11-16 18:00"}]"#,
      fallbackSentence: "原句", nowMillis: now
    )
    #expect(array.count == 1)
    #expect(array[0].title == "数组直接给")

    let items = NaturalLanguageTaskParser.parseDraftsJSON(
      rawJson: #"{"items":[{"title":"items 包裹","deadlineLocal":"2026-11-16 18:00"}]}"#,
      fallbackSentence: "原句", nowMillis: now
    )
    #expect(items[0].title == "items 包裹")

    let todos = NaturalLanguageTaskParser.parseDraftsJSON(
      rawJson: #"{"todos":[{"title":"todos 包裹","deadlineLocal":"2026-11-16 18:00"}]}"#,
      fallbackSentence: "原句", nowMillis: now
    )
    #expect(todos[0].title == "todos 包裹")
  }

  @Test("测试连接返回成功文案")
  func testConnection() async throws {
    let stub = StubTransport([.init(status: 200, body: chatCompletion(#"{"tasks":[]}"#))])
    let parser = NaturalLanguageTaskParser(transport: stub)
    let message = try await parser.testConnection(config: config())
    #expect(message.contains("连接成功"))
    #expect(message.contains("deepseek-chat"))
  }

  @Test("提示词结构与 Android 版一致")
  func promptShape() {
    let prompt = NaturalLanguageTaskParser.buildParsingPrompt(
      sentence: "明天上午十点前把预算表发给财务",
      nowMillis: millis(2026, 11, 16, 15, 20)
    )
    #expect(prompt.contains("当前本地时间：2026-11-16 15:20"))
    #expect(prompt.contains("时区: "))
    #expect(prompt.contains("用户输入：「明天上午十点前把预算表发给财务」"))
    #expect(prompt.contains("deadlineLocal"))
    #expect(prompt.contains("remindMinutesBefore"))
  }
}
