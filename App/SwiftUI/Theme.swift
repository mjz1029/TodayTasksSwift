import SwiftUI

/// 配色逐条取自 Android 版 ui/theme/Color.kt（Warm Ivory & Deep Jade + Amber Urgency 调色板）。
public struct TodayTasksPalette {
  public let primary: Color
  public let onPrimary: Color
  public let primaryContainer: Color
  public let onPrimaryContainer: Color

  public let secondary: Color
  public let secondaryContainer: Color
  public let onSecondaryContainer: Color

  public let tertiary: Color
  public let tertiaryContainer: Color
  public let onTertiaryContainer: Color

  public let error: Color
  public let errorContainer: Color
  public let onErrorContainer: Color

  public let background: Color
  public let onBackground: Color
  public let surfaceLowest: Color
  public let surfaceLow: Color
  public let surface: Color
  public let surfaceHigh: Color
  public let outline: Color
  public let outlineVariant: Color
  public let mutedText: Color

  public static let light = TodayTasksPalette(
    primary: Color(hex: 0x0E6B62),
    onPrimary: .white,
    primaryContainer: Color(hex: 0xCBEFE9),
    onPrimaryContainer: Color(hex: 0x00201C),
    secondary: Color(hex: 0x3E635E),
    secondaryContainer: Color(hex: 0xD6E7E3),
    onSecondaryContainer: Color(hex: 0x0F2B27),
    tertiary: Color(hex: 0xB95B10),
    tertiaryContainer: Color(hex: 0xFFE0C2),
    onTertiaryContainer: Color(hex: 0x361500),
    error: Color(hex: 0xC63A2C),
    errorContainer: Color(hex: 0xFFDAD5),
    onErrorContainer: Color(hex: 0x410002),
    background: Color(hex: 0xFAF9F5),
    onBackground: Color(hex: 0x191C1B),
    surfaceLowest: Color(hex: 0xFFFFFF),
    surfaceLow: Color(hex: 0xF4F2EC),
    surface: Color(hex: 0xECEAE1),
    surfaceHigh: Color(hex: 0xE5E2D8),
    outline: Color(hex: 0x707976),
    outlineVariant: Color(hex: 0xC9D0CC),
    mutedText: Color(hex: 0x4A5350)
  )

  // 深色层：沿用青玉/琥珀色相，但明度阶梯整体上抬——卡片（surfaceLowest）比页面亮、
  // 内嵌面板（surfaceLow）介于两者之间。原实现里卡片比页面还暗（#0B0E0D / #101413，
  // 对比只有 1.05:1），整屏糊成一块黑，卡片只能靠描边分辨。
  public static let dark = TodayTasksPalette(
    primary: Color(hex: 0x7CD8CB),
    onPrimary: Color(hex: 0x003731),
    primaryContainer: Color(hex: 0x005048),
    onPrimaryContainer: Color(hex: 0xA7F3E7),
    secondary: Color(hex: 0xA7CBC5),
    secondaryContainer: Color(hex: 0x24443F),
    onSecondaryContainer: Color(hex: 0xCBEFE9),
    tertiary: Color(hex: 0xFFB874),
    tertiaryContainer: Color(hex: 0x763800),
    onTertiaryContainer: Color(hex: 0xFFDCC0),
    error: Color(hex: 0xFFB4AB),
    errorContainer: Color(hex: 0x7A1A14),
    onErrorContainer: Color(hex: 0xFFDAD6),
    background: Color(hex: 0x0E1211),
    onBackground: Color(hex: 0xE6EAE7),
    surfaceLowest: Color(hex: 0x212927),
    surfaceLow: Color(hex: 0x1A211F),
    surface: Color(hex: 0x161C1B),
    surfaceHigh: Color(hex: 0x2F3836),
    outline: Color(hex: 0x8C9794),
    outlineVariant: Color(hex: 0x39433F),
    mutedText: Color(hex: 0xB3C0BC)
  )

  public static func palette(for scheme: ColorScheme) -> TodayTasksPalette {
    scheme == .dark ? .dark : .light
  }
}

public enum Theme {
  public static let cornerLarge: CGFloat = 24
  public static let cornerMedium: CGFloat = 18
  public static let cornerSmall: CGFloat = 12
  public static let spacing: CGFloat = 12
  public static let sectionSpacing: CGFloat = 16
}

private struct PaletteKey: EnvironmentKey {
  static let defaultValue = TodayTasksPalette.light
}

public extension EnvironmentValues {
  var todayPalette: TodayTasksPalette {
    get { self[PaletteKey.self] }
    set { self[PaletteKey.self] = newValue }
  }
}

public extension View {
  func todayPalette(_ scheme: ColorScheme) -> some View {
    environment(\.todayPalette, TodayTasksPalette.palette(for: scheme))
      .preferredColorScheme(scheme)
  }
}

extension Color {
  init(hex: UInt32) {
    self.init(
      .sRGB,
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255,
      opacity: 1
    )
  }
}

/// 数字用等宽字形（Android 版用 JetBrains Mono；这里用系统等宽，避免打包字体资产）。
public extension Font {
  static func monoNumber(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
    .system(size: size, weight: weight, design: .monospaced)
  }
}
