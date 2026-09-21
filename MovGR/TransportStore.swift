import Foundation
import MovGRShared

@Observable
@MainActor
final class TransportStore {
    var busStops: [ParadaBus] = []
    var metroStops: [ParadaMetro] = []
    var busLines: [LineaBus] = []
    var busLineDetails: [LineaBusDetail] = []
    var metroLine: LineaMetroDetail?
    var isLoading = false
    var lastError: String?

    var busLineMap: [String: LineaBus] {
        Dictionary(uniqueKeysWithValues: busLines.map { ($0.id, $0) })
    }

    func loadIfNeeded() async {
        if !busStops.isEmpty && !metroStops.isEmpty { return }
        await refresh()
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let busStopsTask = APIClient.shared.getBusStops()
            async let metroStopsTask = APIClient.shared.getMetroStops()
            async let busLinesTask = APIClient.shared.getBusLines()
            async let metroLineTask = APIClient.shared.getMetroLine()
            let (stops, metro, lines, metroDetail) = try await (busStopsTask, metroStopsTask, busLinesTask, metroLineTask)
            busStops = stops
            metroStops = metro
            busLines = lines
            metroLine = metroDetail
            lastError = nil
            await loadBusLineDetails(ids: lines.map(\.id))
        } catch {
            lastError = "No se pudo actualizar el mapa"
        }
    }

    private func loadBusLineDetails(ids: [String]) async {
        await withTaskGroup(of: LineaBusDetail?.self) { group in
            for id in ids {
                group.addTask {
                    try? await APIClient.shared.getBusLineDetail(id)
                }
            }
            var details: [LineaBusDetail] = []
            for await detail in group {
                if let detail { details.append(detail) }
            }
            busLineDetails = details
        }
    }

    func color(forBusLine id: String) -> String? {
        busLineMap[id]?.color
    }

    func textColor(forBusLine id: String) -> String? {
        busLineMap[id]?.textColor
    }

    func lineIds(for stop: ParadaBus) -> [String] {
        if let lineas = stop.lineas, !lineas.isEmpty {
            return lineas
        }
        return busStops.first(where: { $0.id == stop.id })?.lineas ?? []
    }
}
