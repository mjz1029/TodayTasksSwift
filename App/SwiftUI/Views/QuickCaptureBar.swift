import SwiftUI
import TodayTasksCore
import TodayTasksViewModel

/// 智能速记条：输入一句话 → 调模型 → 生成草稿。
/// 与 Android 版的差异：解析失败的提示固定显示在输入框下方（Android 只在三种布局里挂了错误区，
/// 上下分栏/左右双栏下失败是无反馈的），并且多条草稿永远走确认列表，不静默丢条目。
struct QuickCaptureBar: View {
  @Binding var text: String
  let state: ParseState
  let llmConfigured: Bool
  let onFill: () -> Void
  let onAcceptAll: () -> Void
  let onAcceptOne: (ParsedTaskDraft) -> Void
  let onDismiss: () -> Void
  let onOpenSettings: () -> Void

  @Environment(\.todayPalette) private var palette

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        Image(systemName: "sparkles")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(palette.primary)

        TextField("说一句就行，例如：今晚8点前完成合同审阅", text: $text)
          .textFieldStyle(.plain)
          .font(.system(size: 13))
          .onSubmit(onFill)

        if state.isLoading {
          ProgressView().controlSize(.small)
        } else {
          Button(action: onFill) {
            Text("填充")
              .font(.system(size: 12, weight: .semibold))
              .foregroundStyle(palette.onPrimary)
              .padding(.horizontal, 12)
              .padding(.vertical, 6)
              .background(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          ? palette.outlineVariant : palette.primary)
              .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
          }
          .buttonStyle(.plain)
          .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }

      if !llmConfigured {
        HStack(spacing: 6) {
          Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10))
          Text("还没配置模型接口，点这里去设置（DeepSeek / OpenAI / Qwen 均可）")
            .font(.system(size: 11))
          Spacer(minLength: 0)
        }
        .foregroundStyle(palette.tertiary)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpenSettings)
      }

      switch state {
      case .failed(let message):
        HStack(alignment: .top, spacing: 6) {
          Image(systemName: "xmark.octagon.fill").font(.system(size: 11))
          Text(message).font(.system(size: 11))
          Spacer(minLength: 0)
          Button("知道了", action: onDismiss)
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(palette.primary)
        }
        .foregroundStyle(palette.error)
        .padding(8)
        .background(palette.errorContainer.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

      case .drafts(let drafts) where drafts.count > 1:
        VStack(alignment: .leading, spacing: 6) {
          HStack {
            Text("识别到 \(drafts.count) 条，确认后创建")
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(palette.secondary)
            Spacer()
            Button("全部创建", action: onAcceptAll)
              .buttonStyle(.plain)
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(palette.primary)
            Button("取消", action: onDismiss)
              .buttonStyle(.plain)
              .font(.system(size: 11))
              .foregroundStyle(palette.mutedText)
          }
          ForEach(Array(drafts.enumerated()), id: \.offset) { index, draft in
            HStack(spacing: 8) {
              Text("\(index + 1)")
                .font(.monoNumber(10))
                .foregroundStyle(palette.mutedText)
              Text(draft.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.onBackground)
                .lineLimit(1)
              Text(DeadlineFormatter.formatShortDeadline(draft.deadlineMillis))
                .font(.monoNumber(10, weight: .medium))
                .foregroundStyle(palette.mutedText)
              Spacer(minLength: 4)
              Button("创建") { onAcceptOne(draft) }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.primary)
            }
            .padding(.vertical, 2)
          }
        }
        .padding(10)
        .background(palette.surfaceLow)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

      case .idle, .loading, .drafts:
        EmptyView()
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background(palette.surfaceLowest)
    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous)
        .stroke(palette.outlineVariant, lineWidth: 0.8)
    )
  }
}