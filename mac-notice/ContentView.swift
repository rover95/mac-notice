import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

@MainActor
/// 主公告板视图，负责窗口状态管理、文本编辑与剪贴板历史。
struct ContentView: View {
    // MARK: - 状态存储
    @AppStorage("noticeText") private var noticeText = ""
    @State private var isPinned = false
    @State private var isCollapsed = false
    @State private var window: NSWindow?
    @State private var expandedFrame: NSRect?
    @State private var hasConfiguredWindow = false
    @State private var collapsedDragOffset: NSPoint?
    @State private var collapsedExpansionOffset: NSPoint?
    @State private var pinnedFrame: NSRect?
    @State private var isShowingHistory = false
    @State private var clipboardHistory: [ClipboardEntry] = []
    @State private var noticeItems: [NoticeEntry] = []
    @State private var noticeInput: String = ""
    @State private var pasteboardChangeCount = NSPasteboard.general.changeCount
    @State private var shouldIgnoreNextPasteboardChange = false
    @State private var originalStyleMask: NSWindow.StyleMask?
    @State private var originalHasShadow: Bool = true
    @State private var showCopiedTip = false
    @State private var copiedTipMessage = "已复制"

    // MARK: - 常量定义
    private let expandedMinimumSize = CGSize(width: 280, height: 240)
    private let panelCornerRadius: CGFloat = 14
    @AppStorage("maxHistoryEntries") private var maxHistoryEntries: Int = 10
    private let pasteboardMonitor = Timer.publish(every: 0.6, on: .main, in: .common).autoconnect()
    @State private var hasLoadedPersistence = false
    @State private var isShowingSettings = false

