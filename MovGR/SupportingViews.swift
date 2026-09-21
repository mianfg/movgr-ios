import CoreLocation
import SwiftUI
import UIKit
import MovGRShared

enum TransportSearchScope: String, Identifiable, Hashable {
    case all
    case bus
    case metro

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "Buscar"
        case .bus: "Parada de bus"
        case .metro: "Estación de metro"
        }
    }

    var prompt: String {
        switch self {
        case .all: "Parada, estación o número"
        case .bus: "Nombre o número"
        case .metro: "Nombre de estación"
        }
    }
}

private enum SearchKindFilter: String, Hashable, CaseIterable {
    case all
    case bus
    case metro

    var title: String {
        switch self {
        case .all: "Todos"
        case .bus: "Bus"
        case .metro: "Metro"
        }
    }
}

struct TransportSearchSheet: View {
    var store: TransportStore
    var settings: AppSettings
    var scope: TransportSearchScope = .all
    var onSelect: (SelectedStop) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var kindFilter: SearchKindFilter = .all
    @State private var favoritesOnly = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterBar
                List {
                    if hasResults {
                        ForEach(sectionKinds, id: \.self) { kind in
                            if kind == .metro, showingMetro {
                                if !favoritesOnly, normalizedQuery.isEmpty, !favoriteMetroMatches.isEmpty {
                                    Section("Estaciones favoritas") {
                                        ForEach(favoriteMetroMatches) { stop in
                                            metroRow(stop)
                                        }
                                    }
                                }
                                if !metroMatches.isEmpty {
                                    Section(metroSectionTitle) {
                                        ForEach(metroMatches) { stop in
                                            metroRow(stop)
                                        }
                                    }
                                }
                            } else if kind == .bus, showingBus {
                                if !favoritesOnly, normalizedQuery.isEmpty, !favoriteBusMatches.isEmpty {
                                    Section("Paradas favoritas") {
                                        ForEach(favoriteBusMatches) { stop in
                                            busRow(stop, favorite: true)
                                        }
                                    }
                                }
                                if !busMatches.isEmpty {
                                    Section(busSectionTitle) {
                                        ForEach(busMatches) { stop in
                                            busRow(stop, favorite: settings.isFavorite(stop))
                                        }
                                    }
                                }
                            }
                        }
                    } else {
                        ContentUnavailableView(
                            emptyTitle,
                            systemImage: favoritesOnly ? "star" : "magnifyingglass"
                        )
                    }
                }
            }
            .navigationTitle(scope.title)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: scope.prompt)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
        }
        .onAppear {
            switch scope {
            case .all: kindFilter = .all
            case .bus: kindFilter = .bus
            case .metro: kindFilter = .metro
            }
        }
    }

    private var filterBar: some View {
        HStack(spacing: 10) {
            if scope == .all {
                SlidingChoicePicker(
                    selection: $kindFilter,
                    options: SearchKindFilter.allCases,
                    effectID: "searchKindFilter",
                    compact: true,
                    usesGlass: false
                ) { value in
                    Text(value.title)
                        .font(.subheadline.weight(.semibold))
                }
            } else {
                Toggle(isOn: $favoritesOnly) {
                    Label("Solo favoritos", systemImage: favoritesOnly ? "star.fill" : "star")
                }
                .tint(.yellow)
            }

            if scope == .all {
                Button {
                    withAnimation(.smooth(duration: 0.28)) {
                        favoritesOnly.toggle()
                    }
                } label: {
                    Image(systemName: favoritesOnly ? "star.fill" : "star")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(favoritesOnly ? Color.yellow : Color.secondary)
                        .frame(width: 44, height: 44)
                        .background(.fill.tertiary, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(favoritesOnly ? "Mostrar todos los resultados" : "Solo favoritos")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var sectionKinds: [TransportKind] {
        switch scope {
        case .all: settings.transportOrder
        case .bus: [.bus]
        case .metro: [.metro]
        }
    }

    private var showingBus: Bool {
        scope == .bus || (scope == .all && (kindFilter == .all || kindFilter == .bus))
    }

    private var showingMetro: Bool {
        scope == .metro || (scope == .all && (kindFilter == .all || kindFilter == .metro))
    }

    private var busSectionTitle: String {
        if favoritesOnly { return "Paradas favoritas" }
        if normalizedQuery.isEmpty, !favoriteBusMatches.isEmpty { return "Paradas de bus" }
        return showingMetro ? "Bus" : "Paradas"
    }

    private var metroSectionTitle: String {
        if favoritesOnly { return "Estaciones favoritas" }
        if normalizedQuery.isEmpty, !favoriteMetroMatches.isEmpty { return "Estaciones" }
        return showingBus ? "Metro" : "Estaciones"
    }

    private var hasResults: Bool {
        (showingMetro && (!metroMatches.isEmpty || !favoriteMetroMatches.isEmpty))
            || (showingBus && (!busMatches.isEmpty || !favoriteBusMatches.isEmpty))
    }

    private var emptyTitle: String {
        if favoritesOnly {
            if showingBus, showingMetro { return "Sin favoritos" }
            if showingMetro { return "Sin estaciones favoritas" }
            return "Sin paradas favoritas"
        }
        return "Sin resultados"
    }

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var favoriteBusMatches: [ParadaBus] {
        guard showingBus, !favoritesOnly else { return [] }
        return filterBus(settings.favoriteBusStops, limitUnfiltered: false)
    }

    private var favoriteMetroMatches: [ParadaMetro] {
        guard showingMetro, !favoritesOnly else { return [] }
        return filterMetro(settings.favoriteMetroStops)
    }

    private var busMatches: [ParadaBus] {
        guard showingBus else { return [] }
        if favoritesOnly {
            return filterBus(settings.favoriteBusStops, limitUnfiltered: false)
        }
        let favoriteIds = settings.favoriteStopIds
        if normalizedQuery.isEmpty {
            return Array(store.busStops.filter { !favoriteIds.contains($0.id) }.prefix(30))
        }
        return filterBus(store.busStops, limitUnfiltered: false)
    }

    private var metroMatches: [ParadaMetro] {
        guard showingMetro else { return [] }
        if favoritesOnly {
            return filterMetro(settings.favoriteMetroStops)
        }
        let favoriteIds = settings.favoriteMetroIds
        let source = settings.metroInverted ? Array(store.metroStops.reversed()) : store.metroStops
        if normalizedQuery.isEmpty {
            return source.filter { !favoriteIds.contains($0.id) }
        }
        return filterMetro(source)
    }

    private func filterMetro(_ stops: [ParadaMetro]) -> [ParadaMetro] {
        let q = normalizedQuery
        if q.isEmpty { return stops }
        return stops.filter { $0.nombre.lowercased().contains(q) }
    }

    private func filterBus(_ stops: [ParadaBus], limitUnfiltered: Bool = true) -> [ParadaBus] {
        let q = normalizedQuery
        let favoriteIds = settings.favoriteStopIds
        if q.isEmpty {
            return limitUnfiltered ? Array(stops.prefix(30)) : stops
        }
        return stops.filter { $0.nombre.lowercased().contains(q) || String($0.id).contains(q) }
            .sorted { lhs, rhs in
                let leftFav = favoriteIds.contains(lhs.id)
                let rightFav = favoriteIds.contains(rhs.id)
                if leftFav != rightFav { return leftFav }
                let leftExact = String(lhs.id) == q
                let rightExact = String(rhs.id) == q
                if leftExact != rightExact { return leftExact }
                return lhs.id < rhs.id
            }
    }

    private func metroRow(_ stop: ParadaMetro) -> some View {
        Button {
            onSelect(.metro(stop))
            dismiss()
        } label: {
            HStack(spacing: 10) {
                TramFrontGlyph()
                    .frame(width: 16, height: 16)
                Text(stop.nombre)
                Spacer()
                if settings.isFavorite(stop) {
                    Image(systemName: "star.fill").foregroundStyle(.yellow)
                }
            }
        }
        .foregroundStyle(.primary)
    }

    private func busRow(_ stop: ParadaBus, favorite: Bool) -> some View {
        Button {
            onSelect(.bus(stop))
            dismiss()
        } label: {
            StopIdentityRow(idText: "\(stop.id)", title: stop.nombre, favorite: favorite)
        }
        .foregroundStyle(.primary)
    }
}

struct SettingsView: View {
    @Bindable var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @Environment(UserLocationProvider.self) private var location

    var body: some View {
        NavigationStack {
            List {
                Section("Mapa") {
                    ForEach(MapBaseStyle.allCases) { style in
                        Button {
                            settings.mapStyle = style
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: style.symbol)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(style.title)
                                    Text(style.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if settings.mapStyle == style {
                                    Image(systemName: "checkmark").foregroundStyle(.primary)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                    Toggle("Mostrar tráfico", isOn: $settings.showTraffic)
                        .tint(.green)
                        .disabled(settings.mapStyle == .satellite)
                }

                Section("Inicio") {
                    SlidingChoicePicker(
                        selection: $settings.preferredTransport,
                        options: settings.transportOrder,
                        effectID: "preferredTransport",
                        compact: true,
                        usesGlass: false
                    ) { value in
                        Group {
                            if value == .bus {
                                BusFrontGlyph()
                            } else {
                                TramFrontGlyph()
                            }
                        }
                        .frame(width: 22, height: 22)
                        .accessibilityLabel(value.title)
                    }
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                    .animation(.smooth(duration: 0.42, extraBounce: 0.04), value: settings.preferredTransport)
                    Text("El que elijas aparece primero en las búsquedas y en recientes.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Metro") {
                    Toggle("Invertir orden de estaciones", isOn: $settings.metroInverted)
                        .tint(.green)
                    Text("Cambia si la línea se muestra de Armilla a Albolote o al revés.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Live Activity") {
                    Toggle("Mostrar en pantalla de bloqueo", isOn: $settings.liveActivityEnabled)
                        .tint(.green)
                    Text("Si está activada, al consultar una parada o estación se muestran las próximas llegadas en la pantalla de bloqueo y en Dynamic Island.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Ajustes")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

enum BottomCardSize: Equatable {
    case small, big
}

@Observable
final class UserLocationProvider: NSObject, CLLocationManagerDelegate {
    var authorizationStatus: CLAuthorizationStatus
    var location: CLLocation?

    private let manager: CLLocationManager

    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    override init() {
        manager = CLLocationManager()
        authorizationStatus = .notDetermined
        super.init()
        authorizationStatus = manager.authorizationStatus
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        if isAuthorized {
            manager.startUpdatingLocation()
        }
    }

    func requestAccess() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        default:
            manager.startUpdatingLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if isAuthorized {
            manager.startUpdatingLocation()
        } else {
            manager.stopUpdatingLocation()
            location = nil
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        location = locations.last
    }
}

struct SheetQueryField: View {
    @Binding var query: String
    var prompt: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(prompt, text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Borrar búsqueda")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct HomeBrowseView: View {
    var settings: AppSettings
    var store: TransportStore
    var location: UserLocationProvider
    var onSelect: (SelectedStop) -> Void
    var onRequestLocation: () -> Void

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 18) {
            ForEach(orderedSections, id: \.self) { section in
                switch section {
                case .recents:
                    recentsSection
                case .nearby:
                    nearbySection
                }
            }
        }
    }

    private enum SectionKind: Hashable {
        case recents
        case nearby
    }

    private var orderedSections: [SectionKind] {
        settings.homeListOrder == .nearbyFirst ? [.nearby, .recents] : [.recents, .nearby]
    }

    private var recentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recientes")
                .font(.subheadline.weight(.semibold))
            if settings.recentStops.isEmpty {
                Text("Aquí aparecerán las paradas y estaciones que consultes.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                ForEach(settings.recentStops) { stop in
                    HomeStopRow(
                        stop: stop,
                        favorite: isFavorite(stop),
                        distance: nil,
                        onSelect: { onSelect(stop) }
                    )
                }
            }
        }
    }

    private var nearbySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cercanas")
                .font(.subheadline.weight(.semibold))
            if !location.isAuthorized {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Activa la ubicación para ver paradas y estaciones cerca de ti.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Activar ubicación", action: onRequestLocation)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                .padding(.vertical, 4)
            } else if nearbyItems.isEmpty {
                Text("No hay paradas cerca ahora mismo.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                ForEach(nearbyItems, id: \.stop.id) { item in
                    HomeStopRow(
                        stop: item.stop,
                        favorite: isFavorite(item.stop),
                        distance: item.distance,
                        onSelect: { onSelect(item.stop) }
                    )
                }
            }
        }
    }

    private var nearbyItems: [(stop: SelectedStop, distance: CLLocationDistance)] {
        guard let userLocation = location.location else { return [] }
        var items: [(SelectedStop, CLLocationDistance)] = []
        for stop in store.busStops {
            guard let coordinate = stop.coordinate else { continue }
            let distance = userLocation.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
            if distance <= 2000 {
                items.append((.bus(stop), distance))
            }
        }
        for stop in store.metroStops {
            guard let coordinate = stop.coordinate else { continue }
            let distance = userLocation.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
            if distance <= 2000 {
                items.append((.metro(stop), distance))
            }
        }
        return items.sorted { $0.1 < $1.1 }.prefix(8).map { (stop: $0.0, distance: $0.1) }
    }

    private func isFavorite(_ stop: SelectedStop) -> Bool {
        switch stop {
        case .bus(let parada): settings.isFavorite(parada)
        case .metro(let parada): settings.isFavorite(parada)
        }
    }
}

private struct HomeStopRow: View {
    var stop: SelectedStop
    var favorite: Bool
    var distance: CLLocationDistance?
    var onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                Group {
                    if stop.kind == .bus {
                        BusFrontGlyph()
                    } else {
                        TramFrontGlyph()
                    }
                }
                .frame(width: 16, height: 16)

                if case .bus(let parada) = stop {
                    StopNumberPill(number: parada.id, compact: true)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(stop.name)
                        .font(.subheadline)
                        .lineLimit(1)
                    if let distance {
                        Text(Self.formatted(distance))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)

                if favorite {
                    Image(systemName: "star.fill").foregroundStyle(.yellow)
                }
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

    private static func formatted(_ meters: CLLocationDistance) -> String {
        if meters < 1000 {
            return "\(Int(meters.rounded())) m"
        }
        let value = (meters / 1000).formatted(.number.precision(.fractionLength(1)))
        return "\(value) km"
    }
}

struct CombinedSearchResults: View {
    var store: TransportStore
    var settings: AppSettings
    var query: String
    var onSelect: (SelectedStop) -> Void

    var body: some View {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let bus = filterBus(q)
        let metro = filterMetro(q)

        if bus.isEmpty && metro.isEmpty {
            ContentUnavailableView("Sin resultados", systemImage: "magnifyingglass")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
        } else {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(settings.transportOrder, id: \.self) { kind in
                    if kind == .bus, !bus.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Bus")
                                .font(.subheadline.weight(.semibold))
                            ForEach(bus) { stop in
                                HomeStopRow(
                                    stop: .bus(stop),
                                    favorite: settings.isFavorite(stop),
                                    distance: nil,
                                    onSelect: { onSelect(.bus(stop)) }
                                )
                            }
                        }
                    } else if kind == .metro, !metro.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Metro")
                                .font(.subheadline.weight(.semibold))
                            ForEach(metro) { stop in
                                HomeStopRow(
                                    stop: .metro(stop),
                                    favorite: settings.isFavorite(stop),
                                    distance: nil,
                                    onSelect: { onSelect(.metro(stop)) }
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    private func filterBus(_ q: String) -> [ParadaBus] {
        let favoriteIds = settings.favoriteStopIds
        return store.busStops
            .filter { $0.nombre.lowercased().contains(q) || String($0.id).contains(q) }
            .sorted { lhs, rhs in
                let leftFav = favoriteIds.contains(lhs.id)
                let rightFav = favoriteIds.contains(rhs.id)
                if leftFav != rightFav { return leftFav }
                return lhs.id < rhs.id
            }
    }

    private func filterMetro(_ q: String) -> [ParadaMetro] {
        store.metroStops.filter { $0.nombre.lowercased().contains(q) }
    }
}
