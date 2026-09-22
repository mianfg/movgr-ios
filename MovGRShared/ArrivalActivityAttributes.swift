import ActivityKit
import Foundation

public struct ArrivalRow: Codable, Hashable, Sendable {
    public var badge: String
    public var colorHex: String
    public var textColorHex: String
    public var title: String
    public var minutes: Int
    public var eta: Date
    public var additionalMinutes: [Int]
    public var additionalETAs: [Date]

    public init(
        badge: String,
        colorHex: String,
        textColorHex: String,
        title: String,
        minutes: Int,
        eta: Date,
        additionalMinutes: [Int] = [],
        additionalETAs: [Date] = []
    ) {
        self.badge = badge
        self.colorHex = colorHex
        self.textColorHex = textColorHex
        self.title = title
        self.minutes = minutes
        self.eta = eta
        self.additionalMinutes = additionalMinutes
        self.additionalETAs = additionalETAs
    }

    public var allMinutes: [Int] { [minutes] + additionalMinutes }
    public var allETAs: [Date] { [eta] + additionalETAs }

    public var minuteLabel: String {
        minutes <= 0 ? "< 1 min" : "\(minutes) min"
    }

    enum CodingKeys: String, CodingKey {
        case badge, colorHex, textColorHex, title, minutes, eta, additionalMinutes, additionalETAs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        badge = try container.decode(String.self, forKey: .badge)
        colorHex = try container.decode(String.self, forKey: .colorHex)
        textColorHex = try container.decode(String.self, forKey: .textColorHex)
        title = try container.decode(String.self, forKey: .title)
        minutes = try container.decode(Int.self, forKey: .minutes)
        additionalMinutes = try container.decodeIfPresent([Int].self, forKey: .additionalMinutes) ?? []
        additionalETAs = Self.decodeUnixDates(container, forKey: .additionalETAs)
        eta = try Self.decodeUnixDate(container, forKey: .eta)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(badge, forKey: .badge)
        try container.encode(colorHex, forKey: .colorHex)
        try container.encode(textColorHex, forKey: .textColorHex)
        try container.encode(title, forKey: .title)
        try container.encode(minutes, forKey: .minutes)
        try container.encode(eta.timeIntervalSince1970, forKey: .eta)
        try container.encode(additionalMinutes, forKey: .additionalMinutes)
        try container.encode(additionalETAs.map(\.timeIntervalSince1970), forKey: .additionalETAs)
    }

