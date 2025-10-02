import SwiftUI
import AppKit

struct ContentView: View {
    @AppStorage("noticeText") private var noticeText = ""
    @State private var isPinned = false
    @State private var isCollapsed = false
    @State private var window: NSWindow?
    @State private var expandedFrame: NSRect?
    @State private var hasConfiguredWindow = false

    var body: some View {
        ZStack {
            if isCollapsed {
                collapsedBubble
            } else {
                expandedBoard
            }
        }
        .padding(isCollapsed ? 0 : 24)
        .background {
            if isCollapsed {
                LiquidGlassBubbleBackground()
            } else {
                LiquidGlassPanelBackground(cornerRadius: 36)
            }
        }
        .clipShape(currentSurfaceShape)
        .contentShape(currentSurfaceShape)
        .frame(
            minWidth: isCollapsed ? 56 : 360,
            idealWidth: isCollapsed ? 72 : 440,
            maxWidth: isCollapsed ? 120 : 680,
            minHeight: isCollapsed ? 56 : 260,
            idealHeight: isCollapsed ? 72 : 500,
            maxHeight: .infinity
        )
        .overlay(WindowAccessor(window: $window).frame(width: 0, height: 0))
        .onChange(of: window) { _ in
            configureWindowIfNeeded()
            updateWindowLevel()
            applyCollapseState(isCollapsed, animated: false)
        }
        .onChange(of: isPinned) { _ in
            updateWindowLevel()
        }
        .onChange(of: isCollapsed) { collapsed in
            applyCollapseState(collapsed)
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: isCollapsed)
        .animation(.easeInOut(duration: 0.2), value: isPinned)
        .ignoresSafeArea()
    }

    private var expandedBoard: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerControls

            ZStack(alignment: .topLeading) {
                if noticeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("粘贴或输入公告…")
                        .foregroundStyle(.secondary)
                        .padding(.top, 10)
                        .padding(.horizontal, 14)
                }

                TextEditor(text: $noticeText)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.primary)
                    .padding(8)
                    .scrollContentBackground(.hidden)
                    .background {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(.ultraThinMaterial.opacity(0.65))
                            .overlay {
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(
                                        LinearGradient(colors: [.white.opacity(0.25), .white.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing),
                                        lineWidth: 1
                                    )
                                    .blendMode(.overlay)
                            }
                    }
                    .shadow(color: .black.opacity(0.08), radius: 18, y: 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 320, minHeight: 240)
    }

    private var headerControls: some View {
        HStack(spacing: 18) {
            HStack(spacing: 12) {
                CloseButton(action: closeWindow)

                ControlButton(systemName: "pin", isActive: isPinned, action: togglePin)
                    .help(isPinned ? "取消图钉" : "图钉置顶")
            }

            Spacer(minLength: 12)

            Text("公告栏")
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundStyle(.white.opacity(0.96))
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(GlassCapsule())

            Spacer(minLength: 12)

            ControlButton(systemName: "bubble.left.and.bubble.right", isActive: isCollapsed, action: toggleCollapse)
                .help("收起为气泡")
        }
    }

    private var collapsedBubble: some View {
        Button(action: toggleCollapse) {
            Image(systemName: "megaphone.fill")
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.white.opacity(0.95), Color.accentColor)
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
        .padding(6)
        .contentShape(Circle())
    }

    private func togglePin() {
        isPinned.toggle()
    }

    private func toggleCollapse() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.74)) {
            isCollapsed.toggle()
        }
    }

    private func closeWindow() {
        if let window {
            window.performClose(nil)
        } else {
            NSApp.terminate(nil)
        }
    }

    private func updateWindowLevel() {
        guard let window else { return }
        window.level = isPinned ? .floating : .normal
    }

    private func applyCollapseState(_ collapsed: Bool, animated: Bool = true) {
        guard let window else { return }

        let animationDuration = animated ? 0.24 : 0

        if collapsed {
            if expandedFrame == nil {
                expandedFrame = window.frame
            }

            let bubbleSize = NSSize(width: 56, height: 56)
            var targetOrigin = window.frame.origin
            targetOrigin.y += window.frame.size.height - bubbleSize.height

            window.minSize = bubbleSize

            NSAnimationContext.runAnimationGroup { context in
                context.duration = animationDuration
                window.animator().setFrame(NSRect(origin: targetOrigin, size: bubbleSize), display: true)
            }
        } else {
            let minimumExpandedSize = NSSize(width: 360, height: 280)
            window.minSize = minimumExpandedSize

            guard let expandedFrame else { return }

            NSAnimationContext.runAnimationGroup { context in
                context.duration = animationDuration
                window.animator().setFrame(expandedFrame, display: true)
            }

            self.expandedFrame = nil
        }
    }

    private func configureWindowIfNeeded() {
        guard let window, !hasConfiguredWindow else { return }
        hasConfiguredWindow = true

        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.collectionBehavior.insert(.fullScreenNone)
        window.styleMask = [.borderless, .resizable]
        window.invalidateShadow()
        window.setFrameAutosaveName("NoticeBoardWindow")
        window.minSize = NSSize(width: 360, height: 280)
    }

    private var currentSurfaceShape: AnyShape {
        if isCollapsed {
            return AnyShape(Circle())
        } else {
            return AnyShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
        }
    }
}

