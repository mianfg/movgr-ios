import ActivityKit
import SwiftUI
import WidgetKit
import MovGRShared

struct ArrivalLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ArrivalActivityAttributes.self) { context in
            LockScreenArrivalView(state: context.state)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        if context.state.kind != .ctagr, let number = context.state.stopNumber {
                            StopNumberPill(number: number, compact: true)
                        }
                        Text(context.state.stopName)
                            .font(.headline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.kind == .metro {
                        HStack(spacing: 4) {
                            MetroDirectionChevrons(down: context.state.metroChevronsDown, font: .caption.weight(.bold))
                            MetroPills(
                                minutes: Array(context.state.selectedMetroMinutes.prefix(1)),
                                etas: Array(context.state.selectedMetroETAs.prefix(1)),
                                isOnline: context.state.isOnline,
                                compact: true
                            )
                        }
                    } else {
                        HStack(spacing: 4) {
                            if let row = context.state.nextRow {
                                LineBadgeView(id: row.badge, colorHex: row.colorHex, textColorHex: row.textColorHex, size: 20)
                                TimeTag(minutes: row.minutes, eta: row.eta, isOnline: context.state.isOnline, compact: true)
                            } else if let line = context.state.preferredLineId {
                                LineBadgeView(id: line, size: 20)
                            }
                        }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.kind == .metro {
                        MetroSplitTimes(state: context.state)
                    } else {
                        BusCompactRow(rows: Array(context.state.rows.prefix(2)), isOnline: context.state.isOnline, maxTimes: 2)
                    }
                }
            } compactLeading: {
                if context.state.usesBusLayout {
                    if let row = context.state.nextRow {
                        LineBadgeView(id: row.badge, colorHex: row.colorHex, textColorHex: row.textColorHex, size: 20)
                    } else if let line = context.state.preferredLineId {
                        LineBadgeView(id: line, size: 20)
                    } else {
                        BusFrontGlyph().frame(width: 16, height: 16)
                    }
                } else {
                    MetroDirectionChevrons(down: context.state.metroChevronsDown, font: .caption.weight(.bold))
                        .frame(width: 16, height: 16)
                }
            } compactTrailing: {
                if context.state.kind == .metro {
                    MetroPills(
                        minutes: Array(context.state.selectedMetroMinutes.prefix(1)),
                        etas: Array(context.state.selectedMetroETAs.prefix(1)),
                        isOnline: context.state.isOnline,
                        compact: true
                    )
                } else if let row = context.state.nextRow {
                    TimeTag(minutes: row.minutes, eta: row.eta, isOnline: context.state.isOnline, compact: true)
                } else if let minutes = context.state.soonestMinutes {
                    TimeTag(minutes: minutes, eta: context.state.soonestETA, isOnline: context.state.isOnline, compact: true)
                }
            } minimal: {
                if context.state.usesBusLayout {
                    if let row = context.state.nextRow {
                        LineBadgeView(id: row.badge, colorHex: row.colorHex, textColorHex: row.textColorHex, size: 18)
                    } else if let line = context.state.preferredLineId {
                        LineBadgeView(id: line, size: 18)
                    } else {
                        BusFrontGlyph().frame(width: 14, height: 14)
                    }
                } else {
                    MetroDirectionChevrons(down: context.state.metroChevronsDown, font: .caption2.weight(.bold))
                        .frame(width: 14, height: 14)
                }
            }
        }
    }
}

private struct LockScreenArrivalView: View {
    var state: ArrivalActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Group {
                    if state.kind == .metro {
                        TramFrontGlyph()
                    } else {
                        BusFrontGlyph()
                    }
                }
                .foregroundStyle(state.kind == .ctagr ? BrandColor.ctagr : Color.primary)
                .frame(width: 18, height: 18)
                if state.kind != .ctagr, let number = state.stopNumber {
                    StopNumberPill(number: number, compact: true)
                }
                Text(state.stopName)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text(lockStatus(state))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(state.isOnline ? Color(hex: "10b981") : .yellow)
            }

            if state.kind == .metro {
                MetroSplitTimes(state: state)
            } else if state.rows.isEmpty {
                Text(state.preferredLineId.map { "No hay salidas de la línea \($0)" } ?? emptyCopy(state))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                BusCompactRow(rows: Array(state.rows.prefix(3)), isOnline: state.isOnline, maxTimes: 3)
            }
        }
    }
}

