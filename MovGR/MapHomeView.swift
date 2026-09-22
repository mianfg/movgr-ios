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
    @State private var ctagrArrivals: LlegadasCtagr?
    @State private var ctagrLoading = false
    @State private var ctagrOnline = true
    @State private var ctagrFailures = 0
    @State private var topChromeHeight: CGFloat = 72
    @State private var bottomChromeHeight: CGFloat = MapSheetDetents.smallHeight
    @State private var showDrawer = true
    @State private var sheetDetent: PresentationDetent = MapSheetDetents.small
    @State private var pendingCenterOnUser = false
    @State private var mapSize: CGSize = .zero
    @State private var mapKit = MapKitBridge()
    @State private var settledSheetHeight: CGFloat = MapSheetDetents.smallHeight
    @State private var suppressSheetRecenter = false
    @State private var sheetRecenterTask: Task<Void, Never>?

    private var selectedMetro: ParadaMetro? {
        if case .metro(let stop) = selectedStop { return stop }
        return nil
    }

    private var selectedBus: ParadaBus? {
        if case .bus(let stop) = selectedStop { return stop }
        return nil
    }

    private var selectedCtagr: ParadaCtagr? {
        if case .ctagr(let stop) = selectedStop { return stop }
        return nil
    }

    var body: some View {
        applyObservers(applyPolling(mapCanvas))
    }

    private var mapCanvas: some View {
        TransportMapView(
            kind: kind,
            store: store,
            mapStyle: settings.mapStyle,
            showTraffic: settings.showTraffic,
            favoriteStopIds: settings.favoriteStopIds,
            favoriteMetroIds: settings.favoriteMetroIds,
            favoriteCtagrIds: settings.favoriteCtagrIds,
            favoritesOnly: settings.mapFavoritesOnly,
            showCtagr: settings.ctagrEnabled,
            selectedStop: $selectedStop,
            position: $position,
            mapKit: mapKit,
            userHeading: locationProvider.headingDegrees
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
        .onPreferenceChange(MapCanvasSizeKey.self) { mapSize = $0 }
        .overlay(alignment: .bottom) {
            mapChrome
                .padding(.horizontal, 16)
                .padding(.bottom, bottomChromeHeight + 8)
                .ignoresSafeArea(edges: .bottom)
                .transaction { $0.animation = nil }
                .animation(nil, value: bottomChromeHeight)
        }
        .sheet(isPresented: $showDrawer) {
            drawer
        }
    }

    private func applyPolling<V: View>(_ view: V) -> some View {
        view
            .task {
                await store.loadIfNeeded()
                if settings.ctagrEnabled {
                    await store.loadCtagrIfNeeded()
                }
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
            .task(id: selectedCtagr?.id ?? "") {
                ctagrArrivals = nil
                ctagrFailures = 0
                guard let stop = selectedCtagr else {
                    ctagrLoading = false
                    ctagrOnline = true
                    return
                }
                await pollCtagr(stop)
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(20))
                    await pollCtagr(stop)
                }
            }
    }

    private func applyObservers<V: View>(_ view: V) -> some View {
        view
            .onChange(of: settings.ctagrEnabled) { _, enabled in
                if enabled {
                    Task { await store.loadCtagrIfNeeded() }
                } else if case .ctagr = selectedStop {
                    selectedStop = nil
                }
            }
            .onChange(of: selectedStop) { _, stop in
                handleSelectedStopChange(stop)
            }
            .onChange(of: kind) { _, newKind in
                handleKindChange(newKind)
            }
            .onChange(of: sheetDetent) { _, _ in
                recenterAfterSheetSettles()
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
            .onChange(of: store.ctagrStops.count) { _, _ in
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
            .onChange(of: showDrawer) { _, shown in
                if !shown { showDrawer = true }
            }
            .onChange(of: locationProvider.location) { _, location in
                guard pendingCenterOnUser, let coordinate = location?.coordinate else { return }
                pendingCenterOnUser = false
                centerOn(coordinate, meters: 900)
            }
    }

    private func handleSelectedStopChange(_ stop: SelectedStop?) {
        if let stop {
            settings.recordRecent(stop)
            kind = stop.mapKind
            if sheetDetent != MapSheetDetents.large {
                suppressSheetRecenter = true
                sheetDetent = MapSheetDetents.large
            }
            if let coordinate = stop.coordinate {
                centerOn(
                    coordinate,
                    meters: 650,
                    bottomChrome: MapSheetDetents.largeHeight(for: mapSize.height)
                )
            }
        }
        switch stop {
        case .metro(let parada):
            ArrivalActivityManager.shared.startTracking(.metro(parada), enabled: settings.liveActivityEnabled)
        case .bus(let parada):
            ArrivalActivityManager.shared.startTracking(.bus(parada), enabled: settings.liveActivityEnabled)
        case .ctagr(let parada):
            ArrivalActivityManager.shared.startTracking(.ctagr(parada), enabled: settings.liveActivityEnabled)
        case .none:
            ArrivalActivityManager.shared.stopTracking()
        }
    }

    private func handleKindChange(_ newKind: TransportKind) {
        if let selectedStop, selectedStop.mapKind != newKind {
            self.selectedStop = nil
            if sheetDetent != MapSheetDetents.small {
                suppressSheetRecenter = true
                sheetDetent = MapSheetDetents.small
            }
            showKindOverview(newKind)
        } else if selectedStop == nil {
            showKindOverview(newKind)
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            TransportModePicker(
                kind: $kind,
                options: settings.transportOrder,
                usesGlass: true,
                compact: true,
                collapsible: true
            )

            Spacer(minLength: 8)
                .allowsHitTesting(false)

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

    private var mapChrome: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)
                .allowsHitTesting(false)

            if kind == .bus {
                Button {
                    withAnimation(.smooth) {
                        settings.ctagrEnabled.toggle()
                    }
                } label: {
                    Image(systemName: "bus.doubledecker.fill")
                        .foregroundStyle(settings.ctagrEnabled ? BrandColor.ctagr : Color.primary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel(settings.ctagrEnabled ? "Ocultar Consorcio" : "Mostrar Consorcio")
            }

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
                centerOnUser()
            } label: {
                Image(systemName: "location.fill")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .accessibilityLabel("Mi ubicación")
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
                sheetDetent = MapSheetDetents.small
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
                sheetDetent = MapSheetDetents.small
            },
            onSelectLine: { lineId in
                if let selectedBus {
                    settings.togglePreferredLine(lineId, for: selectedBus)
                }
            }
        )
    }

    private var ctagrPanel: CtagrLineView {
        CtagrLineView(
            settings: settings,
            selected: selectedCtagr,
            arrivals: ctagrArrivals,
            isLoading: ctagrLoading,
            isOnline: ctagrOnline,
            onSearch: {
                searchScope = .bus
            },
            onClear: {
                selectedStop = nil
                sheetDetent = MapSheetDetents.small
            },
            onSelectLine: { lineId in
                if let selectedCtagr {
                    settings.togglePreferredLine(lineId, for: selectedCtagr)
                }
            }
        )
    }

    private var drawer: some View {
        VStack(spacing: 12) {
            Group {
                if kind == .metro {
                    metroPanel.header
                } else if selectedCtagr != nil {
                    ctagrPanel.header
                } else {
                    busPanel.header
                }
            }

            ScrollViewReader { proxy in
                ScrollView {
                    Group {
                        if kind == .metro {
                            metroPanel.listContent
                        } else if selectedCtagr != nil {
                            ctagrPanel.listContent
                        } else {
                            busPanel.listContent
                        }
                    }
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.hidden)
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
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            Rectangle()
                .fill(.regularMaterial)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .background {
            SheetHeightProbe { height in
                adoptSheetHeight(height)
            }
            .allowsHitTesting(false)
        }
        .presentationDetents(
            [MapSheetDetents.small, MapSheetDetents.large],
            selection: $sheetDetent
        )
        .presentationDragIndicator(.visible)
        .presentationBackground(.clear)
        .presentationBackgroundInteraction(.enabled(upThrough: MapSheetDetents.large))
        .presentationContentInteraction(.scrolls)
        .interactiveDismissDisabled()
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
            .environment(locationProvider)
        }
    }

    private func selectStop(_ stop: SelectedStop) {
        kind = stop.mapKind
        selectedStop = stop
        sheetDetent = MapSheetDetents.large
    }

    private var sharePayload: MovGRSharePayload {
        if let selectedBus { return .bus(selectedBus) }
        if let selectedCtagr { return .ctagr(selectedCtagr) }
        if selectedMetro != nil {
            return .metro(selectedMetro, direction: settings.metroDirection)
        }
        return .home
    }

    private func adoptSheetHeight(_ height: CGFloat) {
        guard height.isFinite, abs(height - bottomChromeHeight) > 0.4 else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            bottomChromeHeight = height
        }
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

    private func pollCtagr(_ stop: ParadaCtagr) async {
        ctagrLoading = ctagrArrivals == nil
        do {
            let next = try await APIClient.shared.getCtagrArrivals(stop.id)
            ctagrFailures = 0
            ctagrArrivals = next
            ctagrOnline = true
            await ArrivalActivityManager.shared.ingestCtagrArrivals(next, stop: stop, isOnline: true)
        } catch {
            ctagrFailures += 1
            if ctagrArrivals == nil, ctagrFailures >= 3 {
                ctagrOnline = false
            }
        }
        ctagrLoading = false
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

    private func recenterAfterSheetSettles() {
        let fromHeight = settledSheetHeight
        let skip = suppressSheetRecenter
        suppressSheetRecenter = false
        let pin = skip ? nil : mapKit.coordinateAtVisibleCenter(sheetHeight: fromHeight)
        sheetRecenterTask?.cancel()
        sheetRecenterTask = Task { @MainActor in
            let started = ContinuousClock.now
            var last = bottomChromeHeight
            var stableMs = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
                let height = bottomChromeHeight
                if abs(height - last) < 0.75 {
                    stableMs += 16
                } else {
                    stableMs = 0
                    last = height
                }
                let elapsed = started.duration(to: .now)
                if stableMs >= 90, elapsed > .milliseconds(220) { break }
                if elapsed > .milliseconds(850) { break }
            }
            guard !Task.isCancelled else { return }
            let toHeight = bottomChromeHeight
            settledSheetHeight = toHeight
            guard !skip, let pin, abs(toHeight - fromHeight) > 20 else { return }
            applyRegion(mapKit.regionPlacing(pin, atVisibleCenter: toHeight))
        }
    }

    private func applyRegion(_ region: MKCoordinateRegion?, animated: Bool = true) {
        guard let region else { return }
        if let current = mapKit.mapView?.region, Self.regionsMatch(current, region) {
            return
        }
        if animated {
            withAnimation(.easeInOut(duration: 0.35)) {
                position = .region(region)
            }
        } else {
            position = .region(region)
        }
    }

    private static func regionsMatch(_ a: MKCoordinateRegion, _ b: MKCoordinateRegion) -> Bool {
        abs(a.center.latitude - b.center.latitude) < 0.00008
            && abs(a.center.longitude - b.center.longitude) < 0.00008
            && abs(a.span.latitudeDelta - b.span.latitudeDelta) < max(a.span.latitudeDelta, 0.001) * 0.04
    }

    private func showKindOverview(_ newKind: TransportKind) {
        if newKind == .metro {
            applyRegion(
                mapKit.regionFitting(
                    store.metroStops.compactMap(\.coordinate),
                    sheetHeight: bottomChromeHeight
                ) ?? MapViewport.fitting(
                    store.metroStops.compactMap(\.coordinate),
                    mapSize: mapSize,
                    topChrome: 0,
                    bottomChrome: bottomChromeHeight
                )
            )
        } else {
            let granada = CLLocationCoordinate2D(latitude: 37.176, longitude: -3.599)
            applyRegion(
                mapKit.regionFocusing(granada, meters: 5500, sheetHeight: bottomChromeHeight)
                    ?? MapViewport.region(
                        centering: granada,
                        meters: 5500,
                        mapSize: mapSize,
                        topChrome: 0,
                        bottomChrome: bottomChromeHeight
                    )
            )
        }
    }

    private func centerOnUser() {
        if let coordinate = locationProvider.location?.coordinate {
            pendingCenterOnUser = false
            centerOn(coordinate, meters: 900)
        } else {
            pendingCenterOnUser = true
            centerOn(CLLocationCoordinate2D(latitude: 37.176, longitude: -3.599), meters: 900)
        }
    }

    private func centerOn(_ coordinate: CLLocationCoordinate2D, meters: CLLocationDistance, bottomChrome: CGFloat? = nil) {
        let sheetHeight = bottomChrome ?? bottomChromeHeight
        applyRegion(
            mapKit.regionFocusing(coordinate, meters: meters, sheetHeight: sheetHeight)
                ?? MapViewport.region(
                    centering: coordinate,
                    meters: meters,
                    mapSize: mapSize,
                    topChrome: 0,
                    bottomChrome: sheetHeight
                )
        )
    }

    private func fitFavorites() {
        let coords: [CLLocationCoordinate2D]
        switch kind {
        case .bus:
            var next = settings.favoriteBusStops.compactMap(\.coordinate)
            if settings.ctagrEnabled {
                next.append(contentsOf: settings.favoriteCtagrStops.compactMap(\.coordinate))
            }
            coords = next
        case .metro:
            coords = settings.favoriteMetroStops.compactMap(\.coordinate)
        case .ctagr:
            coords = settings.favoriteCtagrStops.compactMap(\.coordinate)
        }
        applyRegion(
            mapKit.regionFitting(coords, sheetHeight: bottomChromeHeight)
                ?? MapViewport.fitting(
                    coords,
                    mapSize: mapSize,
                    topChrome: 0,
                    bottomChrome: bottomChromeHeight
                )
        )
    }
}

private struct TopChromeHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
