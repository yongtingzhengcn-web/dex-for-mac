import Foundation
import CoreMedia
import VideoToolbox

/// H.264 / H.265 decoding via VideoToolbox.
///
/// The scrcpy server sends MediaCodec output in Annex B format; VideoToolbox wants
/// AVCC (length-prefixed) samples plus a format description built from the
/// parameter sets in the config packet. Decoded frames arrive on a background
/// queue via `onFrame`.
final class VideoDecoder {
    enum Codec: UInt32 {
        case h264 = 0x68323634  // "h264"
        case h265 = 0x68323635  // "h265"
    }

    private let codec: Codec
    private var session: VTDecompressionSession?
    private var formatDescription: CMVideoFormatDescription?
    private let lock = NSLock()

    var onFrame: (CVPixelBuffer) -> Void = { _ in }
    var onError: (String) -> Void = { _ in }

    init(codec: Codec) {
        self.codec = codec
    }

    deinit { invalidate() }

    func invalidate() {
        lock.lock()
        let s = session
        session = nil
        formatDescription = nil
        lock.unlock()
        if let s {
            VTDecompressionSessionWaitForAsynchronousFrames(s)
            VTDecompressionSessionInvalidate(s)
        }
    }

    // MARK: - Annex B parsing

    /// Split Annex B data into NAL units (start codes stripped).
    private func nalUnits(_ data: Data) -> [Data] {
        var units: [Data] = []
        let bytes = [UInt8](data)
        var i = 0
        var start: Int? = nil
        while i + 2 < bytes.count {
            if bytes[i] == 0 && bytes[i + 1] == 0 && bytes[i + 2] == 1 {
                if let s = start, i > s { units.append(Data(bytes[s..<i])) }
                i += 3
                start = i
            } else if i + 3 < bytes.count && bytes[i] == 0 && bytes[i + 1] == 0 && bytes[i + 2] == 0 && bytes[i + 3] == 1 {
                if let s = start, i > s { units.append(Data(bytes[s..<i])) }
                i += 4
                start = i
            } else {
                i += 1
            }
        }
        if let s = start, s < bytes.count { units.append(Data(bytes[s..<bytes.count])) }
        return units
    }

    /// Convert Annex B NAL units to AVCC (4-byte big-endian length prefixes).
    private func avcc(_ units: [Data]) -> Data {
        var out = Data()
        for unit in units where !unit.isEmpty {
            var len = UInt32(unit.count).bigEndian
            withUnsafeBytes(of: &len) { out.append(contentsOf: $0) }
            out.append(unit)
        }
        return out
    }

    // MARK: - Config / format description

    /// Handle a config packet (SPS/PPS[/VPS]) and (re)create the decode session.
    func handleConfig(_ data: Data) {
        let units = nalUnits(data)
        var desc: CMVideoFormatDescription?
        switch codec {
        case .h264:
            var sps: Data?, pps: Data?
            for u in units {
                switch u[u.startIndex] & 0x1F {
                case 7: if sps == nil { sps = u }
                case 8: if pps == nil { pps = u }
                default: break
                }
            }
            guard let spsData = sps, let ppsData = pps else { return }
            desc = makeFormatDescription(sets: [spsData, ppsData], hevc: false)
        case .h265:
            var vps: Data?, sps: Data?, pps: Data?
            for u in units {
                guard u.count >= 2 else { continue }
                switch (u[u.startIndex] >> 1) & 0x3F {
                case 32: if vps == nil { vps = u }
                case 33: if sps == nil { sps = u }
                case 34: if pps == nil { pps = u }
                default: break
                }
            }
            guard let vpsData = vps, let spsData = sps, let ppsData = pps else { return }
            desc = makeFormatDescription(sets: [vpsData, spsData, ppsData], hevc: true)
        }
        guard let desc else {
            onError("Failed to create video format description")
            return
        }
        createSession(formatDescription: desc)
    }