    /// 根据折叠状态切换主界面布局和窗口外观。
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
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didMoveNotification)) { notification in
            guard isPinned,
                  let window,
                  let movedWindow = notification.object as? NSWindow,
                  movedWindow == window else { return }
            pinnedFrame = window.frame
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResizeNotification)) { notification in
            guard isPinned,
                  let window,
                  let resizedWindow = notification.object as? NSWindow,
                  resizedWindow == window else { return }
            pinnedFrame = window.frame
        }
        .onReceive(pasteboardMonitor) { _ in
            captureClipboardIfNeeded()
        }
        .onAppear {
            if !hasLoadedPersistence {
                loadPersistedNoticeItems()
                loadPersistedClipboardHistory()
                hasLoadedPersistence = true
            }
        }
        .onChange(of: noticeItems) { _ in
            saveNoticeItems()
        }
        .onChange(of: clipboardHistory) { _ in
            saveClipboardHistory()
        }
        .onChange(of: maxHistoryEntries) { newValue in
            var v = newValue
            if v < 1 { v = 1 }
            if v > 999 { v = 999 }
            if v != newValue { maxHistoryEntries = v }
            if clipboardHistory.count > v {
                clipboardHistory = Array(clipboardHistory.prefix(v))
            }
            saveClipboardHistory()
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: isCollapsed)
        .animation(.easeInOut(duration: 0.2), value: isPinned)
        .ignoresSafeArea()
        .environment(\.controlActiveState, .active)
        .sheet(isPresented: $isShowingSettings) {
            SettingsSheet(maxHistoryEntries: $maxHistoryEntries)
                .frame(width: 360)
        }
    }

    /// 展开状态下的公告板主体，包含头部控制和内容区。
    private var expandedBoard: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerControls

            Group {
                if isShowingHistory {
                    clipboardHistoryList
                } else {
                    noticeBoardList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 160, minHeight: 160)
        .overlay(alignment: .center) {
            if showCopiedTip {
                CopiedTipView(text: copiedTipMessage)
                    .transition(.opacity)
            }
        }
    }

    /// 顶部控制栏，处理关闭、置顶、折叠等操作。
    private var headerControls: some View {
        HStack(spacing: 12) {
            CloseButton(action: closeWindow)

            // 折叠/展开按钮紧邻关闭按钮
            ControlButton(systemName: isCollapsed ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left", isActive: isCollapsed, action: toggleCollapse)
                .help(isCollapsed ? "展开公告板" : "收起为气泡")

            ControlButton(systemName: "pin", isActive: isPinned, action: togglePin)
                .help(isPinned ? "取消图钉" : "图钉置顶")

            ControlButton(systemName: "clock.arrow.circlepath", isActive: isShowingHistory, action: toggleHistoryMode)
                .help(isShowingHistory ? "返回公告栏" : "查看历史剪贴板")

            ControlButton(systemName: "gearshape", isActive: false, action: { isShowingSettings = true })
                .help("设置")

            Spacer(minLength: 12)

            ControlButton(systemName: "square.and.arrow.up", isActive: false, action: exportCurrentContent)
                .help("导出文本")
        }
        .padding(.top, 2)
    }

    /// 公告条目列表，顶部为输入框，回车新增为条目。
    private var noticeBoardList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                NoticeInputRow(text: $noticeInput, onSubmit: addNoticeFromInput)
                ForEach(noticeItems) { entry in
                    ClipboardHistoryRow(
                        text: entry.text,
                        onCopy: { copyToPasteboard(entry.text) },
                        onDelete: { deleteNoticeEntry(entry) }
                    )
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 2)
        }
        .padding(8)
        .background(editorBackground)
        .shadow(color: .black.opacity(0.08), radius: 18, y: 12)
    }

    /// 剪贴板历史列表，支持点击回填。
    private var clipboardHistoryList: some View {
        ZStack(alignment: .topLeading) {
            if clipboardHistory.isEmpty {
                EmptyHistoryBubble(text: "暂无历史剪贴板")
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 14)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(clipboardHistory) { entry in
                            ClipboardHistoryRow(
                                text: entry.text,
                                onCopy: { copyToPasteboard(entry.text) },
                                onDelete: { deleteClipboardEntry(entry) }
                            )
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 2)
                }
            }
        }
        .padding(8)
        .background(editorBackground)
        .shadow(color: .black.opacity(0.08), radius: 18, y: 12)
    }

    /// 折叠态圆形按钮，支持拖拽和点击展开。
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

    /// 切换窗口是否置顶到所有空间。
    private func togglePin() {
        isPinned.toggle()
    }

    /// 折叠或展开窗口，同时触发弹簧动画。
    private func toggleCollapse() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.74)) {
            isCollapsed.toggle()
        }
    }

    /// 切换展示公告编辑与剪贴板历史。
    private func toggleHistoryMode() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
            isShowingHistory.toggle()
        }
    }

    /// 关闭窗口并终止应用。
    private func closeWindow() {
        if let window {
            window.close()
        }
        NSApp.terminate(nil)
    }

    /// 根据置顶状态调整窗口层级和行为。
    private func updateWindowLevel() {
        guard let window else { return }
        window.level = isPinned ? .floating : .normal

        if isPinned {
            window.collectionBehavior.remove(.fullScreenNone)
            window.collectionBehavior.insert([.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .fullScreenAllowsTiling])
            if pinnedFrame == nil {
                pinnedFrame = window.frame
            }
            if let pinnedFrame {
                window.setFrame(pinnedFrame, display: true)
            }
            window.isMovable = true
            window.isMovableByWindowBackground = true
        } else {
            window.collectionBehavior.remove(.canJoinAllSpaces)
            window.collectionBehavior.remove(.fullScreenAuxiliary)
            window.collectionBehavior.remove(.stationary)
            window.collectionBehavior.remove(.fullScreenAllowsTiling)
            window.collectionBehavior.insert(.fullScreenNone)
            window.isMovable = true
            window.isMovableByWindowBackground = !isCollapsed
            pinnedFrame = nil
        }
    }

    /// 将窗口折叠为气泡或恢复到记录的矩形大小。
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
            if originalStyleMask == nil { originalStyleMask = window.styleMask }
            originalHasShadow = window.hasShadow
            window.hasShadow = false
            window.styleMask = [.borderless]
            window.invalidateShadow()

            NSAnimationContext.runAnimationGroup { context in
                context.duration = animationDuration
                window.animator().setFrame(NSRect(origin: targetOrigin, size: bubbleSize), display: true)
            }
        } else {
            window.minSize = NSSize(width: expandedMinimumSize.width, height: expandedMinimumSize.height)
            window.isMovableByWindowBackground = true
            if let mask = originalStyleMask {
                window.styleMask = mask
                originalStyleMask = nil
            }
            window.hasShadow = originalHasShadow
            window.invalidateShadow()
            // 还原为面板时再次隐藏三键按钮与标题栏视觉
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true

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

            if isPinned {
                pinnedFrame = targetFrame
            }
            self.expandedFrame = nil
            self.collapsedExpansionOffset = nil
        }
    }

    /// 轮询剪贴板变更并记录新的文本条目。
    private func captureClipboardIfNeeded() {
        let pasteboard = NSPasteboard.general
        let currentChangeCount = pasteboard.changeCount

        guard currentChangeCount != pasteboardChangeCount else { return }
        pasteboardChangeCount = currentChangeCount

        if shouldIgnoreNextPasteboardChange {
            shouldIgnoreNextPasteboardChange = false
            return
        }

        guard let clipboardString = pasteboard.string(forType: .string) else { return }
        let normalized = clipboardString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }

        addClipboardEntry(clipboardString)
    }

    /// 将最新剪贴板内容添加到历史列表并裁剪长度。
    private func addClipboardEntry(_ text: String) {
        if clipboardHistory.first?.text == text {
            return
        }

        let entry = ClipboardEntry(text: text)
        clipboardHistory.insert(entry, at: 0)

        if clipboardHistory.count > maxHistoryEntries {
            clipboardHistory = Array(clipboardHistory.prefix(maxHistoryEntries))
        }
    }

    /// 将输入框内容作为公告条目新增到列表。
    private func addNoticeFromInput() {
        let normalized = noticeInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        let entry = NoticeEntry(text: normalized)
        noticeItems.insert(entry, at: 0)
        noticeInput = ""
    }

    /// 删除一个剪贴板历史条目。
    private func deleteClipboardEntry(_ entry: ClipboardEntry) {
        clipboardHistory.removeAll { $0.id == entry.id }
    }

    /// 删除一个公告条目。
    private func deleteNoticeEntry(_ entry: NoticeEntry) {
        noticeItems.removeAll { $0.id == entry.id }
    }

    // MARK: - 持久化存储（Application Support/"mac-notice" 文件夹）
    private func storageDirectoryURL() -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("mac-notice", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            NSLog("Failed to create storage dir: %@", error.localizedDescription)
        }
        return dir
    }

    private func storageURL(fileName: String) -> URL? {
        storageDirectoryURL()?.appendingPathComponent(fileName, isDirectory: false)
    }

    @MainActor
    private func saveNoticeItems() {
        guard let url = storageURL(fileName: "noticeItems.json") else { return }
        do {
            let data = try JSONEncoder().encode(noticeItems)
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("Failed to save notice items: %@", error.localizedDescription)
        }
    }

    @MainActor
    private func loadPersistedNoticeItems() {
        guard let url = storageURL(fileName: "noticeItems.json") else { return }
        do {
            let data = try Data(contentsOf: url)
            let items = try JSONDecoder().decode([NoticeEntry].self, from: data)
            noticeItems = items
        } catch {
            // 首次运行或解码失败时静默忽略
        }
    }

    @MainActor
    private func saveClipboardHistory() {
        guard let url = storageURL(fileName: "clipboardHistory.json") else { return }
        do {
            let trimmed = Array(clipboardHistory.prefix(maxHistoryEntries))
            let data = try JSONEncoder().encode(trimmed)
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("Failed to save clipboard history: %@", error.localizedDescription)
        }
    }

    @MainActor
    private func loadPersistedClipboardHistory() {
        guard let url = storageURL(fileName: "clipboardHistory.json") else { return }
        do {
            let data = try Data(contentsOf: url)
            let items = try JSONDecoder().decode([ClipboardEntry].self, from: data)
            clipboardHistory = Array(items.prefix(maxHistoryEntries))
        } catch {
            // 首次运行或解码失败时静默忽略
        }
    }

    @MainActor
    /// 将选中的历史内容写回剪贴板，可选跳过历史记录。
    private func copyToPasteboard(_ text: String, suppressHistoryUpdate: Bool = true) {
        let pasteboard = NSPasteboard.general
        shouldIgnoreNextPasteboardChange = suppressHistoryUpdate
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        pasteboardChangeCount = pasteboard.changeCount
        // 显示“已复制”提示
        showCopiedTip = true
        copiedTipMessage = "已复制"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeInOut(duration: 0.2)) {
                showCopiedTip = false
            }
        }
    }

    @MainActor
    /// 导出当前公告或历史列表为文本文件。
    private func exportCurrentContent() {
        let content: String
        let suggestedName: String

        if isShowingHistory {
            content = clipboardHistory.map(\.text).joined(separator: "\n\n")
            suggestedName = "ClipboardHistory"
        } else {
            // 导出公告条目列表
            if noticeItems.isEmpty {
                content = noticeInput
            } else {
                content = noticeItems.map(\.text).joined(separator: "\n\n")
            }
            suggestedName = "Notice"
        }

        presentSavePanel(with: content, suggestedFileName: suggestedName)
    }

    @MainActor
    /// 弹出保存面板并写入导出的文本内容。
    private func presentSavePanel(with content: String, suggestedFileName: String) {
        let panel = NSSavePanel()
        panel.allowsOtherFileTypes = false
        if #available(macOS 12.0, *) {
            panel.allowedContentTypes = [.plainText]
        } else {
            panel.allowedFileTypes = ["txt"]
        }
        panel.canCreateDirectories = true

        if suggestedFileName.lowercased().hasSuffix(".txt") {
            panel.nameFieldStringValue = suggestedFileName
        } else {
            panel.nameFieldStringValue = "\(suggestedFileName).txt"
        }

        let writeContent: (URL) -> Void = { url in
            do {
                try content.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                NSLog("Failed to export text: %@", error.localizedDescription)
            }
        }

        if let hostingWindow = window ?? NSApp.keyWindow ?? NSApp.mainWindow {
            if !hostingWindow.isKeyWindow {
                hostingWindow.makeKeyAndOrderFront(nil)
            }
            panel.beginSheetModal(for: hostingWindow) { response in
                guard response == .OK, let url = panel.url else { return }
                writeContent(url)
            }
        } else {
            let response = panel.runModal()
            guard response == .OK, let url = panel.url else { return }
            writeContent(url)
        }
    }

    /// 初始化窗口外观和交互，仅执行一次。
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
        window.styleMask = [.titled, .resizable, .fullSizeContentView]
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.invalidateShadow()
        window.setFrameAutosaveName("NoticeBoardWindow")
        window.minSize = NSSize(width: expandedMinimumSize.width, height: expandedMinimumSize.height)
    }

    /// 折叠态下的拖拽手势，用于移动气泡位置。
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
                if isPinned, let windowFrame = window?.frame {
                    pinnedFrame = windowFrame
                }
            }
    }

    /// 根据折叠状态选择圆形或圆角矩形外观。
    private var currentSurfaceShape: AnyShape {
        if isCollapsed {
            return AnyShape(Circle())
        } else {
            return AnyShape(RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous))
        }
    }

    @ViewBuilder
    /// 渲染主面板（展开态）的玻璃/磨砂背景；折叠态不渲染外层容器。
    private var surfaceBackground: some View {
        if isCollapsed {
            EmptyView()
        } else {
            if #available(macOS 26.0, *) {
                PanelGlassBackground(cornerRadius: panelCornerRadius)
            } else {
                PanelFrostedBackground(cornerRadius: panelCornerRadius)
            }
        }
    }
}

