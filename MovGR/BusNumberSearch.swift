import SwiftUI
import MovGRShared

struct StopIdentityRow: View {
    var idText: String
    var title: String
    var favorite = false
    var consorcio = false

    var body: some View {
        HStack(spacing: 10) {
            if consorcio {
                StopCodePill(code: idText, consorcio: true)
            } else if let number = Int(idText) {
                StopNumberPill(number: number)
            } else {
                Text(idText)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
            }
            Text(title)
                .font(.subheadline)
                .lineLimit(1)
            Spacer()
            if favorite {
                Image(systemName: "star.fill").foregroundStyle(.yellow)
            }
        }
    }
}

struct TransportModePicker: View {
    @Binding var kind: TransportKind
    var options: [TransportKind] = [.bus, .metro]
    var usesGlass = true
    var compact = false
    var collapsible = false
    @State private var showsLabels = true

    var body: some View {
        SlidingChoicePicker(
            selection: $kind,
            options: options,
            effectID: "transportMode",
            compact: compact,
            usesGlass: usesGlass,
            collapseOnReselect: collapsible,
            showsLabels: collapsible ? $showsLabels : nil
        ) { value in
            HStack(spacing: showsLabels || !collapsible ? 8 : 0) {
                Group {
                    if value == .bus {
                        BusFrontGlyph()
                    } else {
                        TramFrontGlyph()
                    }
                }
                .frame(width: 18, height: 18)
                if showsLabels || !collapsible {
                    Text(value.title)
                        .font(compact ? .caption.weight(.semibold) : .headline)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .accessibilityLabel(value.title)
        }
        .frame(maxWidth: collapsible && !showsLabels ? nil : (compact ? 236 : nil))
        .accessibilityHint(collapsible ? "Toca de nuevo la opción seleccionada para mostrar u ocultar los nombres" : "")
    }
}

struct SlidingChoicePicker<Value: Hashable, Label: View>: View {
    @Binding var selection: Value
    var options: [Value]
    var effectID: String
    var compact = false
    var usesGlass = true
    var collapseOnReselect = false
    var showsLabels: Binding<Bool>? = nil
    @ViewBuilder var label: (Value) -> Label
    @Namespace private var glassNamespace

    private var labelsVisible: Bool {
        showsLabels?.wrappedValue ?? true
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { value in
                Button {
                    withAnimation(.smooth(duration: 0.42, extraBounce: 0.08)) {
                        if collapseOnReselect, selection == value {
                            showsLabels?.wrappedValue.toggle()
                        } else {
                            selection = value
                        }
                    }
                } label: {
                    label(value)
                        .padding(.horizontal, compact && !labelsVisible ? 12 : 0)
                        .frame(maxWidth: labelsVisible ? .infinity : nil)
                        .padding(.vertical, compact ? 0 : 12)
                        .frame(maxHeight: compact ? .infinity : nil)
                        .foregroundStyle(selection == value ? Color.primary : Color.secondary)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .background {
                    if selection == value {
                        if usesGlass {
                            Capsule()
                                .fill(.clear)
                                .glassEffect(.regular.interactive(), in: .capsule)
                                .glassEffectID(effectID, in: glassNamespace)
                                .matchedGeometryEffect(id: effectID, in: glassNamespace)
                        } else {
                            Capsule()
                                .fill(.background.secondary)
                                .matchedGeometryEffect(id: effectID, in: glassNamespace)
                        }
                    }
                }
            }
        }
        .padding(compact ? 3 : 5)
        .frame(height: compact ? 44 : nil)
        .background {
            if usesGlass {
                Capsule().fill(.clear).glassEffect(.regular, in: .capsule)
            } else {
                Capsule().fill(.fill.tertiary)
            }
        }
    }
}

struct StopSearchBar<Leading: View, Trailing: View>: View {
    var title: String
    var isPlaceholder: Bool
    var stopNumber: Int? = nil
    var stopCode: String? = nil
    var onTap: () -> Void
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                leading()
                if let stopCode {
                    StopCodePill(code: stopCode, compact: true, consorcio: true)
                } else if let stopNumber {
                    StopNumberPill(number: stopNumber, compact: true)
                }
                Text(title)
                    .foregroundStyle(isPlaceholder ? Color.secondary : Color.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)

            trailing()
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
