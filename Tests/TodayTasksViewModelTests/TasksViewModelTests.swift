import Foundation
import Testing
import TodayTasksCore
@testable import TodayTasksViewModel

/// 界面状态层测试：筛选口径、计数、撤销删除、AI 草稿接线。
/// 这一层刻意不依赖 SwiftUI，所以在只装 Command Line Tools 的机器上也能真跑。
@Suite("界面状态与动作", .serialized)
@MainActor
final class TasksViewModelTests {

  private let fileURL: URL

  init() throws {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("TodayTasksVMTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    fileURL = dir.appendingPathComponent("tasks.json")
  }

  deinit {
    try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
  }

  private func millis(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Int64 {
    var comps = DateComponents()
    comps.year = y; comps.month = mo; comps.day = d
    comps.hour = h; comps.minute = mi; comps.second = 0
    return Int64((Calendar.current.date(from: comps)!.timeIntervalSince1970 * 1000).rounded())
  }

  private func makeViewModel(now: Int64) async -> TasksViewModel {
    let defaults = UserDefaults(suiteName: "vm-tests-\(UUID().uuidString)")!
    let viewModel = TasksViewModel(
      store: LocalTasksStore(fileURL: fileURL),
      settings: AppSettings(defaults: defaults)
    )
    await viewModel.refresh()
    viewModel.nowMillis = now
    return viewModel
  }

  /// 固定时间点：2026-11-16 14:30
  private var noon: Int64 { millis(2026, 11, 16, 14, 30) }

  private func seed(_ viewModel: TasksViewModel) async {
    let store = LocalTasksStore(fileURL: fileURL)
    _ = try? await store.createMany([
      .init(title: "今天18点交报表", deadlineMillis: millis(2026, 11, 16, 18, 0), priority: .high, category: "工作"),
      .init(title: "今天16点沟通", deadlineMillis: millis(2026, 11, 16, 16, 0), priority: .medium, category: "沟通"),
      .init(title: "昨天没做完", deadlineMillis: millis(2026, 11, 15, 9, 0), priority: .high, category: "工作"),
      .init(title: "明天才到期", deadlineMillis: millis(2026, 11, 17, 9, 0), priority: .low, category: "会议"),
      .init(title: "没设时限", deadlineMillis: 0, priority: .low, category: "个人"),
    ])
    await viewModel.refresh()
    viewModel.nowMillis = noon
  }

  @Test("今日待办：只留今天及以前截止、未完成的，按截止时间升序、紧急优先")
  func filterTodayUnfinished() async {
    let viewModel = await makeViewModel(now: noon)
    await seed(viewModel)
    viewModel.filter = .todayUnfinished

    let titles = viewModel.filteredTasks.map(\.title)
    // deadline 0 的任务与 Android 版一致：deadlineMillis <= endOfDay 成立，算进今日列表并排最前
    #expect(titles == ["没设时限", "昨天没做完", "今天16点沟通", "今天18点交报表"])
    #expect(viewModel.unfinishedTodayTasks.count == 4)
  }

  @Test("即将截止：逾期 + 两小时内")
  func filterUrgentSoon() async {
    let viewModel = await makeViewModel(now: noon)
    await seed(viewModel)
    viewModel.filter = .urgentSoon

    let titles = viewModel.filteredTasks.map(\.title)
    #expect(titles == ["昨天没做完", "今天16点沟通"],
            "16:00 在 14:30 之后两小时内；18:00 超出两小时；deadline=0 既不逾期也不在两小时内，与 Android 口径一致被排除")
  }

  @Test("今日已办：按完成时间倒序")
  func filterTodayCompleted() async {
    let viewModel = await makeViewModel(now: noon)
    await seed(viewModel)
    let store = LocalTasksStore(fileURL: fileURL)
    let tasks = (try? await store.allTasks()) ?? []
    let first = tasks.first { $0.title == "今天16点沟通" }!
    let second = tasks.first { $0.title == "今天18点交报表" }!
    try? await store.toggleCompletion(taskId: first.id, isCompleted: true)
    try? await store.toggleCompletion(taskId: second.id, isCompleted: true)

    await viewModel.refresh()
    viewModel.nowMillis = noon
    viewModel.filter = .todayCompleted

    #expect(viewModel.filteredTasks.count == 2)
    #expect(viewModel.completedTodayCount == 2)
    let stamps = viewModel.filteredTasks.map(\.completedAtMillis)
    #expect(stamps == stamps.sorted(by: >), "完成时间倒序")
  }

  @Test("全部日程包含所有任务")
  func filterAllScheduled() async {
    let viewModel = await makeViewModel(now: noon)
    await seed(viewModel)
    viewModel.filter = .allScheduled
    #expect(viewModel.filteredTasks.count == 5)
  }

  @Test("逾期计数与最近截止")
  func overdueAndNext() async {
    let viewModel = await makeViewModel(now: noon)
    await seed(viewModel)

    #expect(viewModel.overdueCount == 1, "只有「昨天没做完」逾期（无时限不算逾期）")
    #expect(viewModel.nextUrgentTask?.title == "没设时限", "截止时间 0 排最前，与 Android 一致")
  }

  @Test("新建任务：空标题拦下，正常标题落库")
  func createValidatesTitle() async {
    let viewModel = await makeViewModel(now: noon)
    await viewModel.create(title: "   ", notes: "", deadlineMillis: 0,
                           priority: .medium, category: "工作", remindMinutesBefore: 15)
    #expect(viewModel.toast == "请填写工作标题")
    #expect(viewModel.tasks.isEmpty)

    await viewModel.create(title: "写周报", notes: "周五交", deadlineMillis: millis(2026, 11, 16, 18, 0),
                           priority: .high, category: "工作", remindMinutesBefore: 30)
    #expect(viewModel.tasks.count == 1)
    #expect(viewModel.tasks[0].title == "写周报")
    #expect(viewModel.toast == "已添加该工作任务")
  }

  @Test("完成/恢复：完成时间写上再清零")
  func toggleCompletion() async {
    let viewModel = await makeViewModel(now: noon)
    await seed(viewModel)
    let task = viewModel.tasks.first { $0.title == "今天18点交报表" }!

    await viewModel.toggle(task)
    let done = viewModel.tasks.first { $0.id == task.id }!
    #expect(done.isCompleted)
    #expect(done.completedAtMillis > 0)
    #expect(viewModel.toast == "已标记完成")

    await viewModel.toggle(done)
    let restored = viewModel.tasks.first { $0.id == task.id }!
    #expect(!restored.isCompleted)
    #expect(restored.completedAtMillis == 0)
    #expect(viewModel.toast == "已恢复为待办")
  }

  @Test("删除可撤销")
  func deleteAndUndo() async {
    let viewModel = await makeViewModel(now: noon)
    await seed(viewModel)
    let task = viewModel.tasks.first { $0.title == "今天16点沟通" }!

    await viewModel.delete(task)
    #expect(viewModel.tasks.count == 4)
    #expect(viewModel.canUndoDelete)
    #expect(viewModel.toast?.contains("已删除") == true)

    await viewModel.undoDelete()
    #expect(viewModel.tasks.count == 5)
    #expect(viewModel.tasks.contains { $0.title == "今天16点沟通" })
    #expect(viewModel.toast == "已撤销删除")
    #expect(!viewModel.canUndoDelete, "撤销只能用一次")
  }

  @Test("AI 草稿：单条直接建、多条走确认后批量建")
  func acceptDrafts() async {
    let viewModel = await makeViewModel(now: noon)
    let draft = ParsedTaskDraft(title: "和王总确认口径", notes: "", deadlineMillis: millis(2026, 11, 16, 18, 0),
                                priority: .medium, category: "沟通", remindMinutesBefore: 15)

    await viewModel.acceptDraft(draft)
    #expect(viewModel.tasks.count == 1)
    #expect(viewModel.captureText.isEmpty, "建完清空输入框")

    viewModel.parseState = .drafts([
      draft,
      ParsedTaskDraft(title: "补齐县市对标表", deadlineMillis: millis(2026, 11, 17, 9, 0)),
    ])
    await viewModel.acceptAllDrafts()
    #expect(viewModel.tasks.count == 3)
    #expect(viewModel.toast == "已创建 2 条任务")
    #expect(viewModel.parseState == .idle)
  }

  @Test("没配模型时点填充，给出可读错误而不是静默")
  func fillWithoutConfig() async {
    let viewModel = await makeViewModel(now: noon)
    viewModel.captureText = "今晚八点前交季报"
    await viewModel.fillFromAI()
    guard case .failed(let message) = viewModel.parseState else {
      Issue.record("应为失败态，实际 \(viewModel.parseState)")
      return
    }
    #expect(message.contains("API Key"))
  }

  @Test("空输入点填充会提示先写内容")
  func fillWithEmptyText() async {
    let viewModel = await makeViewModel(now: noon)
    viewModel.captureText = "   "
    await viewModel.fillFromAI()
    guard case .failed(let message) = viewModel.parseState else {
      Issue.record("应为失败态")
      return
    }
    #expect(message.contains("先写下要做的事"))
  }

  @Test("清空全部")
  func clearAll() async {
    let viewModel = await makeViewModel(now: noon)
    await seed(viewModel)
    #expect(!viewModel.tasks.isEmpty)
    await viewModel.clearAllTasks()
    #expect(viewModel.tasks.isEmpty)
    #expect(viewModel.toast == "已清空本机数据")
  }

  @Test("每个筛选都有对应的空态文案")
  func emptyStateTexts() async {
    let viewModel = await makeViewModel(now: noon)
    for filter in TaskFilter.allCases {
      viewModel.filter = filter
      #expect(!viewModel.emptyStateText.isEmpty)
    }
    #expect(TaskFilter.allCases.map(\.label) == ["今日待办", "即将截止", "今日已办", "全部日程"])
  }
}
