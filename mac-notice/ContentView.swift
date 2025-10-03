import SwiftUI
import AppKit

struct ContentView: View {
    @AppStorage("noticeText") private var noticeText = ""
    @State private var isPinned = false
    @State private var isCollapsed = false
    @State private var window: NSWindow?
    @State private var expandedFrame: NSRect?
    @State private var hasConfiguredWindow = false
    @State private var collapsedDragOffset: NSPoint?
    @State private var collapsedExpansionOffset: NSPoint?

    private let expandedMinimumSize = CGSize(width: 200, height: 200)

    var body: some View {
        ZStack {
            if isCollapsed {
                collapsedBubble
            } else {
                expandedBoard
            }
        }
        .padding(isCollapsed ? 0 : 18)
        .background {
            surfaceBackground
        }
        .clipShape(currentSurfaceShape)
        .contentShape(currentSurfaceShape)
        .frame(
            minWidth: isCollapsed ? 56 : expandedMinimumSize.width,
            idealWidth: isCollapsed ? 72 : 440,
            maxWidth: isCollapsed ? 120 : 680,
            minHeight: isCollapsed ? 56 : expandedMinimumSize.height,
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
        .environment(\.controlActiveState, .active)
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
                    .background(editorBackground)
                    .shadow(color: .black.opacity(0.08), radius: 18, y: 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 160, minHeight: 160)
    }

    private var headerControls: some View {
        HStack(spacing: 12) {
            CloseButton(action: closeWindow)

            ControlButton(systemName: "pin", isActive: isPinned, action: togglePin)
                .help(isPinned ? "取消图钉" : "图钉置顶")

            Spacer(minLength: 12)

            ControlButton(systemName: "bubble.left.and.bubble.right", isActive: isCollapsed, action: toggleCollapse)
                .help("收起为气泡")
        }
        .padding(.top, 2)
    }

    private var collapsedBubble: some View {
        Group {
            if #available(macOS 26.0, *) {
                LiquidGlassCollapsedBubble()
            } else {
                LegacyCollapsedBubble()
            }
        }
        .contentShape(Circle())
        .onTapGesture(perform: toggleCollapse)
        .highPriorityGesture(collapsedDragGesture, including: .gesture)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("展开公告板")
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
            window.close()
        }
        NSApp.terminate(nil)
    }

    private func updateWindowLevel() {
        guard let window else { return }
        window.level = isPinned ? .floating : .normal

        if isPinned {
            window.collectionBehavior.insert([.canJoinAllSpaces, .fullScreenAuxiliary, .stationary])
        } else {
            window.collectionBehavior.remove(.canJoinAllSpaces)
            window.collectionBehavior.remove(.fullScreenAuxiliary)
            window.collectionBehavior.remove(.stationary)
        }
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

            if let expandedFrame {
                collapsedExpansionOffset = NSPoint(
                    x: expandedFrame.origin.x - targetOrigin.x,
                    y: expandedFrame.origin.y - targetOrigin.y
                )
            } else {
                collapsedExpansionOffset = nil
            }

            window.minSize = bubbleSize
            window.isMovableByWindowBackground = false

            NSAnimationContext.runAnimationGroup { context in
                context.duration = animationDuration
                window.animator().setFrame(NSRect(origin: targetOrigin, size: bubbleSize), display: true)
            }
        } else {
            window.minSize = NSSize(width: expandedMinimumSize.width, height: expandedMinimumSize.height)
            window.isMovableByWindowBackground = true

            guard let storedExpandedFrame = expandedFrame else { return }

            let targetOrigin: NSPoint
            if let offset = collapsedExpansionOffset {
                let bubbleOrigin = window.frame.origin
                targetOrigin = NSPoint(
                    x: bubbleOrigin.x + offset.x,
                    y: bubbleOrigin.y + offset.y
                )
            } else {
                targetOrigin = storedExpandedFrame.origin
            }

            let targetFrame = NSRect(origin: targetOrigin, size: storedExpandedFrame.size)

            NSAnimationContext.runAnimationGroup { context in
                context.duration = animationDuration
                window.animator().setFrame(targetFrame, display: true)
            }

            self.expandedFrame = nil
            self.collapsedExpansionOffset = nil
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
        window.minSize = NSSize(width: expandedMinimumSize.width, height: expandedMinimumSize.height)
    }

    private var collapsedDragGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                guard let window else { return }
                let mouse = NSEvent.mouseLocation

                if collapsedDragOffset == nil {
                    collapsedDragOffset = NSPoint(
                        x: mouse.x - window.frame.origin.x,
                        y: mouse.y - window.frame.origin.y
                    )
                }

                guard let offset = collapsedDragOffset else { return }

                let newOrigin = NSPoint(
                    x: mouse.x - offset.x,
                    y: mouse.y - offset.y
                )

                window.setFrameOrigin(newOrigin)
            }
            .onEnded { _ in
                collapsedDragOffset = nil
            }
    }

    private var currentSurfaceShape: AnyShape {
        if isCollapsed {
            return AnyShape(Circle())
        } else {
            return AnyShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
    }

    @ViewBuilder
    private var surfaceBackground: some View {
        if #available(macOS 26.0, *) {
            LiquidGlassSurface(isCollapsed: isCollapsed)
        } else {
            if isCollapsed {
                FrostedBubbleBackground()
            } else {
                FrostedPanelBackground(cornerRadius: 28)
            }
        }
    }
}

