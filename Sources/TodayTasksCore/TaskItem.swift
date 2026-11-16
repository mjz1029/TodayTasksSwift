import Foundation

/// 优先级。wire 值与 Android 版 TaskPriority 完全一致，便于跨端导入导出。
public enum TaskPriority: String, Codable, CaseIterable, Sendable {
  case high
  case medium
  case low

  public var labelZh: String {
    switch self {
    case .high: return "紧急"
    case .medium: return "常规"
    case .low: return "暂缓"
    }
  }

  /// 与 Kotlin 的 TaskPriority.fromWire 对齐：未知值一律回落为 medium。
  public static func fromWire(_ value: String) -> TaskPriority {
    TaskPriority(rawValue: value) ?? .medium
  }

  public init(from decoder: Decoder) throws {
    let raw = (try? decoder.singleValueContainer().decode(String.self)) ?? ""
    self = TaskPriority.fromWire(raw)
  }
}

/// 一条待办。字段名与 Android 版 TaskItem 一一对应，时间统一用「毫秒时间戳 Int64」。
public struct TaskItem: Identifiable, Equatable, Sendable {
  public var id: String
  public var title: String
  public var notes: String
  /// 0 表示未设置截止时间
  public var deadlineMillis: Int64
  public var isCompleted: Bool
  public var completedAtMillis: Int64
  public var priority: TaskPriority
  public var category: String
  /// 提前多少分钟提醒，0 表示不提醒
  public var remindMinutesBefore: Int64
  public var createdAtMillis: Int64
  public var updatedAtMillis: Int64

  public init(
    id: String = "",
    title: String = "",
    notes: String = "",
    deadlineMillis: Int64 = 0,
    isCompleted: Bool = false,
    completedAtMillis: Int64 = 0,
    priority: TaskPriority = .medium,
    category: String = "工作",
    remindMinutesBefore: Int64 = 15,
    createdAtMillis: Int64 = 0,
    updatedAtMillis: Int64 = 0
  ) {
    self.id = id
    self.title = title
    self.notes = notes
    self.deadlineMillis = deadlineMillis
    self.isCompleted = isCompleted
    self.completedAtMillis = completedAtMillis
    self.priority = priority
    self.category = category
    self.remindMinutesBefore = remindMinutesBefore
    self.createdAtMillis = createdAtMillis
    self.updatedAtMillis = updatedAtMillis
  }

  public func isOverdue(nowMillis: Int64 = TaskItem.nowMillis()) -> Bool {
    !isCompleted && deadlineMillis > 0 && deadlineMillis < nowMillis
  }

  public func isDueToday(nowMillis: Int64 = TaskItem.nowMillis()) -> Bool {
    guard deadlineMillis > 0 else { return false }
    let bounds = TaskItem.dayBounds(anchorMillis: nowMillis)
    return deadlineMillis >= bounds.start && deadlineMillis <= bounds.end
  }

  public func isCompletedToday(nowMillis: Int64 = TaskItem.nowMillis()) -> Bool {
    guard isCompleted, completedAtMillis > 0 else { return false }
    let bounds = TaskItem.dayBounds(anchorMillis: nowMillis)
    return completedAtMillis >= bounds.start && completedAtMillis <= bounds.end
  }

  /// 「今日行动清单」归属判定，与 Android 版 belongsToTodayActionList 一致：
  /// 未完成 → 截止时间在今天结束之前（含已逾期）；已完成 → 今天到期或今天完成。
  public func belongsToTodayActionList(nowMillis: Int64 = TaskItem.nowMillis()) -> Bool {
    let endOfDay = TaskItem.dayBounds(anchorMillis: nowMillis).end
    if !isCompleted {
      return deadlineMillis <= endOfDay
    }
    return isDueToday(nowMillis: nowMillis) || isCompletedToday(nowMillis: nowMillis)
  }

  public static func nowMillis() -> Int64 {
    Int64((Date().timeIntervalSince1970 * 1000).rounded())
  }

