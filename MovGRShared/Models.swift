import CoreLocation
import Foundation

public enum TransportKind: String, Codable, Hashable, Sendable, CaseIterable {
    case bus
    case metro
    case ctagr

    public var title: String {
        switch self {
        case .bus: "Bus"
        case .metro: "Metro"
        case .ctagr: "Consorcio"
        }
    }
}

public struct LineaBus: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var nombre: String?
    public var color: String?
    public var textColor: String?

    enum CodingKeys: String, CodingKey {
        case id, nombre, color
        case textColor = "text_color"
    }
}

public struct ProximoBus: Codable, Hashable, Sendable {
    public var linea: LineaBus
    public var destino: String
    public var minutos: Int
}

public struct ParadaBus: Codable, Hashable, Sendable, Identifiable {
    public var id: Int
    public var nombre: String
    public var lat: Double?
    public var lon: Double?
    public var lineas: [String]?

    public var coordinate: CLLocationCoordinate2D? {
        guard let lat, let lon else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

public struct LlegadasBus: Codable, Hashable, Sendable {
    public var parada: ParadaBus
    public var proximos: [ProximoBus]
}

public enum DireccionMetro: String, Codable, Hashable, Sendable, CaseIterable {
    case albolote = "Albolote"
    case armilla = "Armilla"

    public func chevronsPointDown(inverted: Bool) -> Bool {
        inverted ? self != .armilla : self == .armilla
    }
}

public struct ProximoMetro: Codable, Hashable, Sendable {
    public var direccion: DireccionMetro
    public var minutos: Int
}

public struct ParadaMetro: Codable, Hashable, Sendable, Identifiable {
    public var linea: String
    public var id: String
    public var nombre: String
    public var lat: Double?
    public var lon: Double?

    public var coordinate: CLLocationCoordinate2D? {
        guard let lat, let lon else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

public struct LlegadasMetro: Codable, Hashable, Sendable {
    public var parada: ParadaMetro
    public var proximos: [ProximoMetro]
}

public struct ShapePoint: Codable, Hashable, Sendable {
    public var lat: Double
    public var lon: Double
    public var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

public struct RouteShape: Codable, Hashable, Sendable {
    public var direction: Int
    public var points: [ShapePoint]
}

public struct LineaBusDetail: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var nombre: String?
    public var color: String?
    public var textColor: String?
    public var shapes: [RouteShape]

    enum CodingKeys: String, CodingKey {
        case id, nombre, color, shapes
        case textColor = "text_color"
    }
}

public struct LineaMetroDetail: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var nombre: String?
    public var shapes: [RouteShape]
}

public struct LineaCtagr: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var nombre: String?
    public var color: String?
    public var textColor: String?

    enum CodingKeys: String, CodingKey {
        case id, nombre, color
        case textColor = "text_color"
    }
}

public struct VehiculoCtagr: Codable, Hashable, Sendable {
    public var linea: String
    public var sentido: Int
    public var lat: Double?
    public var lon: Double?
    public var visto: String?
}

public struct ProximoCtagr: Codable, Hashable, Sendable {
    public var linea: LineaCtagr
    public var destino: String
    public var hora: String
    public var minutos: Int
    public var sentido: Int?
    public var enRuta: Bool

    enum CodingKeys: String, CodingKey {
        case linea, destino, hora, minutos, sentido
        case enRuta = "en_ruta"
    }
}

public struct ParadaCtagr: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var nombre: String
    public var municipio: String?
    public var nucleo: String?
    public var lat: Double?
    public var lon: Double?
    public var lineas: [String]?

    public var coordinate: CLLocationCoordinate2D? {
        guard let lat, let lon else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

public struct LlegadasCtagr: Codable, Hashable, Sendable {
    public var parada: ParadaCtagr
    public var proximos: [ProximoCtagr]
    public var vehiculos: [VehiculoCtagr]
}

public struct LineaCtagrDetail: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var nombre: String?
    public var color: String?
    public var textColor: String?
    public var shapes: [RouteShape]
    public var vehiculos: [VehiculoCtagr]

    enum CodingKeys: String, CodingKey {
        case id, nombre, color, shapes, vehiculos
        case textColor = "text_color"
    }
}

public enum SelectedStop: Hashable, Sendable, Identifiable {
    case bus(ParadaBus)
    case metro(ParadaMetro)
    case ctagr(ParadaCtagr)

    public var id: String {
        switch self {
        case .bus(let stop): "bus-\(stop.id)"
        case .metro(let stop): "metro-\(stop.id)"
        case .ctagr(let stop): "ctagr-\(stop.id)"
        }
    }

    public var name: String {
        switch self {
        case .bus(let stop): stop.nombre
        case .metro(let stop): stop.nombre
        case .ctagr(let stop): stop.nombre
        }
    }

    public var kind: TransportKind {
        switch self {
        case .bus: .bus
        case .metro: .metro
        case .ctagr: .ctagr
        }
    }

    public var mapKind: TransportKind {
        self.kind == .metro ? .metro : .bus
    }

    public var coordinate: CLLocationCoordinate2D? {
        switch self {
        case .bus(let stop): stop.coordinate
        case .metro(let stop): stop.coordinate
        case .ctagr(let stop): stop.coordinate
        }
    }
}

extension SelectedStop: Codable {
    private enum Kind: String, Codable {
        case bus
        case metro
        case ctagr
    }

    private enum CodingKeys: String, CodingKey {
        case kind, bus, metro, ctagr
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .bus:
            self = .bus(try container.decode(ParadaBus.self, forKey: .bus))
        case .metro:
            self = .metro(try container.decode(ParadaMetro.self, forKey: .metro))
        case .ctagr:
            self = .ctagr(try container.decode(ParadaCtagr.self, forKey: .ctagr))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .bus(let stop):
            try container.encode(Kind.bus, forKey: .kind)
            try container.encode(stop, forKey: .bus)
        case .metro(let stop):
            try container.encode(Kind.metro, forKey: .kind)
            try container.encode(stop, forKey: .metro)
        case .ctagr(let stop):
            try container.encode(Kind.ctagr, forKey: .kind)
            try container.encode(stop, forKey: .ctagr)
        }
    }
}
