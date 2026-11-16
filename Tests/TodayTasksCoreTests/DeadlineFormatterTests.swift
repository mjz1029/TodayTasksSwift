import Foundation
import Testing
@testable import TodayTasksCore

@Suite("中文时间文案")
struct DeadlineFormatterTests {

  private func millis(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Int64 {
    var comps = DateComponents()
    comps.year = y; comps.month = mo; comps.day = d
    comps.hour = h; comps.minute = mi; comps.second = 0
    return Int64((Calendar.current.date(from: comps)!.timeIntervalSince1970 * 1000).rounded())
  }

  @Test("空截止时间")
  func emptyDeadline() {
    #expect(DeadlineFormatter.formatDeadlineClock(0) == "未设时限")
    #expect(DeadlineFormatter.formatDeadlineFull(0) == "未设截止时间")
    #expect(DeadlineFormatter.formatShortDeadline(0) == "--:--")
    #expect(DeadlineFormatter.formatRemainingLabel(0, isCompleted: false) == "未设时限")
  }

  @Test("今天/明天/日期文案")
  func todayTomorrow() {
    let now = millis(2026, 11, 16, 9, 0)
    #expect(DeadlineFormatter.formatDeadlineFull(millis(2026, 11, 16, 20, 30), nowMillis: now) == "今天 20:30")
    #expect(DeadlineFormatter.formatDeadlineFull(millis(2026, 11, 17, 8, 5), nowMillis: now) == "明天 08:05")
    #expect(DeadlineFormatter.formatDeadlineFull(millis(2026, 11, 20, 15, 0), nowMillis: now) == "11月20日 15:00")
  }

  @Test("剩余与逾期措辞")
  func remainingLabels() {
    let now = millis(2026, 11, 16, 9, 0)
    #expect(DeadlineFormatter.formatRemainingLabel(millis(2026, 11, 16, 9, 0), isCompleted: false, nowMillis: now) == "即将到期")
    #expect(DeadlineFormatter.formatRemainingLabel(millis(2026, 11, 16, 9, 45), isCompleted: false, nowMillis: now) == "剩余 45 分钟")
    #expect(DeadlineFormatter.formatRemainingLabel(millis(2026, 11, 16, 11, 0), isCompleted: false, nowMillis: now) == "剩余 2 小时")
    #expect(DeadlineFormatter.formatRemainingLabel(millis(2026, 11, 16, 10, 30), isCompleted: false, nowMillis: now) == "剩余 1小时30分")
    #expect(DeadlineFormatter.formatRemainingLabel(millis(2026, 11, 18, 9, 0), isCompleted: false, nowMillis: now) == "剩余 2 天")
    #expect(DeadlineFormatter.formatRemainingLabel(millis(2026, 11, 16, 8, 59), isCompleted: false, nowMillis: now) == "已逾期 1 分钟")
    #expect(DeadlineFormatter.formatRemainingLabel(millis(2026, 11, 16, 8, 30), isCompleted: false, nowMillis: now) == "已逾期 30 分钟")
    #expect(DeadlineFormatter.formatRemainingLabel(millis(2026, 11, 16, 8, 0), isCompleted: false, nowMillis: now) == "已逾期 1 小时", "满 60 分钟归到小时档，与 Kotlin 版一致")
    #expect(DeadlineFormatter.formatRemainingLabel(millis(2026, 11, 15, 20, 0), isCompleted: false, nowMillis: now) == "已逾期 13 小时")
    #expect(DeadlineFormatter.formatRemainingLabel(millis(2026, 11, 14, 9, 0), isCompleted: false, nowMillis: now) == "已逾期 2 天")
    #expect(DeadlineFormatter.formatRemainingLabel(millis(2026, 11, 14, 9, 0), isCompleted: true, nowMillis: now) == "已完成")
  }

  @Test("今天/明天整点换算")
  func todayAtTomorrowAt() {
    let base = millis(2026, 11, 16, 9, 0)
    let today18 = DeadlineFormatter.todayAt(hour: 18, minute: 0, baseMillis: base)
    #expect(DeadlineFormatter.formatDeadlineFull(today18, nowMillis: base) == "今天 18:00")
    let tomorrow9 = DeadlineFormatter.tomorrowAt(hour: 9, minute: 0, baseMillis: base)
    #expect(DeadlineFormatter.formatDeadlineFull(tomorrow9, nowMillis: base) == "明天 09:00")
  }

  @Test("同步时间")
  func syncTime() {
    #expect(DeadlineFormatter.formatSyncTime(0) == "等待同步")
    #expect(DeadlineFormatter.formatSyncTime(millis(2026, 11, 16, 10, 7)) == "同步于 10:07")
  }
}