  /// 当天 00:00:00.000 与 23:59:59.999 的毫秒边界（本地时区）。
  public static func dayBounds(anchorMillis: Int64) -> (start: Int64, end: Int64) {
    let calendar = Calendar.current
    let date = Date(timeIntervalSince1970: Double(anchorMillis) / 1000)
    let start = calendar.startOfDay(for: date)
    let end = calendar.date(byAdding: .day, value: 1, to: start)!
      .addingTimeInterval(-0.001)
    return (Int64((start.timeIntervalSince1970 * 1000).rounded()),
            Int64((end.timeIntervalSince1970 * 1000).rounded()))
  }
}

/// 磁盘上的存储结构，字段与 Android 版 LocalTaskRecord 对齐。
/// 解码时对缺失字段一律给默认值，这样 Android 端导出的 JSON 能被直接读入。
public struct LocalTaskRecord: Codable, Equatable, Sendable {
  public var id: String
  public var title: String
  public var notes: String
  public var deadlineMillis: Int64
  public var isCompleted: Bool
  public var completedAtMillis: Int64
  public var priority: TaskPriority
  public var category: String
  public var remindMinutesBefore: Int64
  public var createdAtMillis: Int64
  public var updatedAtMillis: Int64

  public init(
    id: String,
    title: String,
    notes: String = "",
    deadlineMillis: Int64,
    isCompleted: Bool = false,
    completedAtMillis: Int64 = 0,
    priority: TaskPriority = .medium,
    category: String = "工作",
    remindMinutesBefore: Int64 = 15,
    createdAtMillis: Int64 = TaskItem.nowMillis(),
    updatedAtMillis: Int64 = TaskItem.nowMillis()
  ) {
    self.id = id
    self.title = title
    self.notes = notes
    self.deadlineMillis = deadlineMillis
    self.isCompleted = isCompleted
    self.completedAtMillis = completedAtMillis
    self.priority = priority
    self.category = category
    self.remindMinutesBefore = remindMinutesBefore
    self.createdAtMillis = createdAtMillis
    self.updatedAtMillis = updatedAtMillis
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
    title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
    notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
    deadlineMillis = try c.decodeIfPresent(Int64.self, forKey: .deadlineMillis) ?? 0
    isCompleted = try c.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
    completedAtMillis = try c.decodeIfPresent(Int64.self, forKey: .completedAtMillis) ?? 0
    priority = (try? c.decodeIfPresent(TaskPriority.self, forKey: .priority)) ?? .medium
    category = try c.decodeIfPresent(String.self, forKey: .category) ?? "工作"
    remindMinutesBefore = try c.decodeIfPresent(Int64.self, forKey: .remindMinutesBefore) ?? 15
    createdAtMillis = try c.decodeIfPresent(Int64.self, forKey: .createdAtMillis) ?? 0
    updatedAtMillis = try c.decodeIfPresent(Int64.self, forKey: .updatedAtMillis) ?? 0
  }

  public func toTaskItem() -> TaskItem {
    TaskItem(
      id: id,
      title: title,
      notes: notes,
      deadlineMillis: deadlineMillis,
      isCompleted: isCompleted,
      completedAtMillis: completedAtMillis,
      priority: priority,
      category: category,
      remindMinutesBefore: remindMinutesBefore,
      createdAtMillis: createdAtMillis,
      updatedAtMillis: updatedAtMillis
    )
  }

  public static func from(_ task: TaskItem) -> LocalTaskRecord {
    LocalTaskRecord(
      id: task.id,
      title: task.title,
      notes: task.notes,
      deadlineMillis: task.deadlineMillis,
      isCompleted: task.isCompleted,
      completedAtMillis: task.completedAtMillis,
      priority: task.priority,
      category: task.category,
      remindMinutesBefore: task.remindMinutesBefore,
      createdAtMillis: task.createdAtMillis,
      updatedAtMillis: task.updatedAtMillis
    )
  }
}
