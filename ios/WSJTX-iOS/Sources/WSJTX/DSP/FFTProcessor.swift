import Accelerate
import Foundation

// MARK: - FFT Processor

/// Computes short-time FFT magnitude spectra for the waterfall display
/// and feeds spectral frames into the decoder.
public final class FFTProcessor {

    // MARK: Types
    public struct Frame {
        public let bins: [Float]     // linear magnitude, length == fftSize/2
        public let centerFreqs: [Float]  // Hz for each bin
        public let sampleRate: Double
    }

    // MARK: Configuration
    public let fftSize: Int
    public let overlap: Int          // in samples (default 50 %)
    public let sampleRate: Double

    public var onFrame: ((Frame) -> Void)?

    // MARK: Private
    private var fftSetup: FFTSetup
    private let log2n: vDSP_Length
    private var window: [Float]
    private var accumulator: [Float] = []

    public init(fftSize: Int = 2048, overlap: Int = 1024, sampleRate: Double = 12_000) {
        self.fftSize   = fftSize
        self.overlap   = overlap
        self.sampleRate = sampleRate
        self.log2n = vDSP_Length(log2(Double(fftSize)))
        self.fftSetup  = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!

        // Hann window
        var w = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&w, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        self.window = w
    }

    deinit { vDSP_destroy_fftsetup(fftSetup) }

    // MARK: - Public API

    public func process(samples: [Float]) {
        accumulator.append(contentsOf: samples)

        let hop = fftSize - overlap
        while accumulator.count >= fftSize {
            let slice = Array(accumulator.prefix(fftSize))
            accumulator.removeFirst(hop)
            processFrame(slice)
        }
    }

    // MARK: - Private

    private func processFrame(_ samples: [Float]) {
        // Apply Hann window
        var windowed = [Float](repeating: 0, count: fftSize)
        vDSP_vmul(samples, 1, window, 1, &windowed, 1, vDSP_Length(fftSize))

        // Pack into DSPSplitComplex
        var realPart = [Float](repeating: 0, count: fftSize / 2)
        var imagPart = [Float](repeating: 0, count: fftSize / 2)
        var splitComplex = DSPSplitComplex(realp: &realPart, imagp: &imagPart)

        windowed.withUnsafeBytes { ptr in
            let typedPtr = ptr.bindMemory(to: DSPComplex.self)
            vDSP_ctoz(typedPtr.baseAddress!, 2, &splitComplex, 1, vDSP_Length(fftSize / 2))
        }

        vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))

        // Compute magnitude spectrum (linear)
        var magnitudes = [Float](repeating: 0, count: fftSize / 2)
        vDSP_zvabs(&splitComplex, 1, &magnitudes, 1, vDSP_Length(fftSize / 2))

        // Normalise
        var scale = Float(1.0 / Float(fftSize))
        vDSP_vsmul(magnitudes, 1, &scale, &magnitudes, 1, vDSP_Length(fftSize / 2))

        // Build center-frequency array
        let binHz = Float(sampleRate) / Float(fftSize)
        let freqs = (0 ..< fftSize / 2).map { Float($0) * binHz }

        let frame = Frame(bins: magnitudes, centerFreqs: freqs, sampleRate: sampleRate)
        onFrame?(frame)
    }
}

// MARK: - Waterfall Data

/// Ring buffer of FFT frames for the scrolling waterfall display.
public final class WaterfallData: ObservableObject {
    public let maxRows: Int
    public let binCount: Int

    @Published public private(set) var rows: [[Float]] = []  // newest first
    @Published public private(set) var freqAxis: [Float]  = []

    private let fft: FFTProcessor

    public init(maxRows: Int = 300, fftSize: Int = 2048, sampleRate: Double = 12_000) {
        self.maxRows  = maxRows
        self.binCount = fftSize / 2
        self.fft      = FFTProcessor(fftSize: fftSize, sampleRate: sampleRate)

        fft.onFrame = { [weak self] frame in
            guard let self else { return }
            let dBrow = Self.toDecibels(frame.bins)
            DispatchQueue.main.async {
                if self.freqAxis.isEmpty { self.freqAxis = frame.centerFreqs }
                self.rows.insert(dBrow, at: 0)
                if self.rows.count > maxRows { self.rows.removeLast() }
            }
        }
    }

    public func ingest(samples: [Float]) {
        fft.process(samples: samples)
    }

    // MARK: - Helpers

    private static func toDecibels(_ linear: [Float]) -> [Float] {
        var db = [Float](repeating: 0, count: linear.count)
        var count = Int32(linear.count)
        // vDSP_vdbcon: db[i] = 20 * log10(linear[i] + eps)
        var eps: Float = 1e-12
        vDSP_vsadd(linear, 1, &eps, &db, 1, vDSP_Length(linear.count))
        vDSP_vdbcon(db, 1, [Float(1)], &db, 1, vDSP_Length(linear.count), 0)
        return db
    }
}
