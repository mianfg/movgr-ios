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

    public static func ctagrURL(stopId: String) -> URL {
        URL(string: "https://movgr.mianfg.me/ctagr?id=\(stopId)")!
    }

    public static func mapURL(kind: TransportKind, busId: Int? = nil, metroId: String? = nil, ctagrId: String? = nil, direction: DireccionMetro? = nil) -> URL {
        var items = [URLQueryItem(name: "mode", value: kind.rawValue)]
        switch kind {
        case .bus:
            if let busId { items.append(URLQueryItem(name: "id", value: String(busId))) }
        case .metro:
            if let metroId { items.append(URLQueryItem(name: "id", value: metroId)) }
            if let direction { items.append(URLQueryItem(name: "sentido", value: direction.rawValue)) }
        case .ctagr:
            if let ctagrId { items.append(URLQueryItem(name: "id", value: ctagrId)) }
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

public enum MovGRShareTarget: Hashable, Sendable {
    case app
    case bus(id: Int, name: String)
    case metro(name: String?, direction: DireccionMetro)
    case ctagr(id: String, name: String)
}

public struct MovGRSharePayload: Hashable, Sendable {
    public var url: URL
    public var title: String
    public var text: String
    public var target: MovGRShareTarget

    public init(url: URL, title: String, text: String, target: MovGRShareTarget) {
        self.url = url
        self.title = title
        self.text = text
        self.target = target
    }

    public static var home: MovGRSharePayload {
        .init(
            url: MovGRWeb.homeURL,
            title: "movGR",
            text: "Buses y metro de Granada",
            target: .app
        )
    }

    public static func bus(_ stop: ParadaBus) -> MovGRSharePayload {
        .init(
            url: MovGRWeb.busURL(stopId: stop.id),
            title: stop.nombre,
            text: "Parada \(stop.id) · \(stop.nombre)",
            target: .bus(id: stop.id, name: stop.nombre)
        )
    }

    public static func ctagr(_ stop: ParadaCtagr) -> MovGRSharePayload {
        .init(
            url: MovGRWeb.ctagrURL(stopId: stop.id),
            title: stop.nombre,
            text: "Consorcio \(stop.id) · \(stop.nombre)",
            target: .ctagr(id: stop.id, name: stop.nombre)
        )
    }

    public static func metro(_ stop: ParadaMetro?, direction: DireccionMetro) -> MovGRSharePayload {
        if let stop {
            return .init(
                url: MovGRWeb.metroURL(stopId: stop.id, direction: direction),
                title: stop.nombre,
                text: "\(stop.nombre) · \(direction.rawValue)",
                target: .metro(name: stop.nombre, direction: direction)
            )
        }
        return .init(
            url: MovGRWeb.metroURL(stopId: nil, direction: direction),
            title: "Metro",
            text: "Metro · \(direction.rawValue)",
            target: .metro(name: nil, direction: direction)
        )
    }
}

public struct MovGRDeepLink: Equatable, Sendable {
    public var kind: TransportKind
    public var busStopId: Int?
    public var metroStopId: String?
    public var metroDirection: DireccionMetro?
    public var preferMap: Bool

    public var ctagrStopId: String?

    public init(kind: TransportKind, busStopId: Int? = nil, metroStopId: String? = nil, ctagrStopId: String? = nil, metroDirection: DireccionMetro? = nil, preferMap: Bool = false) {
        self.kind = kind
        self.busStopId = busStopId
        self.metroStopId = metroStopId
        self.ctagrStopId = ctagrStopId
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
        if path == "ctagr" || path.hasPrefix("ctagr/") || mode == "ctagr" || mode == "bus-ctagr" {
            return MovGRDeepLink(kind: .ctagr, ctagrStopId: id, preferMap: preferMap)
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
        if isScheme, url.host == "ctagr" {
            return MovGRDeepLink(kind: .ctagr, ctagrStopId: id)
        }
        if isScheme, url.host == "bus" {
            return MovGRDeepLink(kind: .bus, busStopId: id.flatMap(Int.init))
        }
        return nil
    }
}
