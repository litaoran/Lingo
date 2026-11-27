import AVFoundation
import CoreAudio
import Foundation

/// Records from the default input device and converts to 16 kHz mono Float32,
/// the format every supported model expects.
///
/// Turning on Apple's voice processing (echo cancellation) takes a few hundred
/// milliseconds, so the recorder can `prewarm()` an engine while idle: the engine
/// is configured and prepared, but not started, so the microphone stays off until
/// `start()`.
final class AudioRecorder {
    private struct PreparedEngine {
        let engine: AVAudioEngine
        let converter: AVAudioConverter
        let inputFormat: AVAudioFormat
        let echoCancellationRequested: Bool
        let echoCancellationActive: Bool
        let deviceID: AudioDeviceID
        let setupDuration: TimeInterval
    }

    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: Double(TranscriptionEngine.sampleRate),
        channels: 1,
        interleaved: false
    )!

    /// All engine work happens on this queue, so a prewarm in progress and a
    /// start never touch an engine at the same time.
    private let queue = DispatchQueue(label: "io.github.litaoran.Lingo.AudioRecorder", qos: .userInteractive)
    private var prepared: PreparedEngine?
    private var running: PreparedEngine?

    private let lock = NSLock()
    private var samples: [Float] = []
    private var converter: AVAudioConverter?

    /// Called on the audio thread with the RMS level of each buffer.
    var onLevel: ((Float) -> Void)?

    /// Whether the current or last recording used Apple's voice processing.
    private(set) var echoCancellationActive = false
    /// Seconds from `start()` until the first audio buffer arrived.
    private(set) var startupLatency: TimeInterval?
    /// Seconds the last `start()` spent configuring an engine (0 when prewarmed).
    private(set) var voiceProcessingSetup: TimeInterval = 0
    /// Seconds the last `start()` spent in `AVAudioEngine.start()`.
    private(set) var engineStartDuration: TimeInterval = 0
    /// Whether the last `start()` used a prewarmed engine.
    private(set) var usedPrewarmedEngine = false
    private var startedAt = Date()

    /// Prepares an engine in the background so the next `start()` is fast.
    /// The microphone stays off.
    func prewarm(echoCancellation: Bool) {
        queue.async { [self] in
            guard running == nil else { return }
            let device = Self.defaultInputDevice()
            if let prepared, prepared.echoCancellationRequested == echoCancellation, prepared.deviceID == device {
                return
            }
            prepared = try? makeEngine(echoCancellation: echoCancellation, device: device)
        }
    }

    /// Starts recording. With `echoCancellation`, Apple's voice processing removes
    /// sound the Mac itself is playing (videos, music, calls) from the microphone
    /// signal, so only your voice is transcribed. Falls back to the raw microphone
    /// if voice processing isn't available.
    func start(echoCancellation: Bool) throws {
        try queue.sync {
            guard running == nil else { return }
            startedAt = Date()
            startupLatency = nil

            let device = Self.defaultInputDevice()
            let ready = prepared
            prepared = nil
            if let ready, ready.echoCancellationRequested == echoCancellation, ready.deviceID == device {
                do {
                    usedPrewarmedEngine = true
                    voiceProcessingSetup = 0
                    try run(ready)
                    return
                } catch {
                    // The device may have changed since the engine was prepared; build a fresh one.
                }
            }
            let fresh = try makeEngine(echoCancellation: echoCancellation, device: device)
            usedPrewarmedEngine = false
            voiceProcessingSetup = fresh.setupDuration
            try run(fresh)
        }
    }

    /// Stops recording and returns everything captured since `start()`.
    func stop() -> [Float] {
        queue.sync {
            if let running {
                running.engine.inputNode.removeTap(onBus: 0)
                running.engine.stop()
            }
            running = nil
            lock.lock()
            converter = nil
            lock.unlock()
        }
        lock.lock()
        defer { lock.unlock() }
        let captured = samples
        samples = []
        return captured
    }

    // MARK: Engine setup (on `queue`)

    private func makeEngine(echoCancellation: Bool, device: AudioDeviceID) throws -> PreparedEngine {
        let began = Date()
        // A fresh engine picks up the current default input device.
        let engine = AVAudioEngine()
        let input = engine.inputNode
        var echoActive = false
        if echoCancellation {
            do {
                try input.setVoiceProcessingEnabled(true)
                // Keep other apps' audio at its normal volume while recording.
                input.voiceProcessingOtherAudioDuckingConfiguration =
                    AVAudioVoiceProcessingOtherAudioDuckingConfiguration(
                        enableAdvancedDucking: false, duckingLevel: .min)
                echoActive = true
            } catch {
                echoActive = false
            }
        }

        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw LingoError.microphoneUnavailable("no input device found")
        }
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw LingoError.microphoneUnavailable("unsupported input format \(inputFormat)")
        }
        if inputFormat.channelCount > 1 {
            // Voice processing and multi-channel interfaces put the voice on channel 0.
            converter.channelMap = [0]
        }
        engine.prepare()
        return PreparedEngine(
            engine: engine, converter: converter, inputFormat: inputFormat,
            echoCancellationRequested: echoCancellation, echoCancellationActive: echoActive,
            deviceID: device, setupDuration: Date().timeIntervalSince(began))
    }

    private func run(_ candidate: PreparedEngine) throws {
        lock.lock()
        samples.removeAll(keepingCapacity: true)
        converter = candidate.converter
        lock.unlock()

        let input = candidate.engine.inputNode
        input.installTap(onBus: 0, bufferSize: 1024, format: candidate.inputFormat) { [weak self] buffer, _ in
            self?.process(buffer)
        }
        let began = Date()
        do {
            try candidate.engine.start()
        } catch {
            input.removeTap(onBus: 0)
            lock.lock()
            converter = nil
            lock.unlock()
            throw LingoError.microphoneUnavailable(error.localizedDescription)
        }
        engineStartDuration = Date().timeIntervalSince(began)
        echoCancellationActive = candidate.echoCancellationActive
        running = candidate
    }

    private static func defaultInputDevice() -> AudioDeviceID {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return device
    }

    // MARK: Audio thread

    private func process(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let converter = self.converter
        lock.unlock()
        guard let converter else { return }
        if startupLatency == nil { startupLatency = Date().timeIntervalSince(startedAt) }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        var fed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if fed {
                status.pointee = .noDataNow
                return nil
            }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let channel = output.floatChannelData?[0] else { return }

        let count = Int(output.frameLength)
        guard count > 0 else { return }
        let chunk = UnsafeBufferPointer(start: channel, count: count)

        var sumOfSquares: Float = 0
        for sample in chunk { sumOfSquares += sample * sample }

        lock.lock()
        samples.append(contentsOf: chunk)
        lock.unlock()

        onLevel?((sumOfSquares / Float(count)).squareRoot())
    }
}
