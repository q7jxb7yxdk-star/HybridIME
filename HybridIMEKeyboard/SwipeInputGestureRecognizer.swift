import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Observes letter touches without delaying taps; takes ownership only after movement.
@MainActor
final class SwipeInputGestureRecognizer: UIGestureRecognizer {
    var acceptsStart: ((CGPoint) -> Bool)?
    var movementThreshold: CGFloat = 14
    private(set) var points: [CGPoint] = []
    private var trackedTouch: UITouch?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard trackedTouch == nil, touches.count == 1, let touch = touches.first,
              touch.type == .direct,
              acceptsStart?(touch.location(in: view)) == true
        else {
            stopRecognition()
            return
        }
        trackedTouch = touch
        points = [touch.location(in: view)]
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = trackedTouch, touches.contains(touch),
              state == .possible || state == .began || state == .changed
        else { return }
        for sample in event.coalescedTouches(for: touch) ?? [touch] {
            append(sample.location(in: view))
        }
        guard let first = points.first, let last = points.last else { return }
        if state == .possible {
            if hypot(last.x - first.x, last.y - first.y) >= movementThreshold {
                state = .began
            }
        } else {
            state = .changed
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = trackedTouch, touches.contains(touch) else { return }
        append(touch.location(in: view))
        state = state == .began || state == .changed ? .ended : .failed
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        stopRecognition()
    }

    override func reset() {
        super.reset()
        trackedTouch = nil
        points = []
    }

    private func stopRecognition() {
        state = state == .began || state == .changed ? .cancelled : .failed
    }

    private func append(_ point: CGPoint) {
        guard point.x.isFinite, point.y.isFinite else { return }
        if let last = points.last,
           hypot(point.x - last.x, point.y - last.y) < 1 { return }
        // Keep long gestures bounded while retaining the original start and the latest end.
        if points.count >= 512 {
            points = points.enumerated().compactMap { $0.offset.isMultiple(of: 2) ? $0.element : nil }
        }
        points.append(point)
    }
}
