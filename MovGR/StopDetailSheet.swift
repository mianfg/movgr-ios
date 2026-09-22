import SwiftUI
import MovGRShared

struct BusLineView: View {
    @Bindable var settings: AppSettings
    var store: TransportStore
    var selected: ParadaBus?
    var arrivals: LlegadasBus?
    var isLoading: Bool
    var isOnline: Bool
    var onSearch: () -> Void = {}
    var onClear: () -> Void = {}
    var onSelectLine: (String) -> Void

    var body: some View {
        VStack(spacing: 10) {
            header
            listContent
        }
    }

    var header: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Próximos buses")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                LiveDot(isOnline: isOnline)
            }
            .padding(.top, 2)
            searchBar
        }
    }

    private var searchBar: some View {
        StopSearchBar(
            title: selected?.nombre ?? "Buscar parada...",
            isPlaceholder: selected == nil,
            stopNumber: selected?.id,
            onTap: onSearch
        ) {
            BusFrontGlyph()
                .frame(width: 16, height: 16)
        } trailing: {
            if let selected {
                Button {
                    settings.toggleFavorite(selected)
                } label: {
                    Image(systemName: settings.isFavorite(selected) ? "star.fill" : "star")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(settings.isFavorite(selected) ? Color.yellow : Color.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(settings.isFavorite(selected) ? "Quitar de favoritos" : "Añadir a favoritos")
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Quitar parada")
            }
        }
    }

    @ViewBuilder
    var listContent: some View {
        if selected == nil {
            VStack(spacing: 8) {
                BusFrontGlyph()
                    .frame(width: 28, height: 28)
                    .foregroundStyle(.secondary)
                Text("Selecciona una parada")
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        } else if isLoading && arrivals == nil {
            HStack {
                ProgressView()
                Text("Cargando datos...")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        } else if !isOnline && arrivals == nil {
            ContentUnavailableView(
                "Sin conexión",
                systemImage: "icloud.slash",
                description: Text("Se reintentará en unos segundos")
            )
        } else {
            let groups = groupedLines
            if groups.isEmpty {
                ContentUnavailableView("No hay autobuses aproximándose", systemImage: "circle.slash")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            } else {
                let preferred = selected.flatMap { settings.preferredLine(for: $0) }
                LazyVStack(spacing: 0) {
                    ForEach(groups) { group in
                        let isPreferred = preferred == group.id
                        let dimmed = preferred != nil && !isPreferred
                        Button {
                            onSelectLine(group.id)
                        } label: {
                            HStack(spacing: 12) {
                                LineBadgeView(
                                    id: group.id,
                                    colorHex: store.color(forBusLine: group.id) ?? group.linea.color,
                                    textColorHex: store.textColor(forBusLine: group.id) ?? group.linea.textColor
                                )
                                Text(group.displayName)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                HStack(spacing: 6) {
                                    ForEach(Array(group.minutes.prefix(3).enumerated()), id: \.offset) { _, minutes in
                                        MinutesBadge(minutes: minutes)
                                    }
                                }
                                .fixedSize(horizontal: true, vertical: false)
                                .layoutPriority(1)
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .opacity(dimmed ? 0.32 : 1)
                        .accessibilityLabel(accessibilityLabel(for: group, preferred: isPreferred))
                    }
                }
                .padding(.top, 4)
                .animation(.smooth(duration: 0.35), value: groups.map(\.minutes))
            }
        }
    }

    private var groupedLines: [GroupedBusLine] {
        guard let proximos = arrivals?.proximos else { return [] }
        var order: [String] = []
        var lines: [String: LineaBus] = [:]
        var minutes: [String: [Int]] = [:]
        var destinos: [String: String] = [:]
        for proximo in proximos {
            let id = proximo.linea.id
            if minutes[id] == nil {
                order.append(id)
                lines[id] = proximo.linea
                minutes[id] = []
                destinos[id] = proximo.destino
            }
            minutes[id, default: []].append(proximo.minutos)
        }
        let preferred = selected.flatMap { settings.preferredLine(for: $0) }
        return order.map { id in
            GroupedBusLine(
                id: id,
                linea: lines[id]!,
                minutes: (minutes[id] ?? []).sorted(),
                destino: destinos[id]
            )
        }
        .sorted { lhs, rhs in
            if lhs.id == preferred { return true }
            if rhs.id == preferred { return false }
            return (lhs.minutes.first ?? .max) < (rhs.minutes.first ?? .max)
        }
    }

    private func accessibilityLabel(for group: GroupedBusLine, preferred: Bool) -> String {
        let name = group.displayName
        return preferred ? "Dejar de esperar \(name)" : "Esperar \(name)"
    }
}

private struct GroupedBusLine: Identifiable, Hashable {
    var id: String
    var linea: LineaBus
    var minutes: [Int]
    var destino: String?

    var displayName: String {
        if let nombre = linea.nombre, !nombre.isEmpty { return nombre }
        if let destino, !destino.isEmpty { return destino }
        return id
    }
}

struct CtagrLineView: View {
    @Bindable var settings: AppSettings
    var selected: ParadaCtagr?
    var arrivals: LlegadasCtagr?
    var isLoading: Bool
    var isOnline: Bool
    var onSearch: () -> Void = {}
    var onClear: () -> Void = {}
    var onSelectLine: (String) -> Void

    var body: some View {
        VStack(spacing: 10) {
            header
            listContent
        }
    }

    var header: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Consorcio")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                LiveDot(isOnline: isOnline)
            }
            .padding(.top, 2)
            StopSearchBar(
                title: selected.map { [$0.nombre, $0.municipio].compactMap { $0 }.joined(separator: " · ") } ?? "Buscar parada del Consorcio...",
                isPlaceholder: selected == nil,
                stopCode: selected?.id,
                onTap: onSearch
            ) {
                BusFrontGlyph()
                    .foregroundStyle(BrandColor.ctagr)
                    .frame(width: 16, height: 16)
            } trailing: {
                if let selected {
                    Button {
                        settings.toggleFavorite(selected)
                    } label: {
                        Image(systemName: settings.isFavorite(selected) ? "star.fill" : "star")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(settings.isFavorite(selected) ? Color.yellow : Color.secondary)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Button(action: onClear) {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    var listContent: some View {
        if selected == nil {
            VStack(spacing: 8) {
                Text("Horario del Consorcio y buses en ruta, cuando hay GPS.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        } else if isLoading && arrivals == nil {
            HStack {
                ProgressView()
                Text("Cargando horario...")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        } else if !isOnline && arrivals == nil {
            ContentUnavailableView("Sin conexión", systemImage: "icloud.slash")
        } else {
            let groups = groupedLines
            if groups.isEmpty {
                ContentUnavailableView("No hay expediciones próximas", systemImage: "clock")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            } else {
                let preferred = selected.flatMap { settings.preferredLine(for: $0) }
                LazyVStack(spacing: 0) {
                    ForEach(groups) { group in
                        let isPreferred = preferred == group.id
                        Button {
                            onSelectLine(group.id)
                        } label: {
                            HStack(spacing: 12) {
                                LineBadgeView(
                                    id: group.id,
                                    colorHex: group.linea.color ?? "FFFFFF",
                                    textColorHex: group.linea.textColor ?? "15803d"
                                )
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(group.displayName)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                    HStack(spacing: 6) {
                                        Text("Horario")
                                        if group.enRuta {
                                            Text("· GPS en ruta")
                                                .foregroundStyle(BrandColor.ctagr)
                                        }
                                    }
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                VStack(alignment: .trailing, spacing: 4) {
                                    ForEach(Array(group.departures.prefix(3).enumerated()), id: \.offset) { _, item in
                                        HStack(spacing: 6) {
                                            Text(item.hora)
                                                .font(.caption.monospacedDigit())
                                                .foregroundStyle(.secondary)
                                            MinutesBadge(minutes: item.minutos)
                                        }
                                    }
                                }
                                .fixedSize(horizontal: true, vertical: false)
                                .layoutPriority(1)
                            }
                            .frame(minHeight: 48)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .opacity(preferred != nil && !isPreferred ? 0.32 : 1)
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private var groupedLines: [GroupedCtagrLine] {
        guard let proximos = arrivals?.proximos else { return [] }
        var order: [String] = []
        var lines: [String: LineaCtagr] = [:]
        var departures: [String: [(hora: String, minutos: Int)]] = [:]
        var enRuta: [String: Bool] = [:]
        for proximo in proximos {
            let id = proximo.linea.id
            if departures[id] == nil {
                order.append(id)
                lines[id] = proximo.linea
                departures[id] = []
                enRuta[id] = false
            }
            departures[id, default: []].append((proximo.hora, proximo.minutos))
            enRuta[id] = (enRuta[id] ?? false) || proximo.enRuta
        }
        let preferred = selected.flatMap { settings.preferredLine(for: $0) }
        return order.map { id in
            GroupedCtagrLine(
                id: id,
                linea: lines[id]!,
                departures: (departures[id] ?? []).sorted { $0.minutos < $1.minutos },
                enRuta: enRuta[id] ?? false
            )
        }
        .sorted { lhs, rhs in
            if lhs.id == preferred { return true }
            if rhs.id == preferred { return false }
            return (lhs.departures.first?.minutos ?? .max) < (rhs.departures.first?.minutos ?? .max)
        }
    }
}

private struct GroupedCtagrLine: Identifiable, Hashable {
    var id: String
    var linea: LineaCtagr
    var departures: [(hora: String, minutos: Int)]
    var enRuta: Bool

    var displayName: String {
        if let nombre = linea.nombre, !nombre.isEmpty { return nombre }
        return id
    }

    static func == (lhs: GroupedCtagrLine, rhs: GroupedCtagrLine) -> Bool {
        lhs.id == rhs.id && lhs.enRuta == rhs.enRuta
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
