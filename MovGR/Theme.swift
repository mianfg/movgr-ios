import SwiftUI
import MovGRShared

struct MinutesBadge: View {
    var minutes: Int

    var body: some View {
        Text(Self.label(minutes))
            .font(.caption.weight(.semibold).monospacedDigit())
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(minutes <= 0 ? Color.white : Color.primary)
            .background(minutes <= 0 ? Color.red : Color.secondary.opacity(0.18), in: Capsule())
            .layoutPriority(1)
    }

    static func label(_ minutes: Int, compact: Bool = false) -> String {
        let nbsp = "\u{00A0}"
        if compact {
            return minutes <= 0 ? "<1" : "\(minutes)m"
        }
        return minutes <= 0 ? "<1\(nbsp)min" : "\(minutes)\(nbsp)min"
    }
}

struct LiveDot: View {
    var isOnline: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(isOnline ? "En directo" : "Sin conexión")
                .font(.caption.weight(.medium))
            Circle()
                .fill(isOnline ? BrandColor.live : Color.yellow)
                .frame(width: 8, height: 8)
        }
        .foregroundStyle(.secondary)
    }
}

struct MovGRLogo: View {
    var expanded = true
    var compact = false

    var body: some View {
        HStack(spacing: expanded ? 8 : 0) {
            Image("movgr-mark")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: compact ? 22 : 28, height: compact ? 22 : 28)
            if expanded {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("mov")
                        .font(.system(size: compact ? 20 : 24, weight: .regular))
                    Text("GR")
                        .font(.system(size: compact ? 15 : 18, weight: .bold))
                        .tracking(0.6)
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.82, anchor: .leading)),
                    removal: .opacity.combined(with: .scale(scale: 0.82, anchor: .leading))
                ))
            }
        }
    }
}