@ViewBuilder
/// 编辑区域的玻璃效果背景。
private var editorBackground: some View {
    if #available(macOS 26.0, *) {
        LiquidGlassEditorBackground()
    } else {
        LegacyEditorBackground()
    }
}

@available(macOS 26.0, *)
/// 展开态主面板的液态玻璃背景（无描边）。
private struct PanelGlassBackground: View {
    let cornerRadius: CGFloat
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        GlassEffectContainer { Color.clear }
            .glassEffect(.clear, in: shape)
            .mask(shape.inset(by: 0.8))
            .compositingGroup()
            .overlay {
                shape
                    .fill(Color.black.opacity(0.02))
                    .blendMode(.multiply)
            }
            .overlay {
                shape
                    .fill(Color.white.opacity(0.02))
                    .blendMode(.plusLighter)
            }
    }
}

/// 旧系统下的主面板磨砂背景（无描边）。
private struct PanelFrostedBackground: View {
    let cornerRadius: CGFloat
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape
            .fill(Color.white.opacity(0.08))
            .background(.regularMaterial, in: shape)
    }
}

// 已移除外层容器，避免面板与气泡之外出现边框/透明包裹层。
// 如需恢复整体玻璃背景，可将 `surfaceBackground` 切换为下方实现。
// @available(macOS 26.0, *)
// private struct LiquidGlassSurface: View {
//     let isCollapsed: Bool
//     var body: some View {
//         GlassEffectContainer { Color.clear }
//             .modifier(LiquidGlassShapeModifier(isCollapsed: isCollapsed))
//     }
// }

