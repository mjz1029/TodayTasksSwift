import SwiftUI
import UserNotifications
import TodayTasksCore
import TodayTasksUI
import TodayTasksViewModel

/// 本地提醒调度（iOS 与 macOS 共用）。
/// 与 Android 版的差别：每次同步先清空本 App 待发送通知再重排，
/// 删掉的任务不会留下幽灵提醒（Android 那边删任务不 cancel，到点仍会弹）。
public enum ReminderScheduler {

  public static func requestAuthorization() async {
    let center = UNUserNotificationCenter.current()
    _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
  }

  public static func sync(store: LocalTasksStore, enabled: Bool = true) async {
    let center = UNUserNotificationCenter.current()
    center.removeAllPendingNotificationRequests()
    guard enabled else { return }

    let tasks = (try? await store.allTasks()) ?? []
    let now = TaskItem.nowMillis()

    // 只有确实要排提醒时才请求权限：避免冷启动就弹系统授权框（Android 版也是操作时请求）
    let schedulable = tasks.contains { !$0.isCompleted && $0.deadlineMillis > 0
      && ($0.deadlineMillis - $0.remindMinutesBefore * 60_000) > now }
    let isDemo = ProcessInfo.processInfo.environment["TODAYTASKS_DEMO"] == "1"
    if schedulable && !isDemo {
      let settings = await center.notificationSettings()
      if settings.authorizationStatus == .notDetermined {
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        center.removeAllPendingNotificationRequests()
      }
    }

    for task in tasks {
      guard !task.isCompleted, task.deadlineMillis > 0 else { continue }
      let triggerMillis = task.deadlineMillis - task.remindMinutesBefore * 60_000
      guard triggerMillis > now else { continue }

      let content = UNMutableNotificationContent()
      content.title = "工作即将截止"
      content.body = task.title
      content.sound = .default
      content.userInfo = ["taskId": task.id]

      let interval = TimeInterval(triggerMillis - now) / 1000
      let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(interval, 1), repeats: false)
      let request = UNNotificationRequest(identifier: "task-\(task.id)", content: content, trigger: trigger)
      try? await center.add(request)
    }
  }
}
