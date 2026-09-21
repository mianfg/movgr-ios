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
                                Spacer(minLength: 8)
                                HStack(spacing: 6) {
                                    ForEach(Array(group.minutes.prefix(3).enumerated()), id: \.offset) { _, minutes in
                                        MinutesBadge(minutes: minutes)
                                    }
                                }
                                .frame(minHeight: 28, alignment: .trailing)
                            }
                            .frame(height: 44)
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
        for proximo in proximos {
            let id = proximo.linea.id
            if minutes[id] == nil {
                order.append(id)
                lines[id] = proximo.linea
                minutes[id] = []
            }
            minutes[id, default: []].append(proximo.minutos)
        }
        let preferred = selected.flatMap { settings.preferredLine(for: $0) }
        return order.map { id in
            GroupedBusLine(id: id, linea: lines[id]!, minutes: (minutes[id] ?? []).sorted())
        }
        .sorted { lhs, rhs in
            if lhs.id == preferred { return true }
            if rhs.id == preferred { return false }
            return (lhs.minutes.first ?? .max) < (rhs.minutes.first ?? .max)
        }
    }

    private func accessibilityLabel(for group: GroupedBusLine, preferred: Bool) -> String {
        preferred ? "Dejar de esperar la línea \(group.id)" : "Esperar la línea \(group.id)"
    }
}

private struct GroupedBusLine: Identifiable, Hashable {
    var id: String
    var linea: LineaBus
    var minutes: [Int]
}
