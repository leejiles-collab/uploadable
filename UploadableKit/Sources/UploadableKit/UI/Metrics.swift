import SwiftUI

/// The shared measurements. Same workshop as Smaller, different tool.
public enum Metrics {
    public static let screenPadding: CGFloat = 22
    public static let stackSpacing: CGFloat = 20
    public static let cardSpacing: CGFloat = 10
    public static let cardPadding: CGFloat = 14
    public static let cornerRadius: CGFloat = 14
    public static let contentWidth: CGFloat = 540
}

public extension Font {
    /// The payoff. On this app the payoff is a specification being met, so the
    /// biggest thing on the Done screen is the size the form asked for.
    static var hugeNumber: Font { .system(size: 46, weight: .bold, design: .rounded) }
    static var bigNumber: Font { .system(size: 30, weight: .semibold, design: .rounded) }
}