// @available(macOS 26.0, *)
// private struct LiquidGlassShapeModifier: ViewModifier {
//     let isCollapsed: Bool
//     func body(content: Content) -> some View {
//         if isCollapsed {
//             content.glassEffect(.clear.interactive(), in: Circle())
//         } else {
//             content.glassEffect(.clear, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
//         }
//     }
// }

@available(macOS 26.0, *)
/// 折叠气泡（玻璃效果且无边框）。
private struct LiquidGlassCollapsedBubble: View {
    var body: some View {
        GlassEffectContainer {
            Image(systemName: "note.text")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.95))
                .frame(width: 36, height: 36)
                .padding(6)
        }
        .glassEffect(.clear.interactive(), in: Circle())
        .mask(Circle().inset(by: 0.8))
        .compositingGroup()
        .overlay {
            Circle()
                .fill(Color.black.opacity(0.02))
                .blendMode(.multiply)
        }
        .overlay {
            Circle()
                .fill(Color.white.opacity(0.02))
                .blendMode(.plusLighter)
        }
        .frame(width: 56, height: 56)
        .contentShape(Circle())
    }
}

/// 兼容旧系统的折叠气泡样式（无描边）。
private struct LegacyCollapsedBubble: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.12))
                .background(.regularMaterial, in: Circle())
                .shadow(color: .black.opacity(0.18), radius: 6, y: 3)

            Image(systemName: "note.text")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.95))
                .frame(width: 36, height: 36)
                .padding(6)
        }
        .frame(width: 56, height: 56)
        .contentShape(Circle())
    }
}

