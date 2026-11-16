import Foundation
import Testing
@testable import TodayTasksCore

@Suite("本地任务库：落盘、清洗、排序、导入", .serialized)
final class LocalTasksStoreTests {

  private let fileURL: URL

  init() throws {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("TodayTasksTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    self.fileURL = dir.appendingPathComponent("tasks.json")
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

  private func freshStore() -> LocalTasksStore {
    LocalTasksStore(fileURL: fileURL)
  }

  @Test("新建任务真落盘：换一个实例重新读能读到")
  func createPersists() async throws {
    let store = freshStore()
    let id = try await store.create(
      title: "  提交 Q4 进度报告  ",
      notes: "带上季度数据",
      deadlineMillis: millis(2026, 11, 16, 18, 0),
      priority: .high,
      category: "工作",
      remindMinutesBefore: 30
    )
    #expect(id.hasPrefix("local_"))

    let reopened = freshStore()
    let tasks = try await reopened.allTasks()
    #expect(tasks.count == 1)
    #expect(tasks[0].title == "提交 Q4 进度报告")
    #expect(tasks[0].priority == .high)
    #expect(tasks[0].remindMinutesBefore == 30)
    #expect(FileManager.default.fileExists(atPath: fileURL.path))
  }

  @Test("字段清洗规则与 Android 版一致")
  func sanitizing() async throws {
    let store = freshStore()
    _ = try await store.create(
      title: String(repeating: "标", count: 200),
      notes: String(repeating: "注", count: 800),
      deadlineMillis: 0,
      category: "   ",
      remindMinutesBefore: 99_999
    )
    var tasks = try await store.allTasks()
    #expect(tasks[0].title.count == 120)
    #expect(tasks[0].notes.count == 500)
    #expect(tasks[0].category == "工作")
    #expect(tasks[0].remindMinutesBefore == 1440)

    _ = try await store.create(title: "负数提醒", deadlineMillis: 0, remindMinutesBefore: -5)
    tasks = try await store.allTasks()
    #expect(tasks.first { $0.title == "负数提醒" }?.remindMinutesBefore == 0)
  }

  @Test("排序：未完成在前 → 截止时间升序 → 紧急在前 → 已完成沉底")
  func sorting() async throws {
    let store = freshStore()
    _ = try await store.create(title: "未完成-晚", deadlineMillis: millis(2026, 11, 16, 20, 0), priority: .low)
    _ = try await store.create(title: "未完成-早-常规", deadlineMillis: millis(2026, 11, 16, 9, 0))
    _ = try await store.create(title: "未完成-早-紧急", deadlineMillis: millis(2026, 11, 16, 9, 0), priority: .high)
    let doneId = try await store.create(title: "已完成", deadlineMillis: millis(2026, 11, 16, 8, 0), priority: .high)
    try await store.toggleCompletion(taskId: doneId, isCompleted: true)

    let titles = try await store.allTasks().map(\.title)
    #expect(titles == ["未完成-早-紧急", "未完成-早-常规", "未完成-晚", "已完成"])
  }

  @Test("标记完成会写完成时间，取消完成会清零")
  func toggleCompletion() async throws {
    let store = freshStore()
    let id = try await store.create(title: "写周报", deadlineMillis: millis(2026, 11, 16, 18, 0))
    try await store.toggleCompletion(taskId: id, isCompleted: true)
    var tasks = try await store.allTasks()
    #expect(tasks[0].isCompleted)
    #expect(tasks[0].completedAtMillis > 0)

    try await store.toggleCompletion(taskId: id, isCompleted: false)
    tasks = try await store.allTasks()
    #expect(!tasks[0].isCompleted)
    #expect(tasks[0].completedAtMillis == 0)
  }

  @Test("编辑与删除")
  func updateAndDelete() async throws {
    let store = freshStore()
    let id = try await store.create(title: "原标题", deadlineMillis: 0)
    var task = try await store.allTasks()[0]
    task.title = "改后标题"
    task.priority = .low
    task.notes = "补充说明"
    try await store.update(task)

    var tasks = try await store.allTasks()
    #expect(tasks[0].title == "改后标题")
    #expect(tasks[0].priority == .low)
    #expect(tasks[0].id == id)

    try await store.delete(taskId: id)
    tasks = try await store.allTasks()
    #expect(tasks.isEmpty)
  }

  @Test("导入去重：指纹相同的只进一条")
  func importDedupe() async throws {
    let store = freshStore()
    let existingId = try await store.create(title: "已有任务", deadlineMillis: 1_000)

    let duplicate = LocalTaskRecord(id: existingId, title: "已有任务", deadlineMillis: 1_000)
    let fresh = LocalTaskRecord(id: "local_fresh", title: "导入任务", deadlineMillis: 2_000)
    let count = try await store.importRecords([duplicate, fresh, fresh], replaceExisting: false)
    #expect(count == 1)
    #expect(try await store.allTasks().count == 2)
  }

  @Test("导入时空标题跳过")
  func importBlankTitle() async throws {
    let store = freshStore()
    let count = try await store.importRecords([LocalTaskRecord(id: "local_x", title: "   ", deadlineMillis: 1_000)],
                                             replaceExisting: false)
    #expect(count == 0)
    #expect(try await store.allTasks().isEmpty)
  }

  @Test("覆盖模式会清空原表")
  func importReplace() async throws {
    let store = freshStore()
    _ = try await store.create(title: "旧任务", deadlineMillis: 1_000)
    let count = try await store.importRecords([LocalTaskRecord(id: "local_new", title: "新任务", deadlineMillis: 2_000)],
                                             replaceExisting: true)
    #expect(count == 1)
    #expect(try await store.allTasks().map(\.title) == ["新任务"])
  }

  @Test("坏文件不崩溃，返回空表且之后仍能写入")
  func corruptFile() async throws {
    try Data("{ 这不是 JSON".utf8).write(to: fileURL)
    let store = freshStore()
    #expect(try await store.allTasks().isEmpty)

    let id = try await store.create(title: "恢复后新建", deadlineMillis: 0)
    #expect(!id.isEmpty)
    #expect(try await store.allTasks().count == 1)
  }

  @Test("清空全部")
  func clearAll() async throws {
    let store = freshStore()
    _ = try await store.create(title: "一", deadlineMillis: 0)
    _ = try await store.create(title: "二", deadlineMillis: 0)
    try await store.clearAll()
    #expect(try await store.allTasks().isEmpty)
  }

  @Test("变更监听会推送最新快照")
  func listener() async throws {
    let store = freshStore()
    let counter = Counter()
    _ = await store.addListener { tasks in counter.bump(tasks.count) }
    _ = try await store.create(title: "触发监听", deadlineMillis: 0)

    var waited = 0
    while counter.snapshot.1 < 2 && waited < 40 {
      try await Task.sleep(nanoseconds: 50_000_000)
      waited += 1
    }
    #expect(counter.snapshot.1 >= 2, "注册时推一次、写入后推一次")
    #expect(counter.snapshot.0 == 1)
  }
}

private final class Counter: @unchecked Sendable {
  private let lock = NSLock()
  private var lastCount = 0
  private var pushes = 0

  func bump(_ count: Int) {
    lock.lock(); defer { lock.unlock() }
    lastCount = count
    pushes += 1
  }

  var snapshot: (Int, Int) {
    lock.lock(); defer { lock.unlock() }
    return (lastCount, pushes)
  }
}
