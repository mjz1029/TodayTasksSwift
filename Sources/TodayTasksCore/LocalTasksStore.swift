import Foundation

/// 本地任务库。对应 Android 版 LocalTasksStore：整表 JSON 存盘、原子写、
/// 指纹去重的导入、字段清洗规则（标题 120 / 备注 500 / 分类 20 / 提醒 0…1440）。
///
/// 用 actor 保证并发写串行化——Android 那边靠 DataStore 的 edit 事务，
/// 这里靠 actor 隔离 + 原子替换文件，效果一致且不会写出半截文件。
public actor LocalTasksStore {

  public struct NewTaskInput: Sendable {
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
  }

  private let fileURL: URL
  private let json: JSONDecoder
  private let encoder: JSONEncoder
  private var listeners: [UUID: @Sendable ([TaskItem]) -> Void] = [:]

  public init(fileURL: URL) {
    self.fileURL = fileURL
    self.json = JSONDecoder()
    let enc = JSONEncoder()
    enc.outputFormatting = [.withoutEscapingSlashes]
    self.encoder = enc
  }

  /// 默认落盘位置：Application Support/TodayTasks/tasks.json（macOS 与 iOS 各自沙盒内）。
  public static func defaultFileURL(folder: String = "TodayTasks") -> URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                        in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    return base.appendingPathComponent(folder, isDirectory: true)
      .appendingPathComponent("tasks.json")
  }

  // MARK: - 读取

  public func allRecords() throws -> [LocalTaskRecord] {
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
    let data = try Data(contentsOf: fileURL)
    if data.isEmpty { return [] }
    // 与 Kotlin 的 runCatching{}.getOrDefault(emptyList()) 对齐：坏文件不炸，返回空表。
    return (try? json.decode([LocalTaskRecord].self, from: data)) ?? []
  }

  /// 已按「未完成优先 → 截止时间升序 → 紧急优先」排好序的任务列表。
  public func allTasks() throws -> [TaskItem] {
    Self.sorted(try allRecords().map { $0.toTaskItem() })
  }

  public static func sorted(_ tasks: [TaskItem]) -> [TaskItem] {
    tasks.sorted { lhs, rhs in
      if lhs.isCompleted != rhs.isCompleted { return !lhs.isCompleted }
      if lhs.deadlineMillis != rhs.deadlineMillis { return lhs.deadlineMillis < rhs.deadlineMillis }
      let lhsHigh = lhs.priority == .high
      let rhsHigh = rhs.priority == .high
      if lhsHigh != rhsHigh { return lhsHigh }
      return lhs.createdAtMillis < rhs.createdAtMillis
    }
  }

  // MARK: - 写入

  @discardableResult
  public func create(
    title: String,
    notes: String = "",
    deadlineMillis: Int64,
    priority: TaskPriority = .medium,
    category: String = "工作",
    remindMinutesBefore: Int64 = 15
  ) throws -> String {
    let ids = try createMany([NewTaskInput(
      title: title,
      notes: notes,
      deadlineMillis: deadlineMillis,
      priority: priority,
      category: category,
      remindMinutesBefore: remindMinutesBefore
    )])
    return ids.first ?? ""
  }

  @discardableResult
  public func createMany(_ inputs: [NewTaskInput]) throws -> [String] {
    guard !inputs.isEmpty else { return [] }
    let now = TaskItem.nowMillis()
    var created: [LocalTaskRecord] = []
    for input in inputs {
      let cleanTitle = Self.cleanTitle(input.title)
      guard !cleanTitle.isEmpty else { continue }
      created.append(LocalTaskRecord(
        id: Self.newID(),
        title: cleanTitle,
        notes: Self.cleanNotes(input.notes),
        deadlineMillis: input.deadlineMillis,
        isCompleted: false,
        completedAtMillis: 0,
        priority: input.priority,
        category: Self.cleanCategory(input.category),
        remindMinutesBefore: Self.clampReminder(input.remindMinutesBefore),
        createdAtMillis: now,
        updatedAtMillis: now
      ))
    }
    guard !created.isEmpty else { return [] }
    var current = try allRecords()
    current.append(contentsOf: created)
    try persist(current)
    notifyListeners()
    return created.map { $0.id }
  }

  public func update(_ task: TaskItem) throws {
    let now = TaskItem.nowMillis()
    var current = try allRecords()
    guard let idx = current.firstIndex(where: { $0.id == task.id }) else { return }
    current[idx] = LocalTaskRecord(
      id: current[idx].id,
      title: Self.cleanTitle(task.title),
      notes: Self.cleanNotes(task.notes),
      deadlineMillis: task.deadlineMillis,
      isCompleted: task.isCompleted,
      completedAtMillis: task.completedAtMillis,
      priority: task.priority,
      category: Self.cleanCategory(task.category),
      remindMinutesBefore: Self.clampReminder(task.remindMinutesBefore),
      createdAtMillis: current[idx].createdAtMillis,
      updatedAtMillis: now
    )
    try persist(current)
    notifyListeners()
  }

  public func toggleCompletion(taskId: String, isCompleted: Bool) throws {
    let now = TaskItem.nowMillis()
    var current = try allRecords()
    guard let idx = current.firstIndex(where: { $0.id == taskId }) else { return }
    current[idx].isCompleted = isCompleted
    current[idx].completedAtMillis = isCompleted ? now : 0
    current[idx].updatedAtMillis = now
    try persist(current)
    notifyListeners()
  }

  public func delete(taskId: String) throws {
    var current = try allRecords()
    current.removeAll { $0.id == taskId }
    try persist(current)
    notifyListeners()
  }

  /// 换机转移/分享导入。返回真正写入的条数。
  /// 非覆盖模式下用「id|标题|截止时间」指纹去重，id 冲突或为空则重新生成。
  @discardableResult
  public func importRecords(_ incoming: [LocalTaskRecord], replaceExisting: Bool) throws -> Int {
    if incoming.isEmpty && !replaceExisting { return 0 }
    var base = replaceExisting ? [] : try allRecords()
    var existingIds = Set(base.map { $0.id })
    var fingerprints = Set(base.map { Self.fingerprint($0) })
    var imported = 0

    for raw in incoming {
      let cleanTitle = Self.cleanTitle(raw.title)
      guard !cleanTitle.isEmpty else { continue }
      let fp = "\(raw.id)|\(cleanTitle)|\(raw.deadlineMillis)"
      if !replaceExisting && fingerprints.contains(fp) { continue }
      let safeId = (raw.id.isEmpty || existingIds.contains(raw.id)) ? Self.newID() : raw.id
      var normalized = raw
      normalized.id = safeId
      normalized.title = cleanTitle
      normalized.notes = Self.cleanNotes(raw.notes)
      normalized.category = Self.cleanCategory(raw.category)
      normalized.remindMinutesBefore = Self.clampReminder(raw.remindMinutesBefore)
      base.append(normalized)
      existingIds.insert(safeId)
      fingerprints.insert(fp)
      imported += 1
    }
    try persist(base)
    notifyListeners()
    return imported
  }

  public func clearAll() throws {
    try persist([])
    notifyListeners()
  }

  // MARK: - 变更订阅

  /// 注册变更回调，返回取消句柄。
  public func addListener(_ handler: @escaping @Sendable ([TaskItem]) -> Void) -> UUID {
    let token = UUID()
    listeners[token] = handler
    if let tasks = try? allTasks() {
      handler(tasks)
    }
    return token
  }

  public func removeListener(_ token: UUID) {
    listeners.removeValue(forKey: token)
  }

  private func notifyListeners() {
    guard !listeners.isEmpty, let tasks = try? allTasks() else { return }
    for handler in listeners.values { handler(tasks) }
  }

  // MARK: - 落盘与清洗

  private func persist(_ records: [LocalTaskRecord]) throws {
    let data = try encoder.encode(records)
    let dir = fileURL.deletingLastPathComponent()
    if !FileManager.default.fileExists(atPath: dir.path) {
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    // .atomic = 先写临时文件再 rename，避免中途崩溃留下半截 JSON
    try data.write(to: fileURL, options: [.atomic])
  }

  static func newID() -> String {
    let raw = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    return "local_" + raw.prefix(16)
  }

  static func cleanTitle(_ s: String) -> String {
    String(s.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
  }

  static func cleanNotes(_ s: String) -> String {
    String(s.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
  }

  static func cleanCategory(_ s: String) -> String {
    let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return "工作" }
    return String(trimmed.prefix(20))
  }

  static func clampReminder(_ v: Int64) -> Int64 {
    min(max(v, 0), 1440)
  }

  static func fingerprint(_ r: LocalTaskRecord) -> String {
    "\(r.id)|\(r.title)|\(r.deadlineMillis)"
  }
}
