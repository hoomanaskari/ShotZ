import CoreGraphics

/// Quick-access stack side (SPEC §4.1).
public enum StackSide: String, Codable, Sendable, CaseIterable { case left, right }

/// Which display the stack appears on (SPEC §4.1).
public enum StackDisplay: String, Codable, Sendable, CaseIterable { case whereCaptured, main }

/// Quick-access card size (SPEC §4.2). Cards are 16:10.
public enum CardSize: String, Codable, Sendable, CaseIterable {
    case small, medium, large

    public var width: CGFloat {
        switch self {
        case .small: 150
        case .medium: 200
        case .large: 250
        }
    }

    public var height: CGFloat { width * 10 / 16 }
}

/// Export scale for Retina captures (SPEC §7 Capture).
public enum RetinaScale: String, Codable, Sendable, CaseIterable { case native, downscaleTo1x }

/// History retention (SPEC §6).
public enum HistoryRetention: String, Codable, Sendable, CaseIterable {
    case day, week, month, forever

    /// Retention in seconds, nil for forever.
    public var interval: Double? {
        switch self {
        case .day: 86_400
        case .week: 7 * 86_400
        case .month: 30 * 86_400
        case .forever: nil
        }
    }
}
