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
    var favoriteCtagrIds: Set<String> = []
    var favoritesOnly = false
    var showCtagr = false
    @Binding var selectedStop: SelectedStop?
    @Binding var position: MapCameraPosition
    var mapKit: MapKitBridge
    var userHeading: Double? = nil

    @State private var spanDelta: Double = 0.04
    @State private var cameraHeading: Double = 0
    @State private var mapSize: CGSize = .zero
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var mapSelection: String?

    var body: some View {
        Map(position: $position, selection: $mapSelection) {
            UserAnnotation {
                UserHeadingPin(headingDegrees: userHeading, mapHeading: cameraHeading)
            }

            if kind == .bus {
                ForEach(visibleBusPolylines) { line in
                    MapPolyline(coordinates: line.points)
                        .stroke(
                            Color(hex: line.colorHex, fallback: .gray).opacity(line.opacity),
                            style: StrokeStyle(lineWidth: line.lineWidth, lineCap: .round, lineJoin: .round)
                        )
                }
                if showCtagr {
                    ForEach(visibleCtagrPolylines) { line in
                        MapPolyline(coordinates: line.points)
                            .stroke(
                                BrandColor.ctagr.opacity(line.opacity),
                                style: StrokeStyle(lineWidth: line.lineWidth, lineCap: .round, lineJoin: .round, dash: [7, 5])
                            )
                    }
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
        .background {
            MapViewHook(bridge: mapKit)
        }
        .onMapCameraChange(frequency: .continuous) { context in
            cameraHeading = context.camera.heading
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            spanDelta = context.region.span.latitudeDelta
            visibleRegion = context.region
            cameraHeading = context.camera.heading
        }
        .onChange(of: selectedStop) { _, stop in
            mapSelection = stop?.id
        }
        .onChange(of: mapSelection) { _, id in
            guard let id, id != selectedStop?.id,
                  let item = visibleStops.first(where: { $0.id == id }) else { return }
            selectedStop = item.stop
        }
        .onChange(of: kind) { _, _ in
            mapSelection = nil
        }
        .background {
            GeometryReader { geo in
                Color.clear
                    .preference(key: MapCanvasSizeKey.self, value: geo.size)
                    .onAppear { mapSize = geo.size }
                    .onChange(of: geo.size) { _, size in mapSize = size }
            }
        }
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
            if showCtagr {
                items.append(contentsOf: ctagrItems)
            }
        case .ctagr:
            items.append(contentsOf: ctagrItems)
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
            case .ctagr(let stop):
                items.append(ctagrItem(stop, coordinate: coordinate))
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

    private var ctagrItems: [StopMapItem] {
        let source = favoritesOnly
            ? store.ctagrStops.filter { favoriteCtagrIds.contains($0.id) }
            : store.ctagrStops
        if !favoritesOnly, !showBusStops {
            var items: [StopMapItem] = source.compactMap { stop in
                guard favoriteCtagrIds.contains(stop.id), let coordinate = stop.coordinate else { return nil }
                return ctagrItem(stop, coordinate: coordinate)
            }
            if case .ctagr(let stop) = selectedStop, let coordinate = stop.coordinate,
               !items.contains(where: { $0.stop.id == SelectedStop.ctagr(stop).id }) {
                items.append(ctagrItem(stop, coordinate: coordinate))
            }
            return items
        }
        return source.compactMap { stop in
            guard let coordinate = stop.coordinate, isCoordinateVisible(coordinate) else {
                if case .ctagr(let selected) = selectedStop, selected.id == stop.id, let coordinate = stop.coordinate {
                    return ctagrItem(stop, coordinate: coordinate)
                }
                return nil
            }
            return ctagrItem(stop, coordinate: coordinate)
        }
    }

    private func ctagrItem(_ stop: ParadaCtagr, coordinate: CLLocationCoordinate2D) -> StopMapItem {
        StopMapItem(
            stop: .ctagr(stop),
            coordinate: coordinate,
            color: BrandColor.ctagr,
            favorite: favoriteCtagrIds.contains(stop.id)
        )
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

    private var visibleCtagrPolylines: [PolylineItem] {
        if favoritesOnly, selectedStop == nil {
            return []
        }
        let selectedLines: Set<String>
        if case .ctagr(let stop) = selectedStop {
            selectedLines = Set(stop.lineas ?? [])
        } else {
            selectedLines = []
        }
        return store.ctagrLineDetails.flatMap { line in
            line.shapes.enumerated().map { index, shape in
                let highlighted = selectedLines.isEmpty ? false : selectedLines.contains(line.id)
                return PolylineItem(
                    id: "ctagr-\(line.id)-\(index)",
                    points: shape.points.map(\.coordinate),
                    colorHex: "15803d",
                    opacity: selectedLines.isEmpty ? 0.45 : (highlighted ? 0.95 : 0.08),
                    lineWidth: selectedLines.isEmpty ? 2.5 : (highlighted ? 5 : 1.5)
                )
            }
        }
        .sorted { $0.opacity < $1.opacity }
    }
}

enum MapViewport {
    static func region(
        centering coordinate: CLLocationCoordinate2D,
        meters: CLLocationDistance,
        mapSize: CGSize,
        topChrome: CGFloat,
        bottomChrome: CGFloat
    ) -> MKCoordinateRegion {
        var region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: meters,
            longitudinalMeters: meters
        )
        return inset(region, mapSize: mapSize, topChrome: topChrome, bottomChrome: bottomChrome)
    }

    static func fitting(
        _ coordinates: [CLLocationCoordinate2D],
        mapSize: CGSize,
        topChrome: CGFloat,
        bottomChrome: CGFloat
    ) -> MKCoordinateRegion? {
        guard let first = coordinates.first else { return nil }
        if coordinates.count == 1 {
            return region(
                centering: first,
                meters: 900,
                mapSize: mapSize,
                topChrome: topChrome,
                bottomChrome: bottomChrome
            )
        }
        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for coordinate in coordinates {
            minLat = min(minLat, coordinate.latitude)
            maxLat = max(maxLat, coordinate.latitude)
            minLon = min(minLon, coordinate.longitude)
            maxLon = max(maxLon, coordinate.longitude)
        }
        var region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(
                latitudeDelta: max((maxLat - minLat) * 1.6, 0.012),
                longitudeDelta: max((maxLon - minLon) * 1.6, 0.012)
            )
        )
        return inset(region, mapSize: mapSize, topChrome: topChrome, bottomChrome: bottomChrome)
    }

    static func inset(
        _ region: MKCoordinateRegion,
        mapSize: CGSize,
        topChrome: CGFloat,
        bottomChrome: CGFloat
    ) -> MKCoordinateRegion {
        let height = mapSize.height
        guard height > 200 else { return region }
        if region.span.latitudeDelta > 1 || region.span.longitudeDelta > 1 {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 37.176, longitude: -3.599),
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )
        }
        // Place the point in the middle of the band between the top bar and the drawer.
        // Do not also apply Map safe-area padding — that would double-shift and pan the map with the sheet.
        let top = min(max(0, topChrome), height * 0.35)
        let bottom = min(max(0, bottomChrome), height * 0.72)
        let fraction = (bottom - top) / (2 * height)
        var region = region
        region.center.latitude -= region.span.latitudeDelta * Double(fraction)
        return region
    }
}

