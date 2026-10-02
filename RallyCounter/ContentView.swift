import SwiftUI

struct ContentView: View {
    @StateObject private var model = CounterModel()
    @State private var confirmReset = false

    var body: some View {
        ZStack {
            (model.hitFlash ? Color.orange.opacity(0.35) : Color.black)
                .ignoresSafeArea()
                .animation(.easeOut(duration: 0.15), value: model.hitFlash)

            VStack(spacing: 16) {
                counter
                stats
                history
                Spacer(minLength: 0)
                controls
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .preferredColorScheme(.dark)
        .confirmationDialog("Reset", isPresented: $confirmReset) {
            Button("Reset this session", role: .destructive) { model.resetSession() }
            Button("Reset best rally", role: .destructive) { model.resetBest() }
        }
    }

    // MARK: - Sections

    private var counter: some View {
        VStack(spacing: 4) {
            Text(model.isListening ? "LISTENING" : "PAUSED")
                .font(.caption.weight(.semibold))
                .tracking(2)
                .foregroundStyle(model.isListening ? .green : .secondary)

            Text("\(model.currentRally)")
                .font(.system(size: 150, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.4)
                .lineLimit(1)

            HStack(spacing: 28) {
                Button { model.adjustCurrentRally(by: -1) } label: {
                    Image(systemName: "minus.circle.fill").font(.system(size: 34))
                }
                Text(model.lastRally.map { "Last rally: \($0)" } ?? "Rally")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 120)
                Button { model.adjustCurrentRally(by: 1) } label: {
                    Image(systemName: "plus.circle.fill").font(.system(size: 34))
                }
            }
            .tint(.white.opacity(0.7))
        }
        .padding(.top, 8)
    }

    private var stats: some View {
        HStack {
            stat("Best", model.bestRally)
            stat("Total hits", model.totalHits)
            stat("Rallies", model.rallies.count)
        }
    }

    private func stat(_ title: String, _ value: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(value)").font(.title2.weight(.bold)).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var history: some View {
        if !model.rallies.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(model.rallies.enumerated()), id: \.offset) { _, count in
                        Text("\(count)")
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.08), in: Capsule())
                    }
                }
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 14) {
            LevelMeter(levelDb: model.levelDb, thresholdDb: model.thresholdDb)
                .frame(height: 14)

            VStack(alignment: .leading, spacing: 2) {
                Text("Sensitivity").font(.subheadline)
                Slider(value: $model.sensitivity, in: 0...1)
                Text("Hits should cross the white line; background noise should stay below it.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Stepper(value: $model.rallyGap, in: 1...8, step: 0.5) {
                Text("Rally ends after \(model.rallyGap, specifier: "%.1f") s silence")
                    .font(.subheadline)
            }

            if let error = model.errorMessage {
                Text(error).font(.footnote).foregroundStyle(.red)
            }

            HStack(spacing: 12) {
                Button { confirmReset = true } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.title3.weight(.semibold))
                        .frame(width: 56, height: 56)
                        .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                }
                Button { model.toggleListening() } label: {
                    Text(model.isListening ? "Stop" : "Start listening")
                        .font(.title3.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(model.isListening ? Color.red : Color.green,
                                    in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .foregroundStyle(.white)
        }
    }
}

struct LevelMeter: View {
    var levelDb: Float
    var thresholdDb: Float

    private func fraction(_ db: Float) -> CGFloat {
        CGFloat(min(max((db + 90) / 90, 0), 1)) // -90 dBFS ... 0 dBFS
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.1))
                Capsule()
                    .fill(levelDb > thresholdDb ? Color.orange : Color.green)
                    .frame(width: width * fraction(levelDb))
                    .animation(.linear(duration: 0.05), value: levelDb)
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2)
                    .offset(x: width * fraction(thresholdDb) - 1)
            }
        }
    }
}
