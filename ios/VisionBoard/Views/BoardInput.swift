import SwiftUI
import UIKit

// What a finger landed on, in the board's screen space
enum BoardTarget: Equatable {
    case paper
    // A clipping. One finger on it scrolls the board; a tap selects it.
    case item(String)
    // The selected, unlocked clipping. One finger on it moves it.
    case movable(String)
    // The corner handle of the selected clipping
    case handle(String)

    var itemID: String? {
        switch self {
        case .paper: nil
        case .item(let id), .movable(let id), .handle(let id): id
        }
    }
}

// A one-finger drag that started on the selected clipping or its handle
struct BoardDrag {
    enum Phase { case changed, ended, cancelled }
    var phase: Phase
    var target: BoardTarget
    var start: CGPoint
    var location: CGPoint
}

// Every touch on the board lands here. Moving around is a real UIScrollView,
// so panning, flicking, rubber-banding and pinching (with both fingers moving
// the board too) work exactly like Photos or Maps. The clippings are drawn by
// SwiftUI underneath; this view only tells BoardCanvas where the camera is and
// what was tapped or dragged.
struct BoardInput: UIViewRepresentable {
    var camera: CanvasCamera
    // The canvas area the clippings cover, so the board always reaches past them
    var itemBounds: CGRect?
    var target: (CGPoint) -> BoardTarget
    var onCamera: (CanvasCamera) -> Void
    var onTap: (BoardTarget, CGPoint) -> Void
    var onDoubleTap: (BoardTarget, CGPoint) -> Void
    var onDrag: (BoardDrag) -> Void
    var menu: (String) -> UIMenu?
    // A clipping's outline on screen, for the long-press menu's preview
    var outline: (String) -> CGRect?

    func makeUIView(context: Context) -> BoardInputView {
        let view = BoardInputView()
        view.config = self
        return view
    }

    func updateUIView(_ view: BoardInputView, context: Context) {
        view.config = self
        view.apply(camera)
    }
}

final class BoardInputView: UIView, UIScrollViewDelegate, UIGestureRecognizerDelegate, UIContextMenuInteractionDelegate {
    var config: BoardInput?

    private let scroll = BoardScrollView()
    // Stands for `region` of the canvas; the scroll view zooms it
    private let content = UIView()
    private var region = CGRect.zero
    // Set while the camera is being moved from SwiftUI, so it isn't echoed back
    private var applying = false
    private var reported: CanvasCamera?
    private var pending: CanvasCamera?

    private var tap: UITapGestureRecognizer!
    private var move: UIPanGestureRecognizer!
    private(set) var touchDown: (point: CGPoint, target: BoardTarget)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        backgroundColor = .clear

        scroll.owner = self
        scroll.delegate = self
        scroll.minimumZoomScale = CanvasCamera.zoomRange.lowerBound
        scroll.maximumZoomScale = CanvasCamera.zoomRange.upperBound
        scroll.showsVerticalScrollIndicator = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.scrollsToTop = false
        scroll.delaysContentTouches = false
        scroll.alwaysBounceVertical = true
        scroll.alwaysBounceHorizontal = true
        scroll.bouncesZoom = true
        scroll.backgroundColor = .clear
        content.backgroundColor = .clear
        scroll.addSubview(content)
        addSubview(scroll)

        tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        move = UIPanGestureRecognizer(target: self, action: #selector(moved(_:)))
        move.maximumNumberOfTouches = 1
        for recognizer in [tap!, move!] {
            recognizer.delegate = self
            scroll.addGestureRecognizer(recognizer)
        }
        scroll.addInteraction(UIContextMenuInteraction(delegate: self))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: Camera

    private var interacting: Bool {
        scroll.isTracking || scroll.isDragging || scroll.isDecelerating || scroll.isZooming || scroll.isZoomBouncing
    }

    private var currentCamera: CanvasCamera {
        let zoom = scroll.zoomScale
        return CanvasCamera(
            zoom: zoom,
            offset: CGSize(
                width: -scroll.contentOffset.x - region.minX * zoom,
                height: -scroll.contentOffset.y - region.minY * zoom
            )
        )
    }

    func apply(_ camera: CanvasCamera) {
        guard bounds.width > 0, bounds.height > 0 else {
            pending = camera
            return
        }
        if let reported, reported.isClose(to: camera) {
            if !interacting { growRegionIfNeeded(around: camera) }
            return
        }
        set(camera)
    }

    private func set(_ camera: CanvasCamera) {
        applying = true
        defer { applying = false }
        let zoom = min(max(camera.zoom, scroll.minimumZoomScale), scroll.maximumZoomScale)
        region = Self.region(around: camera, items: config?.itemBounds, viewport: bounds.size)
        if abs(scroll.zoomScale - zoom) > 0.0001 { scroll.zoomScale = zoom }
        layoutContent()
        scroll.setContentOffset(
            CGPoint(x: -camera.offset.width - region.minX * zoom, y: -camera.offset.height - region.minY * zoom),
            animated: false
        )
        reported = currentCamera
    }

    // The scrollable canvas covers the clippings and what's on screen, with
    // room to spare on every side, and grows when you reach its edge
    private static func region(around camera: CanvasCamera, items: CGRect?, viewport: CGSize) -> CGRect {
        let visible = CGRect(
            x: -camera.offset.width / camera.zoom, y: -camera.offset.height / camera.zoom,
            width: viewport.width / camera.zoom, height: viewport.height / camera.zoom
        )
        let covered = items.map { $0.union(visible) } ?? visible
        let margin = max(viewport.width, viewport.height) / CanvasCamera.zoomRange.lowerBound * 0.6
        return covered.insetBy(dx: -margin, dy: -margin)
    }

    private func growRegionIfNeeded(around camera: CanvasCamera) {
        let wanted = Self.region(around: camera, items: config?.itemBounds, viewport: bounds.size)
        let margin = max(bounds.width, bounds.height) / CanvasCamera.zoomRange.lowerBound * 0.3
        guard !region.contains(wanted.insetBy(dx: margin, dy: margin)) else { return }
        set(camera)
    }

    private func layoutContent() {
        let zoom = scroll.zoomScale
        content.bounds = CGRect(origin: .zero, size: region.size)
        content.center = CGPoint(x: region.width * zoom / 2, y: region.height * zoom / 2)
        scroll.contentSize = CGSize(width: region.width * zoom, height: region.height * zoom)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard scroll.frame != bounds else { return }
        let camera = pending ?? (region == .zero ? reported : currentCamera)
        scroll.frame = bounds
        pending = nil
        if let camera { set(camera) }
    }

    private func report() {
        guard !applying, region != .zero else { return }
        let camera = currentCamera
        reported = camera
        config?.onCamera(camera)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { content }
    func scrollViewDidScroll(_ scrollView: UIScrollView) { report() }
    func scrollViewDidZoom(_ scrollView: UIScrollView) { report() }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { settle() }
    }
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { settle() }
    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) { settle() }

