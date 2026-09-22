import ActivityKit
import Foundation
import UIKit
import MovGRShared

@MainActor
final class ArrivalActivityManager {
    static let shared = ArrivalActivityManager()

    private var activity: Activity<ArrivalActivityAttributes>?
    private var pollTask: Task<Void, Never>?
    private var tokenTask: Task<Void, Never>?
    private var currentStop: SelectedStop?
    private var pushToken: String?
    private var backgroundTask = UIBackgroundTaskIdentifier.invalid
    private var consecutiveFailures = 0
    private var isForeground = true
    private var lastBusArrivals: LlegadasBus?
    private var lastBusStop: ParadaBus?

    private init() {}

    func startTracking(_ stop: SelectedStop, enabled: Bool) {
        currentStop = stop
        consecutiveFailures = 0
        pollTask?.cancel()
        guard enabled else {
            Task { await endAllActivities() }
            return
        }
        pollTask = Task { [weak self] in
            await self?.runLoop(for: stop)
        }
    }

    func stopTracking() {
        pollTask?.cancel()
        pollTask = nil
        tokenTask?.cancel()
        tokenTask = nil
        let token = pushToken
        currentStop = nil
        pushToken = nil
        lastBusArrivals = nil
        lastBusStop = nil
        Task {
            if let token {
                await APIClient.shared.unsubscribeLiveActivity(token: token)
            }
            await endAllActivities()
        }
    }

    func preferencesDidChange() {
        guard AppSettings.storedLiveActivityEnabled() else { return }
        Task {
            await publishCurrent()
            if let pushToken, let currentStop {
                await registerPush(token: pushToken, stop: currentStop)
            }
        }
    }

    func ingestBusArrivals(_ arrivals: LlegadasBus, stop: ParadaBus, isOnline: Bool) async {
        currentStop = .bus(stop)
        lastBusArrivals = arrivals
        lastBusStop = stop
        if isOnline { consecutiveFailures = 0 }
        await update(
            stop: .bus(stop),
            state: Self.busState(stop: stop, arrivals: arrivals, isOnline: isOnline)
        )
    }

    func ingestCtagrArrivals(_ arrivals: LlegadasCtagr, stop: ParadaCtagr, isOnline: Bool) async {
        currentStop = .ctagr(stop)
        if isOnline { consecutiveFailures = 0 }
        await update(
            stop: .ctagr(stop),
            state: Self.ctagrState(stop: stop, arrivals: arrivals, isOnline: isOnline)
        )
    }

    func ingestMetroArrivals(_ arrivals: LlegadasMetro, stop: ParadaMetro, isOnline: Bool) async {
        currentStop = .metro(stop)
        if isOnline { consecutiveFailures = 0 }
        await update(
            stop: .metro(stop),
            state: Self.metroState(stop: stop, arrivals: arrivals, isOnline: isOnline)
        )
    }

    func handleScenePhase(_ phase: ScenePhaseLike) {
        switch phase {
        case .background:
            isForeground = false
            beginBackground()
        case .active:
            isForeground = true
            endBackground()
            attachToExistingActivity()
            if let currentStop {
                startTracking(currentStop, enabled: AppSettings.storedLiveActivityEnabled())
            }
        default:
            break
        }
    }

    enum ScenePhaseLike {
        case active, inactive, background
    }

    private func runLoop(for stop: SelectedStop) async {
        await publish(stop: stop)
        while !Task.isCancelled, currentStop?.id == stop.id, pushToken == nil {
            try? await Task.sleep(for: .seconds(20))
            if Task.isCancelled || currentStop?.id != stop.id { break }
            await publish(stop: stop)
        }
    }

    private func publishCurrent() async {
        guard let currentStop else { return }
        await publish(stop: currentStop)
    }

    private func publish(stop: SelectedStop) async {
        await push(stop: stop)
    }

    private func push(stop: SelectedStop) async {
        let state: ArrivalActivityAttributes.ContentState
        do {
            state = try await Self.contentState(for: stop)
            consecutiveFailures = 0
            if case .bus(let parada) = stop {
                lastBusStop = parada
            }
        } catch {
            consecutiveFailures += 1
            if consecutiveFailures < 3 {
                return
            }
            if let existing = resolvedActivity(for: stop)?.content.state {
                var offline = existing
                offline.isOnline = false
                await update(stop: stop, state: offline)
            }
            return
        }
        await update(stop: stop, state: state)
    }

    private func update(stop: SelectedStop, state: ArrivalActivityAttributes.ContentState) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let content = ActivityContent(
            state: state,
            staleDate: Self.staleDate(for: state),
            relevanceScore: 100
        )

        if let existing = resolvedActivity(for: stop) {
            activity = existing
            if tokenTask == nil {
                listenForPushToken(existing, stop: stop)
            }
            await existing.update(content)
            await endActivities(except: existing.id)
            return
        }

