import SwiftUI

// MARK: - Q65 Config Panel

/// Inline Q65 control strip shown below the band/mode bar when Q65 is selected.
/// Mirrors the WSJT-X desktop controls for sub-mode, period, RX/TX frequency, and slot.
public struct Q65ConfigPanel: View {

    @ObservedObject var config: Q65Config
    @State private var showFullConfig = false

    public init(config: Q65Config) { self.config = config }

    public var body: some View {
        VStack(spacing: 0) {
            summaryRow
            if showFullConfig { detailPanel }
        }
        .background(Color(.tertiarySystemBackground))
    }

    // MARK: Summary row (always visible)

    private var summaryRow: some View {
        HStack(spacing: 10) {
            // Mode label badge
            Text(config.modeLabel)
                .font(.system(.caption, design: .monospaced).bold())
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.purple.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 4))

            // RX / TX freq
            HStack(spacing: 4) {
                Label("\(config.rxFreq) Hz", systemImage: "antenna.radiowaves.left.and.right")
                    .labelStyle(.titleOnly)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.green)

                if config.rxFreq != config.txFreq {
                    Text("→")
                        .font(.caption2).foregroundStyle(.secondary)
                    Text("\(config.txFreq) Hz")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.red)
                }
            }

            Spacer()

            // Slot badge
            Button {
                config.txSlot = config.txSlot == .first ? .second : .first
            } label: {
                Text("TX \(config.txSlot.rawValue)")
                    .font(.caption.bold())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.orange.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)

            // Expand toggle
            Button { withAnimation { showFullConfig.toggle() } } label: {
                Image(systemName: showFullConfig ? "chevron.up" : "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: Detail panel (expandable)

    private var detailPanel: some View {
        VStack(spacing: 10) {
            Divider()

            // Sub-mode and Period in one row
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sub-mode").font(.caption2).foregroundStyle(.secondary)
                    Picker("Sub-mode", selection: $config.subMode) {
                        ForEach(Q65SubMode.allCases) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Period").font(.caption2).foregroundStyle(.secondary)
                    Picker("Period", selection: $config.period) {
                        ForEach(Q65Period.allCases) { p in
                            Text(p.label).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }

            // RX frequency
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("RX freq")
                        .font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(config.rxFreq) Hz")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.green)
                    Stepper("", value: Binding(
                        get: { config.rxFreq },
                        set: { config.setRxFreq($0) }
                    ), in: 200...3000, step: 50)
                    .labelsHidden()
                    .frame(width: 80)
                }
                Slider(
                    value: Binding(
                        get: { Double(config.rxFreq) },
                        set: { config.setRxFreq(Int($0)) }
                    ),
                    in: 200...3000, step: 50
                )
                .tint(.green)
            }

            // TX frequency + lock toggle
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("TX freq")
                        .font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(config.txFreq) Hz")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.red)

                    Toggle("", isOn: $config.freqLocked)
                        .labelsHidden()
                        .onChange(of: config.freqLocked) { _, locked in
                            if locked { config.txFreq = config.rxFreq }
                        }
                    Image(systemName: config.freqLocked ? "lock" : "lock.open")
                        .font(.caption).foregroundStyle(.secondary)
                    Stepper("", value: $config.txFreq, in: 200...3000, step: 50)
                        .labelsHidden()
                        .frame(width: 80)
                        .disabled(config.freqLocked)
                }
                Slider(value: Binding(
                    get: { Double(config.txFreq) },
                    set: { config.txFreq = config.freqLocked ? config.rxFreq : Int($0) }
                ), in: 200...3000, step: 50)
                .tint(.red)
                .disabled(config.freqLocked)
            }

            // TX Slot
            HStack {
                Text("TX slot").font(.caption2).foregroundStyle(.secondary)
                Picker("TX slot", selection: $config.txSlot) {
                    ForEach(Q65TxSlot.allCases) { s in
                        Text(s.rawValue).tag(s)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 140)

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(config.period.hint)
                        .font(.caption2).foregroundStyle(.secondary)
                    SlotStatusBadge(config: config)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }
}

// MARK: - Slot Status Badge

/// Shows "TX NOW" or "RX NOW" based on current UTC time and configured slot.
struct SlotStatusBadge: View {
    @ObservedObject var config: Q65Config
    @State private var myTurn = false
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(myTurn ? "TX NOW" : "RX NOW")
            .font(.caption2.bold())
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(myTurn ? Color.red.opacity(0.2) : Color.green.opacity(0.2))
            .foregroundStyle(myTurn ? .red : .green)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .onReceive(timer) { _ in
                myTurn = config.txSlot.isMyTurn(period: config.period)
            }
            .onAppear {
                myTurn = config.txSlot.isMyTurn(period: config.period)
            }
    }
}
