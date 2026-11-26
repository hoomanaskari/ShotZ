import Foundation

/// ShotZ's version: the marketing version (`CFBundleShortVersionString`, "1.2.3")
/// and the build number (`CFBundleVersion`, a whole number that only goes up).
///
/// The single source is `Resources/Info.plist`; `scripts/bump-version.sh` changes
/// it and `bundle.sh` copies it into both apps. Sparkle compares build numbers.
public struct AppVersion: Equatable, Hashable, Sendable, CustomStringConvertible {
    public let marketing: String
    public let components: [Int]
    public let build: Int

    /// Nil unless `marketing` is two or three dot-separated numbers and `build` a positive whole number.
    public init?(marketing: String, build: String) {
        let parts = marketing.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count),
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }),
              let number = Int(build), number > 0, String(number) == build   // no "007", "+1" or spaces
        else { return nil }
        self.marketing = marketing
        self.components = parts.compactMap { Int($0) }
        self.build = number
    }

    /// The version of the running app, or nil outside a bundle (unit tests, `swift run`).
    public static func current(bundle: Bundle = .main) -> AppVersion? {
        from(infoDictionary: bundle.infoDictionary ?? [:])
    }

    public static func from(infoDictionary info: [String: Any]) -> AppVersion? {
        guard let marketing = info["CFBundleShortVersionString"] as? String,
              let build = info["CFBundleVersion"] as? String
        else { return nil }
        return AppVersion(marketing: marketing, build: build)
    }

    /// "1.2.3 (45)"
    public var description: String { "\(marketing) (\(build))" }

    /// What Settings shows: the version, or a note when there is no bundle.
    public static func displayString(_ version: AppVersion?) -> String {
        version.map { String(localized: "Version \($0.marketing) (build \($0.build))") }
            ?? String(localized: "Development build (not bundled)")
    }
}