        await endActivities(except: nil)
        do {
            activity = try Activity.request(
                attributes: ArrivalActivityAttributes(stopId: stop.id, kind: stop.kind),
                content: content,
                pushType: .token
            )
            listenForPushToken(activity, stop: stop)
        } catch {
            do {
                activity = try Activity.request(
                    attributes: ArrivalActivityAttributes(stopId: stop.id, kind: stop.kind),
                    content: content,
                    pushType: nil
                )
            } catch {
                if let fallback = liveActivities.first {
                    activity = fallback
                    await fallback.update(content)
                }
            }
        }
    }

    private func listenForPushToken(_ activity: Activity<ArrivalActivityAttributes>?, stop: SelectedStop) {
        guard let activity else { return }
        tokenTask?.cancel()
        tokenTask = Task { [weak self] in
            for await data in activity.pushTokenUpdates {
                guard let self, !Task.isCancelled else { break }
                let hex = data.map { String(format: "%02x", $0) }.joined()
                pushToken = hex
                await registerPush(token: hex, stop: stop)
            }
        }
    }

    private func registerPush(token: String, stop: SelectedStop) async {
        #if DEBUG
        let environment = "sandbox"
        #else
        let environment = "production"
        #endif
        let stopId: String
        let preferred: String?
        let direction: String?
        let inverted: Bool
        switch stop {
        case .bus(let parada):
            stopId = "\(parada.id)"
            preferred = AppSettings.storedPreferredLine(forBusStopId: parada.id)
            direction = nil
            inverted = false
        case .metro(let parada):
            stopId = parada.id
            preferred = nil
            direction = AppSettings.storedMetroDirection().rawValue
            inverted = AppSettings.storedMetroInverted()
        case .ctagr(let parada):
            stopId = parada.id
            preferred = AppSettings.storedPreferredLine(forCtagrStopId: parada.id)
            direction = nil
            inverted = false
        }
        await APIClient.shared.subscribeLiveActivity(
            LiveSubscribeBody(
                token: token,
                environment: environment,
                kind: stop.kind.rawValue,
                stopId: stopId,
                preferredLineId: preferred,
                metroDirection: direction,
                metroInverted: inverted
            )
        )
    }

    private func resolvedActivity(for stop: SelectedStop) -> Activity<ArrivalActivityAttributes>? {
        if let activity,
           activity.attributes.stopId == stop.id,
           activity.activityState == .active || activity.activityState == .stale {
            return activity
        }
        return liveActivities.first { $0.attributes.stopId == stop.id }
    }

    private var liveActivities: [Activity<ArrivalActivityAttributes>] {
        Activity<ArrivalActivityAttributes>.activities.filter {
            $0.activityState == .active || $0.activityState == .stale
        }
    }

    private func attachToExistingActivity() {
        if let currentStop, let existing = resolvedActivity(for: currentStop) {
            activity = existing
            return
        }
        activity = liveActivities.first
    }

    private func endActivities(except keepId: Activity<ArrivalActivityAttributes>.ID?) async {
        for item in Activity<ArrivalActivityAttributes>.activities {
            if let keepId, item.id == keepId { continue }
            await item.end(nil, dismissalPolicy: .immediate)
        }
        if let activity, let keepId, activity.id == keepId { return }
        if keepId == nil { activity = nil }
    }

    private func endAllActivities() async {
        await endActivities(except: nil)
    }

    private func beginBackground() {
        endBackground()
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "movgr.live") { [weak self] in
            self?.endBackground()
        }
    }

    private func endBackground() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }

    static func contentState(for stop: SelectedStop) async throws -> ArrivalActivityAttributes.ContentState {
        switch stop {
        case .bus(let parada):
            let arrivals = try await APIClient.shared.getBusArrivals(parada.id)
            return busState(stop: parada, arrivals: arrivals, isOnline: true)
        case .metro(let parada):
            let arrivals = try await metroArrivals(for: parada)
            return metroState(stop: parada, arrivals: arrivals, isOnline: true)
        case .ctagr(let parada):
            let arrivals = try await APIClient.shared.getCtagrArrivals(parada.id)
            return ctagrState(stop: parada, arrivals: arrivals, isOnline: true)
        }
    }

    static func metroArrivals(for stop: ParadaMetro) async throws -> LlegadasMetro {
        let all = try await APIClient.shared.getMetroArrivals()
        if let match = all.first(where: { $0.parada.id == stop.id }) {
            return match
        }
        return try await APIClient.shared.getMetroArrivals(stopId: stop.id)
    }

    static func busState(
        stop: ParadaBus,
        arrivals: LlegadasBus,
        isOnline: Bool
    ) -> ArrivalActivityAttributes.ContentState {
        let now = Date()
        let preferred = AppSettings.storedPreferredLine(forBusStopId: stop.id)
        let proximos = preferred.map { lineId in
            arrivals.proximos.filter { $0.linea.id == lineId }
        } ?? arrivals.proximos

        var order: [String] = []
        var lines: [String: LineaBus] = [:]
        var minutesByLine: [String: [Int]] = [:]
        for proximo in proximos {
            let id = proximo.linea.id
            if minutesByLine[id] == nil {
                order.append(id)
                lines[id] = proximo.linea
                minutesByLine[id] = []
            }
            minutesByLine[id, default: []].append(proximo.minutos)
        }

        let rows = order.prefix(3).compactMap { id -> ArrivalRow? in
            guard let linea = lines[id] else { return nil }
            let times = (minutesByLine[id] ?? []).sorted().prefix(3)
            guard let first = times.first else { return nil }
            let rest = Array(times.dropFirst())
            return ArrivalRow(
                badge: linea.id,
                colorHex: linea.color ?? "6b7280",
                textColorHex: linea.textColor ?? "FFFFFF",
                title: linea.id,
                minutes: first,
                eta: Self.eta(from: first, now: now),
                additionalMinutes: rest,
                additionalETAs: rest.map { Self.eta(from: $0, now: now) }
            )
        }
        return .init(
            stopName: stop.nombre,
            subtitle: "Parada \(stop.id)",
            kind: .bus,
            rows: Array(rows),
            preferredLineId: preferred,
            stopNumber: stop.id,
            updatedAt: now,
            isOnline: isOnline
        )
    }

    static func ctagrState(
        stop: ParadaCtagr,
        arrivals: LlegadasCtagr,
        isOnline: Bool
    ) -> ArrivalActivityAttributes.ContentState {
        let now = Date()
        let preferred = AppSettings.storedPreferredLine(forCtagrStopId: stop.id)
        let proximos = preferred.map { lineId in
            arrivals.proximos.filter { $0.linea.id == lineId }
        } ?? arrivals.proximos

        var order: [String] = []
        var lines: [String: LineaCtagr] = [:]
        var minutesByLine: [String: [Int]] = [:]
        var horaByLine: [String: String] = [:]
        var enRutaByLine: [String: Bool] = [:]
        for proximo in proximos {
            let id = proximo.linea.id
            if minutesByLine[id] == nil {
                order.append(id)
                lines[id] = proximo.linea
                minutesByLine[id] = []
                horaByLine[id] = proximo.hora
                enRutaByLine[id] = false
            }
            minutesByLine[id, default: []].append(proximo.minutos)
            enRutaByLine[id] = (enRutaByLine[id] ?? false) || proximo.enRuta
        }

        let anyLive = enRutaByLine.values.contains(true)
        let rows = order.prefix(3).compactMap { id -> ArrivalRow? in
            guard let linea = lines[id] else { return nil }
            let times = (minutesByLine[id] ?? []).sorted().prefix(3)
            guard let first = times.first else { return nil }
            let rest = Array(times.dropFirst())
            let hora = horaByLine[id] ?? ""
            let live = enRutaByLine[id] == true ? " · en ruta" : ""
            return ArrivalRow(
                badge: linea.id,
                colorHex: linea.color ?? "FFFFFF",
                textColorHex: linea.textColor ?? "15803d",
                title: hora.isEmpty ? linea.id : "\(hora)\(live)",
                minutes: first,
                eta: Self.eta(from: first, now: now),
                additionalMinutes: rest,
                additionalETAs: rest.map { Self.eta(from: $0, now: now) }
            )
        }
        return .init(
            stopName: stop.nombre,
            subtitle: anyLive ? "Consorcio · en ruta" : "Consorcio · horario",
            kind: .ctagr,
            rows: Array(rows),
            preferredLineId: preferred,
            updatedAt: now,
            isOnline: isOnline
        )
    }

    static func metroState(
        stop: ParadaMetro,
        arrivals: LlegadasMetro,
        isOnline: Bool
    ) -> ArrivalActivityAttributes.ContentState {
        let now = Date()
        let direction = AppSettings.storedMetroDirection()
        let inverted = AppSettings.storedMetroInverted()
        let armilla = arrivals.proximos.filter { $0.direccion == .armilla }.map(\.minutos).sorted()
        let albolote = arrivals.proximos.filter { $0.direccion == .albolote }.map(\.minutos).sorted()
        return .init(
            stopName: stop.nombre,
            subtitle: direction.rawValue,
            kind: .metro,
            rows: [],
            armillaMinutes: Array(armilla.prefix(2)),
            alboloteMinutes: Array(albolote.prefix(2)),
            armillaETAs: etas(from: Array(armilla.prefix(2)), now: now),
            alboloteETAs: etas(from: Array(albolote.prefix(2)), now: now),
            metroDirection: direction,
            metroInverted: inverted,
            updatedAt: now,
            isOnline: isOnline
        )
    }

    private static func staleDate(for state: ArrivalActivityAttributes.ContentState) -> Date {
        let floor = Date().addingTimeInterval(state.isOnline ? 12 * 60 : 3 * 60)
        guard let latest = state.latestETA else { return floor }
        return max(latest.addingTimeInterval(90), floor)
    }

    private static func eta(from minutes: Int, now: Date) -> Date {
        if minutes <= 0 {
            return now.addingTimeInterval(45)
        }
        return now.addingTimeInterval(TimeInterval(minutes * 60 + 59))
    }

    private static func etas(from minutes: [Int], now: Date) -> [Date] {
        minutes.map { eta(from: $0, now: now) }
    }
}
