import Foundation

public enum MovGRWeb {
    public static let origin = URL(string: "https://movgr.mianfg.me")!

    public static func busURL(stopId: Int) -> URL {
        URL(string: "https://movgr.mianfg.me/bus?id=\(stopId)")!
    }

    public static func metroURL(stopId: String?, direction: DireccionMetro) -> URL {
        var items: [URLQueryItem] = [URLQueryItem(name: "sentido", value: direction.rawValue)]
        if let stopId, !stopId.isEmpty {
            items.insert(URLQueryItem(name: "id", value: stopId), at: 0)
        }
        return url(path: "/metro", items: items)
    }

    public static func mapURL(kind: TransportKind, busId: Int? = nil, metroId: String? = nil, direction: DireccionMetro? = nil) -> URL {
        var items = [URLQueryItem(name: "mode", value: kind.rawValue)]
        switch kind {
        case .bus:
            if let busId { items.append(URLQueryItem(name: "id", value: String(busId))) }
        case .metro:
            if let metroId { items.append(URLQueryItem(name: "id", value: metroId)) }
            if let direction { items.append(URLQueryItem(name: "sentido", value: direction.rawValue)) }
        }
        return url(path: "/map", items: items)
    }

    public static let homeURL = origin

    private static func url(path: String, items: [URLQueryItem]) -> URL {
        var components = URLComponents(url: origin, resolvingAgainstBaseURL: false)!
        components.path = path
        components.queryItems = items.isEmpty ? nil : items
        return components.url!
    }
}

public struct MovGRSharePayload: Hashable, Sendable {
    public var url: URL
    public var title: String
    public var text: String

    public init(url: URL, title: String, text: String) {
        self.url = url
        self.title = title
        self.text = text
    }

    public static var home: MovGRSharePayload {
        .init(
            url: MovGRWeb.homeURL,
            title: "movGR",
            text: "Sigue en directo el transporte público de Granada"
        )
    }

    public static func bus(_ stop: ParadaBus) -> MovGRSharePayload {
        .init(
            url: MovGRWeb.busURL(stopId: stop.id),
            title: "Bus: \(stop.id) (\(stop.nombre))",
            text: "Sigue en movGR la parada de autobús \(stop.id) (\(stop.nombre))"
        )
    }

    public static func metro(_ stop: ParadaMetro?, direction: DireccionMetro) -> MovGRSharePayload {
        if let stop {
            return .init(
                url: MovGRWeb.metroURL(stopId: stop.id, direction: direction),
                title: "Metro: \(stop.nombre) sentido \(direction.rawValue)",
                text: "Sigue en movGR la parada de metro \(stop.nombre) sentido \(direction.rawValue)"
            )
        }
        return .init(
            url: MovGRWeb.metroURL(stopId: nil, direction: direction),
            title: "Metro Granada",
            text: "Sigue en movGR el metro de Granada sentido \(direction.rawValue)"
        )
    }
}

public struct MovGRDeepLink: Equatable, Sendable {
    public var kind: TransportKind
    public var busStopId: Int?
    public var metroStopId: String?
    public var metroDirection: DireccionMetro?
    public var preferMap: Bool

    public init(kind: TransportKind, busStopId: Int? = nil, metroStopId: String? = nil, metroDirection: DireccionMetro? = nil, preferMap: Bool = false) {
        self.kind = kind
        self.busStopId = busStopId
        self.metroStopId = metroStopId
        self.metroDirection = metroDirection
        self.preferMap = preferMap
    }

    public static func parse(_ url: URL) -> MovGRDeepLink? {
        let host = url.host?.lowercased() ?? ""
        let isWeb = host.contains("movgr.mianfg.me")
        let isScheme = url.scheme?.lowercased() == "movgr"
        guard isWeb || isScheme else { return nil }

        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first(where: { $0.name == name })?.value
        }

        let mode = value("mode")
        let id = value("id")
        let sentido = value("sentido").flatMap(DireccionMetro.init(rawValue:))
        let preferMap = path == "map" || path.hasPrefix("map/")

        if path == "metro" || path.hasPrefix("metro/") || mode == "metro" {
            return MovGRDeepLink(kind: .metro, metroStopId: id, metroDirection: sentido, preferMap: preferMap)
        }
        if path == "bus" || path.hasPrefix("bus/") || mode == "bus" {
            return MovGRDeepLink(kind: .bus, busStopId: id.flatMap(Int.init), preferMap: preferMap)
        }
        if preferMap {
            return MovGRDeepLink(kind: .bus, preferMap: true)
        }
        if isScheme, url.host == "metro" {
            return MovGRDeepLink(kind: .metro, metroStopId: id, metroDirection: sentido)
        }
        if isScheme, url.host == "bus" {
            return MovGRDeepLink(kind: .bus, busStopId: id.flatMap(Int.init))
        }
        return nil
    }
}
