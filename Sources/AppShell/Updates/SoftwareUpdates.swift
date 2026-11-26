import AppKit
import Combine
import os
@preconcurrency import Sparkle
import ShotzCore

/// Whether this process may use the updater at all.
///
/// Only the production app, outside test runs, with a feed and a public EdDSA key,
/// ever creates Sparkle's updater. ShotZ Dev and test runs never do, so they never
/// contact the network.
public enum UpdateAvailability: Equatable, Sendable {
    case available
    case unavailable(UpdateUnavailableReason)

    public var isAvailable: Bool { self == .available }
}

public enum UpdateUnavailableReason: Equatable, Sendable {
    case developmentApp
    case testRun
    case noFeed
    case noPublicKey

    /// The note Settings shows.
    public var message: String {
        switch self {
        case .developmentApp: String(localized: "ShotZ Dev doesn't check for updates. Rebuild it from the checkout.")
        case .testRun: String(localized: "Updates are off in test runs.")
        case .noFeed: String(localized: "Updates are unavailable: this build has no update feed.")
        case .noPublicKey: String(localized: "Updates are unavailable: this build has no update signing key yet.")
        }
    }
}

public enum UpdatePolicy {
    public static let feedKey = "SUFeedURL"
    public static let publicKeyKey = "SUPublicEDKey"

    public static func decide(variant: AppVariant, testRun: Bool, info: [String: Any]) -> UpdateAvailability {
        guard variant == .production else { return .unavailable(.developmentApp) }
        guard !testRun else { return .unavailable(.testRun) }
        guard let feed = (info[feedKey] as? String)?.trimmingCharacters(in: .whitespaces),
              let url = URL(string: feed), url.scheme == "https"
        else { return .unavailable(.noFeed) }
        guard let key = (info[publicKeyKey] as? String)?.trimmingCharacters(in: .whitespaces), !key.isEmpty else {
            return .unavailable(.noPublicKey)
        }
        return .available
    }
}

/// What the app needs from an updater; Sparkle in the app, a fake in tests.
@MainActor
public protocol UpdaterBackend: AnyObject {
    var automaticallyChecks: Bool { get set }
    var lastCheckDate: Date? { get }
    func checkForUpdates()
}

/// ShotZ's software updates: "Check for Updates…", automatic checks and the
/// last-checked date, for the status menu and Settings.
@MainActor
public final class SoftwareUpdates: ObservableObject {
    public let availability: UpdateAvailability
    /// An update found by a background check and not yet shown (gentle reminder).
    @Published public private(set) var pendingVersion: String?
    @Published public private(set) var lastCheckDate: Date?
    @Published public private(set) var automaticallyChecks: Bool = false

    private var backend: UpdaterBackend?

    /// `makeBackend` runs only when `availability` is `.available`.
    public init(availability: UpdateAvailability, makeBackend: (SoftwareUpdates) -> UpdaterBackend) {
        self.availability = availability
        if availability.isAvailable {
            let backend = makeBackend(self)
            self.backend = backend
            automaticallyChecks = backend.automaticallyChecks
            lastCheckDate = backend.lastCheckDate
        }
    }

    /// The updates for this process: Sparkle in the production app, nothing otherwise.
    public static func forThisApp(bundle: Bundle = .main) -> SoftwareUpdates {
        let availability = UpdatePolicy.decide(variant: .current, testRun: AppVariant.isTestRun,
                                               info: bundle.infoDictionary ?? [:])
        ShotzLog.logger("Updates").notice("Software updates: \(String(describing: availability), privacy: .public)")
        return SoftwareUpdates(availability: availability) { SparkleUpdater(updates: $0) }
    }

    public var isAvailable: Bool { backend != nil }

    public func checkForUpdates() {
        guard let backend else { return }
        pendingVersion = nil
        backend.checkForUpdates()
    }

    public func setAutomaticallyChecks(_ on: Bool) {
        guard let backend else { return }
        backend.automaticallyChecks = on
        automaticallyChecks = backend.automaticallyChecks
    }

    /// Re-reads the updater's state (when Settings or the menu opens, and after a check).
    public func refresh() {
        guard let backend else { return }
        lastCheckDate = backend.lastCheckDate
        automaticallyChecks = backend.automaticallyChecks
    }

    // Called by the backend.
    func noteUpdateWaiting(_ version: String?) { pendingVersion = version }
    func noteSessionFinished() {
        pendingVersion = nil
        refresh()
    }

    /// "Last checked: …" for Settings.
    public var lastCheckedText: String {
        guard let lastCheckDate else { return String(localized: "Not checked yet.") }
        return String(localized: "Last checked \(lastCheckDate.formatted(.relative(presentation: .named))).")
    }
}

/// Sparkle 2's standard updater and user driver, set up for a menu-bar (LSUIElement) app:
/// ShotZ comes to the front whenever Sparkle shows a window, and an update found by a
/// background check waits as a gentle reminder ("Update Available…" in the menu)
/// instead of a window popping up over whatever the person is doing.
@MainActor
final class SparkleUpdater: NSObject, UpdaterBackend, @preconcurrency SPUStandardUserDriverDelegate, SPUUpdaterDelegate {
    private weak var updates: SoftwareUpdates?
    private var controller: SPUStandardUpdaterController!

    init(updates: SoftwareUpdates) {
        self.updates = updates
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)
    }

    var automaticallyChecks: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    var lastCheckDate: Date? { controller.updater.lastUpdateCheckDate }

    func checkForUpdates() {
        bringToFront()
        controller.checkForUpdates(nil)
    }

    private func bringToFront() {
        NSApp.activate()
    }

    // MARK: SPUStandardUserDriverDelegate

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        // Show it now only if it would appear in focus anyway (e.g. right after launch);
        // otherwise keep it as a reminder in the menu.
        immediateFocus
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        if handleShowingUpdate {
            bringToFront()
        } else {
            updates?.noteUpdateWaiting(update.displayVersionString)
        }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        updates?.noteUpdateWaiting(nil)
    }

    func standardUserDriverWillShowModalAlert() { bringToFront() }

    func standardUserDriverWillFinishUpdateSession() { updates?.noteSessionFinished() }

    // MARK: SPUUpdaterDelegate

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        updates?.refresh()
    }
}