    private func settle() {
        guard !interacting else { return }
        growRegionIfNeeded(around: currentCamera)
    }

    // MARK: Touches

    // A single tap acts at once. A second tap close by, soon after, is also
    // a double tap. (A UIKit double-tap recognizer would hold every touch for
    // a moment, so a drag straight after a tap would be lost.)
    private var lastTap: (point: CGPoint, time: TimeInterval)?

    @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
        guard let config else { return }
        let point = recognizer.location(in: self)
        let target = config.target(point)
        let now = ProcessInfo.processInfo.systemUptime
        if let last = lastTap, now - last.time < 0.35, hypot(point.x - last.point.x, point.y - last.point.y) < 30 {
            lastTap = nil
            config.onTap(target, point)
            config.onDoubleTap(target, point)
        } else {
            lastTap = (point, now)
            config.onTap(target, point)
        }
    }

    private var dragging: (start: CGPoint, target: BoardTarget)?

    @objc private func moved(_ recognizer: UIPanGestureRecognizer) {
        guard let config else { return }
        let location = recognizer.location(in: self)
        switch recognizer.state {
        case .began:
            guard let touchDown else { return }
            dragging = (touchDown.point, touchDown.target)
            config.onDrag(BoardDrag(phase: .changed, target: touchDown.target, start: touchDown.point, location: location))
        case .changed:
            guard let dragging else { return }
            config.onDrag(BoardDrag(phase: .changed, target: dragging.target, start: dragging.start, location: location))
        case .ended:
            guard let dragging else { return }
            config.onDrag(BoardDrag(phase: .ended, target: dragging.target, start: dragging.start, location: location))
            self.dragging = nil
        case .cancelled, .failed:
            guard let dragging else { return }
            config.onDrag(BoardDrag(phase: .cancelled, target: dragging.target, start: dragging.start, location: location))
            self.dragging = nil
        default:
            break
        }
    }

    // Where each touch lands decides whether one finger scrolls or moves a clipping
    func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if recognizer === move, let config {
            let point = touch.location(in: self)
            touchDown = (point, config.target(point))
        }
        return true
    }

    override func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        if recognizer === move { return touchStartsMove }
        return super.gestureRecognizerShouldBegin(recognizer)
    }

    var touchStartsMove: Bool {
        switch touchDown?.target {
        case .movable, .handle: true
        default: false
        }
    }

    // MARK: Long-press menu

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        // The location comes in the scroll view's (scrolled) coordinates
        let point = convert(location, from: interaction.view)
        guard let config, let id = config.target(point).itemID, config.menu(id) != nil else { return nil }
        return UIContextMenuConfiguration(identifier: id as NSString, previewProvider: nil) { [weak self] _ in
            self?.config?.menu(id)
        }
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configuration: UIContextMenuConfiguration, highlightPreviewForItemWithIdentifier identifier: any NSCopying) -> UITargetedPreview? {
        preview(for: configuration)
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configuration: UIContextMenuConfiguration, dismissalPreviewForItemWithIdentifier identifier: any NSCopying) -> UITargetedPreview? {
        preview(for: configuration)
    }

    // The clippings are drawn by SwiftUI below this view, so the lifted
    // preview is a snapshot of that spot on screen
    private func preview(for configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        guard let id = configuration.identifier as? String, let rect = config?.outline(id), let window,
              let snapshot = window.resizableSnapshotView(from: convert(rect, to: window), afterScreenUpdates: false, withCapInsets: .zero)
        else { return nil }
        let parameters = UIPreviewParameters()
        parameters.backgroundColor = .clear
        parameters.visiblePath = UIBezierPath(roundedRect: snapshot.bounds, cornerRadius: 12)
        return UITargetedPreview(view: snapshot, parameters: parameters, target: UIPreviewTarget(container: self, center: CGPoint(x: rect.midX, y: rect.midY)))
    }
}

// One finger on the selected clipping moves it rather than the board
final class BoardScrollView: UIScrollView {
    weak var owner: BoardInputView?

    override func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        if recognizer === panGestureRecognizer, recognizer.numberOfTouches < 2, owner?.touchStartsMove == true {
            return false
        }
        return super.gestureRecognizerShouldBegin(recognizer)
    }
}

extension CanvasCamera {
    func isClose(to other: CanvasCamera) -> Bool {
        abs(zoom - other.zoom) < 0.0001
            && abs(offset.width - other.offset.width) < 0.5
            && abs(offset.height - other.offset.height) < 0.5
    }
}
