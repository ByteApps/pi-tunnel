import AppKit

/// The menu bar glyph: a tunnel arch drawn as `total` brick segments over a road,
/// with the first `open` segments at full opacity and the rest dimmed. Rendered as a
/// template image so macOS tints it for light, dark and highlighted states.
enum TunnelIcon {
    private static let unit: CGFloat = 22        // design grid
    private static let pointSize: CGFloat = 18   // menu bar size in points
    private static let stroke: CGFloat = 4.4
    private static let gap: CGFloat = 1.2
    private static let dimAlpha: CGFloat = 0.28

    static func image(total: Int, open: Int) -> NSImage {
        let n = max(total, 1)
        let k = min(max(open, 0), n)
        let img = NSImage(size: NSSize(width: pointSize, height: pointSize), flipped: false) { _ in
            let t = NSAffineTransform()
            t.scale(by: pointSize / unit)
            t.concat()
            draw(total: n, open: k)
            return true
        }
        img.isTemplate = true
        return img
    }

    /// M4 3 V11, arc over the top (center 11,11 r7) to 18,11, V3 — y up.
    private static func arch() -> NSBezierPath {
        let p = NSBezierPath()
        p.move(to: NSPoint(x: 4, y: 3))
        p.line(to: NSPoint(x: 4, y: 11))
        p.appendArc(withCenter: NSPoint(x: 11, y: 11), radius: 7, startAngle: 180, endAngle: 0, clockwise: true)
        p.line(to: NSPoint(x: 18, y: 3))
        p.lineWidth = stroke
        p.lineCapStyle = .butt
        return p
    }

    private static var archLength: CGFloat { 8 + .pi * 7 + 8 }

    private static func draw(total n: Int, open k: Int) {
        let g = n > 1 ? gap : 0
        let seg = (archLength - g * CGFloat(n - 1)) / CGFloat(n)

        // Dimmed track: every segment.
        let dim = arch()
        var track: [CGFloat] = [seg, g]
        if n == 1 { track = [seg, 1000] }
        dim.setLineDash(track, count: track.count, phase: 0)
        NSColor.black.withAlphaComponent(dimAlpha).setStroke()
        dim.stroke()

        // Lit segments: k dashes then a 0-length dash followed by a huge gap.
        if k > 0 {
            let lit = arch()
            var pattern: [CGFloat] = []
            for _ in 0..<k { pattern += [seg, g] }
            pattern += [0, 1000]
            lit.setLineDash(pattern, count: pattern.count, phase: 0)
            NSColor.black.setStroke()
            lit.stroke()
        }

        // Road, always solid so the glyph still reads as a tunnel when nothing is open.
        let road = NSBezierPath()
        road.move(to: NSPoint(x: 2, y: 2))
        road.line(to: NSPoint(x: 20, y: 2))
        road.lineWidth = 2
        road.lineCapStyle = .round
        NSColor.black.setStroke()
        road.stroke()
    }

    /// 8pt status dot for menu rows (not a template; keeps its colour).
    static func dot(_ state: PortState) -> NSImage {
        let img = NSImage(size: NSSize(width: 10, height: 10), flipped: false) { _ in
            let color: NSColor
            switch state {
            case .open: color = .systemGreen
            case .busy: color = .systemOrange
            case .closed: color = .tertiaryLabelColor
            }
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: 1, y: 1, width: 8, height: 8)).fill()
            return true
        }
        return img
    }
}
