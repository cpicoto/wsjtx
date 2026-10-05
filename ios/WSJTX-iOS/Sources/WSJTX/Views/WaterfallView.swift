import SwiftUI
import UIKit

// MARK: - Waterfall View

/// Scrolling waterfall spectrogram rendered with a UIKit-backed `CALayer` for
/// performance.  New FFT rows are prepended at the top; older rows scroll down.
public struct WaterfallView: UIViewRepresentable {

    @ObservedObject var data: WaterfallData

    // Frequency axis limits (Hz)
    public var fLow:  Float = 200
    public var fHigh: Float = 3000

    // dB colour map limits
    public var dbLow:  Float = -15
    public var dbHigh: Float =  40

    public func makeUIView(context: Context) -> WaterfallUIView {
        let v = WaterfallUIView()
        v.fLow   = fLow
        v.fHigh  = fHigh
        v.dbLow  = dbLow
        v.dbHigh = dbHigh
        return v
    }

    public func updateUIView(_ uiView: WaterfallUIView, context: Context) {
        guard let newest = data.rows.first else { return }
        uiView.pushRow(newest, freqAxis: data.freqAxis)
    }
}

// MARK: - WaterfallUIView

public final class WaterfallUIView: UIView {

    public var fLow:  Float = 200
    public var fHigh: Float = 3000
    public var dbLow:  Float = -15
    public var dbHigh: Float =  40

    private let pixelRowHeight: Int = 2
    private var imageBuffer: UIImage?
    private let imageView = UIImageView()
    private let freqOverlay = FrequencyAxisOverlay()

    // Freq cursor (touches)
    private var selectedHz: Float = 1000
    public var onFrequencySelected: ((Float) -> Void)?

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) { super.init(coder: coder); setup() }

    private func setup() {
        backgroundColor = .black
        imageView.contentMode = .scaleToFill
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        freqOverlay.translatesAutoresizingMaskIntoConstraints = false
        addSubview(freqOverlay)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),

            freqOverlay.topAnchor.constraint(equalTo: imageView.bottomAnchor),
            freqOverlay.bottomAnchor.constraint(equalTo: bottomAnchor),
            freqOverlay.leadingAnchor.constraint(equalTo: leadingAnchor),
            freqOverlay.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tap)
    }

    // MARK: - Row push

    public func pushRow(_ row: [Float], freqAxis: [Float]) {
        let width = Int(bounds.width) > 0 ? Int(bounds.width) : 375
        let height = pixelRowHeight

        // Map freq axis to pixel x, interpolate dB → colour
        let pixels = mapRow(row, freqAxis: freqAxis, width: width)
        let newStrip = renderStrip(pixels: pixels, width: width, height: height)

        // Compose: new strip at top, shift old image down
        let totalHeight = Int(imageView.bounds.height > 0 ? imageView.bounds.height : 280)
        UIGraphicsBeginImageContextWithOptions(CGSize(width: width, height: totalHeight), false, 1)
        newStrip.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
        if let old = imageBuffer {
            old.draw(in: CGRect(x: 0, y: height, width: width, height: totalHeight - height))
        }
        let composed = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        imageBuffer  = composed
        imageView.image = composed
        freqOverlay.fLow  = fLow
        freqOverlay.fHigh = fHigh
        freqOverlay.setNeedsDisplay()
    }

    // MARK: - Colour mapping

    private func mapRow(_ row: [Float], freqAxis: [Float], width: Int) -> [UIColor] {
        guard !freqAxis.isEmpty else { return [UIColor](repeating: .black, count: width) }
        return (0 ..< width).map { px in
            let hz = fLow + (fHigh - fLow) * Float(px) / Float(width)
            let db = interpolateDB(hz: hz, row: row, freqAxis: freqAxis)
            return waterfallColor(db: db)
        }
    }

    private func interpolateDB(hz: Float, row: [Float], freqAxis: [Float]) -> Float {
        guard let lo = freqAxis.lastIndex(where: { $0 <= hz }),
              lo + 1 < row.count else {
            return row.last ?? dbLow
        }
        let f0 = freqAxis[lo], f1 = freqAxis[lo + 1]
        let t  = f1 > f0 ? (hz - f0) / (f1 - f0) : 0
        return row[lo] * (1 - t) + row[lo + 1] * t
    }

    /// WSJT-X style blue→cyan→green→yellow→red colour map.
    private func waterfallColor(db: Float) -> UIColor {
        let norm = max(0, min(1, (db - dbLow) / (dbHigh - dbLow)))
        let h, s, b: CGFloat
        switch norm {
        case ..<0.25:
            h = 0.67; s = 1; b = CGFloat(norm * 4)
        case ..<0.5:
            h = 0.5 + CGFloat((norm - 0.25) * 2 * 0.17); s = 1; b = 1
        case ..<0.75:
            h = 0.33 - CGFloat((norm - 0.5) * 2 * 0.16); s = 1; b = 1
        default:
            h = 0; s = 1; b = 1
        }
        return UIColor(hue: h, saturation: s, brightness: max(0.05, b), alpha: 1)
    }

    private func renderStrip(pixels: [UIColor], width: Int, height: Int) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(CGSize(width: width, height: height), false, 1)
        for (x, c) in pixels.enumerated() {
            c.setFill()
            UIRectFill(CGRect(x: x, y: 0, width: 1, height: height))
        }
        let img = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
        UIGraphicsEndImageContext()
        return img
    }

    // MARK: - Touch → frequency

    @objc private func handleTap(_ gr: UITapGestureRecognizer) {
        let pt = gr.location(in: imageView)
        let w  = imageView.bounds.width
        guard w > 0 else { return }
        let hz = fLow + (fHigh - fLow) * Float(pt.x / w)
        selectedHz = hz
        onFrequencySelected?(hz)
    }
}

// MARK: - Frequency Axis Overlay

final class FrequencyAxisOverlay: UIView {
    var fLow:  Float = 200
    var fHigh: Float = 3000

    override init(frame: CGRect) { super.init(frame: frame); backgroundColor = .clear }
    required init?(coder: NSCoder) { super.init(coder: coder) }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let tickFreqs: [Float] = stride(from: 500, through: 3000, by: 500).map { $0 }

        let attr: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 9, weight: .regular),
            .foregroundColor: UIColor.lightGray
        ]

        for f in tickFreqs where f >= fLow && f <= fHigh {
            let x = CGFloat((f - fLow) / (fHigh - fLow)) * rect.width
            ctx.setStrokeColor(UIColor.gray.cgColor)
            ctx.setLineWidth(0.5)
            ctx.move(to: CGPoint(x: x, y: 0))
            ctx.addLine(to: CGPoint(x: x, y: 4))
            ctx.strokePath()

            let label = f >= 1000 ? String(format: "%.1fk", f / 1000) : "\(Int(f))"
            (label as NSString).draw(
                at: CGPoint(x: x - 10, y: 5),
                withAttributes: attr
            )
        }
    }
}
