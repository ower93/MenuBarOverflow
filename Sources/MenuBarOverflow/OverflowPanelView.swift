import AppKit
import SwiftUI

struct OverflowPanelView: View {
    @ObservedObject var model: OverflowPanelModel
    let onHeightChange: (CGFloat) -> Void

    var body: some View {
        VStack(spacing: 8) {
            content
                .frame(height: OverflowPanelMetrics.contentHeight(for: model.contentKind))
                .background(OverflowGlassSection())
            OverflowFooterView(model: model)
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(width: OverflowPanelMetrics.width, height: model.preferredHeight)
        .background {
            OverflowPanelTint()
                .ignoresSafeArea()
        }
        .overlay {
            RoundedRectangle(cornerRadius: OverflowPanelMetrics.cornerRadius, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.38),
                            Color.white.opacity(0.07),
                            Color.black.opacity(0.14),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
                .padding(0.4)
                .allowsHitTesting(false)
        }
        .onAppear {
            onHeightChange(model.preferredHeight)
        }
        .onChange(of: model.preferredHeight) { _, newHeight in
            onHeightChange(newHeight)
        }
        .animation(.easeInOut(duration: 0.16), value: model.preferredHeight)
    }

    @ViewBuilder
    private var content: some View {
        switch model.contentKind {
        case .accessibility:
            OverflowPermissionView(model: model)
        case .loading:
            OverflowLoadingView()
        case .empty:
            OverflowEmptyView()
        case .items:
            OverflowItemsView(model: model)
        }
    }
}

private struct OverflowItemsView: View {
    @ObservedObject var model: OverflowPanelModel

    private let columns = Array(
        repeating: GridItem(.flexible(minimum: 0), spacing: OverflowPanelMetrics.gridSpacing),
        count: OverflowPanelMetrics.gridColumnCount
    )

    var body: some View {
        Group {
            if model.items.count > OverflowPanelMetrics.maximumVisibleItems {
                ScrollView(.vertical, showsIndicators: false) {
                    tiles
                }
            } else {
                tiles
            }
        }
    }

    private var tiles: some View {
        LazyVGrid(columns: columns, spacing: OverflowPanelMetrics.gridSpacing) {
            ForEach(model.items) { item in
                OverflowItemTile(item: item) { anchorFrame in
                    model.activate(item, anchorFrame: anchorFrame)
                }
            }
        }
        .padding(6)
    }
}

private struct OverflowItemTile: View {
    let item: OverflowPanelItem
    let action: (CGRect?) -> Void
    @State private var isHovering = false
    @State private var iconScreenFrame: CGRect?

    var body: some View {
        Button {
            action(iconScreenFrame)
        } label: {
            VStack(spacing: 4) {
                Group {
                    if let icon = item.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                    } else {
                        Image(systemName: "app.dashed")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 32, height: 32)
                .padding(3)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .background {
                    ScreenFrameReader { frame in
                        iconScreenFrame = frame
                    }
                }

                Text(item.title)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.74)
                    .frame(maxWidth: .infinity, minHeight: 26, maxHeight: 26, alignment: .top)
            }
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity)
            .frame(height: OverflowPanelMetrics.gridCellHeight)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(isHovering ? 0.075 : 0))
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(item.toolTip)
        .accessibilityLabel(item.title)
    }
}

private struct ScreenFrameReader: NSViewRepresentable {
    final class TrackingView: NSView {
        var onFrameChange: ((CGRect?) -> Void)?
        private var lastFrame: CGRect?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            publishFrame()
        }

        override func layout() {
            super.layout()
            publishFrame()
        }

        private func publishFrame() {
            guard let window else {
                if lastFrame != nil {
                    lastFrame = nil
                    DispatchQueue.main.async { [weak self] in
                        self?.onFrameChange?(nil)
                    }
                }
                return
            }

            let frame = window.convertToScreen(convert(bounds, to: nil))
            guard frame != lastFrame else { return }
            lastFrame = frame
            DispatchQueue.main.async { [weak self] in
                self?.onFrameChange?(frame)
            }
        }
    }

    let onFrameChange: (CGRect?) -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onFrameChange = onFrameChange
        return view
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        nsView.onFrameChange = onFrameChange
        nsView.needsLayout = true
    }
}

private struct OverflowPermissionView: View {
    @ObservedObject var model: OverflowPanelModel

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "lock.shield")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Color.orange)
            VStack(spacing: 4) {
                Text("Accessibility access is required")
                    .font(.system(size: 12.5, weight: .semibold))
                Text("Allow access to discover and open hidden menu bar items.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 230)
            }
            HStack(spacing: 8) {
                Button("Request Access", action: model.onRequestAccessibility ?? {})
                    .buttonStyle(.borderedProminent)
                    .tint(OverflowDesign.accent)
                Button("Open Settings", action: model.onOpenAccessibilitySettings ?? {})
                    .buttonStyle(.bordered)
            }
            .controlSize(.mini)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 12)
    }
}

private struct OverflowLoadingView: View {
    var body: some View {
        VStack(spacing: 7) {
            ProgressView()
                .controlSize(.small)
            Text("Finding hidden menu bar items")
                .font(.system(size: 11.5, weight: .semibold))
            Text("Checking running apps and menu bar visibility…")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct OverflowEmptyView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(OverflowDesign.success)
            Text("No hidden items found")
                .font(.system(size: 11.5, weight: .semibold))
            Text("All detected menu bar items currently fit on screen.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct OverflowFooterView: View {
    @ObservedObject var model: OverflowPanelModel

    private var openAtLoginBinding: Binding<Bool> {
        Binding(
            get: { model.loginState.isOn },
            set: { _ in model.onToggleOpenAtLogin?() }
        )
    }

    var body: some View {
        VStack(spacing: 5) {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text("Open at Login")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(model.loginState.canToggle ? Color.primary : Color.secondary)

                    Toggle("Open at Login", isOn: openAtLoginBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .disabled(!model.loginState.canToggle)
                        .help(model.loginState.helpText)

                    if model.loginState.needsSettings {
                        Button(action: model.onOpenLoginItemsSettings ?? {}) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.orange)
                                .frame(width: 22, height: 22)
                        }
                        .buttonStyle(.plain)
                        .help("Approve Open at Login in System Settings")
                    }

                    Spacer(minLength: 4)

                    Button(action: model.onQuit ?? {}) {
                        Image(systemName: "power")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .help("Quit Menu Bar Overflow")
                    .keyboardShortcut("q", modifiers: [.command])
                }
                .padding(.horizontal, 8)
                .frame(height: 38)

                Divider()
                    .opacity(0.24)
                    .padding(.horizontal, 8)

                HStack(spacing: 7) {
                    Circle()
                        .fill(model.isAccessibilityTrusted ? OverflowDesign.success : Color.orange)
                        .frame(width: 6, height: 6)
                    Text(model.subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Button(action: model.onRefresh ?? {}) {
                        ZStack {
                            Circle()
                                .fill(Color.primary.opacity(0.055))
                            if model.isScanning {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 26, height: 26)
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isScanning)
                    .help("Refresh hidden menu bar items")
                    .keyboardShortcut("r", modifiers: [.command])
                }
                .padding(.horizontal, 8)
                .frame(height: 34)
            }
            .background(OverflowGlassSection())

            Text("Menu Bar Overflow")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(Color.secondary.opacity(0.72))
                .lineLimit(1)
                .frame(height: 11)
        }
        .frame(height: 89)
    }
}
