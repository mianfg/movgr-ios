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
                        if let number = context.state.stopNumber {
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
                            MetroPills(minutes: context.state.selectedMetroMinutes, etas: context.state.selectedMetroETAs, isOnline: context.state.isOnline, compact: true)
                        }
                    } else if let minutes = context.state.soonestMinutes {
                        TimeTag(minutes: minutes, eta: context.state.nextRow?.eta, isOnline: context.state.isOnline, compact: true)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.kind == .metro {
                        MetroSplitTimes(state: context.state)
                    } else {
                BusCompactRow(rows: Array(context.state.rows.prefix(3)), isOnline: context.state.isOnline)
                    }
                }
            } compactLeading: {
                if context.state.kind == .bus {
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
                    MetroPills(minutes: context.state.selectedMetroMinutes, etas: context.state.selectedMetroETAs, isOnline: context.state.isOnline, compact: true)
                } else if let minutes = context.state.soonestMinutes {
                    TimeTag(minutes: minutes, eta: context.state.nextRow?.eta, isOnline: context.state.isOnline, compact: true)
                }
            } minimal: {
                if context.state.kind == .bus {
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
                    if state.kind == .bus {
                        BusFrontGlyph()
                    } else {
                        TramFrontGlyph()
                    }
                }
                .frame(width: 18, height: 18)
                if let number = state.stopNumber {
                    StopNumberPill(number: number, compact: true)
                }
                Text(state.stopName)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text(state.isOnline ? "En directo" : "Sin conexión")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(state.isOnline ? Color(hex: "10b981") : .yellow)
            }

            if state.kind == .metro {
                MetroSplitTimes(state: state)
            } else if state.rows.isEmpty {
                Text(state.preferredLineId.map { "No hay llegadas de la línea \($0)" } ?? "No hay autobuses aproximándose")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                BusCompactRow(rows: Array(state.rows.prefix(3)), isOnline: state.isOnline)
            }
        }
    }
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
                TramFrontGlyph()
                    .frame(width: 12, height: 12)
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
        }
    }
}

private struct BusCompactRow: View {
    var rows: [ArrivalRow]
    var isOnline = true

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 6) {
                    LineBadgeView(id: row.badge, colorHex: row.colorHex, textColorHex: row.textColorHex, size: 22)
                    HStack(spacing: 4) {
                        ForEach(Array(row.allMinutes.prefix(3).enumerated()), id: \.offset) { index, minutes in
                            TimeTag(
                                minutes: minutes,
                                eta: index < row.allETAs.count ? row.allETAs[index] : nil,
                                isOnline: isOnline,
                                compact: true
                            )
                        }
                    }
                }
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
        Group {
            if !isOnline, let eta, eta > Date.now.addingTimeInterval(1) {
                Text(timerInterval: Date.now...eta, countsDown: true, showsHours: false)
            } else {
                Text(minutesLabel(minutes, compact: compact))
            }
        }
        .font((compact ? Font.caption2 : Font.caption).weight(.semibold).monospacedDigit())
        .padding(.horizontal, compact ? 5 : 8)
        .padding(.vertical, compact ? 2 : 4)
        .foregroundStyle(minutes <= 0 ? Color.white : Color.primary)
        .background(minutes <= 0 ? Color.red : Color.secondary.opacity(0.18), in: Capsule())
        .multilineTextAlignment(.center)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

private func minutesLabel(_ minutes: Int, compact: Bool) -> String {
    if compact {
        return minutes <= 0 ? "<1" : "\(minutes)m"
    }
    return minutes <= 0 ? "< 1 min" : "\(minutes) min"
}
