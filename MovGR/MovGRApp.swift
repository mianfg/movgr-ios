import SwiftUI
import MovGRShared

@main
struct MovGRApp: App {
    @State private var settings = AppSettings()
    @State private var store = TransportStore()
    @State private var deepLinks = DeepLinkRouter()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            MapHomeView(settings: settings, store: store, deepLinks: deepLinks)
                .tint(.primary)
                .onOpenURL { deepLinks.handle($0) }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL {
                        deepLinks.handle(url)
                    }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                ArrivalActivityManager.shared.handleScenePhase(.background)
            case .active:
                ArrivalActivityManager.shared.handleScenePhase(.active)
            default:
                ArrivalActivityManager.shared.handleScenePhase(.inactive)
            }
        }
    }
}
