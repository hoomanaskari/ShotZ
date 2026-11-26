// swift-tools-version: 6.0
import PackageDescription

// Module layout and dependency edges are defined in docs/ARCHITECTURE.md §1.
// ShotzCore  ←  CaptureKit, QuickAccess, AnnotationKit, AppShell
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
        .target(name: "CaptureKit", dependencies: ["ShotzCore"]),
        .target(name: "QuickAccess", dependencies: ["ShotzCore"]),
        .target(name: "AnnotationKit", dependencies: ["ShotzCore"]),
        .target(name: "AnnotationEditor", dependencies: ["ShotzCore", "AnnotationKit"]),
        .target(name: "AppShell", dependencies: ["ShotzCore"]),
        .executableTarget(
            name: "Shotz",
            dependencies: [
                "ShotzCore", "CaptureKit", "QuickAccess",
                "AnnotationKit", "AnnotationEditor", "AppShell",
            ]
        ),

        .testTarget(name: "ShotzCoreTests", dependencies: ["ShotzCore"]),
        .testTarget(name: "CaptureKitTests", dependencies: ["CaptureKit", "ShotzCore"]),
        .testTarget(name: "QuickAccessTests", dependencies: ["QuickAccess", "ShotzCore"]),
        .testTarget(name: "AnnotationKitTests", dependencies: ["AnnotationKit", "ShotzCore"], exclude: ["Goldens"]),
        .testTarget(name: "AnnotationEditorTests", dependencies: ["AnnotationEditor", "AnnotationKit", "ShotzCore"]),
        .testTarget(name: "AppShellTests", dependencies: ["AppShell", "ShotzCore"]),
    ],
    swiftLanguageModes: [.v6]
)
