import SwiftUI
import TodayTasksCore
import TodayTasksViewModel

/// 设置：模型接口 + 数据管理。对应 Android SettingsSheet + LlmSettingsSheet（精简为一屏）。
struct SettingsView: View {
  @ObservedObject var viewModel: TasksViewModel
  let onClose: () -> Void

  @Environment(\.todayPalette) private var palette

  @State private var provider: LlmProvider
  @State private var baseURL: String
  @State private var model: String
  @State private var apiKey: String
  @State private var showKey = false
  @State private var testResult: String?
  @State private var testing = false
  @State private var confirmClear = false

  init(viewModel: TasksViewModel, onClose: @escaping () -> Void) {
    self.viewModel = viewModel
    self.onClose = onClose
    let config = viewModel.llmConfig
    _provider = State(initialValue: config.provider)
    _baseURL = State(initialValue: config.baseURL)
    _model = State(initialValue: config.model)
    _apiKey = State(initialValue: config.apiKey)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Text("设置").font(.system(size: 16, weight: .semibold)).foregroundStyle(palette.onBackground)
        Spacer()
        Button(action: onClose) {
          Image(systemName: "xmark").font(.system(size: 12, weight: .semibold))
            .foregroundStyle(palette.mutedText)
        }
        .buttonStyle(.plain)
      }

      VStack(alignment: .leading, spacing: 10) {
        Text("模型接口").font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.primary)

        Picker("服务商", selection: $provider) {
          ForEach(LlmProvider.allCases, id: \.self) { item in
            Text(item.displayName).tag(item)
          }
        }
        .onChange(of: provider) { _, newValue in
          baseURL = newValue.defaultBaseURL
          model = newValue.defaultModel
        }

        TextField("接口地址", text: $baseURL, prompt: Text(provider.defaultBaseURL.isEmpty ? "https://api.example.com/v1" : provider.defaultBaseURL))
          .textFieldStyle(.roundedBorder)
          .font(.monoNumber(11, weight: .regular))

        TextField("模型名", text: $model, prompt: Text(provider.defaultModel))
          .textFieldStyle(.roundedBorder)
          .font(.monoNumber(11, weight: .regular))

        HStack(spacing: 6) {
          Group {
            if showKey {
              TextField("API Key", text: $apiKey)
            } else {
              SecureField("API Key", text: $apiKey)
            }
          }
          .textFieldStyle(.roundedBorder)
          .font(.monoNumber(11, weight: .regular))

          Button(showKey ? "隐藏" : "显示") { showKey.toggle() }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(palette.mutedText)
        }

        Text(provider.hint)
          .font(.system(size: 11))
          .foregroundStyle(palette.mutedText)

        HStack(spacing: 10) {
          Button {
            Task { await testConnection() }
          } label: {
            HStack(spacing: 6) {
              if testing { ProgressView().controlSize(.mini) }
              Text(testing ? "测试中…" : "测试连接")
                .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(palette.primary)
          }
          .buttonStyle(.plain)
          .disabled(testing)

          Spacer()

          Button {
            viewModel.saveLlmConfig(LlmConfig(provider: provider, baseURL: baseURL, model: model, apiKey: apiKey))
            onClose()
          } label: {
            Text("保存")
              .font(.system(size: 12, weight: .semibold))
              .foregroundStyle(palette.onPrimary)
              .padding(.horizontal, 16).padding(.vertical, 7)
              .background(palette.primary)
              .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
          }
          .buttonStyle(.plain)
        }

        if let testResult {
          Text(testResult)
            .font(.system(size: 11))
            .foregroundStyle(testResult.hasPrefix("连接成功") ? palette.primary : palette.error)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .padding(14)
      .background(palette.surfaceLowest)
      .clipShape(RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous)
        .stroke(palette.outlineVariant, lineWidth: 0.8))

      VStack(alignment: .leading, spacing: 10) {
        Text("数据").font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.primary)
        Text("纯单机本地模式：任务只存在这台设备上，不上传任何服务器。")
          .font(.system(size: 11))
          .foregroundStyle(palette.mutedText)

        HStack {
          Button(role: .destructive) {
            confirmClear = true
          } label: {
            Text("清空本机全部任务").font(.system(size: 12, weight: .medium)).foregroundStyle(palette.error)
          }
          .buttonStyle(.plain)
          Spacer()
          Text("当前 \(viewModel.tasks.count) 条")
            .font(.monoNumber(11, weight: .medium))
            .foregroundStyle(palette.mutedText)
        }
        .alert("确认清空？", isPresented: $confirmClear) {
          Button("取消", role: .cancel) {}
          Button("清空", role: .destructive) {
            Task { await viewModel.clearAllTasks() }
          }
        } message: {
          Text("会删除本机所有任务，无法恢复。")
        }
      }
      .padding(14)
      .background(palette.surfaceLowest)
      .clipShape(RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous)
        .stroke(palette.outlineVariant, lineWidth: 0.8))

      Spacer(minLength: 0)
      Text("今日待办 · SwiftUI 版 1.0（对应 Android 版 1.0）")
        .font(.system(size: 10))
        .foregroundStyle(palette.mutedText)
    }
    .padding(20)
    .frame(minWidth: 420, minHeight: 520)
    .background(palette.background)
  }

  private func testConnection() async {
    testing = true
    testResult = nil
    defer { testing = false }
    let config = LlmConfig(provider: provider, baseURL: baseURL, model: model, apiKey: apiKey)
    do {
      let message = try await NaturalLanguageTaskParser().testConnection(config: config)
      testResult = message
    } catch {
      testResult = "失败：\(error.localizedDescription)"
    }
  }
}