import SwiftUI
import TodayTasksCore

/// 今日焦点头部：进度环 + 计数 + 最近截止任务。对应 Android ui/components/TodayFocusHeader.kt。
struct TodayFocusHeaderView: View {
  let unfinishedCount: Int
  let completedCount: Int
  let overdueCount: Int
  let nextUrgentTask: TaskItem?
  let nowMillis: Int64
  let compact: Bool

  @Environment(\.todayPalette) private var palette

  private var progress: Double {
    let total = max(unfinishedCount + completedCount, 1)
    if unfinishedCount == 0 && completedCount == 0 { return 1 }
    return min(max(Double(completedCount) / Double(total), 0), 1)
  }

  private var ringSize: CGFloat { compact ? 60 : 72 }

  private var headline: String {
    if unfinishedCount == 0 && completedCount == 0 { return "今天工作暂未安排" }
    if unfinishedCount == 0 { return "今天的工作全部完成！" }
    return "今天还有 \(unfinishedCount) 项工作未完成"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Theme.spacing) {
      HStack(spacing: 16) {
        ZStack {
          Circle()
            .stroke(palette.surfaceHigh, style: StrokeStyle(lineWidth: 7, lineCap: .round))
          Circle()
            .trim(from: 0, to: progress)
            .stroke(overdueCount > 0 ? palette.tertiary : palette.primary,
                    style: StrokeStyle(lineWidth: 7, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .animation(.spring(response: 0.45, dampingFraction: 0.78), value: progress)
          VStack(spacing: 0) {
            Text("\(unfinishedCount)")
              .font(.monoNumber(compact ? 20 : 23))
              .foregroundStyle(overdueCount > 0 ? palette.error : palette.primary)
            Text("待办")
              .font(.system(size: 10))
              .foregroundStyle(palette.mutedText)
          }
        }
        .frame(width: ringSize, height: ringSize)

        VStack(alignment: .leading, spacing: 5) {
          Text(headline)
            .font(.system(size: compact ? 15 : 17, weight: .semibold))
            .foregroundStyle(palette.onBackground)
            .lineLimit(2)

          HStack(spacing: 8) {
            TagView(text: "已完成 \(completedCount) 项",
                    background: palette.primaryContainer,
                    foreground: palette.onPrimaryContainer)
            if overdueCount > 0 {
              TagView(text: "逾期 \(overdueCount) 项",
                      background: palette.errorContainer,
                      foreground: palette.onErrorContainer)
            }
          }
        }
        Spacer(minLength: 0)
      }

      if let next = nextUrgentTask {
        Divider().overlay(palette.outlineVariant)
        HStack(spacing: 8) {
          Text("最近截止")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(palette.mutedText)
          Text(next.title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(palette.onBackground)
            .lineLimit(1)
          Spacer(minLength: 4)
          Text(DeadlineFormatter.formatDeadlineFull(next.deadlineMillis, nowMillis: nowMillis))
            .font(.monoNumber(11, weight: .medium))
            .foregroundStyle(next.isOverdue(nowMillis: nowMillis) ? palette.error : palette.secondary)
        }
      }
    }
    .padding(.horizontal, 18)
    .padding(.vertical, compact ? 14 : 18)
    .background(palette.surfaceLowest)
    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous)
        .stroke(palette.outlineVariant, lineWidth: 0.8)
    )
  }
}

struct TagView: View {
  let text: String
  let background: Color
  let foreground: Color

  var body: some View {
    Text(text)
      .font(.system(size: 11, weight: .medium))
      .foregroundStyle(foreground)
      .padding(.horizontal, 8)
      .padding(.vertical, 3)
      .background(background)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}
