import Foundation
import Testing
@testable import TodayTasksCore

@Suite("TaskItem 时间与归属判定")
struct TaskItemTests {

  private func millis(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Int64 {
    var comps = DateComponents()
    comps.year = y; comps.month = mo; comps.day = d
    comps.hour = h; comps.minute = mi; comps.second = 0
    return Int64((Calendar.current.date(from: comps)!.timeIntervalSince1970 * 1000).rounded())
  }

  @Test("一天边界覆盖整天")
  func dayBounds() {
    let now = millis(2026, 11, 16, 14, 30)
    let bounds = TaskItem.dayBounds(anchorMillis: now)
    #expect(bounds.start < now)
    #expect(bounds.end > now)
    let span = Double(bounds.end - bounds.start) / 1000
    #expect(abs(span - 86_400) < 2)
  }

  @Test("今天到期判定")
  func dueToday() {
    let now = millis(2026, 11, 16, 14, 30)
    #expect(TaskItem(title: "今天", deadlineMillis: millis(2026, 11, 16, 20, 0)).isDueToday(nowMillis: now))
    #expect(!TaskItem(title: "明天", deadlineMillis: millis(2026, 11, 17, 9, 0)).isDueToday(nowMillis: now))
    #expect(!TaskItem(title: "无期限", deadlineMillis: 0).isDueToday(nowMillis: now))
  }

  @Test("逾期判定，已完成不算逾期")
  func overdue() {
    let now = millis(2026, 11, 16, 14, 30)
    #expect(TaskItem(title: "逾期", deadlineMillis: millis(2026, 11, 16, 9, 0)).isOverdue(nowMillis: now))
    #expect(!TaskItem(title: "已完成", deadlineMillis: millis(2026, 11, 16, 9, 0), isCompleted: true)
      .isOverdue(nowMillis: now))
  }

  @Test("未完成任务：今天及以前到期都进今日清单")
  func todayListUncompleted() {
    let now = millis(2026, 11, 16, 14, 30)
    #expect(TaskItem(title: "昨天没做", deadlineMillis: millis(2026, 11, 15, 9, 0))
      .belongsToTodayActionList(nowMillis: now))
    #expect(TaskItem(title: "今天", deadlineMillis: millis(2026, 11, 16, 18, 0))
      .belongsToTodayActionList(nowMillis: now))
    #expect(!TaskItem(title: "明天", deadlineMillis: millis(2026, 11, 17, 9, 0))
      .belongsToTodayActionList(nowMillis: now))
  }

  @Test("已完成任务只看今天")
  func todayListCompleted() {
    let now = millis(2026, 11, 16, 14, 30)
    let doneToday = TaskItem(title: "今天做完", deadlineMillis: millis(2026, 11, 16, 10, 0),
                             isCompleted: true, completedAtMillis: millis(2026, 11, 16, 12, 0))
    let doneYesterday = TaskItem(title: "昨天做完", deadlineMillis: millis(2026, 11, 15, 10, 0),
                                 isCompleted: true, completedAtMillis: millis(2026, 11, 15, 12, 0))
    #expect(doneToday.belongsToTodayActionList(nowMillis: now))
    #expect(!doneYesterday.belongsToTodayActionList(nowMillis: now))
  }

  @Test("优先级 wire 值与 Kotlin 对齐，未知值回落常规")
  func priorityWire() {
    #expect(TaskPriority.fromWire("high") == .high)
    #expect(TaskPriority.fromWire("low") == .low)
    #expect(TaskPriority.fromWire("whatever") == .medium)
    #expect(TaskPriority.high.labelZh == "紧急")
    #expect(TaskPriority.medium.labelZh == "常规")
    #expect(TaskPriority.low.labelZh == "暂缓")
  }

  @Test("Android 端缺省字段的 JSON 能读入")
  func androidJsonCompat() throws {
    let json = #"[{"id":"local_abc","title":"给客户回电话","deadlineMillis":1794820000000}]"#
    let records = try JSONDecoder().decode([LocalTaskRecord].self, from: Data(json.utf8))
    #expect(records.count == 1)
    #expect(records[0].priority == .medium)
    #expect(records[0].category == "工作")
    #expect(records[0].remindMinutesBefore == 15)
  }
}