private func lockStatus(_ state: ArrivalActivityAttributes.ContentState) -> String {
    if !state.isOnline { return "Sin conexión" }
    if state.kind == .ctagr {
        return state.subtitle
    }
    return "En directo"
}

private func emptyCopy(_ state: ArrivalActivityAttributes.ContentState) -> String {
    state.kind == .ctagr ? "No hay expediciones próximas" : "No hay autobuses aproximándose"
}

private struct MetroSplitTimes: View {
    var state: ArrivalActivityAttributes.ContentState

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            directionColumn(title: "Armilla", direction: .armilla, minutes: state.armillaMinutes, etas: state.armillaETAs)
            directionColumn(title: "Albolote", direction: .albolote, minutes: state.alboloteMinutes, etas: state.alboloteETAs)
        }
    }

    private func directionColumn(title: String, direction: DireccionMetro, minutes: [Int], etas: [Date]) -> some View {
        let selected = state.metroDirection == direction
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                MetroDirectionChevrons(
                    down: direction.chevronsPointDown(inverted: state.metroInverted),
                    font: .caption2.weight(.bold)
                )
                Text(title)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(selected ? Color.primary : Color.secondary)
            MetroPills(minutes: minutes, etas: etas, isOnline: state.isOnline, compact: false, emptyPlaceholder: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(selected ? 1 : 0.82)
    }
}

private struct MetroPills: View {
    var minutes: [Int]
    var etas: [Date] = []
    var isOnline = true
    var compact = false
    var emptyPlaceholder = false

    var body: some View {
        if minutes.isEmpty {
            if emptyPlaceholder {
                Text("—")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
        } else {
            HStack(spacing: compact ? 3 : 6) {
                ForEach(Array(minutes.prefix(compact ? 1 : 2).enumerated()), id: \.offset) { index, value in
                    TimeTag(
                        minutes: value,
                        eta: index < etas.count ? etas[index] : nil,
                        isOnline: isOnline,
                        compact: compact
                    )
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }
}

private struct BusCompactRow: View {
    var rows: [ArrivalRow]
    var isOnline = true
    var maxTimes = 3

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 6) {
                    LineBadgeView(id: row.badge, colorHex: row.colorHex, textColorHex: row.textColorHex, size: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            ForEach(Array(row.allMinutes.prefix(maxTimes).enumerated()), id: \.offset) { index, minutes in
                                TimeTag(
                                    minutes: minutes,
                                    eta: index < row.allETAs.count ? row.allETAs[index] : nil,
                                    isOnline: isOnline,
                                    compact: true
                                )
                            }
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        if row.title.contains(":") {
                            Text(row.title)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct TimeTag: View {
    var minutes: Int
    var eta: Date? = nil
    var isOnline = true
    var compact = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            chrome(remainingMinutes(at: context.date))
        }
    }

    private func remainingMinutes(at date: Date) -> Int {
        guard let eta else { return minutes }
        let seconds = eta.timeIntervalSince(date)
        if seconds <= 0 { return 0 }
        return Int(seconds / 60)
    }

    private func chrome(_ remaining: Int) -> some View {
        let imminent = remaining <= 0
        return Text(minutesLabel(remaining))
            .font((compact ? Font.caption2 : Font.caption).weight(.semibold).monospacedDigit())
            .padding(.horizontal, imminent ? (compact ? 5 : 8) : 0)
            .padding(.vertical, imminent ? (compact ? 2 : 4) : 0)
            .foregroundStyle(imminent ? Color.white : Color.primary)
            .background {
                if imminent {
                    Capsule().fill(Color.red)
                }
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(1)
    }
}

private func minutesLabel(_ minutes: Int) -> String {
    minutes <= 0 ? "<1min" : "\(minutes)min"
}
