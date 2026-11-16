// swift-tools-version: 6.0
import PackageDescription

// 三个可测层 + 两个 App 层：
//   TodayTasksCore       纯逻辑（无 UI 依赖）
//   TodayTasksViewModel  界面状态（只依赖 Combine）
//   TodayTasksUI         SwiftUI 视图（需要 Xcode 工具链：SwiftUIMacros）
//   TodayTasksMacApp     macOS 可执行入口（无 Xcode 时用 CLT 编不了，所以默认只在有 Xcode 时构建）
// iOS target 等 Xcode 工程建好后复用 TodayTasksUI。
let package = Package(
  name: "TodayTasks",
  platforms: [
    .macOS(.v14),
    .iOS(.v17),
  ],
  products: [
    .library(name: "TodayTasksCore", targets: ["TodayTasksCore"]),
    .library(name: "TodayTasksViewModel", targets: ["TodayTasksViewModel"]),
    .library(name: "TodayTasksUI", targets: ["TodayTasksUI"]),
    .executable(name: "TodayTasksMac", targets: ["TodayTasksMacApp"]),
  ],
  targets: [
    .target(
      name: "TodayTasksCore",
      swiftSettings: [.swiftLanguageMode(.v5)]
    ),
    .target(
      name: "TodayTasksViewModel",
      dependencies: ["TodayTasksCore"],
      swiftSettings: [.swiftLanguageMode(.v5)]
    ),
    .target(
      name: "TodayTasksUI",
      dependencies: ["TodayTasksCore", "TodayTasksViewModel"],
      path: "App/SwiftUI",
      swiftSettings: [.swiftLanguageMode(.v5)]
    ),
    .executableTarget(
      name: "TodayTasksMacApp",
      dependencies: ["TodayTasksCore", "TodayTasksViewModel", "TodayTasksUI"],
      path: "App/MacApp",
      swiftSettings: [.swiftLanguageMode(.v5)]
    ),
    .testTarget(
      name: "TodayTasksCoreTests",
      dependencies: ["TodayTasksCore"],
      swiftSettings: [.swiftLanguageMode(.v5)]
    ),
    .testTarget(
      name: "TodayTasksViewModelTests",
      dependencies: ["TodayTasksViewModel"],
      swiftSettings: [.swiftLanguageMode(.v5)]
    ),
  ]
)
