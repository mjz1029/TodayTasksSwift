import SwiftUI
import TodayTasksCore
import TodayTasksViewModel

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// 单条任务分享：二维码 + TT1 口令 + 粘贴导入。
/// 对应 Android 版 SingleTaskShareSheet 的主干（相机扫描那半在 iOS 真机上才有意义，模拟器无法验证）。
public struct ShareTaskSheet: View {
  @ObservedObject var viewModel: TasksViewModel
  let onClose: () -> Void

  @Environment(\.todayPalette) private var palette
  @State private var copied = false

  public init(viewModel: TasksViewModel, onClose: @escaping () -> Void) {
    self.viewModel = viewModel
    self.onClose = onClose
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Text("分享任务").font(.system(size: 16, weight: .semibold)).foregroundStyle(palette.onBackground)
        Spacer()
        Button(action: onClose) {
          Image(systemName: "xmark").font(.system(size: 12, weight: .semibold))
            .foregroundStyle(palette.mutedText)
        }
        .buttonStyle(.plain)
      }

      if let task = viewModel.shareTask {
        Text(task.title)
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(palette.onBackground)
          .lineLimit(2)

        if let image = qrImage {
          HStack {
            Spacer()
            Image(decorative: image, scale: 1)
              .interpolation(.none)
              .resizable()
              .frame(width: 180, height: 180)
              .padding(10)
              .background(.white)
              .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            Spacer()
          }
        } else {
          Text("二维码生成失败，请复制下面的口令")
            .font(.system(size: 11)).foregroundStyle(palette.error)
        }

        VStack(alignment: .leading, spacing: 6) {
          Text("分享口令").font(.system(size: 11, weight: .medium)).foregroundStyle(palette.mutedText)
          Text(viewModel.shareToken)
            .font(.monoNumber(10, weight: .regular))
            .foregroundStyle(palette.secondary)
            .lineLimit(3)
            .textSelection(.enabled)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.surfaceLow)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

          HStack(spacing: 10) {
            Button {
              copyToPasteboard(viewModel.shareToken)
              copied = true
              Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                copied = false
              }
            } label: {
              Text(copied ? "已复制" : "复制口令")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.primary)
            }
            .buttonStyle(.plain)
            Spacer()
            Text("对方粘贴口令即可导入，扫码同样有效")
              .font(.system(size: 10))
              .foregroundStyle(palette.mutedText)
          }
        }
      }

      Divider().overlay(palette.outlineVariant)

      VStack(alignment: .leading, spacing: 6) {
        Text("导入别人的任务").font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.primary)
        HStack(spacing: 8) {
          TextField("粘贴 TT1: 开头的口令，或二维码里的文本", text: $viewModel.importCodeText)
            .textFieldStyle(.plain)
            .font(.monoNumber(11, weight: .regular))
            .lineLimit(1)
            .padding(.horizontal, 8).padding(.vertical, 7)
            .background(palette.surfaceLow)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
          Button {
            Task { await viewModel.importFromCode() }
          } label: {
            Text("导入")
              .font(.system(size: 12, weight: .semibold))
              .foregroundStyle(palette.onPrimary)
              .padding(.horizontal, 12).padding(.vertical, 6)
              .background(palette.primary)
              .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
          }
          .buttonStyle(.plain)
        }
      }

      Spacer(minLength: 0)
    }
    .padding(20)
    .frame(minWidth: 380, minHeight: 460)
    .background(palette.background)
  }

  private var qrImage: CGImage? {
    QrCode.generate(viewModel.shareToken, scale: 8)
  }

  private func copyToPasteboard(_ text: String) {
    #if os(iOS)
    UIPasteboard.general.string = text
    #elseif os(macOS)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
    #endif
  }
}
