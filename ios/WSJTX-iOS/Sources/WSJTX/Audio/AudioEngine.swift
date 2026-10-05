import AVFoundation
import Accelerate

// MARK: - Audio Engine

/// Manages real-time audio capture (microphone / line-in) and playback
/// using AVAudioEngine.  All heavy work happens on a dedicated serial queue
/// so the main thread is never blocked.
public final class AudioEngine: ObservableObject {

    // MARK: Public state
    @Published public private(set) var isRunning = false
    @Published public private(set) var inputLevel: Float = 0   // 0…1

    /// Called for every captured buffer.  Runs on `processingQueue`.
    public var onSampleBuffer: (([Float], Double) -> Void)?

    // MARK: Private
    private let engine       = AVAudioEngine()
    private let processingQ  = DispatchQueue(label: "wsjtx.audio", qos: .userInitiated)
    private var playerNode   = AVAudioPlayerNode()
    private let targetRate: Double = 12_000    // WSJT-X standard

    // MARK: - Setup

    public init() {
        setupSession()
        setupGraph()
    }

    private func setupSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord,
                                    mode: .measurement,
                                    options: [.defaultToSpeaker, .allowBluetooth])
            try session.setPreferredSampleRate(48_000)
            try session.setPreferredIOBufferDuration(0.02)
            try session.setActive(true)
        } catch {
            print("[AudioEngine] Session setup error: \(error)")
        }
    }

    private let txSampleRate: Double = 48_000  // hardware output rate for TX

    private func setupGraph() {
        let input  = engine.inputNode
        let rxFmt  = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        let txFmt  = AVAudioFormat(standardFormatWithSampleRate: txSampleRate, channels: 1)!

        engine.attach(playerNode)
        // Connect player node with the same explicit format used for TX buffers;
        // mismatched formats are what caused the NSException / SIGABRT on transmit.
        engine.connect(playerNode, to: engine.mainMixerNode, format: txFmt)

        // Down-sample tap: capture at 48 kHz, present 12 kHz to decoder
        input.installTap(onBus: 0, bufferSize: 4096, format: rxFmt) { [weak self] buf, _ in
            guard let self, let data = buf.floatChannelData?[0] else { return }
            let count = Int(buf.frameLength)
            let samples = Array(UnsafeBufferPointer(start: data, count: count))
            let down = self.downsample(samples, from: 48_000, to: Int(self.targetRate))
            let rms = self.rms(down)
            DispatchQueue.main.async { self.inputLevel = min(rms * 4, 1) }
            self.onSampleBuffer?(down, self.targetRate)
        }
    }

    // MARK: - Control

    public func start() {
        guard !isRunning else { return }
        do {
            try engine.start()
            isRunning = true
        } catch {
            print("[AudioEngine] Start error: \(error)")
        }
    }

    public func stop() {
        guard isRunning else { return }
        engine.stop()
        isRunning = false
    }

    // MARK: - Transmit

    /// Converts FSK symbol indices to an audio waveform and plays it.
    /// Synthesises at 48 kHz to match the playerNode's output connection format.
    public func transmit(symbols: [Int], mode: RadioMode) {
        let sampleRate = txSampleRate  // 48 kHz — must match the playerNode connection format
        let symLen = Int(sampleRate / mode.toneSeparation)  // samples per symbol
        let totalSamples = symbols.count * symLen
        var wave = [Float](repeating: 0, count: totalSamples)
        var phase: Double = 0

        let baseFreq = 1_000.0   // base audio offset Hz

        for (i, sym) in symbols.enumerated() {
            let freq = baseFreq + Double(sym) * mode.toneSeparation
            let start = i * symLen
            for j in 0 ..< symLen {
                let t = Double(j) / sampleRate
                wave[start + j] = Float(sin(2 * .pi * freq * t + phase))
            }
            // maintain phase continuity across symbols
            phase += 2 * .pi * freq * Double(symLen) / sampleRate
        }

        // Apply raised-cosine ramp to avoid key clicks (8-ms edges)
        let rampLen = Int(sampleRate * 0.008)
        for i in 0 ..< min(rampLen, wave.count) {
            let t = Double(i) / Double(rampLen)
            let env = Float(0.5 * (1 - cos(.pi * t)))
            wave[i] *= env
            wave[wave.count - 1 - i] *= env
        }

        guard let fmt = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(wave.count))
        else { return }

        buf.frameLength = AVAudioFrameCount(wave.count)
        wave.withUnsafeBufferPointer { ptr in
            buf.floatChannelData?[0].update(from: ptr.baseAddress!, count: wave.count)
        }

        guard engine.isRunning else { return }
        if !playerNode.isPlaying { playerNode.play() }
        playerNode.scheduleBuffer(buf) { [weak self] in
            DispatchQueue.main.async { self?.playerNode.stop() }
        }
    }

    // MARK: - DSP helpers

    private func downsample(_ samples: [Float], from inRate: Int, to outRate: Int) -> [Float] {
        let ratio = inRate / outRate
        guard ratio > 1 else { return samples }

        // Simple polyphase FIR decimation: first low-pass filter then pick every Nth sample.
        // For production use replace with vDSP_decimf / Apple's Accelerate polyphase filters.
        var filtered = samples
        let cutoff: Float = Float(outRate) / Float(inRate) * 0.45
        filtered = firLowPass(filtered, cutoff: cutoff, order: 32)

        var out = [Float]()
        out.reserveCapacity(samples.count / ratio)
        stride(from: 0, to: filtered.count, by: ratio).forEach { out.append(filtered[$0]) }
        return out
    }

    private func firLowPass(_ input: [Float], cutoff: Float, order: Int) -> [Float] {
        // Kaiser-windowed sinc FIR.
        let n = order + 1
        var kernel = [Float](repeating: 0, count: n)
        let M = Float(order)
        for i in 0 ..< n {
            let x = Float(i) - M / 2
            kernel[i] = x == 0 ? 2 * cutoff : sin(2 * .pi * cutoff * x) / (.pi * x)
            // Hamming window
            kernel[i] *= 0.54 - 0.46 * cos(2 * .pi * Float(i) / M)
        }
        var out = [Float](repeating: 0, count: input.count)
        vDSP_conv(input, 1, kernel, 1, &out, 1, vDSP_Length(input.count), vDSP_Length(n))
        return out
    }

    private func rms(_ samples: [Float]) -> Float {
        var val: Float = 0
        vDSP_measqv(samples, 1, &val, vDSP_Length(samples.count))
        return sqrt(val)
    }
}
