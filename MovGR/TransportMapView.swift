import MapKit
import SwiftUI
import MovGRShared

struct TransportMapView: View {
    var kind: TransportKind
    var store: TransportStore
    var mapStyle: MapBaseStyle = .standard
    var showTraffic = false
    var favoriteStopIds: Set<Int> = []
    var favoriteMetroIds: Set<String> = []
    var favoritesOnly = false
    @Binding var selectedStop: SelectedStop?
    @Binding var position: MapCameraPosition
    var topChromeHeight: CGFloat = 0
    var bottomChromeHeight: CGFloat = 0

    @State private var spanDelta: Double = 0.04
    @State private var mapSize: CGSize = .zero
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var mapSelection: String?

    var body: some View {
        Map(position: $position, selection: $mapSelection) {
            UserAnnotation()

            if kind == .bus {
                ForEach(visibleBusPolylines) { line in
                    MapPolyline(coordinates: line.points)
                        .stroke(
                            Color(hex: line.colorHex, fallback: .gray).opacity(line.opacity),
                            style: StrokeStyle(lineWidth: line.lineWidth, lineCap: .round, lineJoin: .round)
                        )
                }
            } else if let metro = store.metroLine {
                ForEach(Array(metro.shapes.enumerated()), id: \.offset) { _, shape in
                    MapPolyline(coordinates: shape.points.map(\.coordinate))
                        .stroke(BrandColor.metro.opacity(0.9), lineWidth: 4)
                }
            }

            ForEach(visibleStops) { item in
                Annotation(item.stop.name, coordinate: item.coordinate, anchor: .center) {
                    StopDot(
                        color: item.color,
                        selected: selectedStop?.id == item.stop.id,
                        dimmed: selectedStop != nil && selectedStop?.id != item.stop.id,
                        kind: item.stop.kind,
                        favorite: item.favorite
                    )
                    .onTapGesture {
                        selectedStop = item.stop
                    }
                }
                .tag(item.id)
            }
        }
        .mapStyle(resolvedMapStyle)
        .mapControlVisibility(.hidden)
        .onMapCameraChange(frequency: .onEnd) { context in
            spanDelta = context.region.span.latitudeDelta
            visibleRegion = context.region
        }
        .onChange(of: selectedStop) { _, stop in
            mapSelection = stop?.id
            guard let coordinate = stop?.coordinate else { return }
            recenter(on: coordinate)
        }
        .onChange(of: mapSelection) { _, id in
            guard let id, id != selectedStop?.id,
                  let item = visibleStops.first(where: { $0.id == id }) else { return }
            selectedStop = item.stop
        }
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { mapSize = geo.size }
                    .onChange(of: geo.size) { _, size in mapSize = size }
            }
        }
        .onChange(of: kind) { _, newKind in
            mapSelection = nil
            withAnimation {
                if newKind == .metro, let region = Self.metroRegion(from: store.metroStops) {
                    position = .region(region)
                } else {
                    position = .region(
                        MKCoordinateRegion(
                            center: CLLocationCoordinate2D(latitude: 37.176, longitude: -3.599),
                            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                        )
                    )
                }
            }
        }
    }

    private func recenter(on coordinate: CLLocationCoordinate2D) {
        withAnimation(.easeInOut(duration: 0.35)) {
            position = .region(visibleRegion(centering: coordinate))
        }
    }

    /// Shifts the camera south so the stop sits in the map area that is not covered by chrome.
    private func visibleRegion(centering coordinate: CLLocationCoordinate2D, latitudinalMeters: CLLocationDistance = 650) -> MKCoordinateRegion {
        var region = MKCoordinateRegion(center: coordinate, latitudinalMeters: latitudinalMeters, longitudinalMeters: latitudinalMeters)
        let height = mapSize.height
        guard height > 0 else { return region }
        let visualOffset = (bottomChromeHeight - topChromeHeight) / 2
        let fraction = visualOffset / height
        region.center.latitude -= region.span.latitudeDelta * Double(fraction)
        return region
    }

    private var resolvedMapStyle: MapStyle {
        switch mapStyle {
        case .standard:
            .standard(elevation: .realistic, pointsOfInterest: .excludingAll, showsTraffic: showTraffic)
        case .hybrid:
            .hybrid(elevation: .realistic, pointsOfInterest: .excludingAll, showsTraffic: showTraffic)
        case .satellite:
            .imagery(elevation: .realistic)
        }
    }

    private static func metroRegion(from stops: [ParadaMetro]) -> MKCoordinateRegion? {
        let coords = stops.compactMap(\.coordinate)
        guard let first = coords.first else { return nil }
        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for coord in coords {
            minLat = min(minLat, coord.latitude)
            maxLat = max(maxLat, coord.latitude)
            minLon = min(minLon, coord.longitude)
            maxLon = max(maxLon, coord.longitude)
        }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        return MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: (maxLat - minLat) * 1.4 + 0.01, longitudeDelta: (maxLon - minLon) * 1.4 + 0.01)
        )
    }

    private var showBusStops: Bool {
        spanDelta < 0.045 || selectedStop != nil
    }

    private func isCoordinateVisible(_ coordinate: CLLocationCoordinate2D) -> Bool {
        guard let region = visibleRegion else { return true }
        let latPad = region.span.latitudeDelta * 0.7
        let lonPad = region.span.longitudeDelta * 0.7
        return abs(coordinate.latitude - region.center.latitude) <= latPad
            && abs(coordinate.longitude - region.center.longitude) <= lonPad
    }

    private var visibleStops: [StopMapItem] {
        var items: [StopMapItem] = []
        switch kind {
        case .metro:
            items.append(contentsOf: metroItems)
        case .bus:
            items.append(contentsOf: busItems)
        }
        if let selectedStop, let coordinate = selectedStop.coordinate,
           !items.contains(where: { $0.stop.id == selectedStop.id }) {
            switch selectedStop {
            case .bus(let stop):
                items.append(busItem(stop, coordinate: coordinate))
            case .metro(let stop):
                items.append(
                    StopMapItem(
                        stop: .metro(stop),
                        coordinate: coordinate,
                        color: BrandColor.metro,
                        favorite: favoriteMetroIds.contains(stop.id)
                    )
                )
            }
        }
        return items
    }

    private var metroItems: [StopMapItem] {
        let source = favoritesOnly
            ? store.metroStops.filter { favoriteMetroIds.contains($0.id) }
            : store.metroStops
        return source.compactMap { stop in
            guard let coordinate = stop.coordinate else { return nil }
            return StopMapItem(
                stop: .metro(stop),
                coordinate: coordinate,
                color: BrandColor.metro,
                favorite: favoriteMetroIds.contains(stop.id)
            )
        }
    }

    private var busItems: [StopMapItem] {
        let source = favoritesOnly
            ? store.busStops.filter { favoriteStopIds.contains($0.id) }
            : store.busStops
        if !favoritesOnly, !showBusStops {
            var items: [StopMapItem] = source.compactMap { stop in
                guard favoriteStopIds.contains(stop.id), let coordinate = stop.coordinate else { return nil }
                return busItem(stop, coordinate: coordinate)
            }
            if case .bus(let stop) = selectedStop, let coordinate = stop.coordinate,
               !items.contains(where: { $0.stop.id == SelectedStop.bus(stop).id }) {
                items.append(busItem(stop, coordinate: coordinate))
            }
            return items
        }
        return source.compactMap { stop in
            guard let coordinate = stop.coordinate, isCoordinateVisible(coordinate) else {
                if case .bus(let selected) = selectedStop, selected.id == stop.id, let coordinate = stop.coordinate {
                    return busItem(stop, coordinate: coordinate)
                }
                return nil
            }
            return busItem(stop, coordinate: coordinate)
        }
    }

    private func busItem(_ stop: ParadaBus, coordinate: CLLocationCoordinate2D) -> StopMapItem {
        StopMapItem(
            stop: .bus(stop),
            coordinate: coordinate,
            color: Color(hex: store.color(forBusLine: stop.lineas?.first ?? ""), fallback: .gray),
            favorite: favoriteStopIds.contains(stop.id)
        )
    }

    private var visibleBusPolylines: [PolylineItem] {
        if favoritesOnly, selectedStop == nil {
            return []
        }
        let selectedLines: Set<String>
        if case .bus(let stop) = selectedStop {
            let ids = store.lineIds(for: stop)
            selectedLines = Set(ids)
        } else {
            selectedLines = []
        }
        let items = store.busLineDetails.flatMap { line in
            line.shapes.enumerated().map { index, shape in
                let highlighted = selectedLines.isEmpty ? false : selectedLines.contains(line.id)
                return PolylineItem(
                    id: "\(line.id)-\(index)",
                    points: shape.points.map(\.coordinate),
                    colorHex: line.color,
                    opacity: selectedLines.isEmpty ? 0.72 : (highlighted ? 0.95 : 0.12),
                    lineWidth: selectedLines.isEmpty ? 3 : (highlighted ? 6 : 2)
                )
            }
        }
        return items.sorted { $0.opacity < $1.opacity }
    }
}

