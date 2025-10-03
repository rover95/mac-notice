import SwiftUI

@main
struct mac_noticeApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 200, minHeight: 200)
        }
        .defaultSize(width: 480, height: 360)
        .windowStyle(.hiddenTitleBar)
    }
}
