import Cocoa
import Metal
import MetalKit

/// Metal-backed video surface for the DeX stream, plus mouse/keyboard capture.
///
/// VideoToolbox delivers NV12 (biplanar 4:2:0) pixel buffers; we upload the Y and
/// CbCr planes through CVMetalTextureCache and convert to RGB (BT.709 video range)
/// in the fragment shader.
final class VideoView: MTKView, MTKViewDelegate {

    // MARK: Rendering

    private var textureCache: CVMetalTextureCache?
    private var pipeline: MTLRenderPipelineState?
    private let renderLock = NSLock()
    private var currentBuffer: CVPixelBuffer?

    /// Native display size of the stream (from session packets).
    private(set) var streamSize = CGSize(width: 1920, height: 1080)

    private let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;
    struct VSOut { float4 pos [[position]]; float2 uv; };
    vertex VSOut dex_vs(uint vid [[vertex_id]], constant float4 &rect [[buffer(0)]]) {
        float2 uvs[4] = { {0,1}, {1,1}, {0,0}, {1,0} };
        float2 corners[4] = {
            {rect.x, rect.y}, {rect.z, rect.y}, {rect.x, rect.w}, {rect.z, rect.w}
        };
        VSOut o;
        o.pos = float4(corners[vid], 0, 1);
        o.uv = uvs[vid];
        return o;
    }
    fragment float4 dex_fs(VSOut in [[stage_in]],
                           texture2d<float> yTex [[texture(0)]],
                           texture2d<float> uvTex [[texture(1)]]) {
        constexpr sampler s(filter::linear, address::clamp_to_edge);
        float y = yTex.sample(s, in.uv).r;
        float2 cbcr = uvTex.sample(s, in.uv).rg - 0.5;
        float Y = (y - 0.0625) * 1.164;
        float r = Y + 1.793 * cbcr.y;
        float g = Y - 0.213 * cbcr.y - 0.533 * cbcr.x;
        float b = Y + 2.112 * cbcr.x;
        return float4(r, g, b, 1.0);
    }
    """

    // MARK: Input plumbing

    /// Called for every input event destined for the device; the session owns the
    /// control channel. Set by SessionController.
    var inputHandler: ((InputEvent) -> Void)?

    enum InputEvent {
        case touch(action: UInt8, x: Int32, y: Int32, pressure: UInt16,
                   actionButton: UInt32, buttons: UInt32)
        case scroll(x: Int32, y: Int32, hScroll: Float, vScroll: Float, buttons: UInt32)
        case key(action: UInt8, keycode: Int32, meta: Int32)
        case text(String)
        case paste(String)
    }

    private var buttonsDown: UInt32 = 0

    override init(frame frameRect: CGRect, device: MTLDevice?) {
        super.init(frame: frameRect, device: device)
        setup()
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        self.device = device
        delegate = self
        framebufferOnly = true
        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1)
        isPaused = false
        enableSetNeedsDisplay = true
        CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)
        do {
            let lib = try device.makeLibrary(source: shaderSource, options: nil)
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = lib.makeFunction(name: "dex_vs")
            desc.fragmentFunction = lib.makeFunction(name: "dex_fs")
            desc.colorAttachments[0].pixelFormat = colorPixelFormat
            pipeline = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            NSLog("DeXClient: failed to build Metal pipeline: \(error)")
        }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseMoved, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
    }

    func updateStreamSize(_ size: CGSize) {
        renderLock.lock()
        streamSize = size
        renderLock.unlock()
        needsDisplay = true
    }

    func render(pixelBuffer: CVPixelBuffer) {
        renderLock.lock()
        currentBuffer = pixelBuffer
        renderLock.unlock()
        DispatchQueue.main.async { [weak self] in self?.needsDisplay = true }
    }

    /// Letterboxed rect (in view coordinates) that the stream occupies.
    func videoRect() -> CGRect {
        renderLock.lock()
        let size = streamSize
        renderLock.unlock()
        guard size.width > 0, size.height > 0 else { return bounds }
        let viewAspect = bounds.width / max(bounds.height, 1)
        let streamAspect = size.width / size.height
        var rect = bounds
        if viewAspect > streamAspect {
            rect.size.width = bounds.height * streamAspect
            rect.origin.x = (bounds.width - rect.width) / 2
        } else {
            rect.size.height = bounds.width / streamAspect
            rect.origin.y = (bounds.height - rect.height) / 2
        }
        return rect
    }

    // MARK: MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        renderLock.lock()
        let buffer = currentBuffer
        renderLock.unlock()
        guard let buffer,
              let textureCache,
              let pipeline,
              let device,
              let cmd = device.makeCommandQueue()?.makeCommandBuffer(),
              let pass = currentRenderPassDescriptor,
              let drawable = currentDrawable else { return }

        let w = CVPixelBufferGetWidth(buffer)
        let h = CVPixelBufferGetHeight(buffer)
        var yTexRef: CVMetalTexture?
        var uvTexRef: CVMetalTexture?
        guard CVMetalTextureCacheCreateTextureFromImage(nil, textureCache, buffer, nil,
                .r8Unorm, w, h, 0, &yTexRef) == kCVReturnSuccess, let yTexRef,
              CVMetalTextureCacheCreateTextureFromImage(nil, textureCache, buffer, nil,
                .rg8Unorm, w / 2, h / 2, 1, &uvTexRef) == kCVReturnSuccess, let uvTexRef,
              let yTex = CVMetalTextureGetTexture(yTexRef),
              let uvTex = CVMetalTextureGetTexture(uvTexRef) else { return }

        // Aspect-fit rect in NDC.
        let vr = videoRect()
        var rect = vector_float4(
            Float(vr.minX / bounds.width * 2 - 1),
            Float(vr.minY / bounds.height * 2 - 1),
            Float(vr.maxX / bounds.width * 2 - 1),
            Float(vr.maxY / bounds.height * 2 - 1))

        let encoder = cmd.makeRenderCommandEncoder(descriptor: pass)!
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBytes(&rect, length: MemoryLayout<vector_float4>.size, index: 0)
        encoder.setFragmentTexture(yTex, index: 0)
        encoder.setFragmentTexture(uvTex, index: 1)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        cmd.present(drawable)
        cmd.commit()
    }

    // MARK: - Coordinate mapping

    /// View point (AppKit, y-up) → stream pixel coordinates (y-down), clamped.
    private func displayPoint(for viewPoint: NSPoint) -> (Int32, Int32)? {
        let vr = videoRect()
        guard vr.width > 1, vr.height > 1 else { return nil }
        renderLock.lock()
        let size = streamSize
        renderLock.unlock()
        let fx = (viewPoint.x - vr.minX) / vr.width
        let fy = 1 - (viewPoint.y - vr.minY) / vr.height  // flip y
        let x = Int32((fx * size.width).rounded())
        let y = Int32((fy * size.height).rounded())
        return (max(0, min(Int32(size.width) - 1, x)), max(0, min(Int32(size.height) - 1, y)))
    }

    // MARK: - Mouse

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let (x, y) = displayPoint(for: convert(event.locationInWindow, from: nil)) else { return }
        buttonsDown |= ControlMessages.BUTTON_PRIMARY
        inputHandler?(.touch(action: ControlMessages.ACTION_DOWN, x: x, y: y,
                             pressure: ControlMessages.pressure(pressed: true),
                             actionButton: ControlMessages.BUTTON_PRIMARY, buttons: buttonsDown))
    }

    override func mouseUp(with event: NSEvent) {
        guard let (x, y) = displayPoint(for: convert(event.locationInWindow, from: nil)) else { return }
        buttonsDown &= ~ControlMessages.BUTTON_PRIMARY
        inputHandler?(.touch(action: ControlMessages.ACTION_UP, x: x, y: y,
                             pressure: 0,
                             actionButton: ControlMessages.BUTTON_PRIMARY, buttons: buttonsDown))
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let (x, y) = displayPoint(for: convert(event.locationInWindow, from: nil)) else { return }
        buttonsDown |= ControlMessages.BUTTON_SECONDARY
        inputHandler?(.touch(action: ControlMessages.ACTION_DOWN, x: x, y: y,
                             pressure: ControlMessages.pressure(pressed: true),
                             actionButton: ControlMessages.BUTTON_SECONDARY, buttons: buttonsDown))
    }

    override func rightMouseUp(with event: NSEvent) {
        guard let (x, y) = displayPoint(for: convert(event.locationInWindow, from: nil)) else { return }
        buttonsDown &= ~ControlMessages.BUTTON_SECONDARY
        inputHandler?(.touch(action: ControlMessages.ACTION_UP, x: x, y: y,
                             pressure: 0,
                             actionButton: ControlMessages.BUTTON_SECONDARY, buttons: buttonsDown))
    }

    private func mouseMovedOrDragged(_ event: NSEvent) {
        guard let (x, y) = displayPoint(for: convert(event.locationInWindow, from: nil)) else { return }
        let pressed = buttonsDown != 0
        inputHandler?(.touch(
            action: pressed ? ControlMessages.ACTION_MOVE : ControlMessages.ACTION_HOVER_MOVE,
            x: x, y: y,
            pressure: ControlMessages.pressure(pressed: pressed),
            actionButton: 0, buttons: buttonsDown))
    }

    override func mouseDragged(with event: NSEvent) { mouseMovedOrDragged(event) }
    override func rightMouseDragged(with event: NSEvent) { mouseMovedOrDragged(event) }
    override func mouseMoved(with event: NSEvent) { mouseMovedOrDragged(event) }

    override func scrollWheel(with event: NSEvent) {
        guard let (x, y) = displayPoint(for: convert(event.locationInWindow, from: nil)) else { return }
        // scrcpy scroll units are "ticks"; pixel deltas from trackpads are scaled down.
        let v = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / 40 : event.scrollingDeltaY
        let h = event.hasPreciseScrollingDeltas ? event.scrollingDeltaX / 40 : event.scrollingDeltaX
        guard v != 0 || h != 0 else { return }
        inputHandler?(.scroll(x: x, y: y, hScroll: Float(h), vScroll: Float(v), buttons: buttonsDown))
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        let meta = KeyMap.metaState(from: event.modifierFlags)
        // Cmd+V pastes the Mac clipboard into the device.
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "v",
           let text = NSPasteboard.general.string(forType: .string) {
            inputHandler?(.paste(text))
            return
        }
        if let kc = KeyMap.keyCodeTable[event.keyCode] {
            inputHandler?(.key(action: ControlMessages.ACTION_DOWN, keycode: kc, meta: meta))
            return
        }
        // Non-mapped printable characters (incl. CJK committed by the IME) go as text.
        if let chars = event.characters, !chars.isEmpty, !event.modifierFlags.contains(.command) {
            inputHandler?(.text(chars))
        }
    }

    override func keyUp(with event: NSEvent) {
        if let kc = KeyMap.keyCodeTable[event.keyCode] {
            inputHandler?(.key(action: ControlMessages.ACTION_UP, keycode: kc,
                               meta: KeyMap.metaState(from: event.modifierFlags)))
        }
    }

    /// Swallow the beep for unhandled keys while the stream window is focused.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "v" {
            keyDown(with: event)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