private struct StopMapItem: Identifiable {
    var stop: SelectedStop
    var coordinate: CLLocationCoordinate2D
    var color: Color
    var favorite: Bool
    var id: String { stop.id }
}

private struct PolylineItem: Identifiable {
    var id: String
    var points: [CLLocationCoordinate2D]
    var colorHex: String?
    var opacity: Double
    var lineWidth: CGFloat
}

private struct StopDot: View {
    var color: Color
    var selected: Bool
    var dimmed: Bool
    var kind: TransportKind
    var favorite = false

    private var dotSize: CGFloat {
        if selected { return 16 }
        if kind == .metro { return 12 }
        return favorite ? 14 : 10
    }

    var body: some View {
        ZStack {
            if selected {
                Circle()
                    .fill(color.opacity(0.25))
                    .frame(width: 28, height: 28)
            }
            Circle()
                .fill(color)
                .frame(width: dotSize, height: dotSize)
                .overlay {
                    Circle().strokeBorder(.white, lineWidth: selected ? 3 : 1)
                }
                .shadow(color: selected ? color.opacity(0.6) : .clear, radius: 6)
                .opacity(dimmed ? 0.28 : 1)
            if favorite {
                Image(systemName: "star.fill")
                    .font(.system(size: selected ? 8 : 7, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 28, height: 28)
        .contentShape(Circle())
    }
}