@available(macOS 26.0, *)
/// 玻璃效果编辑器背景，提供层次感。
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

/// 单条剪贴板历史的行视图。
private struct ClipboardHistoryRow: View {
    let text: String
    var onCopy: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    @State private var isHovering = false
    @State private var isExpanded = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

        ZStack(alignment: .topLeading) {
            Text(text)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(isExpanded ? nil : 2)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .background {
                    if #available(macOS 26.0, *) {
                        GlassEffectContainer { Color.clear }
                            .glassEffect(.clear, in: shape)
                            .mask(shape.inset(by: 0.8))
                            .overlay { shape.fill(Color.black.opacity(0.5)).blendMode(.multiply) }
                            .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                    } else {
                        shape
                            .fill(Color.white.opacity(0.06))
                            .background(.regularMaterial, in: shape)
                            .overlay { shape.fill(Color.black.opacity(0.5)).blendMode(.multiply) }
                            .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                    }
                }
                .contentShape(shape)
                .onTapGesture { onCopy?() }

            if let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .background(Color.clear)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("删除条目")
                .opacity(isHovering ? 1 : 0)
                .offset(x: -2, y: -2)
            }
        }
        .overlay(alignment: .trailing) {
            if isHovering {
                Button(action: { withAnimation(.easeInOut(duration: 0.18)) { isExpanded.toggle() } }) {
                    Image(systemName: isExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .frame(width: 22, height: 22)
                        .background { Circle().fill(Color.black.opacity(0.28)) }
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .onHover { isHovering = $0 }
    }
}

/// 复制完成提示气泡。
private struct CopiedTipView: View {
    let text: String
    var body: some View {
        let shape = Capsule(style: .continuous)
        Text(text)
            .font(.system(.footnote, design: .rounded))
            .foregroundStyle(.primary)
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background {
                if #available(macOS 26.0, *) {
                    GlassEffectContainer { Color.clear }
                        .glassEffect(.clear, in: shape)
                        .mask(shape.inset(by: 0.6))
                } else {
                    shape.fill(Color.white.opacity(0.12)).background(.regularMaterial, in: shape)
                }
            }
            .contentShape(shape)
    }
}

/// 空状态的小气泡容器，气泡内文案垂直居中。
private struct EmptyHistoryBubble: View {
    let text: String

    var body: some View {
        let shape = Capsule(style: .continuous)

        return Text(text)
            .font(.system(.body, design: .rounded))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background {
                if #available(macOS 26.0, *) {
                    GlassEffectContainer { Color.clear }
                        .glassEffect(.clear, in: shape)
                        .mask(shape.inset(by: 0.8))
                        .compositingGroup()
                        .overlay { shape.fill(Color.black.opacity(0.02)).blendMode(.multiply) }
                        .overlay { shape.fill(Color.white.opacity(0.02)).blendMode(.plusLighter) }
                        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                } else {
                    shape
                        .fill(Color.white.opacity(0.06))
                        .background(.regularMaterial, in: shape)
                        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                }
            }
            .contentShape(shape)
    }
}

