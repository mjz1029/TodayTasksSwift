import Foundation
import TodayTasksCore

/// 命令行验证专用：`TODAYTASKS_DEMO=1` 且数据文件为空时，通过 App 自己的 LocalTasksStore API
/// 写入几条真实结构的任务，方便截图核对界面。正式运行时不会触发（未设环境变量即空操作）。
public enum DemoSeeder {

  public static func seedIfRequested(store: LocalTasksStore) async {
    guard ProcessInfo.processInfo.environment["TODAYTASKS_DEMO"] == "1" else { return }
    let existing = (try? await store.allTasks()) ?? []
    guard existing.isEmpty else { return }

    let now = TaskItem.nowMillis()
    let today1800 = DeadlineFormatter.todayAt(hour: 18, minute: 0, baseMillis: now)
    let today2030 = DeadlineFormatter.todayAt(hour: 20, minute: 30, baseMillis: now)
    let yesterday1000 = today1800 - 32 * 3600 * 1000

    _ = try? await store.createMany([
      .init(title: "整理 11 月经营分析汇总，报送州公司",
            notes: "带上同比还原口径那一页，抄送市场部",
            deadlineMillis: today1800, priority: .high, category: "工作", remindMinutesBefore: 30),
      .init(title: "和财务确认计费收入转换率口径",
            notes: "口径以财务下发文件为准",
            deadlineMillis: today2030, priority: .medium, category: "沟通", remindMinutesBefore: 15),
      .init(title: "把上周绩效对标表补齐到县市维度",
            deadlineMillis: yesterday1000, priority: .high, category: "工作", remindMinutesBefore: 15),
      .init(title: "整理明日晨会材料",
            deadlineMillis: DeadlineFormatter.tomorrowAt(hour: 9, minute: 0, baseMillis: now),
            priority: .low, category: "会议", remindMinutesBefore: 60),
    ])
  }
}