    /// Build a CMVideoFormatDescription from parameter sets (h264: SPS,PPS;
    /// hevc: VPS,SPS,PPS), keeping every Data buffer alive for the whole call.
    private func makeFormatDescription(sets: [Data], hevc: Bool) -> CMVideoFormatDescription? {
        // Collect one UnsafeRawBufferPointer per parameter set, then build the
        // pointer/size arrays the C API wants.
        func withBuffers(_ datas: [Data],
                         _ body: ([UnsafeRawBufferPointer]) -> CMVideoFormatDescription?)
            -> CMVideoFormatDescription? {
            guard let first = datas.first else { return nil }
            return first.withUnsafeBytes { buf in
                if datas.count == 1 { return body([buf]) }
                return withBuffers(Array(datas.dropFirst())) { body([buf] + $0) }
            }
        }
        return withBuffers(sets) { buffers in
            var ptrs = buffers.map { $0.baseAddress!.assumingMemoryBound(to: UInt8.self) }
            var sizes = buffers.map { $0.count }
            var d: CMFormatDescription?
            let status: OSStatus
            if hevc {
                status = CMVideoFormatDescriptionCreateFromHEVCParameterSets(
                    allocator: kCFAllocatorDefault, parameterSetCount: buffers.count,
                    parameterSetPointers: &ptrs, parameterSetSizes: &sizes,
                    nalUnitHeaderLength: 4, extensions: nil, formatDescriptionOut: &d)
            } else {
                status = CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: kCFAllocatorDefault, parameterSetCount: buffers.count,
                    parameterSetPointers: &ptrs, parameterSetSizes: &sizes,
                    nalUnitHeaderLength: 4, formatDescriptionOut: &d)
            }
            return status == noErr ? d : nil
        }
    }

    private func createSession(formatDescription: CMVideoFormatDescription) {
        invalidate()
        var callbackRecord = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: { refcon, _, status, _, imageBuffer, _, _ in
                guard status == noErr, let imageBuffer, let refcon else { return }
                let decoder = Unmanaged<VideoDecoder>.fromOpaque(refcon).takeUnretainedValue()
                decoder.onFrame(imageBuffer)
            },
            decompressionOutputRefCon: Unmanaged.passUnretained(self).toOpaque())
        let attrs: [CFString: Any] = [
            kCVPixelBufferMetalCompatibilityKey: true,
            kCVPixelBufferOpenGLCompatibilityKey: false,
        ]
        var s: VTDecompressionSession?
        let status = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault, formatDescription: formatDescription,
            decoderSpecification: nil, imageBufferAttributes: attrs as CFDictionary,
            outputCallback: &callbackRecord, decompressionSessionOut: &s)
        lock.lock()
        self.formatDescription = formatDescription
        self.session = s
        lock.unlock()
        if status != noErr {
            onError("VTDecompressionSessionCreate failed: \(status)")
        }
    }

    // MARK: - Packet decode

    /// Decode one media packet (Annex B). Config packets must go to handleConfig.
    func handlePacket(_ data: Data, pts: UInt64) {
        lock.lock()
        let s = session
        let desc = formatDescription
        lock.unlock()
        guard let s, let desc else { return }  // waiting for config

        let avccData = avcc(nalUnits(data))
        guard !avccData.isEmpty else { return }

        var block: CMBlockBuffer?
        var status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: avccData.count,
            blockAllocator: nil, customBlockSource: nil, offsetToData: 0,
            dataLength: avccData.count, flags: 0, blockBufferOut: &block)
        guard status == kCMBlockBufferNoErr, let block else { return }
        status = avccData.withUnsafeBytes { ptr in
            CMBlockBufferReplaceDataBytes(with: ptr.baseAddress!, blockBuffer: block,
                                          offsetIntoDestination: 0, dataLength: avccData.count)
        }
        guard status == kCMBlockBufferNoErr else { return }

        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: CMTime(value: CMTimeValue(pts), timescale: 1_000_000),
            decodeTimeStamp: .invalid)
        var sampleSize = avccData.count
        var sampleBuffer: CMSampleBuffer?
        status = CMSampleBufferCreate(
            allocator: kCFAllocatorDefault, dataBuffer: block, dataReady: true,
            makeDataReadyCallback: nil, refcon: nil, formatDescription: desc,
            sampleCount: 1, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
            sampleSizeEntryCount: 1, sampleSizeArray: &sampleSize, sampleBufferOut: &sampleBuffer)
        guard status == noErr, let sampleBuffer else { return }

        let flags = VTDecodeFrameFlags._EnableAsynchronousDecompression
        var infoFlags = VTDecodeInfoFlags()
        VTDecompressionSessionDecodeFrame(s, sampleBuffer: sampleBuffer, flags: flags,
                                          frameRefcon: nil, infoFlagsOut: &infoFlags)
    }
}