    fileprivate static func decodeUnixDate(_ container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> Date {
        if let value = try? container.decode(Double.self, forKey: key) {
            return Date(timeIntervalSince1970: value)
        }
        return try container.decode(Date.self, forKey: key)
    }

    fileprivate static func decodeUnixDates(_ container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> [Date] {
        if let values = try? container.decode([Double].self, forKey: key) {
            return values.map { Date(timeIntervalSince1970: $0) }
        }
        return (try? container.decode([Date].self, forKey: key)) ?? []
    }
}

public struct ArrivalActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public var stopName: String
        public var subtitle: String
        public var kind: TransportKind
        public var rows: [ArrivalRow]
        public var armillaMinutes: [Int]
        public var alboloteMinutes: [Int]
        public var armillaETAs: [Date]
        public var alboloteETAs: [Date]
        public var metroDirection: DireccionMetro
        public var metroInverted: Bool
        public var preferredLineId: String?
        public var stopNumber: Int?
        public var updatedAt: Date
        public var isOnline: Bool

        public init(
            stopName: String,
            subtitle: String,
            kind: TransportKind,
            rows: [ArrivalRow],
            armillaMinutes: [Int] = [],
            alboloteMinutes: [Int] = [],
            armillaETAs: [Date] = [],
            alboloteETAs: [Date] = [],
            metroDirection: DireccionMetro = .armilla,
            metroInverted: Bool = false,
            preferredLineId: String? = nil,
            stopNumber: Int? = nil,
            updatedAt: Date,
            isOnline: Bool
        ) {
            self.stopName = stopName
            self.subtitle = subtitle
            self.kind = kind
            self.rows = rows
            self.armillaMinutes = armillaMinutes
            self.alboloteMinutes = alboloteMinutes
            self.armillaETAs = armillaETAs
            self.alboloteETAs = alboloteETAs
            self.metroDirection = metroDirection
            self.metroInverted = metroInverted
            self.preferredLineId = preferredLineId
            self.stopNumber = stopNumber
            self.updatedAt = updatedAt
            self.isOnline = isOnline
        }

        public var nextRow: ArrivalRow? { rows.first }

        public var selectedMetroMinutes: [Int] {
            metroDirection == .armilla ? armillaMinutes : alboloteMinutes
        }

        public var selectedMetroETAs: [Date] {
            metroDirection == .armilla ? armillaETAs : alboloteETAs
        }

        public var metroChevronsDown: Bool {
            metroDirection.chevronsPointDown(inverted: metroInverted)
        }

        public var soonestMinutes: Int? {
            switch kind {
            case .bus, .ctagr:
                return rows.flatMap(\.allMinutes).min()
            case .metro:
                return selectedMetroMinutes.min()
            }
        }

        public var soonestETA: Date? {
            switch kind {
            case .bus, .ctagr:
                return rows.flatMap(\.allETAs).min()
            case .metro:
                return selectedMetroETAs.min()
            }
        }

        public var latestETA: Date? {
            switch kind {
            case .bus, .ctagr:
                return rows.flatMap(\.allETAs).max()
            case .metro:
                return (armillaETAs + alboloteETAs).max()
            }
        }

        public var usesBusLayout: Bool { kind != .metro }

        enum CodingKeys: String, CodingKey {
            case stopName, subtitle, kind, rows
            case armillaMinutes, alboloteMinutes, armillaETAs, alboloteETAs, metroDirection, metroInverted
            case preferredLineId, stopNumber, updatedAt, isOnline
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            stopName = try container.decode(String.self, forKey: .stopName)
            subtitle = try container.decode(String.self, forKey: .subtitle)
            kind = try container.decode(TransportKind.self, forKey: .kind)
            rows = try container.decodeIfPresent([ArrivalRow].self, forKey: .rows) ?? []
            armillaMinutes = try container.decodeIfPresent([Int].self, forKey: .armillaMinutes) ?? []
            alboloteMinutes = try container.decodeIfPresent([Int].self, forKey: .alboloteMinutes) ?? []
            armillaETAs = Self.decodeUnixDates(container, forKey: .armillaETAs)
            alboloteETAs = Self.decodeUnixDates(container, forKey: .alboloteETAs)
            metroDirection = try container.decodeIfPresent(DireccionMetro.self, forKey: .metroDirection) ?? .armilla
            metroInverted = try container.decodeIfPresent(Bool.self, forKey: .metroInverted) ?? false
            preferredLineId = try container.decodeIfPresent(String.self, forKey: .preferredLineId)
            stopNumber = try container.decodeIfPresent(Int.self, forKey: .stopNumber)
            updatedAt = Self.decodeUnixDate(container, forKey: .updatedAt) ?? Date()
            isOnline = try container.decodeIfPresent(Bool.self, forKey: .isOnline) ?? true
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(stopName, forKey: .stopName)
            try container.encode(subtitle, forKey: .subtitle)
            try container.encode(kind, forKey: .kind)
            try container.encode(rows, forKey: .rows)
            try container.encode(armillaMinutes, forKey: .armillaMinutes)
            try container.encode(alboloteMinutes, forKey: .alboloteMinutes)
            try container.encode(armillaETAs.map(\.timeIntervalSince1970), forKey: .armillaETAs)
            try container.encode(alboloteETAs.map(\.timeIntervalSince1970), forKey: .alboloteETAs)
            try container.encode(metroDirection, forKey: .metroDirection)
            try container.encode(metroInverted, forKey: .metroInverted)
            try container.encodeIfPresent(preferredLineId, forKey: .preferredLineId)
            try container.encodeIfPresent(stopNumber, forKey: .stopNumber)
            try container.encode(updatedAt.timeIntervalSince1970, forKey: .updatedAt)
            try container.encode(isOnline, forKey: .isOnline)
        }

        private static func decodeUnixDate(_ container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> Date? {
            if let value = try? container.decode(Double.self, forKey: key) {
                return Date(timeIntervalSince1970: value)
            }
            return try? container.decode(Date.self, forKey: key)
        }

        private static func decodeUnixDates(_ container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> [Date] {
            if let values = try? container.decode([Double].self, forKey: key) {
                return values.map { Date(timeIntervalSince1970: $0) }
            }
            return (try? container.decode([Date].self, forKey: key)) ?? []
        }
    }

    public var stopId: String
    public var kind: TransportKind

    public init(stopId: String, kind: TransportKind) {
        self.stopId = stopId
        self.kind = kind
    }
}
