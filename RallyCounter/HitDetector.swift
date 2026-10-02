import AVFoundation

/// Detects sharp, high-frequency transients (ball on racket) in a mic stream.
///
/// Pipeline per sample: 1st-order high-pass (~1.5 kHz, removes voices/wind/rumble)
/// -> energy in short hops (128 samples, ~2.7 ms) -> a hop is a hit when it is
/// (a) well above an adaptive noise floor, (b) above an absolute minimum level,
/// (c) a sudden rise vs ~10 ms earlier, and (d) outside the lockout after the last hit.
///
/// `process` runs on the audio thread; callbacks are delivered on the main queue.
final class HitDetector {
    /// 0...1, higher = picks up quieter hits (and more false positives).
    var sensitivity: Float = 0.6
    /// Seconds after a hit during which no new hit can be counted.
    var lockout: Double = 0.15

    var onHit: (() -> Void)?
    var onMeter: ((_ levelDb: Float, _ thresholdDb: Float) -> Void)?

    private let hopSize = 128
    private let highPassCutoff = 1500.0
    private let minRiseDb: Float = 9

    private var sampleRate: Double = 48_000
    private var hpCoeff: Float = 0
    private var hpPrevIn: Float = 0
    private var hpPrevOut: Float = 0
    private var hopSum: Float = 0
    private var hopFill = 0
    private var history = [Float](repeating: -100, count: 4)
    private var historyIndex = 0
    private var floorDb: Float = -70
    private var samplesSinceHit = Int.max / 2
    private var meterPeak: Float = -100
    private var meterHops = 0

    func reset(sampleRate: Double) {
        self.sampleRate = sampleRate
        let rc = 1.0 / (2.0 * Double.pi * highPassCutoff)
        let dt = 1.0 / sampleRate
        hpCoeff = Float(rc / (rc + dt))
        hpPrevIn = 0
        hpPrevOut = 0
        hopSum = 0
        hopFill = 0
        history = [Float](repeating: -100, count: history.count)
        historyIndex = 0
        floorDb = -70
        samplesSinceHit = Int.max / 2
        meterPeak = -100
        meterHops = 0
    }

    func process(_ buffer: AVAudioPCMBuffer) {
        guard let data = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        for i in 0..<count {
            let x = data[i]
            let y = hpCoeff * (hpPrevOut + x - hpPrevIn)
            hpPrevIn = x
            hpPrevOut = y
            hopSum += y * y
            hopFill += 1
            if hopFill == hopSize {
                endHop()
                hopSum = 0
                hopFill = 0
            }
        }
    }

    private func endHop() {
        let db = 10 * log10f(hopSum / Float(hopSize) + 1e-12)
        if samplesSinceHit < Int.max / 2 { samplesSinceHit += hopSize }

        let s = min(max(sensitivity, 0), 1)
        let aboveFloorDb = 28 - 20 * s   // 28 dB (strict) ... 8 dB (sensitive)
        let absoluteMinDb = -30 - 30 * s // -30 dBFS ... -60 dBFS
        let threshold = max(floorDb + aboveFloorDb, absoluteMinDb)

        let earlierDb = history[historyIndex] // value from `history.count` hops ago
        let lockoutSamples = Int(lockout * sampleRate)
        let outsideLockout = samplesSinceHit > lockoutSamples

        if outsideLockout && db > threshold && db - earlierDb > minRiseDb {
            samplesSinceHit = 0
            if let onHit { DispatchQueue.main.async(execute: onHit) }
        } else if outsideLockout {
            // Track the background: drop quickly, rise slowly (~1–2 s).
            let rate: Float = db < floorDb ? 0.05 : 0.003
            floorDb = max(floorDb + rate * (db - floorDb), -90)
        }

        history[historyIndex] = db
        historyIndex = (historyIndex + 1) % history.count

        meterPeak = max(meterPeak, db)
        meterHops += 1
        if meterHops >= 12 {
            if let onMeter {
                let peak = meterPeak
                DispatchQueue.main.async { onMeter(peak, threshold) }
            }
            meterPeak = -100
            meterHops = 0
        }
    }
}
