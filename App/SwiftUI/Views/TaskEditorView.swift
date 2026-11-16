import SwiftUI
import TodayTasksCore

/// 任务编辑器。字段与 Android TaskEditorContent 一致：标题 / 备注 / 截止时间 / 优先级 / 分类 / 提前提醒。
struct TaskEditorView: View {
  private let existing: TaskItem?
  private let onSave: (TaskItem) -> Void
  private let onDelete: ((TaskItem) -> Void)?
  private let onCancel: () -> Void

  @Environment(\.todayPalette) private var palette

  @State private var title: String
  @State private var notes: String
  @State private var deadline: Date
  @State private var hasDeadline: Bool
  @State private var priority: TaskPriority
  @State private var category: String
  @State private var remindMinutes: Int64

  static let categories = ["工作", "会议", "沟通", "开发", "个人"]
  static let reminderOptions: [Int64] = [0, 5, 15, 30, 60]

  init(
    task: TaskItem?,
    initialDraft: ParsedTaskDraft? = nil,
    onSave: @escaping (TaskItem) -> Void,
    onDelete: ((TaskItem) -> Void)? = nil,
    onCancel: @escaping () -> Void
  ) {
    self.existing = task
    self.onSave = onSave
    self.onDelete = onDelete
    self.onCancel = onCancel

    let baseMillis = task?.deadlineMillis ?? initialDraft?.deadlineMillis ?? 0
    _title = State(initialValue: task?.title ?? initialDraft?.title ?? "")
    _notes = State(initialValue: task?.notes ?? initialDraft?.notes ?? "")
    _hasDeadline = State(initialValue: baseMillis > 0 || initialDraft != nil || task == nil)
    let resolvedMillis = baseMillis > 0 ? baseMillis : DeadlineFormatter.todayAt(hour: 18, minute: 0)
    _deadline = State(initialValue: Date(timeIntervalSince1970: Double(resolvedMillis) / 1000))
    _priority = State(initialValue: task?.priority ?? initialDraft?.priority ?? .medium)
    _category = State(initialValue: task?.category ?? initialDraft?.category ?? "工作")
    _remindMinutes = State(initialValue: task?.remindMinutesBefore ?? initialDraft?.remindMinutesBefore ?? 15)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Text(existing == nil ? "新建工作" : "编辑工作")
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(palette.onBackground)
        Spacer()
        Button(action: onCancel) {
          Image(systemName: "xmark").font(.system(size: 12, weight: .semibold))
            .foregroundStyle(palette.mutedText)
        }
        .buttonStyle(.plain)
      }

      field("工作标题") {
        TextField("例如：提交 Q4 进度报告", text: $title)
          .textFieldStyle(.plain)
          .font(.system(size: 13))
      }

      field("备注（可选）") {
        TextField("记录关键要点、链接或交付细节", text: $notes, axis: .vertical)
          .textFieldStyle(.plain)
          .font(.system(size: 12))
          .lineLimit(2...4)
      }

      field("截止时间") {
        HStack(spacing: 8) {
          Toggle("", isOn: $hasDeadline)
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
          if hasDeadline {
            DatePicker("", selection: $deadline, displayedComponents: [.date, .hourAndMinute])
              .labelsHidden()
              .datePickerStyle(.compact)
          } else {
            Text("未设时限").font(.system(size: 12)).foregroundStyle(palette.mutedText)
          }
          Spacer(minLength: 0)
        }
        HStack(spacing: 6) {
          quickChip("今天 18:00") {
            hasDeadline = true
            deadline = date(from: DeadlineFormatter.todayAt(hour: 18, minute: 0))
          }
          quickChip("明早 09:00") {
            hasDeadline = true
            deadline = date(from: DeadlineFormatter.tomorrowAt(hour: 9, minute: 0))
          }
          quickChip("一小时后") {
            hasDeadline = true
            deadline = Date().addingTimeInterval(3600)
          }
        }
      }

      field("紧急程度") {
        Picker("", selection: $priority) {
          ForEach(TaskPriority.allCases, id: \.self) { item in
            Text(item.labelZh).tag(item)
          }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
      }

      HStack(spacing: 12) {
        field("分类") {
          Picker("", selection: $category) {
            ForEach(Self.categories, id: \.self) { Text($0).tag($0) }
          }
          .labelsHidden()
          .pickerStyle(.menu)
        }
        field("提前提醒") {
          Picker("", selection: $remindMinutes) {
            ForEach(Self.reminderOptions, id: \.self) { minutes in
              Text(minutes == 0 ? "不提醒" : "\(minutes) 分钟前").tag(minutes)
            }
          }
          .labelsHidden()
          .pickerStyle(.menu)
        }
      }

      Divider().overlay(palette.outlineVariant)

      HStack {
        if let existing, let onDelete {
          Button(role: .destructive) {
            onDelete(existing)
          } label: {
            Text("删除").font(.system(size: 12, weight: .medium))
              .foregroundStyle(palette.error)
          }
          .buttonStyle(.plain)
        }
        Spacer()
        Button(action: onCancel) {
          Text("取消").font(.system(size: 12))
            .foregroundStyle(palette.mutedText)
            .padding(.horizontal, 14).padding(.vertical, 7)
        }
        .buttonStyle(.plain)

        Button(action: save) {
          Text("保存")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(palette.onPrimary)
            .padding(.horizontal, 18).padding(.vertical, 7)
            .background(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? palette.outlineVariant : palette.primary)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
    .padding(20)
    .frame(minWidth: 380, idealWidth: 420)
    .background(palette.background)
  }

  private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(palette.mutedText)
      content()
    }
  }

  private func quickChip(_ text: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(text)
        .font(.system(size: 11))
        .foregroundStyle(palette.secondary)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(palette.secondaryContainer)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
    .buttonStyle(.plain)
  }

  private func date(from millis: Int64) -> Date {
    Date(timeIntervalSince1970: Double(millis) / 1000)
  }

  private func save() {
    let deadlineMillis: Int64 = hasDeadline
      ? Int64((deadline.timeIntervalSince1970 * 1000).rounded())
      : 0
    let now = TaskItem.nowMillis()
    let task = TaskItem(
      id: existing?.id ?? "",
      title: title,
      notes: notes,
      deadlineMillis: deadlineMillis,
      isCompleted: existing?.isCompleted ?? false,
      completedAtMillis: existing?.completedAtMillis ?? 0,
      priority: priority,
      category: category,
      remindMinutesBefore: remindMinutes,
      createdAtMillis: existing?.createdAtMillis ?? now,
      updatedAtMillis: now
    )
    onSave(task)
  }
}
