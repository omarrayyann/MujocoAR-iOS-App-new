import UIKit

struct Line {
    let from: CGPoint
    let to: CGPoint
}
struct HandOverlay {
    let dots: [CGPoint]
    let lines: [Line]
}

class OverlayView: UIView {
    // Transparent background
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
        isOpaque = false
    }

    private var overlays: [HandOverlay] = []

    /// Replace old overlays each frame
    func draw(overlays: [HandOverlay]) {
        self.overlays = overlays
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard !overlays.isEmpty else { return }

        // Draw bones
        UIColor.systemBlue.setStroke()
        let bonePath = UIBezierPath()
        bonePath.lineWidth = 2
        for o in overlays {
          for line in o.lines {
            bonePath.move(to: line.from)
            bonePath.addLine(to: line.to)
          }
        }
        bonePath.stroke()

        // Draw joints
        UIColor.red.setFill()
        for o in overlays {
          for dot in o.dots {
            let r: CGFloat = 6
            let d = CGRect(x: dot.x - r,
                           y: dot.y - r,
                           width: 2*r, height: 2*r)
            UIBezierPath(ovalIn: d).fill()
          }
        }
    }
}
