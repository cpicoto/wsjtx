import SwiftUI

@main
struct WSJTXApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(appState)
                .preferredColorScheme(appState.settings.colorScheme)
        }
    }
}

/// Top-level application state shared across all views.
@MainActor
final class AppState: ObservableObject {
    @Published var settings = AppSettings()
    @Published var audioEngine: AudioEngine
    @Published var decoder: FT8Decoder
    @Published var encoder: FT8Encoder
    @Published var messages: [DecodedMessage] = []
    @Published var logbook: [QSORecord] = []
    @Published var currentBand: Band = .m20
    @Published var currentMode: RadioMode = .ft8
    @Published var transmitting = false
    @Published var dxCall = ""
    @Published var dxGrid = ""
    @Published var txMessage = ""
    @Published var rigControl: RigControl

    init() {
        let settings = AppSettings()
        let engine = AudioEngine()
        let dec = FT8Decoder()
        let enc = FT8Encoder(settings: settings)
        let rig = RigControl(settings: settings)

        self.settings = settings
        self.audioEngine = engine
        self.decoder = dec
        self.encoder = enc
        self.rigControl = rig

        wireDecoder(engine: engine, decoder: dec)
    }

    private func wireDecoder(engine: AudioEngine, decoder: FT8Decoder) {
        engine.onSampleBuffer = { [weak self] samples, sampleRate in
            guard let self else { return }
            decoder.ingest(samples: samples, sampleRate: sampleRate)
        }
        decoder.onMessage = { [weak self] msg in
            guard let self else { return }
            Task { @MainActor in
                self.messages.insert(msg, at: 0)
                if self.messages.count > 500 { self.messages.removeLast() }
            }
        }
    }

    func startListening() {
        audioEngine.start()
    }

    func stopListening() {
        audioEngine.stop()
    }

    func transmit(message: String) {
        guard !settings.myCall.isEmpty else { return }
        let symbols = encoder.encode(message: message, mode: currentMode)
        audioEngine.transmit(symbols: symbols, mode: currentMode)
        transmitting = true
    }

    func logQSO() {
        guard !dxCall.isEmpty else { return }
        let record = QSORecord(
            myCall: settings.myCall,
            dxCall: dxCall,
            frequency: currentBand.defaultFrequency(for: currentMode),
            mode: currentMode,
            grid: dxGrid
        )
        logbook.append(record)
        ADIFExporter.append(record: record, to: settings.logPath)
    }
}
