import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit
import MovGRShared

struct MovGRShareSheet: View {
    var payload: MovGRSharePayload

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 12) {
                contextGlyph
                    .frame(width: 22, height: 22)
                    .frame(width: 44, height: 44)
                    .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(contextKicker)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(contextTitle)
                        .font(.headline)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Group {
                if let image = Self.qrImage(from: payload.url.absoluteString) {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 152, height: 152)
                        .padding(10)
                        .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .accessibilityLabel("Código QR")
                }
            }
            .frame(maxWidth: .infinity)

            ShareLink(
                item: payload.url,
                subject: Text(payload.title),
                message: Text(payload.text)
            ) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up")
                    Text("Compartir enlace")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)
        .padding(.bottom, 12)
        .background {
            Rectangle()
                .fill(.regularMaterial)
                .ignoresSafeArea()
        }
        .presentationDetents([.height(318)])
        .presentationDragIndicator(.visible)
        .presentationBackground(.clear)
    }

    private var contextKicker: String {
        switch payload.target {
        case .app:
            "Toda la app"
        case .bus(let id, _):
            "Parada \(id)"
        case .metro(let name, let direction):
            name == nil ? "Metro · \(direction.rawValue)" : "Estación · \(direction.rawValue)"
        case .ctagr(let id, _):
            "Consorcio \(id)"
        }
    }

    private var contextTitle: String {
        switch payload.target {
        case .app:
            "Buses y metro de Granada"
        case .bus(_, let name):
            name
        case .metro(let name, let direction):
            name ?? "Sentido \(direction.rawValue)"
        case .ctagr(_, let name):
            name
        }
    }

    @ViewBuilder
    private var contextGlyph: some View {
        switch payload.target {
        case .app:
            Image("movgr-mark")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
        case .bus:
            BusFrontGlyph()
        case .metro:
            TramFrontGlyph()
        case .ctagr:
            BusFrontGlyph()
                .foregroundStyle(BrandColor.ctagr)
        }
    }

    static func qrImage(from string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        let context = CIContext()
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
