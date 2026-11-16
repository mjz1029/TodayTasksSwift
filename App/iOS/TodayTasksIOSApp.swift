import SwiftUI
import TodayTasksCore
import TodayTasksUI
import TodayTasksViewModel

/// iPhone / iPad 入口。数据落在沙盒 Application Support/todaytasks/tasks.json，
/// 与 macOS 版同一套 LocalTasksStore（换机转移才能互通）。
@main
struct TodayTasksIOSApp: App {
  @StateObject private var viewModel = TasksViewModel()

  var body: some Scene {
    WindowGroup {
      TasksWorkspaceView(viewModel: viewModel)
        .task {
          ReminderBridge.shared.onSync = {
            await ReminderScheduler.sync(
              store: viewModel.store,
              enabled: AppSettings.shared.remindersEnabled
            )
          }
          await DemoSeeder.seedIfRequested(store: viewModel.store)
          await viewModel.refresh()
          await ReminderScheduler.sync(store: viewModel.store, enabled: AppSettings.shared.remindersEnabled)
          // 截图/验收用：TODAYTASKS_AUTOOPEN=share 时直接打开第一条任务的分享面板
          if ProcessInfo.processInfo.environment["TODAYTASKS_AUTOOPEN"] == "share",
             let first = viewModel.tasks.first {
            viewModel.openShare(for: first)
          }
        }
    }
  }
}
