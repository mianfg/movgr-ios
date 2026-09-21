import Foundation

public enum APIError: Error {
    case invalidURL
    case http(Int)
}

public actor APIClient {
    public static let shared = APIClient()
    public static let baseURL = URL(string: "https://movgr.apis.mianfg.me")!

    private let session: URLSession
    private let decoder: JSONDecoder

    public init(session: URLSession = .shared) {
        self.session = session
        self.decoder = JSONDecoder()
    }

    public func getBusStops() async throws -> [ParadaBus] {
        try await get("/bus/paradas")
    }

    public func getBusStop(_ id: Int) async throws -> ParadaBus {
        try await get("/bus/parada/\(id)")
    }

    public func getBusArrivals(_ stopId: Int) async throws -> LlegadasBus {
        try await get("/bus/llegadas/\(stopId)")
    }

    public func getBusLines() async throws -> [LineaBus] {
        try await get("/bus/lineas")
    }

    public func getBusLineDetail(_ id: String) async throws -> LineaBusDetail {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        return try await get("/bus/lineas/\(encoded)")
    }

    public func getMetroStops() async throws -> [ParadaMetro] {
        try await get("/metro/paradas")
    }

    public func getMetroArrivals() async throws -> [LlegadasMetro] {
        try await get("/metro/llegadas")
    }

    public func getMetroArrivals(stopId: String) async throws -> LlegadasMetro {
        let encoded = stopId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? stopId
        return try await get("/metro/llegadas/\(encoded)")
    }

    public func getMetroLine() async throws -> LineaMetroDetail {
        try await get("/metro/lineas")
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        var lastError: Error = APIError.invalidURL
        for attempt in 0..<3 {
            do {
                return try await getOnce(path)
            } catch {
                lastError = error
                if case APIError.http(let code) = error, (400..<500).contains(code), code != 429 {
                    throw error
                }
                if attempt < 2 {
                    try await Task.sleep(for: .milliseconds(400 * (attempt + 1)))
                }
            }
        }
        throw lastError
    }

    private func getOnce<T: Decodable>(_ path: String) async throws -> T {
        guard let url = URL(string: path, relativeTo: Self.baseURL) else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw APIError.http(http.statusCode)
        }
        return try decoder.decode(T.self, from: data)
    }
}
