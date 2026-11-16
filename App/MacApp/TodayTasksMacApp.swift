import AppKit
import Foundation
import SwiftUI
import TodayTasksCore
import TodayTasksViewModel
import TodayTasksUI
import UserNotifications

/// 进程级装配：数据文件位置、提醒调度、可选的演示数据（仅用于命令行截图验证）。
@MainActor
final class AppEnvironment {
  static let shared = AppEnvironment()

  let viewModel: TasksViewModel
  private(set) var store: LocalTasksStore

  init() {
    let env = ProcessInfo.processInfo.environment
    let dataURL: URL
    if let custom = env["TODAYTASKS_DATA_FILE"], !custom.isEmpty {
      dataURL = URL(fileURLWithPath: custom)
    } else {
      dataURL = LocalTasksStore.defaultFileURL()
    }
    self.store = LocalTasksStore(fileURL: dataURL)
    self.viewModel = TasksViewModel(store: store)

    ReminderBridge.shared.onSync = { [weak self] in
      await self?.syncReminders()
    }
  }

  /// 提醒调度统一走 TodayTasksUI 里的 ReminderScheduler（iOS 与 macOS 共用同一份实现）。
  func syncReminders() async {
    await ReminderScheduler.sync(store: store, enabled: AppSettings.shared.remindersEnabled)
  }

  /// 打开第一条任务的分享面板（仅快照用）。
  func openShareForSnapshot() {
    if let first = viewModel.tasks.first {
      viewModel.openShare(for: first)
      print("snapshot share token length=\(viewModel.shareToken.count)")
    }
  }

  /// 抓真实窗口像素。ImageRenderer 渲染不了 TextField / Picker 这类原生控件（会画成黄块），
  /// 判断深色模式观感必须用这条路径。
  func writeWindowShot(to path: String) {
    guard let window = NSApp.windows.first(where: { $0.isVisible }),
          let view = window.contentView else {
      print("window shot failed: no window")
      return
    }
    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
      print("window shot failed: no bitmap rep")
      return
    }
    view.cacheDisplay(in: view.bounds, to: rep)
    guard let png = rep.representation(using: .png, properties: [:]) else {
      print("window shot failed: no png")
      return
    }
    try? png.write(to: URL(fileURLWithPath: path))
    print("window shot written: \(path) \(Int(view.bounds.width))x\(Int(view.bounds.height))")
  }

  /// 把任意视图渲染成 PNG（命令行验证用）。
  func renderSnapshot(to path: String, size: CGSize = CGSize(width: 940, height: 820), content: AnyView? = nil) {
    print("snapshot tasks=\(viewModel.tasks.count) today=\(viewModel.unfinishedTodayTasks.count)")
    // ImageRenderer 不吃进程的 NSAppearance，必须显式注入 colorScheme，否则永远渲成浅色。
    let scheme: ColorScheme = ProcessInfo.processInfo.environment["TODAYTASKS_SNAPSHOT_SCHEME"] == "dark" ? .dark : .light
    let view = (content ?? AnyView(TasksWorkspaceView(viewModel: viewModel)))
      .environment(\.isSnapshotting, true)
      .environment(\.colorScheme, scheme)
      .environment(\.todayPalette, TodayTasksPalette.palette(for: scheme))
      .frame(width: size.width, height: size.height)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    guard let nsImage = renderer.nsImage,
          let tiff = nsImage.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
      print("snapshot failed")
      return
    }
    try? png.write(to: URL(fileURLWithPath: path))
    print("snapshot written: \(path)")
  }

  /// 演示数据统一走 DemoSeeder（环境变量门控，正式运行不触发）。
  func seedDemoDataIfRequested() async {
    await DemoSeeder.seedIfRequested(store: store)
    await viewModel.refresh()
  }

}

final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
    Task { @MainActor in
      await AppEnvironment.shared.seedDemoDataIfRequested()
      await AppEnvironment.shared.syncReminders()
      await AppEnvironment.shared.viewModel.start()

      // 命令行验证用：TODAYTASKS_APPEARANCE=dark|light 强制窗口外观。
      switch ProcessInfo.processInfo.environment["TODAYTASKS_APPEARANCE"] {
      case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
      case "light": NSApp.appearance = NSAppearance(named: .aqua)
      default: break
      }

      // 命令行验证用：TODAYTASKS_WINDOWSHOT=/tmp/x.png 抓真实窗口（含原生控件）后退出。
      if let shotPath = ProcessInfo.processInfo.environment["TODAYTASKS_WINDOWSHOT"], !shotPath.isEmpty {
        // TODAYTASKS_WINDOWSHOT_EDIT=1 时先选中第一条任务，让宽窗口右侧编辑栏渲染出来
        if ProcessInfo.processInfo.environment["TODAYTASKS_WINDOWSHOT_EDIT"] == "1" {
          AppEnvironment.shared.viewModel.editingTask = AppEnvironment.shared.viewModel.tasks.first
        }
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        AppEnvironment.shared.writeWindowShot(to: shotPath)
        NSApp.terminate(nil)
        return
      }

      // 命令行验证用：TODAYTASKS_SNAPSHOT=/tmp/x.png 时把主视图渲成图片后退出。
      // 走 ImageRenderer 而不是 screencapture，因为截图需要「屏幕录制」系统权限。
      if let path = ProcessInfo.processInfo.environment["TODAYTASKS_SNAPSHOT"], !path.isEmpty {
        // TODAYTASKS_SNAPSHOT_SHEET=share 时渲染分享面板而不是主界面
        let sheet = ProcessInfo.processInfo.environment["TODAYTASKS_SNAPSHOT_SHEET"]
        if sheet == "share" {
          AppEnvironment.shared.openShareForSnapshot()
          AppEnvironment.shared.renderSnapshot(to: path,
                                               content: AnyView(ShareTaskSheet(viewModel: AppEnvironment.shared.viewModel,
                                                                              onClose: {})))
        } else {
          AppEnvironment.shared.renderSnapshot(to: path)
        }
        NSApp.terminate(nil)
      }
    }
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct TodayTasksMacApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    WindowGroup("今日待办") {
      TasksWorkspaceView(viewModel: AppEnvironment.shared.viewModel)
        .frame(minWidth: 560, minHeight: 680)
    }
    .windowResizability(.contentMinSize)
    .commands {
      CommandGroup(replacing: .newItem) {}
    }
  }
}