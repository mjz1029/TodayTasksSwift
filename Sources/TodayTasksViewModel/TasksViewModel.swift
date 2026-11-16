import Foundation
import Combine
import TodayTasksCore

/// 四个筛选，label 与 Android 版 TaskFilter 完全一致。
public enum TaskFilter: String, CaseIterable, Identifiable, Sendable {
  case todayUnfinished
  case urgentSoon
  case todayCompleted
  case allScheduled

  public var id: String { rawValue }

  public var label: String {
    switch self {
    case .todayUnfinished: return "今日待办"
    case .urgentSoon: return "即将截止"
    case .todayCompleted: return "今日已办"
    case .allScheduled: return "全部日程"
    }
  }
}

public enum ParseState: Equatable, Sendable {
  case idle
  case loading
  case failed(String)
  case drafts([ParsedTaskDraft])

  public var isLoading: Bool { self == .loading }
}

/// 界面状态与动作。数据全部来自 LocalTasksStore，不留任何内存假数据。
@MainActor
public final class TasksViewModel: ObservableObject {

  @Published public private(set) var tasks: [TaskItem] = []
  @Published public var filter: TaskFilter = .todayUnfinished
  @Published public var parseState: ParseState = .idle
  @Published public var captureText: String = ""
  @Published public var llmConfig: LlmConfig
  @Published public var toast: String?
  @Published public var isShowingSettings = false
  @Published public var editingTask: TaskItem?
  @Published public var shareTask: TaskItem?
  @Published public var shareToken: String = ""
  @Published public var importCodeText: String = ""
  @Published public var nowMillis: Int64 = TaskItem.nowMillis()

  public let settings: AppSettings
  public let store: LocalTasksStore
  private let parser: NaturalLanguageTaskParser
  private var listenerToken: UUID?
  private var undoBuffer: [LocalTaskRecord] = []

  public init(
    store: LocalTasksStore = LocalTasksStore(fileURL: LocalTasksStore.defaultFileURL()),
    parser: NaturalLanguageTaskParser = NaturalLanguageTaskParser(),
    settings: AppSettings = .shared
  ) {
    self.store = store
    self.parser = parser
    self.settings = settings
    self.llmConfig = settings.llmConfig
  }

  // MARK: - 生命周期

  public func start() async {
    guard listenerToken == nil else { return }
    listenerToken = await store.addListener { [weak self] tasks in
      Task { @MainActor in
        self?.tasks = tasks
        self?.nowMillis = TaskItem.nowMillis()
      }
    }
    await refresh()
  }

  public func refresh() async {
    await reloadTasks()
    nowMillis = TaskItem.nowMillis()
  }

  /// 只刷新任务列表，不动 nowMillis（时间相关的测试/界面锚点不能被写入动作改掉）。
  private func reloadTasks() async {
    tasks = (try? await store.allTasks()) ?? []
  }

  public func tick() {
    nowMillis = TaskItem.nowMillis()
  }

  // MARK: - 派生数据（与 Android 版 TasksWorkspaceScreen 同一套口径）

  public var endOfToday: Int64 { TaskItem.dayBounds(anchorMillis: nowMillis).end }

  public var unfinishedTodayTasks: [TaskItem] {
    tasks
      .filter { !$0.isCompleted && $0.deadlineMillis <= endOfToday }
      .sorted { lhs, rhs in
        if lhs.deadlineMillis != rhs.deadlineMillis { return lhs.deadlineMillis < rhs.deadlineMillis }
        let lh = lhs.priority == .high
        let rh = rhs.priority == .high
        if lh != rh { return lh }
        return lhs.createdAtMillis < rhs.createdAtMillis
      }
  }

  public var completedTodayCount: Int {
    tasks.filter { $0.isCompletedToday(nowMillis: nowMillis) || ($0.isCompleted && $0.isDueToday(nowMillis: nowMillis)) }.count
  }

  public var overdueCount: Int {
    unfinishedTodayTasks.filter { $0.isOverdue(nowMillis: nowMillis) }.count
  }

  public var nextUrgentTask: TaskItem? { unfinishedTodayTasks.first }

  public var filteredTasks: [TaskItem] {
    switch filter {
    case .todayUnfinished:
      return unfinishedTodayTasks
    case .urgentSoon:
      return unfinishedTodayTasks.filter {
        $0.isOverdue(nowMillis: nowMillis)
          || ($0.deadlineMillis - nowMillis) >= 0 && ($0.deadlineMillis - nowMillis) <= 2 * 3600 * 1000
      }
    case .todayCompleted:
      return tasks
        .filter { $0.isCompleted && ($0.isCompletedToday(nowMillis: nowMillis) || $0.isDueToday(nowMillis: nowMillis)) }
        .sorted { $0.completedAtMillis > $1.completedAtMillis }
    case .allScheduled:
      return tasks
    }
  }

  public var emptyStateText: String {
    switch filter {
    case .todayUnfinished, .urgentSoon: return "今天没有待办，先歇一会儿"
    case .todayCompleted: return "今天还没有完成的工作"
    case .allScheduled: return "还没有任何工作安排，从下面加一条"
    }
  }

  // MARK: - 任务动作

