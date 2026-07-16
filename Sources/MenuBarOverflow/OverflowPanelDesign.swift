import SwiftUI

enum OverflowPanelMetrics {
    static let width: CGFloat = 300
    static let minimumHeight: CGFloat = 214
    static let maximumHeight: CGFloat = 356
    static let cornerRadius: CGFloat = 16
    static let gridColumnCount = 3
    static let gridCellHeight: CGFloat = 72
    static let gridSpacing: CGFloat = 6
    static let maximumVisibleGridRows = 3
    static let fixedChromeHeight: CGFloat = 115

    static var maximumVisibleItems: Int {
        gridColumnCount * maximumVisibleGridRows
    }

    static func gridRowCount(for itemCount: Int) -> Int {
        max(1, (itemCount + gridColumnCount - 1) / gridColumnCount)
    }

    static func contentHeight(for kind: OverflowPanelContentKind) -> CGFloat {
        switch kind {
        case .accessibility:
            return 136
        case .loading:
            return 86
        case .empty:
            return 84
        case .items(let count):
            let visibleRows = min(maximumVisibleGridRows, gridRowCount(for: count))
            let spacing = CGFloat(max(0, visibleRows - 1)) * gridSpacing
            return CGFloat(visibleRows) * gridCellHeight + spacing + 12
        }
    }

    static func preferredHeight(for kind: OverflowPanelContentKind) -> CGFloat {
        min(maximumHeight, max(minimumHeight, fixedChromeHeight + contentHeight(for: kind)))
    }
}

enum OverflowDesign {
    static let accent = Color(red: 0.04, green: 0.45, blue: 0.96)
    static let success = Color(red: 0.05, green: 0.70, blue: 0.34)
}

struct OverflowPanelTint: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            (colorScheme == .dark ? Color.black : Color.white)
                .opacity(colorScheme == .dark ? 0.48 : 0.44)
            LinearGradient(
                colors: [
                    OverflowDesign.accent.opacity(colorScheme == .dark ? 0.055 : 0.035),
                    Color.clear,
                    Color.black.opacity(colorScheme == .dark ? 0.08 : 0.035),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

struct OverflowGlassSection: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(.ultraThinMaterial)
            .opacity(0.72)
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white.opacity(colorScheme == .dark ? 0.035 : 0.16))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.16 : 0.34),
                                Color.white.opacity(0.04),
                                Color.black.opacity(colorScheme == .dark ? 0.18 : 0.07),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.7
                    )
            }
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.18 : 0.08), radius: 7, y: 3)
    }
}
