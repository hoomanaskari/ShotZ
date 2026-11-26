// swift-tools-version: 6.0
import PackageDescription

// Module layout and dependency edges are defined in docs/ARCHITECTURE.md §1.
// ShotzCore  ←  ShotzUI, CaptureKit, QuickAccess, AnnotationKit, AppShell
// ShotzUI  ←  QuickAccess, AnnotationEditor, AppShell (design tokens and shared controls)
// AnnotationKit  ←  AnnotationEditor
// everything  ←  Shotz (executable)

let package = Package(
    name: "Shotz",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Shotz", targets: ["Shotz"]),
    ],
    targets: [
        .target(name: "ShotzCore"),
        .target(name: "ShotzUI", dependencies: ["ShotzCore"]),
        .target(name: "CaptureKit", dependencies: ["ShotzCore"]),
        .target(name: "QuickAccess", dependencies: ["ShotzCore", "ShotzUI"]),
        .target(name: "AnnotationKit", dependencies: ["ShotzCore"]),
        .target(name: "AnnotationEditor", dependencies: ["ShotzCore", "ShotzUI", "AnnotationKit"]),
        .target(name: "AppShell", dependencies: ["ShotzCore", "ShotzUI"]),
        .executableTarget(
            name: "Shotz",
            dependencies: [
                "ShotzCore", "ShotzUI", "CaptureKit", "QuickAccess",
                "AnnotationKit", "AnnotationEditor", "AppShell",
            ]
        ),

        .testTarget(name: "ShotzCoreTests", dependencies: ["ShotzCore"]),
        .testTarget(name: "ShotzUITests", dependencies: ["ShotzUI", "ShotzCore"], exclude: ["Goldens"]),
        .testTarget(name: "CaptureKitTests", dependencies: ["CaptureKit", "ShotzCore"]),
        .testTarget(name: "QuickAccessTests", dependencies: ["QuickAccess", "ShotzCore", "ShotzUI"]),
        .testTarget(name: "AnnotationKitTests", dependencies: ["AnnotationKit", "ShotzCore"], exclude: ["Goldens"]),
        .testTarget(name: "AnnotationEditorTests", dependencies: ["AnnotationEditor", "AnnotationKit", "ShotzCore", "ShotzUI"]),
        .testTarget(name: "AppShellTests", dependencies: ["AppShell", "ShotzCore", "ShotzUI"]),
    ],
    swiftLanguageModes: [.v6]
)
