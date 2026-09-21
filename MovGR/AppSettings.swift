import Foundation
import SwiftUI
import MovGRShared

enum MapLayerFilter: String, CaseIterable, Identifiable {
    case all
    case bus
    case metro

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "Todos"
        case .bus: "Bus"
        case .metro: "Metro"
        }
    }

    var showsBus: Bool { self != .metro }
    var showsMetro: Bool { self != .bus }

    func includes(_ kind: TransportKind) -> Bool {
        switch self {
        case .all: true
        case .bus: kind == .bus
        case .metro: kind == .metro
        }
    }
}

enum HomeListOrder: String, CaseIterable, Identifiable {
    case recentsFirst
    case nearbyFirst

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recentsFirst: "Recientes primero"
        case .nearbyFirst: "Cercanas primero"
        }
    }

    var subtitle: String {
        switch self {
        case .recentsFirst: "Últimas paradas y estaciones consultadas"
        case .nearbyFirst: "Lo más cerca de ti, si hay ubicación"
        }
    }
}

enum MapBaseStyle: String, CaseIterable, Identifiable {
    case standard
    case hybrid
    case satellite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: "Estándar"
        case .hybrid: "Híbrido"
        case .satellite: "Satélite"
        }
    }

    var subtitle: String {
        switch self {
        case .standard: "Mapa de calles de Apple"
        case .hybrid: "Satélite con nombres de calles"
        case .satellite: "Solo imagen satélite"
        }
    }

    var symbol: String {
        switch self {
        case .standard: "map"
        case .hybrid: "square.2.layers.3d"
        case .satellite: "globe.americas.fill"
        }
    }
}

@Observable
@MainActor
final class AppSettings {
    private enum Keys {
        static let metroInverted = "movgr.metroInverted"
        static let metroDirection = "movgr.metroDirection"
        static let favoriteBusStops = "movgr.favoriteBusStops"
        static let favoriteMetroStops = "movgr.favoriteMetroStops"
        static let liveActivityEnabled = "movgr.liveActivityEnabled"
        static let mapStyle = "movgr.mapStyle"
        static let showTraffic = "movgr.showTraffic"
        static let mapFavoritesOnly = "movgr.mapFavoritesOnly"
        static let preferredBusLines = "movgr.preferredBusLines"
        static let preferredTransport = "movgr.preferredTransport"
        static let logoExpanded = "movgr.logoExpanded"
        static let recentStops = "movgr.recentStops"
        static let homeListOrder = "movgr.homeListOrder"
        static let mapLayers = "movgr.mapLayers"
    }

    var metroInverted: Bool {
        didSet { UserDefaults.standard.set(metroInverted, forKey: Keys.metroInverted) }
    }

    var metroDirection: DireccionMetro {
        didSet { UserDefaults.standard.set(metroDirection.rawValue, forKey: Keys.metroDirection) }
    }

    var favoriteBusStops: [ParadaBus] {
        didSet { saveBusFavorites() }
    }

    var favoriteMetroStops: [ParadaMetro] {
        didSet { saveMetroFavorites() }
    }

    var liveActivityEnabled: Bool {
        didSet {
            UserDefaults.standard.set(liveActivityEnabled, forKey: Keys.liveActivityEnabled)
            if !liveActivityEnabled {
                ArrivalActivityManager.shared.stopTracking()
            }
        }
    }

    var mapStyle: MapBaseStyle {
        didSet { UserDefaults.standard.set(mapStyle.rawValue, forKey: Keys.mapStyle) }
    }

    var showTraffic: Bool {
        didSet { UserDefaults.standard.set(showTraffic, forKey: Keys.showTraffic) }
    }

    var mapFavoritesOnly: Bool {
        didSet { UserDefaults.standard.set(mapFavoritesOnly, forKey: Keys.mapFavoritesOnly) }
    }

    var preferredBusLines: [String: String] {
        didSet { UserDefaults.standard.set(preferredBusLines, forKey: Keys.preferredBusLines) }
    }

    var preferredTransport: TransportKind {
        didSet { UserDefaults.standard.set(preferredTransport.rawValue, forKey: Keys.preferredTransport) }
    }

    var logoExpanded: Bool {
        didSet { UserDefaults.standard.set(logoExpanded, forKey: Keys.logoExpanded) }
    }

    var recentStops: [SelectedStop] {
        didSet { saveRecentStops() }
    }

    var homeListOrder: HomeListOrder {
        didSet { UserDefaults.standard.set(homeListOrder.rawValue, forKey: Keys.homeListOrder) }
    }

    var mapLayers: MapLayerFilter {
        didSet { UserDefaults.standard.set(mapLayers.rawValue, forKey: Keys.mapLayers) }
    }

    var transportOrder: [TransportKind] {
        preferredTransport == .metro ? [.metro, .bus] : [.bus, .metro]
    }

    var favoriteStopIds: Set<Int> {
        Set(favoriteBusStops.map(\.id))
    }

    var favoriteMetroIds: Set<String> {
        Set(favoriteMetroStops.map(\.id))
    }

