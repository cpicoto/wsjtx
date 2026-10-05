import Foundation
import Combine

// MARK: - Q65 Period

/// T/R sequence length in seconds.
public enum Q65Period: Int, CaseIterable, Identifiable, Codable {
    case p15  = 15
    case p30  = 30
    case p60  = 60
    case p120 = 120
    case p300 = 300

    public var id: Int { rawValue }

    public var label: String { "\(rawValue)s" }

    /// Recommended band/use-case hint.
    public var hint: String {
        switch self {
        case .p15:  return "2 m tropo/MS"
        case .p30:  return "70 cm"
        case .p60:  return "23 cm / 70 cm EME"
        case .p120: return "23 cm EME (deep)"
        case .p300: return "6 cm+ EME"
        }
    }
}

// MARK: - Q65 TX Slot

/// Which half of the period pair this station transmits in.
/// Mirrors the WSJT-X "1st / 2nd" toggle.
public enum Q65TxSlot: String, CaseIterable, Identifiable, Codable {
    case first  = "1st"
    case second = "2nd"

    public var id: String { rawValue }

    /// Returns true when the current UTC time falls in this station's TX slot.
    public func isMyTurn(period: Q65Period) -> Bool {
        let t = Int(Date().timeIntervalSince1970)
        let slot = (t / period.rawValue) % 2  // 0 = even, 1 = odd
        return self == .first ? slot == 0 : slot == 1
    }
}

// MARK: - Q65 Config

/// All Q65-specific operating parameters, mirroring the WSJT-X desktop controls.
public final class Q65Config: ObservableObject {

    /// Tone-spacing sub-mode (A = widest, E = narrowest).
    @Published public var subMode: Q65SubMode = .a

    /// T/R sequence length.
    @Published public var period: Q65Period = .p60

    /// Audio receive frequency (Hz) — yellow marker on waterfall.
    /// Signals within ±tolerance of rxFreq are decoded.
    @Published public var rxFreq: Int = 1_000

    /// Audio transmit frequency (Hz) — red marker while TX is active.
    /// May differ from rxFreq for split/Doppler-corrected operation.
    @Published public var txFreq: Int = 1_000

    /// Whether TX and RX frequencies are locked together.
    @Published public var freqLocked: Bool = true

    /// TX slot within the period pair.
    @Published public var txSlot: Q65TxSlot = .first

    /// Shorthand for the current mode label, e.g. "Q65-60A".
    public var modeLabel: String { "Q65-\(period.rawValue)\(subMode.rawValue)" }

    /// Returns the tone separation for the current sub-mode.
    public var toneSeparation: Double { subMode.toneSeparation }

    /// Returns the cycle length for the current period (as Double, for RadioMode compat).
    public var cycleLength: Double { Double(period.rawValue) }

    // Keep RX and TX in sync when locked
    public init() {
        // Observe rxFreq changes and mirror to txFreq when locked
    }

    public func setRxFreq(_ hz: Int) {
        rxFreq = hz
        if freqLocked { txFreq = hz }
    }

    public func setTxFreq(_ hz: Int) {
        txFreq = hz
        if freqLocked { rxFreq = hz }
    }
}
