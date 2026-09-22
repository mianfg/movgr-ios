import SwiftUI
import MovGRShared

struct MetroLineView: View {
    @Bindable var settings: AppSettings
    var arrivals: [LlegadasMetro]
    var selected: ParadaMetro?
    var isLoading: Bool
    var isOnline: Bool
    var compact: Bool = false
    var onSelect: (ParadaMetro) -> Void
    var onClear: () -> Void = {}
    var onSearch: () -> Void = {}

    private var display: [LlegadasMetro] {
        settings.metroInverted ? arrivals.reversed() : arrivals
    }

    private var chevronsPointDown: Bool {
        settings.metroDirection.chevronsPointDown(inverted: settings.metroInverted)
    }

    var body: some View {
        VStack(spacing: compact ? 10 : 12) {
            header
            listContent
        }
    }

    var header: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Próximos trenes")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                LiveDot(isOnline: isOnline)
            }
            .padding(.top, 2)
            controls
        }
    }

    private var controls: some View {
        HStack(alignment: .center, spacing: 8) {
            StopSearchBar(
                title: selected?.nombre ?? "Buscar estación...",
                isPlaceholder: selected == nil,
                onTap: onSearch
            ) {
                TramFrontGlyph()
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
                    .accessibilityLabel("Quitar estación")
                }
            }

            SlidingChoicePicker(
                selection: $settings.metroDirection,
                options: DireccionMetro.allCases,
                effectID: "metroDirection",
                compact: true,
                usesGlass: false
            ) { direction in
                HStack(spacing: 4) {
                    MetroDirectionChevrons(
                        down: direction.chevronsPointDown(inverted: settings.metroInverted),
                        font: .caption2.weight(.bold)
                    )
                    Text(direction.rawValue)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: compact ? 168 : 200)
        }
        .frame(height: 44)
    }

    @ViewBuilder
    var listContent: some View {
        if isLoading && arrivals.isEmpty {
            HStack {
                ProgressView()
                Text("Cargando datos...")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
        } else if !isOnline && arrivals.isEmpty {
            ContentUnavailableView("Sin conexión", systemImage: "icloud.slash", description: Text("Se reintentará en unos segundos"))
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(display.enumerated()), id: \.element.parada.id) { index, llegada in
                    let isSelected = selected?.id == llegada.parada.id
                    Button {
                        onSelect(llegada.parada)
                    } label: {
                        MetroStationRow(
                            llegada: llegada,
                            direction: settings.metroDirection,
                            selected: isSelected,
                            hasSelection: selected != nil,
                            showChevron: index < display.count - 1,
                            chevronDown: chevronsPointDown,
                            nearSelected: isNearSelected(index: index)
                        )
                    }
                    .buttonStyle(.plain)
                    .id(llegada.parada.id)
                }
            }
            .padding(.top, 2)
        }
    }

    private func isNearSelected(index: Int) -> Bool {
        guard let selected, let selectedIndex = display.firstIndex(where: { $0.parada.id == selected.id }) else {
            return false
        }
        return index == selectedIndex || index == selectedIndex - 1
    }
}

private struct MetroStationRow: View {
    var llegada: LlegadasMetro
    var direction: DireccionMetro
    var selected: Bool
    var hasSelection: Bool
    var showChevron: Bool
    var chevronDown: Bool
    var nearSelected: Bool

    private var times: [ProximoMetro] {
        llegada.proximos.filter { $0.direccion == direction }
    }

    private var isTerminus: Bool {
        llegada.parada.nombre == direction.rawValue
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(selected ? BrandColor.metro : Color.secondary.opacity(0.35))
                        .frame(width: selected ? 12 : 9, height: selected ? 12 : 9)
                    if selected {
                        Circle()
                            .stroke(BrandColor.metro.opacity(0.35), lineWidth: 5)
                            .frame(width: 12, height: 12)
                    }
                }
                .frame(width: 18, height: 18)

                HStack(alignment: .center, spacing: 8) {
                    Text(llegada.parada.nombre)
                        .font(selected ? .subheadline.weight(.semibold) : .subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 8)
                    timesView
                }
            }
            .frame(minHeight: 32, alignment: .center)

            if showChevron {
                Image(systemName: "chevron.up.2")
                    .font(.system(size: 9, weight: .bold))
                    .rotationEffect(.degrees(chevronDown ? 180 : 0))
                    .foregroundStyle(nearSelected ? Color.primary.opacity(0.55) : Color.secondary.opacity(0.28))
                    .frame(width: 18, height: 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .opacity(!hasSelection || selected ? 1 : 0.32)
    }

    @ViewBuilder
    private var timesView: some View {
        if times.isEmpty {
            if isTerminus {
                Color.clear.frame(height: 28)
            } else {
                Text("Sin trenes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            HStack(spacing: 6) {
                ForEach(Array(times.enumerated()), id: \.offset) { _, item in
                    MinutesBadge(minutes: item.minutos)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(1)
        }
    }
}
