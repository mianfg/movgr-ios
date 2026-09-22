import SwiftUI
import UIKit

public struct LineBadgeView: View {
    public var id: String
    public var colorHex: String?
    public var textColorHex: String?
    public var size: CGFloat = 32

    public init(id: String, colorHex: String? = nil, textColorHex: String? = nil, size: CGFloat = 32) {
        self.id = id
        self.colorHex = colorHex
        self.textColorHex = textColorHex
        self.size = size
    }

    public var body: some View {
        let cleaned = (colorHex ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            .uppercased()
        let isLight = cleaned == "FFFFFF" || cleaned == "FFF"
        let fill = Color(hex: colorHex, fallback: Color(red: 0.42, green: 0.42, blue: 0.46))
        let wide = id.count > 3
        let width = wide ? max(size, CGFloat(id.count) * size * 0.34 + 10) : size
        ZStack {
            Group {
                if wide {
                    RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                        .fill(fill)
                } else {
                    Circle().fill(fill)
                }
            }
            if UIImage(named: "linea-\(id)") != nil {
                Image("linea-\(id)")
                    .resizable()
                    .renderingMode(.original)
                    .interpolation(.high)
                    .scaledToFill()
                    .padding(-size * 0.1)
            } else {
                Text(id)
                    .font(.system(size: size < 28 ? 9 : (wide ? 9 : 12), weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                    .padding(.horizontal, 3)
                    .foregroundStyle(Color(hex: textColorHex, fallback: .white))
            }
        }
        .frame(width: width, height: size)
        .overlay {
            if isLight {
                Group {
                    if wide {
                        RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                            .strokeBorder(BrandColor.ctagr.opacity(0.85), lineWidth: 1.5)
                    } else {
                        Circle().strokeBorder(BrandColor.ctagr.opacity(0.85), lineWidth: 1.5)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: wide ? size * 0.32 : size / 2, style: .continuous))
        .compositingGroup()
        .accessibilityLabel(id)
    }
}

public struct StopCodePill: View {
    public var code: String
    public var compact = false
    public var consorcio = false

    public init(code: String, compact: Bool = false, consorcio: Bool = false) {
        self.code = code
        self.compact = compact
        self.consorcio = consorcio
    }

    public var body: some View {
        Text(code)
            .font(.system(size: compact ? 11 : 13, weight: .bold, design: .rounded))
            .monospacedDigit()
            .padding(.horizontal, compact ? 6 : 8)
            .padding(.vertical, compact ? 3 : 4)
            .foregroundStyle(consorcio ? BrandColor.ctagr : Color.primary)
            .background {
                Capsule()
                    .fill(consorcio ? BrandColor.ctagrFill : Color.secondary.opacity(0.2))
            }
            .overlay {
                if consorcio {
                    Capsule().strokeBorder(BrandColor.ctagr.opacity(0.85), lineWidth: 1)
                }
            }
            .accessibilityLabel("Parada \(code)")
    }
}

public struct StopNumberPill: View {
    public var number: Int
    public var compact = false

    public init(number: Int, compact: Bool = false) {
        self.number = number
        self.compact = compact
    }

    public var body: some View {
        Text("\(number)")
            .font(.system(size: compact ? 12 : 15, weight: .bold, design: .rounded))
            .monospacedDigit()
            .padding(.horizontal, compact ? 7 : 9)
            .padding(.vertical, compact ? 3 : 4)
            .foregroundStyle(.primary)
            .background(.secondary.opacity(0.2), in: Capsule())
            .accessibilityLabel("Parada \(number)")
    }
}

public struct MetroDirectionChevrons: View {
    public var down: Bool
    public var font: Font = .caption2.weight(.bold)

    public init(down: Bool, font: Font = .caption2.weight(.bold)) {
        self.down = down
        self.font = font
    }

    public var body: some View {
        Image(systemName: "chevron.up.2")
            .font(font)
            .rotationEffect(.degrees(down ? 180 : 0))
    }
}

public struct BusFrontGlyph: View {
    public init() {}

    public var body: some View {
        LucideStroke { p in
            p.move(to: CGPoint(x: 4, y: 6)); p.addLine(to: CGPoint(x: 2, y: 7))
            p.move(to: CGPoint(x: 10, y: 6)); p.addLine(to: CGPoint(x: 14, y: 6))
            p.move(to: CGPoint(x: 22, y: 7)); p.addLine(to: CGPoint(x: 20, y: 6))
            p.addRoundedRect(in: CGRect(x: 4, y: 3, width: 16, height: 16), cornerSize: CGSize(width: 2, height: 2))
            p.move(to: CGPoint(x: 4, y: 11)); p.addLine(to: CGPoint(x: 20, y: 11))
            p.addEllipse(in: CGRect(x: 7.25, y: 14.25, width: 1.5, height: 1.5))
            p.addEllipse(in: CGRect(x: 15.25, y: 14.25, width: 1.5, height: 1.5))
            p.move(to: CGPoint(x: 6, y: 19)); p.addLine(to: CGPoint(x: 6, y: 21))
            p.move(to: CGPoint(x: 18, y: 21)); p.addLine(to: CGPoint(x: 18, y: 19))
        }
    }
}

public struct TramFrontGlyph: View {
    public init() {}

    public var body: some View {
        LucideStroke { p in
            p.addRoundedRect(in: CGRect(x: 4, y: 3, width: 16, height: 16), cornerSize: CGSize(width: 2, height: 2))
            p.move(to: CGPoint(x: 4, y: 11)); p.addLine(to: CGPoint(x: 20, y: 11))
            p.move(to: CGPoint(x: 12, y: 3)); p.addLine(to: CGPoint(x: 12, y: 11))
            p.move(to: CGPoint(x: 8, y: 19)); p.addLine(to: CGPoint(x: 6, y: 22))
            p.move(to: CGPoint(x: 18, y: 22)); p.addLine(to: CGPoint(x: 16, y: 19))
            p.addEllipse(in: CGRect(x: 7.25, y: 14.25, width: 1.5, height: 1.5))
            p.addEllipse(in: CGRect(x: 15.25, y: 14.25, width: 1.5, height: 1.5))
        }
    }
}

private struct LucideStroke: View {
    var builder: (inout Path) -> Void

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / 24
            var path = Path()
            builder(&path)
            context.stroke(
                path.applying(CGAffineTransform(scaleX: scale, y: scale)),
                with: .foreground,
                style: StrokeStyle(lineWidth: 1.35, lineCap: .round, lineJoin: .round)
            )
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
