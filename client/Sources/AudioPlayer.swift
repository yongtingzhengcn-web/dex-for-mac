import Foundation
import AVFoundation

/// Plays the scrcpy raw audio stream: PCM signed 16-bit little-endian, stereo,
/// 48000 Hz, delivered as framed packets (12-byte headers are stripped by the
/// session before data reaches here).
final class AudioPlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format: AVAudioFormat?
    private var started = false

    /// Don't let more than this much audio sit queued, or latency grows.
    private let maxQueuedSeconds: Double = 0.25
    private var lastBufferEnd: AVAudioTime?

    init() {
        format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 48000,
                               channels: 2, interleaved: true)
    }

    func start() {
        guard !started, let format else { return }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        do {
            try engine.start()
            player.play()
            started = true
        } catch {
            NSLog("DeXClient: audio engine failed to start: \(error)")
        }
    }

    func stop() {
        guard started else { return }
        player.stop()
        engine.stop()
        started = false
        lastBufferEnd = nil
    }

    /// Feed one raw PCM packet (s16le stereo 48k).
    func enqueue(_ data: Data) {
        guard started, let format else { return }
        let frameCount = data.count / 4  // 2 channels × 2 bytes
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(frameCount)) else { return }
        buffer.frameLength = AVAudioFrameCount(frameCount)
        data.withUnsafeBytes { src in
            if let dst = buffer.int16ChannelData {
                memcpy(dst[0], src.baseAddress!, data.count)
            }
        }

        // Drop packets when we are already too far ahead (keeps latency bounded).
        if let end = lastBufferEnd, let now = player.lastRenderTime,
           let nodeTime = player.playerTime(forNodeTime: now) {
            let lead = Double(end.sampleTime - nodeTime.sampleTime) / format.sampleRate
            if lead > maxQueuedSeconds { return }
        }

        let duration = Double(frameCount) / format.sampleRate
        player.scheduleBuffer(buffer, completionHandler: nil)
        if let end = lastBufferEnd {
            lastBufferEnd = AVAudioTime(sampleTime: end.sampleTime + AVAudioFramePosition(frameCount),
                                        atRate: format.sampleRate)
        } else {
            lastBufferEnd = AVAudioTime(sampleTime: AVAudioFramePosition(frameCount),
                                        atRate: format.sampleRate)
        }
        _ = duration
    }
}
