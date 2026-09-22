import MapKit
import SwiftUI

@MainActor
@Observable
final class MapKitBridge {
    weak var mapView: MKMapView?

    func attach(_ map: MKMapView) {
        mapView = map
        hideLegal(on: map)
    }

    /// How many points of this map view are covered by the bottom sheet.
    func overlap(sheetHeight: CGFloat) -> CGFloat {
        guard let map = mapView else {
            return max(0, sheetHeight)
        }
        let mapInScreen = map.convert(map.bounds, to: nil)
        let screenMaxY = map.window?.windowScene?.screen.bounds.maxY ?? mapInScreen.maxY
        let sheetTop = screenMaxY - sheetHeight
        return min(max(0, mapInScreen.maxY - sheetTop), max(0, map.bounds.height - 80))
    }

    /// Uncovered map rectangle in map-view coordinates (top-left origin).
    func visibleRect(sheetHeight: CGFloat) -> CGRect {
        guard let map = mapView else { return .zero }
        let covered = overlap(sheetHeight: sheetHeight)
        return CGRect(
            x: 0,
            y: 0,
            width: map.bounds.width,
            height: max(80, map.bounds.height - covered)
        )
    }

    func coordinateAtVisibleCenter(sheetHeight: CGFloat) -> CLLocationCoordinate2D? {
        guard let map = mapView, map.bounds.height > 0 else { return nil }
        let rect = visibleRect(sheetHeight: sheetHeight)
        return map.convert(CGPoint(x: rect.midX, y: rect.midY), toCoordinateFrom: map)
    }

    /// Pan so `coordinate` sits in the middle of the uncovered map. Zoom is unchanged.
    /// Does not mutate the live map — SwiftUI owns the camera.
    func regionPlacing(_ coordinate: CLLocationCoordinate2D, atVisibleCenter sheetHeight: CGFloat) -> MKCoordinateRegion? {
        guard let map = mapView, map.bounds.height > 0 else { return nil }
        let rect = visibleRect(sheetHeight: sheetHeight)
        let current = map.convert(coordinate, toPointTo: map)
        let target = CGPoint(x: rect.midX, y: rect.midY)
        var centerPoint = map.convert(map.centerCoordinate, toPointTo: map)
        centerPoint.x += current.x - target.x
        centerPoint.y += current.y - target.y
        var region = map.region
        region.center = map.convert(centerPoint, toCoordinateFrom: map)
        return region
    }

    func regionFocusing(_ coordinate: CLLocationCoordinate2D, meters: CLLocationDistance, sheetHeight: CGFloat) -> MKCoordinateRegion? {
        guard let map = mapView, map.bounds.height > 1 else { return nil }
        var region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: meters,
            longitudinalMeters: meters
        )
        return inset(region, sheetHeight: sheetHeight)
    }

    func regionFitting(_ coordinates: [CLLocationCoordinate2D], sheetHeight: CGFloat) -> MKCoordinateRegion? {
        guard let map = mapView, let first = coordinates.first else { return nil }
        if coordinates.count == 1 {
            return regionFocusing(first, meters: 900, sheetHeight: sheetHeight)
        }
        var zoom = MKMapRect.null
        for coordinate in coordinates {
            let point = MKMapPoint(coordinate)
            zoom = zoom.union(MKMapRect(origin: point, size: MKMapSize(width: 1, height: 1)))
        }
        if zoom.width < 2_000 {
            zoom = zoom.insetBy(dx: -8_000, dy: -8_000)
        }
        let pad = overlap(sheetHeight: sheetHeight)
        let fitted = map.mapRectThatFits(
            zoom,
            edgePadding: UIEdgeInsets(top: 36, left: 28, bottom: pad + 36, right: 28)
        )
        return MKCoordinateRegion(fitted)
    }

    func inset(_ region: MKCoordinateRegion, sheetHeight: CGFloat) -> MKCoordinateRegion {
        guard let map = mapView, map.bounds.height > 1 else { return region }
        let visible = visibleRect(sheetHeight: sheetHeight)
        let height = map.bounds.height
        let width = map.bounds.width
        var region = region
        region.center.latitude -= region.span.latitudeDelta * Double((map.bounds.midY - visible.midY) / height)
        region.center.longitude += region.span.longitudeDelta * Double((visible.midX - map.bounds.midX) / width)
        return region
    }

    private func hideLegal(on map: MKMapView) {
        map.layoutMargins.bottom = 0
        func walk(_ view: UIView) {
            let name = NSStringFromClass(type(of: view))
            if name.contains("Attribution") || name.contains("AppleLogo") || name.contains("LogoImage") {
                view.isHidden = true
                view.alpha = 0
            }
            view.subviews.forEach(walk)
        }
        walk(map)
    }
}

struct MapViewHook: UIViewRepresentable {
    var bridge: MapKitBridge

    func makeUIView(context: Context) -> MapViewHookView {
        let view = MapViewHookView()
        view.bridge = bridge
        return view
    }

    func updateUIView(_ uiView: MapViewHookView, context: Context) {
        uiView.bridge = bridge
        uiView.attachIfNeeded()
    }
}

final class MapViewHookView: UIView {
    var bridge: MapKitBridge?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        attachIfNeeded()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        attachIfNeeded()
    }

    func attachIfNeeded() {
        guard let map = findMapView() else { return }
        MainActor.assumeIsolated {
            bridge?.attach(map)
        }
    }

    private func findMapView() -> MKMapView? {
        var view: UIView? = superview
        while let current = view {
            if let map = current as? MKMapView { return map }
            if let map = search(current) { return map }
            view = current.superview
        }
        return window.flatMap(search)
    }

    private func search(_ root: UIView) -> MKMapView? {
        if let map = root as? MKMapView { return map }
        for child in root.subviews {
            if let map = search(child) { return map }
        }
        return nil
    }
}
