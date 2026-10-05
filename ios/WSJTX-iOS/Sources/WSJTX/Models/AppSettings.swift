import Foundation
import SwiftUI

// MARK: - App Settings

/// Persisted user preferences, stored in UserDefaults.
public final class AppSettings: ObservableObject {

    // MARK: Station
    @AppStorage("myCall")     public var myCall     = ""
    @AppStorage("myGrid")     public var myGrid     = ""
    @AppStorage("myPower")    public var myPower    = 10   // dBm, default 10 mW

    // MARK: Audio
    @AppStorage("txGain")     public var txGain     = 0.5  // 0…1
    @AppStorage("rxGain")     public var rxGain     = 1.0  // 0…1
    @AppStorage("sampleRate") public var sampleRate = 12_000  // Hz

    // MARK: Network / Rig control
    @AppStorage("rigHost")    public var rigHost    = "192.168.1.1"
    @AppStorage("rigPort")    public var rigPort    = 4532  // Hamlib / flrig default
    @AppStorage("wsjtxPort")  public var wsjtxPort  = 2237  // WSJT-X UDP protocol

    // MARK: Decode
    @AppStorage("maxDecodes") public var maxDecodes = 30
    @AppStorage("nSHallow")   public var nShallow   = 2     // shallow decode passes
    @AppStorage("nDeep")      public var nDeep      = 0     // deep decode passes (CPU heavy)
    @AppStorage("tolerance")  public var tolerance   = 4.0  // Hz, frequency pull-in window

    // MARK: Logging
    @AppStorage("logPath")    public var logPath    = Self.defaultLogPath

    // MARK: UI
    @AppStorage("colorSchemeRaw") private var colorSchemeRaw = 0
    public var colorScheme: ColorScheme? {
        switch colorSchemeRaw {
        case 1:  return .light
        case 2:  return .dark
        default: return nil     // follow system
        }
    }
    public func setColorScheme(_ cs: ColorScheme?) {
        switch cs {
        case .light:  colorSchemeRaw = 1
        case .dark:   colorSchemeRaw = 2
        default:      colorSchemeRaw = 0
        }
    }

    @AppStorage("waterfallLow")  public var waterfallLow  = -15.0  // dB
    @AppStorage("waterfallHigh") public var waterfallHigh =  35.0  // dB

    // MARK: PSK Reporter
    @AppStorage("pskReporter")   public var pskReporterEnabled = false

    // MARK: Helpers

    private static var defaultLogPath: String {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("wsjtx.adi").path
    }

    /// Returns the standard WSJT-X ADIF log file URL.
    public var logURL: URL { URL(fileURLWithPath: logPath) }
}
