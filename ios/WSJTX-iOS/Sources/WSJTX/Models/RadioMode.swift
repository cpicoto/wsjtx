import Foundation

// MARK: - Radio Mode

/// All digital modes supported by WSJT-X iOS.
public enum RadioMode: String, CaseIterable, Codable, Identifiable {
    case ft8   = "FT8"
    case ft4   = "FT4"
    case jt65  = "JT65"
    case jt9   = "JT9"
    case wspr  = "WSPR"
    case q65   = "Q65"

    public var id: String { rawValue }

    /// Length of one transmit/receive cycle in seconds.
    public var cycleLength: Double {
        switch self {
        case .ft8:  return 15
        case .ft4:  return 7.5
        case .jt65: return 60
        case .jt9:  return 60
        case .wspr: return 120
        case .q65:  return 60   // Q65-60 (standard for 1.2 GHz / 432 MHz EME)
        }
    }

    /// Tone separation in Hz between adjacent FSK symbols.
    public var toneSeparation: Double {
        switch self {
        case .ft8:  return 6.25
        case .ft4:  return 20.833
        case .jt65: return 2.692
        case .jt9:  return 1.736
        case .wspr: return 1.465
        case .q65:  return 12_000.0 / 6_912.0   // Q65-60A: ≈ 1.7361 Hz
        }
    }

    /// Number of tones in the modulation alphabet.
    public var toneCount: Int {
        switch self {
        case .ft8, .ft4: return 8
        case .jt65:      return 65
        case .jt9:       return 9
        case .wspr:      return 4
        case .q65:       return 64  // 64-tone FSK
        }
    }

    /// Total symbols per transmission frame (including sync).
    public var symbolCount: Int {
        switch self {
        case .ft8:  return 79
        case .ft4:  return 105
        case .jt65: return 126
        case .jt9:  return 85
        case .wspr: return 162
        case .q65:  return 85   // 7 Costas sync + 78 data
        }
    }

    /// Synchronisation-frame first-symbol offset in samples at 12000 Hz.
    public var syncOffset: Int {
        switch self {
        case .ft8:  return 0
        case .ft4:  return 0
        default:    return 0
        }
    }

    /// Whether the mode requires strict UTC synchronisation.
    public var requiresUTCSync: Bool { true }
}

// MARK: - Band

/// Amateur radio HF/VHF bands with their WSJT-X default dial frequencies.
public enum Band: String, CaseIterable, Codable, Identifiable {
    case m160  = "160m"
    case m80   = "80m"
    case m60   = "60m"
    case m40   = "40m"
    case m30   = "30m"
    case m20   = "20m"
    case m17   = "17m"
    case m15   = "15m"
    case m12   = "12m"
    case m10   = "10m"
    case m6    = "6m"
    case m2    = "2m"
    case m70cm = "70cm"
    case m23cm = "23cm"

    public var id: String { rawValue }

    /// Returns the WSJT-X standard dial frequency (Hz) for a given mode.
    public func defaultFrequency(for mode: RadioMode) -> Double {
        switch (self, mode) {
        case (.m160, .ft8):  return 1_840_000
        case (.m80,  .ft8):  return 3_573_000
        case (.m60,  .ft8):  return 5_357_000
        case (.m40,  .ft8):  return 7_074_000
        case (.m30,  .ft8):  return 10_136_000
        case (.m20,  .ft8):  return 14_074_000
        case (.m17,  .ft8):  return 18_100_000
        case (.m15,  .ft8):  return 21_074_000
        case (.m12,  .ft8):  return 24_915_000
        case (.m10,  .ft8):  return 28_074_000
        case (.m6,   .ft8):  return 50_313_000
        case (.m2,   .ft8):  return 144_174_000

        case (.m80,  .ft4):  return 3_575_000
        case (.m40,  .ft4):  return 7_047_500
        case (.m20,  .ft4):  return 14_080_000

        case (.m40,  .wspr): return 7_038_600
        case (.m20,  .wspr): return 14_095_600
        case (.m30,  .wspr): return 10_138_700

        // VHF/UHF/microwave Q65 EME frequencies (WSJT-X defaults)
        case (.m2,   .q65):  return 144_174_000
        case (.m70cm,.q65):  return 432_174_000
        case (.m23cm,.q65):  return 1_296_174_000   // 1.2 GHz / 23 cm EME

        default:             return defaultFrequency(for: .ft8)
        }
    }

    /// Human-readable dial frequency string.
    public func frequencyString(for mode: RadioMode) -> String {
        let f = defaultFrequency(for: mode) / 1_000
        return String(format: "%.3f MHz", f / 1_000)
    }
}
