import AVFoundation
import SwiftUI
import UIKit

/// Owns the audio engine and the rally/score state. All public members are used on the main thread.
final class CounterModel: ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var currentRally = 0
    @Published private(set) var lastRally: Int?
    @Published private(set) var totalHits = 0
    @Published private(set) var rallies: [Int] = []
    @Published private(set) var levelDb: Float = -100
    @Published private(set) var thresholdDb: Float = -40
    @Published private(set) var hitFlash = false
    @Published var errorMessage: String?

    @Published var sensitivity: Double {
        didSet {
            detector.sensitivity = Float(sensitivity)
            UserDefaults.standard.set(sensitivity, forKey: "sensitivity")
        }
    }
    /// Silence longer than this (seconds) ends the rally.
    @Published var rallyGap: Double {
        didSet { UserDefaults.standard.set(rallyGap, forKey: "rallyGap") }
    }
    @Published private(set) var bestRally: Int {
        didSet { UserDefaults.standard.set(bestRally, forKey: "bestRally") }
    }

    private let engine = AVAudioEngine()
    private let detector = HitDetector()
    private var lastHitTime: Date?
    private var rallyTimer: Timer?
    private var observers: [NSObjectProtocol] = []

    init() {
        let defaults = UserDefaults.standard
        sensitivity = defaults.object(forKey: "sensitivity") as? Double ?? 0.6
        rallyGap = defaults.object(forKey: "rallyGap") as? Double ?? 3
        bestRally = defaults.integer(forKey: "bestRally")
        detector.sensitivity = Float(sensitivity)

        detector.onHit = { [weak self] in self?.registerHit() }
        detector.onMeter = { [weak self] level, threshold in
            self?.levelDb = level
            self?.thresholdDb = threshold
        }

        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification,
                                            object: nil, queue: .main) { [weak self] note in
            self?.handleInterruption(note)
        })
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange,
                                            object: engine, queue: .main) { [weak self] _ in
            guard let self, self.isListening else { return }
            self.restartEngine()
        })
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    // MARK: - Controls

    func toggleListening() {
        isListening ? stop() : start()
    }

    func start() {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async {
                if granted {
                    self.startEngine()
                } else {
                    self.errorMessage = "Microphone access is off. Enable it in Settings → Privacy & Security → Microphone."
                }
            }
        }
    }

    func stop() {
        stopEngine()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isListening = false
        UIApplication.shared.isIdleTimerDisabled = false
        rallyTimer?.invalidate()
        rallyTimer = nil
        closeRally()
        levelDb = -100
    }

    func adjustCurrentRally(by delta: Int) {
        let newValue = max(0, currentRally + delta)
        totalHits = max(0, totalHits + (newValue - currentRally))
        currentRally = newValue
        if currentRally > bestRally { bestRally = currentRally }
        if delta > 0 && lastHitTime == nil { lastHitTime = Date() }
    }

    func resetSession() {
        currentRally = 0
        lastRally = nil
        totalHits = 0
        rallies = []
        lastHitTime = nil
    }

    func resetBest() {
        bestRally = 0
    }

    // MARK: - Hits & rallies

    private func registerHit() {
        let now = Date()
        if let last = lastHitTime, now.timeIntervalSince(last) > rallyGap {
            closeRally()
        }
        lastHitTime = now
        currentRally += 1
        totalHits += 1
        if currentRally > bestRally { bestRally = currentRally }

        hitFlash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.hitFlash = false
        }
    }

    private func checkRallyEnded() {
        guard let last = lastHitTime, Date().timeIntervalSince(last) > rallyGap else { return }
        closeRally()
    }

    private func closeRally() {
        if currentRally > 0 {
            rallies.insert(currentRally, at: 0)
            lastRally = currentRally
        }
        currentRally = 0
        lastHitTime = nil
    }

    // MARK: - Audio

    private struct NoInputError: LocalizedError {
        var errorDescription: String? { "No microphone input is available." }
    }

    private func startEngine() {
        do {
            let session = AVAudioSession.sharedInstance()
            // .measurement turns off iOS voice processing / auto gain, which would flatten the hit transients.
            try session.setCategory(.record, mode: .measurement, options: [])
            try? session.setPreferredIOBufferDuration(0.005)
            try session.setActive(true)

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { throw NoInputError() }

            detector.reset(sampleRate: format.sampleRate)
            input.removeTap(onBus: 0)
            let detector = self.detector
            input.installTap(onBus: 0, bufferSize: 256, format: format) { buffer, _ in
                detector.process(buffer)
            }
            engine.prepare()
            try engine.start()

            isListening = true
            errorMessage = nil
            UIApplication.shared.isIdleTimerDisabled = true
            if rallyTimer == nil {
                rallyTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                    self?.checkRallyEnded()
                }
            }
        } catch {
            errorMessage = "Couldn't start the microphone: \(error.localizedDescription)"
            stop()
        }
    }

    private func stopEngine() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    private func restartEngine() {
        stopEngine()
        startEngine()
    }

    private func handleInterruption(_ note: Notification) {
        guard isListening,
              let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw),
              type == .ended else { return }
        restartEngine()
    }
}
