// swift-tools-version: 6.0
import PackageDescription

// Module layout and dependency edges are defined in docs/ARCHITECTURE.md §1.
// ShotzCore  ←  ShotzUI, CaptureKit, QuickAccess, AnnotationKit, AppShell
// ShotzUI  ←  QuickAccess, AnnotationEditor, AppShell (design tokens and shared controls)
// AnnotationKit  ←  AnnotationEditor
// everything  ←  Shotz (executable)
// Sparkle (software updates, production app only)  ←  AppShell

let package = Package(
    name: "Shotz",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Shotz", targets: ["Shotz"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.4"),
    ],
    targets: [
        .target(name: "ShotzCore"),
        .target(name: "ShotzUI", dependencies: ["ShotzCore"]),
        .target(name: "CaptureKit", dependencies: ["ShotzCore"]),
        .target(name: "QuickAccess", dependencies: ["ShotzCore", "ShotzUI"]),
        .target(name: "AnnotationKit", dependencies: ["ShotzCore"]),
        .target(name: "AnnotationEditor", dependencies: ["ShotzCore", "ShotzUI", "AnnotationKit"]),
        .target(name: "AppShell", dependencies: ["ShotzCore", "ShotzUI", .product(name: "Sparkle", package: "Sparkle")]),
        .executableTarget(
            name: "Shotz",
            dependencies: [
                "ShotzCore", "ShotzUI", "CaptureKit", "QuickAccess",
                "AnnotationKit", "AnnotationEditor", "AppShell",
            ]
        ),

        // Test-only helpers (in-memory preferences, self-removing temp folders); never shipped.
        .target(name: "ShotzTestSupport", dependencies: ["ShotzCore"], path: "Tests/ShotzTestSupport"),
        .testTarget(name: "ShotzCoreTests", dependencies: ["ShotzTestSupport", "ShotzCore"]),
        .testTarget(name: "ShotzUITests", dependencies: ["ShotzTestSupport", "ShotzUI", "ShotzCore"], exclude: ["Goldens"]),
        .testTarget(name: "CaptureKitTests", dependencies: ["ShotzTestSupport", "CaptureKit", "ShotzCore"]),
        .testTarget(name: "QuickAccessTests", dependencies: ["ShotzTestSupport", "QuickAccess", "ShotzCore", "ShotzUI"]),
        .testTarget(name: "AnnotationKitTests", dependencies: ["ShotzTestSupport", "AnnotationKit", "ShotzCore"], exclude: ["Goldens"]),
        .testTarget(name: "AnnotationEditorTests", dependencies: ["ShotzTestSupport", "AnnotationEditor", "AnnotationKit", "ShotzCore", "ShotzUI"]),
        .testTarget(name: "AppShellTests", dependencies: ["ShotzTestSupport", "AppShell", "ShotzCore", "ShotzUI"]),
    ],
    swiftLanguageModes: [.v6]
)
