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

struct TransportSearchSheet: View {
    var store: TransportStore
    var settings: AppSettings
    var scope: TransportSearchScope = .all
    var onSelect: (SelectedStop) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(UserLocationProvider.self) private var location
    @State private var query = ""
    @State private var favoritesOnly = false

    var body: some View {
        NavigationStack {
            List {
                if isSearching {
                    searchResults
                } else {
                    ForEach(settings.searchBrowseOrder) { section in
                        browseSection(section)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(scope.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                searchHeader
            }
        }
        .onAppear {
            if location.isAuthorized {
                location.requestAccess()
            }
        }
        .onChange(of: query) { _, value in
            if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                favoritesOnly = false
            }
        }
    }

    private var isSearching: Bool {
        !normalizedQuery.isEmpty
    }

    private var searchHeader: some View {
        HStack(spacing: 10) {
            SheetQueryField(query: $query, prompt: scope.prompt)

            if isSearching {
                Button {
                    withAnimation(.smooth(duration: 0.28)) {
                        favoritesOnly.toggle()
                    }
                } label: {
                    Image(systemName: favoritesOnly ? "star.fill" : "star")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(favoritesOnly ? Color.yellow : Color.primary)
                        .frame(width: 44, height: 44)
                        .background(.fill.tertiary, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(favoritesOnly ? "Mostrar todos los resultados" : "Solo favoritos")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    @ViewBuilder
    private func browseSection(_ section: SearchBrowseSection) -> some View {
        let expanded = !settings.isSearchSectionCollapsed(section)
        Section {
            if expanded {
                switch section {
                case .favorites:
                    favoritesContent
                case .recents:
                    recentsContent
                case .nearby:
                    nearbyContent
                }
            }
        } header: {
            Button {
                withAnimation(.smooth(duration: 0.28)) {
                    settings.toggleSearchSectionCollapsed(section)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: section.symbolName)
                    Text(section.title)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expanded ? 0 : -90))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .textCase(nil)
            .accessibilityLabel(section.title)
            .accessibilityHint(expanded ? "Ocultar lista" : "Mostrar lista")
        }
    }

    @ViewBuilder
    private var favoritesContent: some View {
        if scopedFavorites.isEmpty {
            Text("Marca paradas con la estrella para verlas aquí.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            ForEach(scopedFavorites) { stop in
                recentRow(stop)
            }
        }
    }

    @ViewBuilder
    private var recentsContent: some View {
        if scopedRecents.isEmpty {
            Text("Las paradas que consultes aparecerán aquí.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            ForEach(scopedRecents) { stop in
                recentRow(stop)
            }
        }
    }

    @ViewBuilder
    private var nearbyContent: some View {
        if !location.isAuthorized {
            VStack(alignment: .leading, spacing: 8) {
                Text("Activa la ubicación para ver paradas cerca de ti.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Activar ubicación") {
                    location.requestAccess()
                }
            }
        } else if nearbyItems.isEmpty {
            Text("No hay paradas cerca ahora mismo.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            ForEach(nearbyItems, id: \.stop.id) { item in
                nearbyRow(item.stop, distance: item.distance)
            }
        }
    }

    private var scopedFavorites: [SelectedStop] {
        var items: [SelectedStop] = []
        for kind in settings.transportOrder {
            switch kind {
            case .bus where showingBus:
                items.append(contentsOf: settings.favoriteBusStops.map { .bus($0) })
                if settings.ctagrEnabled {
                    items.append(contentsOf: settings.favoriteCtagrStops.map { .ctagr($0) })
                }
            case .metro where showingMetro:
                items.append(contentsOf: settings.favoriteMetroStops.map { .metro($0) })
            default:
                break
            }
        }
        return items
    }

    @ViewBuilder
    private var searchResults: some View {
        if !hasResults {
            ContentUnavailableView(
                emptyTitle,
                systemImage: favoritesOnly ? "star" : "magnifyingglass"
            )
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } else {
            if showingBus, !busMatches.isEmpty {
                Section(showingMetro || showingCtagr ? "Bus urbano" : "Paradas") {
                    ForEach(busMatches) { stop in
                        busRow(stop, favorite: settings.isFavorite(stop))
                    }
                }
            }
            if showingCtagr, !ctagrMatches.isEmpty {
                Section("Consorcio") {
                    ForEach(ctagrMatches) { stop in
                        ctagrRow(stop)
                    }
                }
            }
            if showingMetro, !metroMatches.isEmpty {
                Section(showingBus ? "Metro" : "Estaciones") {
                    ForEach(metroMatches) { stop in
                        metroRow(stop)
                    }
                }
            }
        }
    }

    private var showingBus: Bool {
        scope == .bus || scope == .all
    }

    private var showingMetro: Bool {
        scope == .metro || scope == .all
    }

    private var showingCtagr: Bool {
        settings.ctagrEnabled && (scope == .bus || scope == .all)
    }

    private var hasResults: Bool {
        (showingBus && !busMatches.isEmpty) || (showingCtagr && !ctagrMatches.isEmpty) || (showingMetro && !metroMatches.isEmpty)
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

    private var scopedRecents: [SelectedStop] {
        settings.recentStops.filter { matchesScope($0) }
    }

    private var nearbyItems: [(stop: SelectedStop, distance: CLLocationDistance)] {
        guard let userLocation = location.location else { return [] }
        var items: [(SelectedStop, CLLocationDistance)] = []
        if showingBus {
            for stop in store.busStops {
                guard let coordinate = stop.coordinate else { continue }
                let distance = userLocation.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
                if distance <= 2000 {
                    items.append((.bus(stop), distance))
                }
            }
        }
        if showingCtagr {
            for stop in store.ctagrStops {
                guard let coordinate = stop.coordinate else { continue }
                let distance = userLocation.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
                if distance <= 2000 {
                    items.append((.ctagr(stop), distance))
                }
            }
        }
        if showingMetro {
            for stop in store.metroStops {
                guard let coordinate = stop.coordinate else { continue }
                let distance = userLocation.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
                if distance <= 2000 {
                    items.append((.metro(stop), distance))
                }
            }
        }
        return items.sorted { $0.1 < $1.1 }.prefix(8).map { (stop: $0.0, distance: $0.1) }
    }

    private func matchesScope(_ stop: SelectedStop) -> Bool {
        switch scope {
        case .all: stop.kind != .ctagr || settings.ctagrEnabled
        case .bus: stop.kind == .bus || (stop.kind == .ctagr && settings.ctagrEnabled)
        case .metro: stop.kind == .metro
        }
    }

    private var busMatches: [ParadaBus] {
        guard showingBus else { return [] }
        let source = favoritesOnly ? settings.favoriteBusStops : store.busStops
        return filterBus(source)
    }

    private var metroMatches: [ParadaMetro] {
        guard showingMetro else { return [] }
        let source = favoritesOnly ? settings.favoriteMetroStops : store.metroStops
        return filterMetro(source)
    }

    private var ctagrMatches: [ParadaCtagr] {
        guard showingCtagr else { return [] }
        let source = favoritesOnly ? settings.favoriteCtagrStops : store.ctagrStops
        return filterCtagr(source)
    }

    private func filterCtagr(_ stops: [ParadaCtagr]) -> [ParadaCtagr] {
        let q = normalizedQuery
        if q.isEmpty { return [] }
        let favoriteIds = settings.favoriteCtagrIds
        return stops.filter {
            $0.nombre.lowercased().contains(q)
                || $0.id.lowercased().contains(q)
                || ($0.municipio?.lowercased().contains(q) ?? false)
                || ($0.lineas?.contains { $0.lowercased().contains(q) } ?? false)
        }
        .sorted { lhs, rhs in
            let leftFav = favoriteIds.contains(lhs.id)
            let rightFav = favoriteIds.contains(rhs.id)
            if leftFav != rightFav { return leftFav }
            return lhs.nombre < rhs.nombre
        }
    }

    private func filterMetro(_ stops: [ParadaMetro]) -> [ParadaMetro] {
        let q = normalizedQuery
        if q.isEmpty { return [] }
        return stops.filter { $0.nombre.lowercased().contains(q) }
    }

    private func filterBus(_ stops: [ParadaBus]) -> [ParadaBus] {
        let q = normalizedQuery
        if q.isEmpty { return [] }
        let favoriteIds = settings.favoriteStopIds
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

    @ViewBuilder
    private func nearbyRow(_ stop: SelectedStop, distance: CLLocationDistance) -> some View {
        Button {
            onSelect(stop)
            dismiss()
        } label: {
            HStack(spacing: 10) {
                recentRowLabel(stop)
                Spacer(minLength: 0)
                Text(formattedDistance(distance))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(.primary)
    }

    @ViewBuilder
    private func recentRow(_ stop: SelectedStop) -> some View {
        switch stop {
        case .bus(let parada):
            busRow(parada, favorite: settings.isFavorite(parada))
        case .metro(let parada):
            metroRow(parada)
        case .ctagr(let parada):
            ctagrRow(parada)
        }
    }

    @ViewBuilder
    private func recentRowLabel(_ stop: SelectedStop) -> some View {
        switch stop {
        case .bus(let parada):
            StopIdentityRow(idText: "\(parada.id)", title: parada.nombre, favorite: settings.isFavorite(parada))
        case .metro(let parada):
            HStack(spacing: 10) {
                TramFrontGlyph()
                    .frame(width: 16, height: 16)
                Text(parada.nombre)
                Spacer()
                if settings.isFavorite(parada) {
                    Image(systemName: "star.fill").foregroundStyle(.yellow)
                }
            }
        case .ctagr(let parada):
            StopIdentityRow(idText: parada.id, title: parada.nombre, favorite: settings.isFavorite(parada), consorcio: true)
        }
    }

    private func formattedDistance(_ meters: CLLocationDistance) -> String {
        if meters < 1000 {
            return "\(Int(meters.rounded())) m"
        }
        return String(format: "%.1f km", meters / 1000)
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

    private func ctagrRow(_ stop: ParadaCtagr) -> some View {
        Button {
            onSelect(.ctagr(stop))
            dismiss()
        } label: {
            StopIdentityRow(
                idText: stop.id,
                title: [stop.nombre, stop.municipio].compactMap { $0 }.joined(separator: " · "),
                favorite: settings.isFavorite(stop),
                consorcio: true
            )
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

                Section("Consorcio metropolitano") {
                    Toggle("Mostrar líneas del Consorcio", isOn: $settings.ctagrEnabled)
                        .tint(BrandColor.ctagr)
                    Text("Paradas interurbanas (0124, 0245…) en el mapa de bus, en la búsqueda y en la pantalla de bloqueo. Si molestan, apágalo aquí o con el icono de autobús de dos pisos.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Bus y metro") {
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
                    Text("El que elijas queda primero en el selector de arriba y al buscar.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    ForEach(settings.searchBrowseOrder) { section in
                        HStack(alignment: .center, spacing: 12) {
                            Image(systemName: section.symbolName)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 22, alignment: .center)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(section.title)
                                Text(section.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onMove(perform: settings.moveSearchBrowse)
                } header: {
                    Text("Búsqueda")
                } footer: {
                    Text("Arrastra para reordenar Favoritos, Recientes y Cercanas. Se guarda al pulsar Listo.")
                }
                .environment(\.editMode, .constant(.active))

                Section("Metro") {
                    Toggle("Invertir el sentido de la línea", isOn: $settings.metroInverted)
                        .tint(.green)
                    Text("Cambia si las estaciones se listan de Armilla a Albolote o al revés.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Pantalla de bloqueo") {
                    Toggle("Mostrar próximas llegadas", isOn: $settings.liveActivityEnabled)
                        .tint(.green)
                    Text("Al consultar una parada o estación, las llegadas aparecen en la pantalla de bloqueo y en Dynamic Island.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Ajustes")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

enum MapSheetDetents {
    static let smallHeight: CGFloat = 248
    static let small = PresentationDetent.height(smallHeight)
    static let largeFraction: CGFloat = 0.48
    static let large = PresentationDetent.fraction(largeFraction)

    static func largeHeight(for mapHeight: CGFloat) -> CGFloat {
        (mapHeight > 200 ? mapHeight : 852) * largeFraction
    }
}

@Observable
final class UserLocationProvider: NSObject, CLLocationManagerDelegate {
    var authorizationStatus: CLAuthorizationStatus
    var location: CLLocation?
    var heading: CLHeading?

    private let manager: CLLocationManager

    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    var headingDegrees: Double? {
        guard let heading, heading.headingAccuracy >= 0 else { return nil }
        let value = heading.trueHeading >= 0 ? heading.trueHeading : heading.magneticHeading
        guard value >= 0 else { return nil }
        return value
    }

    override init() {
        manager = CLLocationManager()
        authorizationStatus = .notDetermined
        super.init()
        authorizationStatus = manager.authorizationStatus
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.headingFilter = 2
        if isAuthorized {
            startUpdates()
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
            startUpdates()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if isAuthorized {
            startUpdates()
        } else {
            manager.stopUpdatingLocation()
            manager.stopUpdatingHeading()
            location = nil
            heading = nil
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        location = locations.last
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        heading = newHeading
    }

    func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        true
    }

    private func startUpdates() {
        manager.startUpdatingLocation()
        syncHeadingOrientation()
        if CLLocationManager.headingAvailable() {
            manager.startUpdatingHeading()
        }
    }

    private func syncHeadingOrientation() {
        switch UIDevice.current.orientation {
        case .landscapeLeft:
            manager.headingOrientation = .landscapeLeft
        case .landscapeRight:
            manager.headingOrientation = .landscapeRight
        case .portraitUpsideDown:
            manager.headingOrientation = .portraitUpsideDown
        default:
            manager.headingOrientation = .portrait
        }
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
                case .favorites:
                    EmptyView()
                case .recents:
                    recentsSection
                case .nearby:
                    nearbySection
                }
            }
        }
    }

    private var orderedSections: [SearchBrowseSection] {
        settings.searchBrowseOrder.filter { $0 != .favorites }
    }

    private var recentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: SearchBrowseSection.recents.symbolName)
                Text("Recientes")
            }
                .font(.subheadline.weight(.semibold))
            if settings.recentStops.isEmpty {
                Text("Aquí aparecerán las paradas y estaciones que consultes.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                ForEach(settings.recentStops.filter { $0.kind != .ctagr || settings.ctagrEnabled }) { stop in
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
            HStack(spacing: 6) {
                Image(systemName: SearchBrowseSection.nearby.symbolName)
                Text("Cercanas")
            }
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
        if settings.ctagrEnabled {
            for stop in store.ctagrStops {
                guard let coordinate = stop.coordinate else { continue }
                let distance = userLocation.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
                if distance <= 2000 {
                    items.append((.ctagr(stop), distance))
                }
            }
        }
        return items.sorted { $0.1 < $1.1 }.prefix(8).map { (stop: $0.0, distance: $0.1) }
    }

    private func isFavorite(_ stop: SelectedStop) -> Bool {
        switch stop {
        case .bus(let parada): settings.isFavorite(parada)
        case .metro(let parada): settings.isFavorite(parada)
        case .ctagr(let parada): settings.isFavorite(parada)
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
                    if stop.kind == .metro {
                        TramFrontGlyph()
                    } else {
                        BusFrontGlyph()
                    }
                }
                .foregroundStyle(stop.kind == .ctagr ? BrandColor.ctagr : Color.primary)
                .frame(width: 16, height: 16)

                if case .bus(let parada) = stop {
                    StopNumberPill(number: parada.id, compact: true)
                } else if case .ctagr(let parada) = stop {
                    StopCodePill(code: parada.id, compact: true, consorcio: true)
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
        let ctagr = settings.ctagrEnabled ? filterCtagr(q) : []

        if bus.isEmpty && metro.isEmpty && ctagr.isEmpty {
            ContentUnavailableView("Sin resultados", systemImage: "magnifyingglass")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
        } else {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(settings.transportOrder, id: \.self) { kind in
                    if kind == .bus, !bus.isEmpty || !ctagr.isEmpty {
                        if !bus.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Bus urbano")
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
                        }
                        if !ctagr.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Consorcio")
                                    .font(.subheadline.weight(.semibold))
                                ForEach(ctagr) { stop in
                                    HomeStopRow(
                                        stop: .ctagr(stop),
                                        favorite: settings.isFavorite(stop),
                                        distance: nil,
                                        onSelect: { onSelect(.ctagr(stop)) }
                                    )
                                }
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

    private func filterCtagr(_ q: String) -> [ParadaCtagr] {
        let favoriteIds = settings.favoriteCtagrIds
        return store.ctagrStops
            .filter {
                $0.nombre.lowercased().contains(q)
                    || $0.id.lowercased().contains(q)
                    || ($0.municipio?.lowercased().contains(q) ?? false)
            }
            .sorted { lhs, rhs in
                let leftFav = favoriteIds.contains(lhs.id)
                let rightFav = favoriteIds.contains(rhs.id)
                if leftFav != rightFav { return leftFav }
                return lhs.nombre < rhs.nombre
            }
    }
}
