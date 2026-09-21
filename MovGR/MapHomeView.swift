import CoreLocation
import MapKit
import SwiftUI
import MovGRShared

struct MapHomeView: View {
    @Bindable var settings: AppSettings
    var store: TransportStore
    var deepLinks: DeepLinkRouter

    @State private var kind: TransportKind = .bus
    @State private var selectedStop: SelectedStop?
    @State private var position: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.176, longitude: -3.599),
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
    )
    @State private var showSettings = false
    @State private var searchScope: TransportSearchScope?
    @State private var showShare = false
    @Namespace private var glassNamespace
    @State private var locationProvider = UserLocationProvider()
    @State private var metroArrivals: [LlegadasMetro] = []
    @State private var metroLoading = false
    @State private var metroOnline = true
    @State private var busArrivals: LlegadasBus?
    @State private var busLoading = false
    @State private var busOnline = true
    @State private var busFailures = 0
    @State private var topChromeHeight: CGFloat = 72
    @State private var bottomChromeHeight: CGFloat = 320
    @State private var cardSize: BottomCardSize = .small
    @State private var cardDrag: CGFloat = 0
    @State private var viewHeight: CGFloat = 800

    private var selectedMetro: ParadaMetro? {
        if case .metro(let stop) = selectedStop { return stop }
        return nil
    }

    private var selectedBus: ParadaBus? {
        if case .bus(let stop) = selectedStop { return stop }
        return nil
    }

    private var smallCardHeight: CGFloat { 248 }
    private var bigCardHeight: CGFloat { min(max(viewHeight * 0.48, 340), 520) }

    private var displayedCardHeight: CGFloat {
        let base = cardSize == .small ? smallCardHeight : bigCardHeight
        return min(bigCardHeight, max(smallCardHeight, base - cardDrag))
    }

    var body: some View {
        TransportMapView(
            kind: kind,
            store: store,
            mapStyle: settings.mapStyle,
            showTraffic: settings.showTraffic,
            favoriteStopIds: settings.favoriteStopIds,
            favoriteMetroIds: settings.favoriteMetroIds,
            favoritesOnly: settings.mapFavoritesOnly,
            selectedStop: $selectedStop,
            position: $position,
            topChromeHeight: topChromeHeight,
            bottomChromeHeight: bottomChromeHeight
        )
        .ignoresSafeArea()
        .safeAreaInset(edge: .top, spacing: 10) {
            topBar
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .background {
                    GeometryReader { geo in
                        Color.clear.preference(key: TopChromeHeightKey.self, value: geo.size.height + 10)
                    }
                }
        }
        .environment(locationProvider)
        .onPreferenceChange(TopChromeHeightKey.self) { topChromeHeight = $0 }
        .overlay(alignment: .bottom) {
            bottomStack
        }
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { viewHeight = geo.size.height }
                    .onChange(of: geo.size.height) { _, height in viewHeight = height }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(settings: settings)
                .environment(locationProvider)
        }
        .sheet(isPresented: $showShare) {
            MovGRShareSheet(payload: sharePayload)
        }
        .sheet(item: $searchScope) { scope in
            TransportSearchSheet(store: store, settings: settings, scope: scope) { stop in
                selectStop(stop)
            }
        }
        .task {
            await store.loadIfNeeded()
            applyDeepLink()
        }
        .task {
            await pollMetro()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                await pollMetro()
            }
        }
        .task(id: selectedBus?.id ?? 0) {
            busArrivals = nil
            busFailures = 0
            guard let stop = selectedBus else {
                busLoading = false
                busOnline = true
                return
            }
            await pollBus(stop)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(12))
                await pollBus(stop)
            }
        }
        .onChange(of: selectedStop) { _, stop in
            if let stop {
                settings.recordRecent(stop)
                kind = stop.kind
                withAnimation(.smooth(duration: 0.42, extraBounce: 0.04)) {
                    cardSize = .big
                }
            }
            switch stop {
            case .metro(let parada):
                ArrivalActivityManager.shared.startTracking(.metro(parada), enabled: settings.liveActivityEnabled)
            case .bus(let parada):
                ArrivalActivityManager.shared.startTracking(.bus(parada), enabled: settings.liveActivityEnabled)
            case .none:
                ArrivalActivityManager.shared.stopTracking()
            }
        }
        .onChange(of: kind) { _, newKind in
            if let selectedStop, selectedStop.kind != newKind {
                self.selectedStop = nil
                withAnimation(.smooth(duration: 0.42, extraBounce: 0.04)) {
                    cardSize = .small
                }
            }
        }
        .onChange(of: settings.mapFavoritesOnly) { _, only in
            guard only else { return }
            fitFavorites()
        }
        .onChange(of: deepLinks.pending) { _, _ in
            applyDeepLink()
        }
        .onChange(of: store.busStops.count) { _, _ in
            applyDeepLink()
        }
        .onChange(of: store.metroStops.count) { _, _ in
            applyDeepLink()
        }
        .onChange(of: settings.liveActivityEnabled) { _, enabled in
            if let selectedStop {
                ArrivalActivityManager.shared.startTracking(selectedStop, enabled: enabled)
            }
        }
        .onChange(of: settings.metroDirection) { _, _ in
            ArrivalActivityManager.shared.preferencesDidChange()
        }
        .onChange(of: settings.metroInverted) { _, _ in
            ArrivalActivityManager.shared.preferencesDidChange()
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                withAnimation(.smooth(duration: 0.42, extraBounce: 0.08)) {
                    settings.logoExpanded.toggle()
                }
            } label: {
                MovGRLogo(expanded: settings.logoExpanded, compact: true)
                    .padding(.horizontal, settings.logoExpanded ? 14 : 9)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .capsule)
            .accessibilityLabel(settings.logoExpanded ? "Contraer logo" : "Expandir logo")

            Spacer(minLength: 8)

            HStack(spacing: 10) {
                Button {
                    showShare = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .glassEffectID("share", in: glassNamespace)
                .accessibilityLabel("Compartir")

                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .glassEffectID("settings", in: glassNamespace)
            }
        }
    }

    private var bottomStack: some View {
        VStack(spacing: 10) {
            HStack {
                Spacer()
                mapFabs
            }

            VStack(spacing: 10) {
                card
                TransportModePicker(
                    kind: $kind,
                    options: settings.transportOrder,
                    usesGlass: true,
                    compact: true
                )
            }
            .background {
                GeometryReader { geo in
                    Color.clear
                        .onAppear { bottomChromeHeight = geo.size.height + 8 }
                        .onChange(of: geo.size.height) { _, height in
                            bottomChromeHeight = height + 8
                        }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .animation(.smooth(duration: 0.42, extraBounce: 0.04), value: kind)
        .animation(.smooth(duration: 0.42, extraBounce: 0.04), value: cardSize)
    }

    private var mapFabs: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.smooth) {
                    settings.mapFavoritesOnly.toggle()
                }
            } label: {
                Image(systemName: settings.mapFavoritesOnly ? "star.fill" : "star")
                    .foregroundStyle(settings.mapFavoritesOnly ? Color.yellow : Color.primary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .accessibilityLabel(settings.mapFavoritesOnly ? "Mostrar todas las paradas" : "Solo paradas favoritas")

            Button {
                locationProvider.requestAccess()
                withAnimation {
                    position = .userLocation(followsHeading: false, fallback: .automatic)
                }
            } label: {
                Image(systemName: "location.fill")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .accessibilityLabel("Mi ubicación")
        }
    }

    private var card: some View {
        VStack(spacing: 10) {
            Capsule()
                .fill(.secondary.opacity(0.4))
                .frame(width: 36, height: 5)
                .padding(.top, 6)
                .padding(.bottom, 6)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .gesture(sheetDrag)
                .accessibilityLabel(cardSize == .big ? "Reducir panel" : "Ampliar panel")
                .accessibilityAddTraits(.isButton)
                .onTapGesture {
                    withAnimation(.smooth(duration: 0.42, extraBounce: 0.04)) {
                        cardSize = cardSize == .big ? .small : .big
                    }
                }

            Group {
                if kind == .metro {
                    metroPanel.header
                } else {
                    busPanel.header
                }
            }

            ScrollViewReader { proxy in
                ScrollView {
                    Group {
                        if kind == .metro {
                            metroPanel.listContent
                        } else {
                            busPanel.listContent
                        }
                    }
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
                .onChange(of: selectedMetro?.id) { _, id in
                    guard let id else { return }
                    withAnimation(.easeInOut) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
                .onChange(of: settings.metroInverted) { _, _ in
                    guard let id = selectedMetro?.id else { return }
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .frame(height: displayedCardHeight, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .top)
        .clipped()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var sheetDrag: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                cardDrag = value.translation.height
            }
            .onEnded { value in
                let predicted = value.predictedEndTranslation.height
                withAnimation(.smooth(duration: 0.42, extraBounce: 0.04)) {
                    if predicted < -56 {
                        cardSize = .big
                    } else if predicted > 56 {
                        cardSize = .small
                    } else {
                        let midpoint = (smallCardHeight + bigCardHeight) / 2
                        cardSize = displayedCardHeight >= midpoint ? .big : .small
                    }
                    cardDrag = 0
                }
            }
    }

    private var metroPanel: MetroLineView {
        MetroLineView(
            settings: settings,
            arrivals: metroArrivals,
            selected: selectedMetro,
            isLoading: metroLoading,
            isOnline: metroOnline,
            compact: true,
            onSelect: { stop in
                selectedStop = .metro(stop)
            },
            onClear: {
                selectedStop = nil
                withAnimation(.smooth(duration: 0.42, extraBounce: 0.04)) {
                    cardSize = .small
                }
            },
            onSearch: {
                searchScope = .metro
            }
        )
    }

    private var busPanel: BusLineView {
        BusLineView(
            settings: settings,
            store: store,
            selected: selectedBus,
            arrivals: busArrivals,
            isLoading: busLoading,
            isOnline: busOnline,
            onSearch: {
                searchScope = .bus
            },
            onClear: {
                selectedStop = nil
                withAnimation(.smooth(duration: 0.42, extraBounce: 0.04)) {
                    cardSize = .small
                }
            },
            onSelectLine: { lineId in
                if let selectedBus {
                    settings.togglePreferredLine(lineId, for: selectedBus)
                }
            }
        )
    }

    private func selectStop(_ stop: SelectedStop) {
        kind = stop.kind
        selectedStop = stop
    }

    private var sharePayload: MovGRSharePayload {
        if let selectedBus { return .bus(selectedBus) }
        if selectedMetro != nil {
            return .metro(selectedMetro, direction: settings.metroDirection)
        }
        return .home
    }

    private func applyDeepLink() {
        deepLinks.applyToMap(store: store, settings: settings, kind: &kind, selectedStop: &selectedStop)
    }

    private func pollBus(_ stop: ParadaBus) async {
        busLoading = busArrivals == nil
        do {
            let next = try await APIClient.shared.getBusArrivals(stop.id)
            busFailures = 0
            busArrivals = next
            busOnline = true
            await ArrivalActivityManager.shared.ingestBusArrivals(next, stop: stop, isOnline: true)
        } catch {
            busFailures += 1
            if busArrivals == nil, busFailures >= 3 {
                busOnline = false
            }
        }
        busLoading = false
    }

    private func pollMetro() async {
        metroLoading = metroArrivals.isEmpty
        do {
            metroArrivals = try await APIClient.shared.getMetroArrivals()
            metroOnline = true
            if case .metro(let stop) = selectedStop,
               let arrivals = metroArrivals.first(where: { $0.parada.id == stop.id }) {
                await ArrivalActivityManager.shared.ingestMetroArrivals(arrivals, stop: stop, isOnline: true)
            }
        } catch {
            if metroArrivals.isEmpty {
                metroOnline = false
            }
        }
        metroLoading = false
    }

    private func fitFavorites() {
        let coords: [CLLocationCoordinate2D]
        switch kind {
        case .bus:
            coords = settings.favoriteBusStops.compactMap(\.coordinate)
        case .metro:
            coords = settings.favoriteMetroStops.compactMap(\.coordinate)
        }
        guard let first = coords.first else { return }
        if coords.count == 1 {
            withAnimation {
                position = .region(MKCoordinateRegion(center: first, latitudinalMeters: 900, longitudinalMeters: 900))
            }
            return
        }
        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for coord in coords {
            minLat = min(minLat, coord.latitude)
            maxLat = max(maxLat, coord.latitude)
            minLon = min(minLon, coord.longitude)
            maxLon = max(maxLon, coord.longitude)
        }
        withAnimation {
            position = .region(
                MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
                    span: MKCoordinateSpan(
                        latitudeDelta: max((maxLat - minLat) * 1.6, 0.012),
                        longitudeDelta: max((maxLon - minLon) * 1.6, 0.012)
                    )
                )
            )
        }
    }
}

private struct TopChromeHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
