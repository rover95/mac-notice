import SwiftUI

@main
/// 应用主入口，配置公告板窗口的生命周期。
struct mac_noticeApp: App {
    /// 构建桌面窗口场景并设置默认尺寸与标题栏样式。
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 200, minHeight: 200)
        }
        .defaultSize(width: 480, height: 360)
        .windowStyle(.hiddenTitleBar)
    }
}
