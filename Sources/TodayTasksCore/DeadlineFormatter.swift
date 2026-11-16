import Foundation

/// 时间文案，逐条对齐 Android 版 DeadlineFormatter（同一套中文措辞）。
public enum DeadlineFormatter {

  private static func formatter(_ format: String) -> DateFormatter {
    let f = DateFormatter()
    f.locale = Locale(identifier: "zh_CN")
    f.timeZone = .current
    f.dateFormat = format
    return f
  }

  private static let timeFormat = formatter("HH:mm")
  private static let dateTimeFormat = formatter("MM月dd日 HH:mm")
  private static let shortDateFormat = formatter("MM/dd HH:mm")

  private static func date(_ millis: Int64) -> Date {
    Date(timeIntervalSince1970: Double(millis) / 1000)
  }

  public static func formatDeadlineClock(_ deadlineMillis: Int64) -> String {
    guard deadlineMillis > 0 else { return "未设时限" }
    return timeFormat.string(from: date(deadlineMillis))
  }

  public static func formatDeadlineFull(
    _ deadlineMillis: Int64,
    nowMillis: Int64 = TaskItem.nowMillis()
  ) -> String {
    guard deadlineMillis > 0 else { return "未设截止时间" }
    let calendar = Calendar.current
    let target = date(deadlineMillis)
    let now = date(nowMillis)
    if calendar.isDate(target, inSameDayAs: now) {
      return "今天 " + timeFormat.string(from: target)
    }
    if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
       calendar.isDate(target, inSameDayAs: tomorrow) {
      return "明天 " + timeFormat.string(from: target)
    }
    return dateTimeFormat.string(from: target)
  }

  public static func formatShortDeadline(
    _ deadlineMillis: Int64,
    nowMillis: Int64 = TaskItem.nowMillis()
  ) -> String {
    guard deadlineMillis > 0 else { return "--:--" }
    let target = date(deadlineMillis)
    if Calendar.current.isDate(target, inSameDayAs: date(nowMillis)) {
      return timeFormat.string(from: target)
    }
    return shortDateFormat.string(from: target)
  }

  public static func formatRemainingLabel(
    _ deadlineMillis: Int64,
    isCompleted: Bool,
    nowMillis: Int64 = TaskItem.nowMillis()
  ) -> String {
    if isCompleted { return "已完成" }
    guard deadlineMillis > 0 else { return "未设时限" }
    let diff = deadlineMillis - nowMillis
    if diff < 0 {
      let overdueMinutes = (-diff) / 60_000
      if overdueMinutes < 60 { return "已逾期 \(max(overdueMinutes, 1)) 分钟" }
      if overdueMinutes < 1440 { return "已逾期 \(overdueMinutes / 60) 小时" }
      return "已逾期 \(overdueMinutes / 1440) 天"
    }
    let remainMinutes = diff / 60_000
    if remainMinutes < 1 { return "即将到期" }
    if remainMinutes < 60 { return "剩余 \(remainMinutes) 分钟" }
    if remainMinutes < 1440 {
      let h = remainMinutes / 60
      let m = remainMinutes % 60
      return m == 0 ? "剩余 \(h) 小时" : "剩余 \(h)小时\(m)分"
    }
    return "剩余 \(remainMinutes / 1440) 天"
  }

  public static func formatSyncTime(_ syncMillis: Int64) -> String {
    guard syncMillis > 0 else { return "等待同步" }
    return "同步于 " + timeFormat.string(from: date(syncMillis))
  }

  public static func todayAt(
    hour: Int,
    minute: Int,
    baseMillis: Int64 = TaskItem.nowMillis()
  ) -> Int64 {
    let calendar = Calendar.current
    var comps = calendar.dateComponents([.year, .month, .day], from: date(baseMillis))
    comps.hour = hour
    comps.minute = minute
    comps.second = 0
    let result = calendar.date(from: comps) ?? date(baseMillis)
    return Int64((result.timeIntervalSince1970 * 1000).rounded())
  }

  public static func tomorrowAt(
    hour: Int,
    minute: Int,
    baseMillis: Int64 = TaskItem.nowMillis()
  ) -> Int64 {
    let calendar = Calendar.current
    let base = date(baseMillis)
    let tomorrow = calendar.date(byAdding: .day, value: 1, to: base) ?? base
    return todayAt(hour: hour, minute: minute, baseMillis: Int64((tomorrow.timeIntervalSince1970 * 1000).rounded()))
  }
}