  public func create(
    title: String,
    notes: String,
    deadlineMillis: Int64,
    priority: TaskPriority,
    category: String,
    remindMinutesBefore: Int64
  ) async {
    let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else {
      toast = "请填写工作标题"
      return
    }
    do {
      try await store.create(
        title: clean,
        notes: notes,
        deadlineMillis: deadlineMillis,
        priority: priority,
        category: category,
        remindMinutesBefore: remindMinutesBefore
      )
      await reloadTasks()
      await ReminderBridge.shared.sync()
      toast = "已添加该工作任务"
    } catch {
      toast = "保存失败：\(error.localizedDescription)"
    }
  }

  public func update(_ task: TaskItem) async {
    do {
      try await store.update(task)
      await reloadTasks()
      await ReminderBridge.shared.sync()
      toast = "已更新该工作任务"
    } catch {
      toast = "更新失败：\(error.localizedDescription)"
    }
  }

  public func toggle(_ task: TaskItem) async {
    do {
      try await store.toggleCompletion(taskId: task.id, isCompleted: !task.isCompleted)
      await reloadTasks()
      await ReminderBridge.shared.sync()
      toast = task.isCompleted ? "已恢复为待办" : "已标记完成"
    } catch {
      toast = "操作失败：\(error.localizedDescription)"
    }
  }

  /// 删除带撤销：Android 版删了就没了，这里留一份内存快照，toast 上给「撤销」。
  public func delete(_ task: TaskItem) async {
    undoBuffer = [LocalTaskRecord.from(task)]
    do {
      try await store.delete(taskId: task.id)
      await reloadTasks()
      await ReminderBridge.shared.sync()
      toast = "已删除「\(task.title)」"
    } catch {
      toast = "删除失败：\(error.localizedDescription)"
    }
  }

  public func undoDelete() async {
    guard !undoBuffer.isEmpty else { return }
    let buffer = undoBuffer
    undoBuffer = []
    do {
      let count = try await store.importRecords(buffer, replaceExisting: false)
      await reloadTasks()
      await ReminderBridge.shared.sync()
      toast = count > 0 ? "已撤销删除" : "该任务已存在"
    } catch {
      toast = "撤销失败：\(error.localizedDescription)"
    }
  }

  public var canUndoDelete: Bool { !undoBuffer.isEmpty }

  // MARK: - AI 速记

  public func fillFromAI() async {
    let sentence = captureText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !sentence.isEmpty else {
      parseState = .failed("先写下要做的事，例如「今晚八点前交季报」")
      return
    }
    parseState = .loading
    do {
      let drafts = try await parser.parse(sentence: sentence, config: llmConfig)
      parseState = .drafts(drafts)
      if drafts.count == 1 {
        await acceptDraft(drafts[0])
      }
    } catch {
      parseState = .failed(error.localizedDescription)
    }
  }

  public func acceptDraft(_ draft: ParsedTaskDraft) async {
    do {
      try await store.createMany([draft.toNewTaskInput])
      captureText = ""
      parseState = .idle
      await reloadTasks()
      await ReminderBridge.shared.sync()
      toast = "已按速记创建任务"
    } catch {
      parseState = .failed("创建失败：\(error.localizedDescription)")
    }
  }

  public func acceptAllDrafts() async {
    guard case .drafts(let drafts) = parseState, !drafts.isEmpty else { return }
    do {
      let ids = try await store.createMany(drafts.map(\.toNewTaskInput))
      captureText = ""
      parseState = .idle
      await reloadTasks()
      await ReminderBridge.shared.sync()
      toast = "已创建 \(ids.count) 条任务"
    } catch {
      parseState = .failed("创建失败：\(error.localizedDescription)")
    }
  }

  public func dismissParseState() { parseState = .idle }

  // MARK: - 单条分享 / 导入

  public func openShare(for task: TaskItem) {
    shareToken = (try? SingleTaskShareCodec.encodeToken(task)) ?? ""
    shareTask = task
  }

  /// 粘贴对方的口令或二维码文本，导成本机任务（走 importRecords，自动去重）。
  public func importFromCode() async {
    let raw = importCodeText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !raw.isEmpty else {
      toast = "请粘贴分享口令或二维码内容"
      return
    }
    switch SingleTaskShareCodec.decodeToken(raw) {
    case .success(let payload):
      do {
        let count = try await store.importRecords([payload.toNewLocalRecord()], replaceExisting: false)
        await reloadTasks()
        importCodeText = ""
        toast = count > 0 ? "已导入「\(payload.title)」" : "这条任务已经在列表里了"
      } catch {
        toast = "导入失败：\(error.localizedDescription)"
      }
    case .failure(let error):
      toast = error.errorDescription ?? "分享内容无法识别"
    }
  }

  // MARK: - 设置

  public func saveLlmConfig(_ config: LlmConfig) {
    llmConfig = config
    settings.llmConfig = config
    toast = "模型配置已保存"
  }

  public func clearAllTasks() async {
    do {
      try await store.clearAll()
      await reloadTasks()
      await ReminderBridge.shared.sync()
      toast = "已清空本机数据"
    } catch {
      toast = "清空失败：\(error.localizedDescription)"
    }
  }
}