/// 表示剪贴板历史项的数据模型。
private struct ClipboardEntry: Identifiable, Equatable, Sendable, Codable {
    let id = UUID()
    let text: String
}

/// 公告条目数据模型。
private struct NoticeEntry: Identifiable, Equatable, Sendable, Codable {
    let id = UUID()
    let text: String
}

/// 旧系统下的编辑器磨砂背景。
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

/// 顶部控制按钮的通用样式。
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

/// 顶部关闭按钮，触发退出应用。
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

/// 公告输入行：样式与条目一致，按回车新增。
private struct NoticeInputRow: View {
    @Binding var text: String
    var onSubmit: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(Color.accentColor)
                .font(.system(size: 14, weight: .semibold, design: .rounded))

            TextField("输入便签内容，按回车添加", text: $text)
                .textFieldStyle(.plain)
                .font(.system(.body, design: .rounded))
                .onSubmit {
                    onSubmit()
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background {
            if #available(macOS 26.0, *) {
                GlassEffectContainer { Color.clear }
                    .glassEffect(.clear, in: shape)
                    .mask(shape.inset(by: 0.8))
                    .overlay { shape.fill(Color.black.opacity(0.5)).blendMode(.multiply) }
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
            } else {
                shape
                    .fill(Color.white.opacity(0.06))
                    .background(.regularMaterial, in: shape)
                    .overlay { shape.fill(Color.black.opacity(0.5)).blendMode(.multiply) }
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
            }
        }
        .contentShape(shape)
    }
}

/// 旧版展开面板的磨砂背景。
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

/// 旧版折叠气泡的磨砂背景。
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


/// 将泛型 Shape 装箱为类型擦除结构。
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

// （已移除测量逻辑的 PreferenceKey）

/// 捕获宿主 NSWindow，用于窗口配置。
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

// MARK: - 设置面板
private struct SettingsSheet: View {
    @Binding var maxHistoryEntries: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("设置")
                .font(.title3)
                .bold()

            HStack(spacing: 8) {
                Text("历史记录最大条数：")
                TextField("", value: $maxHistoryEntries, formatter: numberFormatter)
                    .frame(width: 64)
                    .textFieldStyle(.roundedBorder)
                Stepper("", value: $maxHistoryEntries, in: 1...999, step: 1)
                    .labelsHidden()
                Spacer()
            }

            Text("范围 1–999。超过该数量时会自动从尾部截断。")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }

    private var numberFormatter: NumberFormatter {
        let nf = NumberFormatter()
        nf.minimum = 1
        nf.maximum = 999
        nf.allowsFloats = false
        nf.numberStyle = .none
        return nf
    }
}