    init() {
        metroInverted = UserDefaults.standard.bool(forKey: Keys.metroInverted)
        if let raw = UserDefaults.standard.string(forKey: Keys.metroDirection),
           let direction = DireccionMetro(rawValue: raw) {
            metroDirection = direction
        } else {
            metroDirection = .armilla
        }
        if let data = UserDefaults.standard.data(forKey: Keys.favoriteBusStops),
           let stops = try? JSONDecoder().decode([ParadaBus].self, from: data) {
            favoriteBusStops = stops
        } else {
            favoriteBusStops = []
        }
        if let data = UserDefaults.standard.data(forKey: Keys.favoriteMetroStops),
           let stops = try? JSONDecoder().decode([ParadaMetro].self, from: data) {
            favoriteMetroStops = stops
        } else {
            favoriteMetroStops = []
        }
        if UserDefaults.standard.object(forKey: Keys.liveActivityEnabled) == nil {
            liveActivityEnabled = true
        } else {
            liveActivityEnabled = UserDefaults.standard.bool(forKey: Keys.liveActivityEnabled)
        }
        if let raw = UserDefaults.standard.string(forKey: Keys.mapStyle),
           let style = MapBaseStyle(rawValue: raw) {
            mapStyle = style
        } else {
            mapStyle = .standard
        }
        showTraffic = UserDefaults.standard.bool(forKey: Keys.showTraffic)
        mapFavoritesOnly = UserDefaults.standard.bool(forKey: Keys.mapFavoritesOnly)
        preferredBusLines = UserDefaults.standard.dictionary(forKey: Keys.preferredBusLines) as? [String: String] ?? [:]
        preferredTransport = Self.storedPreferredTransport()
        if UserDefaults.standard.object(forKey: Keys.logoExpanded) == nil {
            logoExpanded = true
        } else {
            logoExpanded = UserDefaults.standard.bool(forKey: Keys.logoExpanded)
        }
        if let data = UserDefaults.standard.data(forKey: Keys.recentStops),
           let stops = try? JSONDecoder().decode([SelectedStop].self, from: data) {
            recentStops = stops
        } else {
            recentStops = []
        }
        if let raw = UserDefaults.standard.string(forKey: Keys.homeListOrder),
           let order = HomeListOrder(rawValue: raw) {
            homeListOrder = order
        } else {
            homeListOrder = .recentsFirst
        }
        if let raw = UserDefaults.standard.string(forKey: Keys.mapLayers),
           let layers = MapLayerFilter(rawValue: raw) {
            mapLayers = layers
        } else {
            mapLayers = .all
        }
    }

    static func storedPreferredTransport() -> TransportKind {
        if let raw = UserDefaults.standard.string(forKey: Keys.preferredTransport),
           let kind = TransportKind(rawValue: raw) {
            return kind
        }
        return .bus
    }

    static func storedLiveActivityEnabled() -> Bool {
        if UserDefaults.standard.object(forKey: Keys.liveActivityEnabled) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: Keys.liveActivityEnabled)
    }

    static func storedMetroDirection() -> DireccionMetro {
        if let raw = UserDefaults.standard.string(forKey: Keys.metroDirection),
           let direction = DireccionMetro(rawValue: raw) {
            return direction
        }
        return .armilla
    }

    static func storedMetroInverted() -> Bool {
        UserDefaults.standard.bool(forKey: Keys.metroInverted)
    }

    static func storedPreferredLine(forBusStopId stopId: Int) -> String? {
        let lines = UserDefaults.standard.dictionary(forKey: Keys.preferredBusLines) as? [String: String] ?? [:]
        return lines["\(stopId)"]
    }

    func preferredLine(for stop: ParadaBus) -> String? {
        preferredBusLines["\(stop.id)"]
    }

    func togglePreferredLine(_ lineId: String, for stop: ParadaBus) {
        var next = preferredBusLines
        let key = "\(stop.id)"
        if next[key] == lineId {
            next.removeValue(forKey: key)
        } else {
            next[key] = lineId
        }
        preferredBusLines = next
        ArrivalActivityManager.shared.preferencesDidChange()
    }

    func isFavorite(_ stop: ParadaBus) -> Bool {
        favoriteBusStops.contains { $0.id == stop.id }
    }

    func isFavorite(_ stop: ParadaMetro) -> Bool {
        favoriteMetroStops.contains { $0.id == stop.id }
    }

    func toggleFavorite(_ stop: ParadaBus) {
        if let index = favoriteBusStops.firstIndex(where: { $0.id == stop.id }) {
            favoriteBusStops.remove(at: index)
        } else {
            favoriteBusStops.append(stop)
        }
    }

    func toggleFavorite(_ stop: ParadaMetro) {
        if let index = favoriteMetroStops.firstIndex(where: { $0.id == stop.id }) {
            favoriteMetroStops.remove(at: index)
        } else {
            favoriteMetroStops.append(stop)
        }
    }

    func recordRecent(_ stop: SelectedStop) {
        var next = recentStops.filter { $0.id != stop.id }
        next.insert(stop, at: 0)
        recentStops = Array(next.prefix(12))
    }

    private func saveRecentStops() {
        if let data = try? JSONEncoder().encode(recentStops) {
            UserDefaults.standard.set(data, forKey: Keys.recentStops)
        }
    }

    private func saveBusFavorites() {
        if let data = try? JSONEncoder().encode(favoriteBusStops) {
            UserDefaults.standard.set(data, forKey: Keys.favoriteBusStops)
        }
    }

    private func saveMetroFavorites() {
        if let data = try? JSONEncoder().encode(favoriteMetroStops) {
            UserDefaults.standard.set(data, forKey: Keys.favoriteMetroStops)
        }
    }
}
