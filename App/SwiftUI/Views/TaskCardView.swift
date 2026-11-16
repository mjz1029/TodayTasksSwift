import SwiftUI
import TodayTasksCore

/// 任务卡片。视觉沿用 Android TaskCard：左侧优先级色条 + 完成圆圈 + 分类/优先级标签 + 剩余时限。
struct TaskCardView: View {
  let task: TaskItem
  let nowMillis: Int64
  let onToggle: () -> Void
  let onSelect: () -> Void
  let onDelete: () -> Void
  var onShare: (() -> Void)? = nil

  @Environment(\.todayPalette) private var palette

  private var accent: Color {
    switch task.priority {
    case .high: return palette.error
    case .medium: return palette.tertiary
    case .low: return palette.outline
    }
  }

  private var overdue: Bool { task.isOverdue(nowMillis: nowMillis) }

  var body: some View {
    HStack(spacing: 0) {
      Rectangle().fill(accent).frame(width: 4)

      HStack(alignment: .top, spacing: 12) {
        Button(action: onToggle) {
          ZStack {
            Circle()
              .stroke(task.isCompleted ? palette.primary : palette.outlineVariant, lineWidth: 1.8)
              .frame(width: 22, height: 22)
            if task.isCompleted {
              Circle().fill(palette.primary).frame(width: 22, height: 22)
              Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(palette.onPrimary)
            }
          }
        }
        .buttonStyle(.plain)
        .help(task.isCompleted ? "恢复为待办" : "标记完成")
        .padding(.top, 2)

        VStack(alignment: .leading, spacing: 6) {
          Text(task.title)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(palette.onBackground)
            .strikethrough(task.isCompleted, color: palette.mutedText)
            .lineLimit(2)
            .multilineTextAlignment(.leading)

          if !task.notes.isEmpty {
            Text(task.notes)
              .font(.system(size: 12))
              .foregroundStyle(palette.mutedText)
              .lineLimit(2)
          }

          HStack(spacing: 6) {
            TagView(text: task.category, background: palette.surfaceHigh, foreground: palette.secondary)
            TagView(text: task.priority.labelZh,
                    background: task.priority == .high ? palette.errorContainer : palette.tertiaryContainer,
                    foreground: task.priority == .high ? palette.onErrorContainer : palette.onTertiaryContainer)
            Text(DeadlineFormatter.formatDeadlineFull(task.deadlineMillis, nowMillis: nowMillis))
              .font(.monoNumber(11, weight: .medium))
              .foregroundStyle(palette.mutedText)
            Text(DeadlineFormatter.formatRemainingLabel(task.deadlineMillis,
                                                        isCompleted: task.isCompleted,
                                                        nowMillis: nowMillis))
              .font(.system(size: 11, weight: .medium))
              .foregroundStyle(overdue ? palette.error : (task.isCompleted ? palette.mutedText : palette.primary))
          }
        }

        Spacer(minLength: 4)

        Menu {
          Button("编辑", action: onSelect)
          if let onShare {
            Button("分享 / 转移", action: onShare)
          }
          Button("删除", role: .destructive, action: onDelete)
        } label: {
          Image(systemName: "ellipsis")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(palette.mutedText)
            .frame(width: 24, height: 24)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 24)
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 12)
    }
    .background(palette.surfaceLowest)
    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous)
        .stroke(overdue ? palette.error.opacity(0.45) : palette.outlineVariant, lineWidth: 0.8)
    )
    .contentShape(Rectangle())
    .onTapGesture(perform: onSelect)
  }
}