struct MapCanvasSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next.width > 0, next.height > 0 { value = next }
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
                .fill(kind == .ctagr && !selected ? Color.white : color)
                .frame(width: dotSize, height: dotSize)
                .overlay {
                    Circle().strokeBorder(
                        kind == .ctagr && !selected ? color : Color.white,
                        lineWidth: selected ? 3 : (kind == .ctagr ? 1.5 : 1)
                    )
                }
                .shadow(color: selected ? color.opacity(0.6) : .clear, radius: 6)
                .opacity(dimmed ? 0.28 : 1)
            if favorite {
                Image(systemName: "star.fill")
                    .font(.system(size: selected ? 8 : 7, weight: .bold))
                    .foregroundStyle(kind == .ctagr && !selected ? color : Color.white)
            }
        }
        .frame(width: 28, height: 28)
        .contentShape(Circle())
    }
}

private struct UserHeadingPin: View {
    var headingDegrees: Double?
    var mapHeading: Double

    private let blue = Color(red: 0.04, green: 0.52, blue: 1)

    var body: some View {
        ZStack {
            if let headingDegrees {
                HeadingCone()
                    .fill(
                        LinearGradient(
                            colors: [blue.opacity(0.42), blue.opacity(0.08)],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(width: 72, height: 72)
                    .rotationEffect(.degrees(headingDegrees - mapHeading))
                    .animation(.easeOut(duration: 0.16), value: headingDegrees)
            }

            Circle()
                .fill(.white)
                .frame(width: 24, height: 24)
                .shadow(color: .black.opacity(0.22), radius: 3, y: 1)

            Circle()
                .fill(blue)
                .frame(width: 16, height: 16)
        }
        .frame(width: 72, height: 72)
        .allowsHitTesting(false)
        .accessibilityLabel("Tu ubicación")
        .accessibilityValue(headingDegrees == nil ? "Sin orientación" : "Con orientación")
    }
}

private struct HeadingCone: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        path.move(to: center)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(-55 - 90),
            endAngle: .degrees(55 - 90),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}
