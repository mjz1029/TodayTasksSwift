import SwiftUI
import TodayTasksCore
import TodayTasksViewModel

/// 主工作区：头部焦点 → 筛选 → 任务列表 → 速记条。
/// 自适应：宽窗口（≥900pt）用右侧固定编辑栏，窄窗口（iPhone / 小窗）用弹出 sheet。
public struct TasksWorkspaceView: View {
  @StateObject private var viewModel: TasksViewModel
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.isSnapshotting) private var isSnapshotting

  @State private var isCreating = false
  @State private var compactMode = false
  @State private var toastTask: Task<Void, Never>?

  /// 调色板由当前 colorScheme 直接推导。不能用 `@Environment(\.todayPalette)`：
  /// 本视图自己再往里 `.environment` 注入对 self 不生效，之前深色模式下页面底色
  /// 拿到的仍是默认浅色调色板，和深色卡片拼成一屏浅底黑板。
  private var palette: TodayTasksPalette {
    TodayTasksPalette.palette(for: colorScheme)
  }

  public init(viewModel: TasksViewModel) {
    _viewModel = StateObject(wrappedValue: viewModel)
  }

  public var body: some View {
    GeometryReader { proxy in
      let isWide = proxy.size.width >= 900
      HStack(spacing: 0) {
        mainColumn(isWide: isWide)
          .frame(width: isWide ? max(420, proxy.size.width * 0.52) : nil)

        if isWide {
          Divider().overlay(palette.outlineVariant)
          editorPane
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }
      .background(palette.background)
      .environment(\.todayPalette, palette)
    }
    .task {
      await viewModel.start()
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 30_000_000_000)
        viewModel.tick()
      }
    }
    .sheet(isPresented: $isCreating) {
      TaskEditorView(task: nil,
                     onSave: { task in
                       isCreating = false
                       Task {
                         await viewModel.create(
                           title: task.title,
                           notes: task.notes,
                           deadlineMillis: task.deadlineMillis,
                           priority: task.priority,
                           category: task.category,
                           remindMinutesBefore: task.remindMinutesBefore
                         )
                       }
                     },
                     onCancel: { isCreating = false })
        .todayPalette(colorScheme)
    }
    .sheet(isPresented: $viewModel.isShowingSettings) {
      SettingsView(viewModel: viewModel, onClose: { viewModel.isShowingSettings = false })
        .todayPalette(colorScheme)
    }
    .sheet(item: $viewModel.shareTask) { _ in
      ShareTaskSheet(viewModel: viewModel, onClose: { viewModel.shareTask = nil })
        .todayPalette(colorScheme)
    }
    .sheet(item: $sheetTask) { task in
      TaskEditorView(
        task: task,
        onSave: { updated in
          sheetTask = nil
          Task { await viewModel.update(updated) }
        },
        onDelete: { target in
          sheetTask = nil
          Task { await viewModel.delete(target) }
        },
        onCancel: { sheetTask = nil }
      )
      .todayPalette(colorScheme)
    }
  }

  // MARK: - 左/主栏


  @ViewBuilder
  private func contentColumn(isWide: Bool) -> some View {
    VStack(alignment: .leading, spacing: Theme.sectionSpacing) {

        TodayFocusHeaderView(
          unfinishedCount: viewModel.unfinishedTodayTasks.count,
          completedCount: viewModel.completedTodayCount,
          overdueCount: viewModel.overdueCount,
          nextUrgentTask: viewModel.nextUrgentTask,
          nowMillis: viewModel.nowMillis,
          compact: compactMode
        )
        .padding(.top, 16)

        filterChips

        if viewModel.filteredTasks.isEmpty {
          emptyState
        } else {
          LazyVStack(spacing: 10) {
            ForEach(viewModel.filteredTasks) { task in
              TaskCardView(
                task: task,
                nowMillis: viewModel.nowMillis,
                onToggle: { Task { await viewModel.toggle(task) } },
                onSelect: {
                  if isWide {
                    viewModel.editingTask = task
                  } else {
                    presentEditor(for: task)
                  }
                },
                onDelete: { Task { await viewModel.delete(task) } },
                onShare: { viewModel.openShare(for: task) }
                )
            }
          }
        }
      }

    .padding(.horizontal, 16)
    .padding(.bottom, 12)
  }

  private func mainColumn(isWide: Bool) -> some View {
    VStack(spacing: 0) {
      if isSnapshotting {
        contentColumn(isWide: isWide)
      } else {
        ScrollView { contentColumn(isWide: isWide) }
      }

      VStack(spacing: 10) {
        QuickCaptureBar(
          text: $viewModel.captureText,
          state: viewModel.parseState,
          llmConfigured: viewModel.llmConfig.isConfigured,
          onFill: { Task { await viewModel.fillFromAI() } },
          onAcceptAll: { Task { await viewModel.acceptAllDrafts() } },
          onAcceptOne: { draft in Task { await viewModel.acceptDraft(draft) } },
          onDismiss: { viewModel.dismissParseState() },
          onOpenSettings: { viewModel.isShowingSettings = true }
        )

        HStack(spacing: 10) {
          Button {
            isCreating = true
          } label: {
            HStack(spacing: 6) {
              Image(systemName: "plus").font(.system(size: 11, weight: .bold))
              Text("新建工作").font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(palette.onPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(palette.primary)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
          }
          .buttonStyle(.plain)

          Spacer()

          Button {
            viewModel.isShowingSettings = true
          } label: {
            Image(systemName: "gearshape").font(.system(size: 13))
              .foregroundStyle(palette.mutedText)
          }
          .buttonStyle(.plain)
          .help("设置")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
      }
      .background(palette.background)
    }
    .overlay(alignment: .bottom) {
      if let toast = viewModel.toast {
        toastView(toast)
          .padding(.bottom, 76)
          .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
    .animation(.easeInOut(duration: 0.2), value: viewModel.toast)
    .onChange(of: viewModel.toast) { _, newValue in
      guard let newValue else { return }
      toastTask?.cancel()
      toastTask = Task {
        try? await Task.sleep(nanoseconds: 2_600_000_000)
        if !Task.isCancelled, viewModel.toast == newValue { viewModel.toast = nil }
      }
    }
  }

  private var filterChips: some View {
    HStack(spacing: 8) {
      ForEach(TaskFilter.allCases) { item in
        let selected = viewModel.filter == item
        Button {
          viewModel.filter = item
        } label: {
          Text(item.label)
            .font(.system(size: 12, weight: selected ? .semibold : .regular))
            .foregroundStyle(selected ? palette.onPrimary : palette.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(selected ? palette.primary : palette.surfaceLow)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
      }
      Spacer(minLength: 0)
    }
  }

  private var emptyState: some View {
    VStack(spacing: 8) {
      Image(systemName: viewModel.filter == .todayCompleted ? "checkmark.seal" : "tray")
        .font(.system(size: 28, weight: .light))
        .foregroundStyle(palette.outline)
      Text(viewModel.emptyStateText)
        .font(.system(size: 12))
        .foregroundStyle(palette.mutedText)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 48)
    .background(palette.surfaceLow.opacity(0.55))
    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous))
  }

  // MARK: - 右侧编辑栏（宽窗口）

  @ViewBuilder
  private var editorPane: some View {
    if let task = viewModel.editingTask {
      TaskEditorView(
        task: task,
        onSave: { updated in
          viewModel.editingTask = nil
          Task { await viewModel.update(updated) }
        },
        onDelete: { target in
          viewModel.editingTask = nil
          Task { await viewModel.delete(target) }
        },
        onCancel: { viewModel.editingTask = nil }
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    } else {
      VStack(spacing: 8) {
        Image(systemName: "sidebar.right").font(.system(size: 26, weight: .light))
          .foregroundStyle(palette.outline)
        Text("选一条任务在这里编辑").font(.system(size: 12)).foregroundStyle(palette.mutedText)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(palette.surfaceLow.opacity(0.4))
    }
  }

  // MARK: - 窄窗口用 sheet 编辑

  @State private var sheetTask: TaskItem?
  @State private var showingSheet = false

  private func presentEditor(for task: TaskItem) {
    sheetTask = task
    showingSheet = true
  }

  private func toastView(_ text: String) -> some View {
    HStack(spacing: 10) {
      Text(text).font(.system(size: 12)).foregroundStyle(palette.onPrimary)
      if viewModel.canUndoDelete {
        Button("撤销") { Task { await viewModel.undoDelete() } }
          .buttonStyle(.plain)
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(palette.onPrimary)
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 9)
    .background(palette.onBackground.opacity(0.92))
    .clipShape(Capsule())
  }
}

private struct SnapshotKey: EnvironmentKey {
  static let defaultValue = false
}

public extension EnvironmentValues {
  /// true 时不用 ScrollView（ImageRenderer 渲染 ScrollView 会得到空白内容，仅用于命令行截图验证）
  var isSnapshotting: Bool {
    get { self[SnapshotKey.self] }
    set { self[SnapshotKey.self] = newValue }
  }
}