@ViewBuilder
private var editorBackground: some View {
    if #available(macOS 26.0, *) {
        LiquidGlassEditorBackground()
    } else {
        LegacyEditorBackground()
    }
}

@available(macOS 26.0, *)
private struct LiquidGlassSurface: View {
    let isCollapsed: Bool

    var body: some View {
        GlassEffectContainer {
            Color.clear
        }
        .modifier(LiquidGlassShapeModifier(isCollapsed: isCollapsed))
    }
}

@available(macOS 26.0, *)
private struct LiquidGlassShapeModifier: ViewModifier {
    let isCollapsed: Bool

    func body(content: Content) -> some View {
        if isCollapsed {
            content
                .glassEffect(
                    .clear
                        .interactive(),
                    in: Circle()
                )
        } else {
            content
                .glassEffect(
                    .clear,
                    in: RoundedRectangle(cornerRadius: 28, style: .continuous)
                )
        }
    }
}

@available(macOS 26.0, *)
private struct LiquidGlassCollapsedBubble: View {
    var body: some View {
        GlassEffectContainer {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.white.opacity(0.95), Color.accentColor)
                .frame(width: 36, height: 36)
                .padding(6)
        }
        .glassEffect(
            .clear
                .interactive(),
            in: Circle()
        )
        .frame(width: 56, height: 56)
        .contentShape(Circle())
    }
}

private struct LegacyCollapsedBubble: View {
    var body: some View {
        Image(systemName: "bubble.left.and.bubble.right.fill")
            .font(.system(size: 24, weight: .semibold, design: .rounded))
            .symbolRenderingMode(.palette)
            .foregroundStyle(Color.white.opacity(0.95), Color.accentColor)
            .frame(width: 36, height: 36)
            .padding(6)
            .contentShape(Circle())
    }
}

@available(macOS 26.0, *)
private struct LiquidGlassEditorBackground: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)

        GlassEffectContainer {
            ZStack {
                shape
                    .fill(Color.black.opacity(0.12))
                    .blendMode(.plusLighter)

                shape
                    .strokeBorder(Color.black.opacity(0.18), lineWidth: 0.9)
                    .blendMode(.overlay)
            }
        }
        .glassEffect(
            .clear
                .tint(Color.black.opacity(0.1)),
            in: shape
        )
    }
}

private struct LegacyEditorBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Color.white.opacity(0.08))
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(
                        LinearGradient(colors: [.white.opacity(0.25), .white.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1
                    )
                    .blendMode(.overlay)
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
                .foregroundStyle(isActive ? Color.white.opacity(0.98) : Color.white.opacity(0.82))
                .frame(width: 32, height: 32)
                .background {
                    Circle()
                        .fill(Color.white.opacity(isActive ? 0.22 : 0.12))
                        .background(.regularMaterial, in: Circle())
                        .overlay {
                            Circle()
                                .stroke(Color.white.opacity(0.25), lineWidth: 0.8)
                                .blendMode(.overlay)
                        }
                        .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
                }
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
                .background {
                    Circle()
                        .fill(Color.red.opacity(0.24))
                        .background(.regularMaterial, in: Circle())
                        .overlay {
                            Circle()
                                .stroke(Color.white.opacity(0.28), lineWidth: 0.9)
                                .blendMode(.overlay)
                        }
                        .shadow(color: Color.red.opacity(0.24), radius: 8, y: 3)
                }
        }
        .buttonStyle(.plain)
        .help("关闭公告栏")
    }
}

private struct FrostedPanelBackground: View {
    let cornerRadius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        shape
            .fill(Color.white.opacity(0.08))
            .background(.regularMaterial, in: shape)
            .overlay {
                shape
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    .blendMode(.overlay)
            }
            .shadow(color: .black.opacity(0.22), radius: 26, y: 18)
            .shadow(color: Color.white.opacity(0.12), radius: 10, y: -6)
    }
}

private struct FrostedBubbleBackground: View {
    var body: some View {
        Circle()
            .fill(Color.white.opacity(0.12))
            .background(.regularMaterial, in: Circle())
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
                    .blendMode(.overlay)
            }
            .shadow(color: .black.opacity(0.24), radius: 16, y: 12)
            .shadow(color: Color.white.opacity(0.12), radius: 6, y: -4)
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
