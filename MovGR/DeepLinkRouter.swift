import SwiftUI
import MovGRShared

@Observable
@MainActor
final class DeepLinkRouter {
    var pending: MovGRDeepLink?

    func handle(_ url: URL) {
        pending = MovGRDeepLink.parse(url)
    }

    func applyToMap(
        store: TransportStore,
        settings: AppSettings,
        kind: inout TransportKind,
        selectedStop: inout SelectedStop?
    ) {
        guard let link = pending else { return }
        guard consume(link, store: store, settings: settings, kind: &kind, selectedStop: &selectedStop) else { return }
        pending = nil
    }

    private func consume(
        _ link: MovGRDeepLink,
        store: TransportStore,
        settings: AppSettings,
        kind: inout TransportKind,
        selectedStop: inout SelectedStop?
    ) -> Bool {
        kind = link.kind
        if let direction = link.metroDirection {
            settings.metroDirection = direction
        }
        switch link.kind {
        case .bus:
            if let id = link.busStopId {
                guard let stop = store.busStops.first(where: { $0.id == id }) else { return false }
                selectedStop = .bus(stop)
            }
        case .metro:
            if let id = link.metroStopId {
                guard let stop = store.metroStops.first(where: { $0.id == id }) else { return false }
                selectedStop = .metro(stop)
            }
        }
        return true
    }
}