private struct ControlButton: View {
    let systemName: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .symbolVariant(isActive ? .fill : .none)
                .foregroundStyle(isActive ? Color.white.opacity(0.95) : Color.white.opacity(0.82))
                .frame(width: 36, height: 36)
                .background(GlassOrb(tint: isActive ? Color.accentColor : Color.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }
}

private struct CloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.94))
                .frame(width: 32, height: 32)
                .background(GlassOrb(tint: Color.red.opacity(0.65)))
        }
        .buttonStyle(.plain)
        .help("关闭公告栏")
    }
}

private struct GlassCapsule: View {
    var body: some View {
        Capsule(style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.24),
                        Color.white.opacity(0.05)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .background(.ultraThinMaterial.opacity(0.78), in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(LinearGradient(colors: [.white.opacity(0.7), .white.opacity(0.18)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.1)
                    .blendMode(.overlay)
            }
            .shadow(color: .white.opacity(0.25), radius: 10, y: -2)
            .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
    }
}

private struct GlassOrb: View {
    let tint: Color

    var body: some View {
        Circle()
            .fill(tint.opacity(0.5))
            .background(.ultraThinMaterial.opacity(0.82), in: Circle())
            .overlay {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.55),
                                Color.white.opacity(0.08)
                            ],
                            center: .topLeading,
                            startRadius: 4,
                            endRadius: 48
                        )
                    )
                    .blendMode(.screen)
                    .opacity(0.9)
            }
            .overlay {
                Circle()
                    .stroke(LinearGradient(colors: [.white.opacity(0.75), .white.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.1)
                    .blendMode(.overlay)
            }
            .shadow(color: tint.opacity(0.55), radius: 16, y: 8)
    }
}

private struct LiquidGlassPanelBackground: View {
    let cornerRadius: CGFloat

    init(cornerRadius: CGFloat = 36) {
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.white.opacity(0.04))
            .background(.ultraThinMaterial.opacity(0.92), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius + 10, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 12)
                    .blur(radius: 20)
                    .opacity(0.8)
                    .blendMode(.screen)
                    .padding(-18)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(LinearGradient(colors: [.white.opacity(0.8), .white.opacity(0.18)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.4)
                    .blendMode(.overlay)
            }
            .overlay(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.6),
                                Color.white.opacity(0.05)
                            ],
                            center: .topLeading,
                            startRadius: 4,
                            endRadius: 180
                        )
                    )
                    .blendMode(.screen)
                    .opacity(0.75)
                    .mask(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    )
            }
            .overlay(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.cyan.opacity(0.24),
                                Color.purple.opacity(0.12),
                                Color.clear
                            ],
                            startPoint: .bottomTrailing,
                            endPoint: .topLeading
                        )
                    )
                    .blendMode(.plusLighter)
                    .opacity(0.6)
                    .mask(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    )
            }
            .shadow(color: .black.opacity(0.28), radius: 36, y: 30)
            .shadow(color: .cyan.opacity(0.22), radius: 28, y: 12)
    }
}

private struct LiquidGlassBubbleBackground: View {
    var body: some View {
        Circle()
            .fill(Color.white.opacity(0.08))
            .background(.ultraThinMaterial.opacity(0.95), in: Circle())
            .overlay(alignment: .topLeading) {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.85),
                                Color.white.opacity(0.1)
                            ],
                            center: .topLeading,
                            startRadius: 6,
                            endRadius: 80
                        )
                    )
                    .blur(radius: 2)
                    .blendMode(.screen)
                    .opacity(0.8)
            }
            .overlay {
                Circle()
                    .stroke(LinearGradient(colors: [.white.opacity(0.9), .white.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.6)
                    .blendMode(.overlay)
            }
            .overlay(alignment: .bottomTrailing) {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.cyan.opacity(0.35),
                                Color.purple.opacity(0.15),
                                Color.clear
                            ],
                            startPoint: .bottomTrailing,
                            endPoint: .topLeading
                        )
                    )
                    .blendMode(.plusLighter)
                    .opacity(0.55)
            }
            .shadow(color: .black.opacity(0.3), radius: 32, y: 24)
            .shadow(color: .cyan.opacity(0.25), radius: 26, y: 8)
    }
}

private struct AnyShape: Shape {
    private let pathClosure: (CGRect) -> Path

    init<S: Shape>(_ shape: S) {
        pathClosure = { rect in
            shape.path(in: rect)
        }
    }

    func path(in rect: CGRect) -> Path {
        pathClosure(rect)
    }
}

private struct WindowAccessor: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            window = view.window
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            window = nsView.window
        }
    }
}

#Preview {
    ContentView()
        .frame(width: 420, height: 360)
}
