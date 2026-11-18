import SwiftUI
import UIKit

// Press and hold a clipping, and round buttons fan out around your finger.
// Slide onto one and let go to run it; let go anywhere else to close. One
// dial serves the whole app: the Feed and the board fill it with their own
// actions, and RootView draws it above everything, tab bar included.

struct DialAction: Identifiable {
    let id: String
    let title: String
    let symbol: String
    // The color the icon takes while the finger is on it (red for Delete)
    var tint: Color = .black
    let run: @MainActor () -> Void
}

@MainActor
@Observable
final class ActionDial {
    static let shared = ActionDial()

    // Where the finger came down, in window points
    private(set) var origin: CGPoint = .zero
    private(set) var actions: [DialAction] = []
    private(set) var hovered: Int?
    private(set) var isShown = false
    // Which way the arc opens, in radians, so it stays on screen
    private(set) var direction: Double = -.pi / 2
    @ObservationIgnored private var screen: CGRect = .zero

    static let radius: CGFloat = 88
    static let buttonSize: CGFloat = 56
    private static let step = 0.78 // about 45 degrees between buttons

    private let thump = UIImpactFeedbackGenerator(style: .medium)
    private let tick = UISelectionFeedbackGenerator()
    private let done = UIImpactFeedbackGenerator(style: .light)

    func begin(at point: CGPoint, in screen: CGRect, actions: [DialAction]) {
        guard !actions.isEmpty else { return }
        self.screen = screen
        self.actions = actions
        origin = point
        hovered = nil
        // Open toward the middle of the screen: up by default, leaning away
        // from the nearer side edge, and down when the finger is near the top
        let lean = Double(max(-1, min(1, (screen.midX - point.x) / (screen.width / 2))))
        let nearTop = point.y - Self.radius - Self.buttonSize < screen.minY + 70
        direction = nearTop ? .pi / 2 - lean * 0.9 : -.pi / 2 + lean * 0.9
        thump.impactOccurred()
        tick.prepare()
        withAnimation(.spring(duration: 0.28, bounce: 0.3)) { isShown = true }
    }

    func move(to point: CGPoint) {
        guard isShown else { return }
        let next = target(at: point)
        if next != hovered {
            hovered = next
            if next != nil { tick.selectionChanged() }
        }
    }

    // Runs the action under the finger, if any, then closes
    func end(at point: CGPoint) {
        guard isShown else { return }
        let picked = target(at: point).map { actions[$0] }
        close()
        if let picked {
            done.impactOccurred()
            picked.run()
        }
    }

    func cancel() {
        guard isShown else { return }
        close()
    }

    private func close() {
        withAnimation(.easeOut(duration: 0.15)) {
            isShown = false
            hovered = nil
        }
    }

    func angle(of index: Int) -> Double {
        direction + (Double(index) - Double(actions.count - 1) / 2) * Self.step
    }

    // Each button's center, nudged in so none is cut off by the screen edge
    func position(of index: Int) -> CGPoint {
        let a = angle(of: index)
        let p = CGPoint(x: origin.x + Self.radius * cos(a), y: origin.y + Self.radius * sin(a))
        let margin = Self.buttonSize / 2 + 6
        return CGPoint(
            x: min(max(p.x, screen.minX + margin), screen.maxX - margin),
            y: min(max(p.y, screen.minY + margin + 44), screen.maxY - margin)
        )
    }

    // The button the finger is on, or points at once it has moved away
    // from the center. A small slide is enough, as on Pinterest.
    private func target(at point: CGPoint) -> Int? {
        guard !actions.isEmpty else { return nil }
        let near = actions.indices.min { distance(point, position(of: $0)) < distance(point, position(of: $1)) }!
        if distance(point, position(of: near)) < Self.buttonSize * 0.75 { return near }
        guard distance(point, origin) > 34 else { return nil }
        let heading = atan2(point.y - origin.y, point.x - origin.x)
        let closest = actions.indices.min { gap(heading, angle(of: $0)) < gap(heading, angle(of: $1)) }!
        return gap(heading, angle(of: closest)) < Self.step * 0.7 ? closest : nil
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

    private func gap(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 2 * .pi)
        return min(d, 2 * .pi - d)
    }
}

// Drawn once, over the whole window. It never takes touches: the finger
// stays with whatever started the press.
struct ActionDialOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let dial = ActionDial.shared

    var body: some View {
        GeometryReader { geo in
            let shift = geo.frame(in: .global).origin
            if dial.isShown {
                ZStack(alignment: .topLeading) {
                    Color.black.opacity(0.35)
                    DialRing(dial: dial, shift: shift, reduceMotion: reduceMotion)
                }
                .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

private struct DialRing: View {
    let dial: ActionDial
    let shift: CGPoint
    let reduceMotion: Bool
    @State private var out = false

    var body: some View {
        let origin = local(dial.origin)
        ZStack(alignment: .topLeading) {
            Circle()
                .stroke(.white.opacity(0.7), lineWidth: 3)
                .frame(width: 46, height: 46)
                .position(origin)

            ForEach(Array(dial.actions.enumerated()), id: \.element.id) { index, action in
                let on = dial.hovered == index
                Image(systemName: action.symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(on ? action.tint : .white)
                    .frame(width: ActionDial.buttonSize, height: ActionDial.buttonSize)
                    .background(on ? Color.white : Color(white: 0.2).opacity(0.92), in: Circle())
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 2)
                    .scaleEffect(on ? 1.18 : (out ? 1 : 0.4))
                    .position(out ? local(dial.position(of: index)) : origin)
                    .animation(.spring(duration: 0.2, bounce: 0.35), value: on)
            }

            if let index = dial.hovered {
                Text(dial.actions[index].title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.white, in: Capsule())
                    .fixedSize()
                    .position(labelPoint(index))
                    .transition(.opacity)
                    .id(index)
            }
        }
        .onAppear {
            if reduceMotion {
                out = true
            } else {
                withAnimation(.spring(duration: 0.3, bounce: 0.35)) { out = true }
            }
        }
    }

    private func local(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x - shift.x, y: p.y - shift.y) }

    // Just past the hovered button, on the far side from the finger
    private func labelPoint(_ index: Int) -> CGPoint {
        let p = local(dial.position(of: index))
        let below = dial.direction > 0
        return CGPoint(x: p.x, y: p.y + (below ? 1 : -1) * (ActionDial.buttonSize / 2 + 26))
    }
}

// A press-and-hold that opens the dial on any SwiftUI view. `actions` is
// asked when the hold starts, so it always reflects the latest state.
struct DialPress: UIGestureRecognizerRepresentable {
    var actions: @MainActor () -> [DialAction]?

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let hold = UILongPressGestureRecognizer()
        hold.minimumPressDuration = 0.35
        hold.allowableMovement = 12
        return hold
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        let dial = ActionDial.shared
        let point = recognizer.location(in: nil)
        switch recognizer.state {
        case .began:
            guard let window = recognizer.view?.window, let list = actions() else { return }
            dial.begin(at: point, in: window.bounds, actions: list)
        case .changed:
            dial.move(to: point)
        case .ended:
            dial.end(at: point)
        case .cancelled, .failed:
            dial.cancel()
        default:
            break
        }
    }
}
