// GaussianSplat.swift — on-device Gaussian Splatting viewer (the headline differentiator vs Polycam,
// which requires cloud processing). Renders .ply / .splat radiance fields fully offline via MetalSplatter.

import SwiftUI
import MetalKit
import MetalSplatter
import simd
import OSLog

/// Shared orbit/state for the splat renderer, driven by SwiftUI gestures.
final class SplatController: ObservableObject {
    @Published var url: URL?
    @Published var status: String = "No splat loaded"
    // orbit
    var yaw: Float = 0.6
    var pitch: Float = -0.15
    var distance: Float = 2.4
    var splatCount: Int = 0
}

/// SwiftUI screen: loads a Gaussian-splat PLY and renders it on-device with orbit controls.
struct SplatViewerScreen: View {
    @Environment(\.theme) private var theme
    @StateObject private var controller = SplatController()
    @State private var importing = false
    let assetURL: URL?
    var onClose: (() -> Void)?

    init(assetURL: URL? = nil, onClose: (() -> Void)? = nil) {
        self.assetURL = assetURL
        self.onClose = onClose
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if controller.url != nil {
                GaussianSplatMetalView(controller: controller)
                    .ignoresSafeArea()
                    .gesture(
                        DragGesture()
                            .onChanged { v in
                                controller.yaw += Float(v.translation.width) * 0.0005
                                controller.pitch += Float(v.translation.height) * 0.0005
                                controller.pitch = max(-1.4, min(1.4, controller.pitch))
                            }
                    )
                    .gesture(
                        MagnificationGesture().onChanged { s in
                            controller.distance = max(0.4, min(8, 2.4 / Float(s)))
                        }
                    )
            } else {
                emptyState
            }

            // chrome
            VStack {
                HStack(spacing: 8) {
                    Button { onClose?() } label: {
                        StIcon(name: "back", size: 18, color: .white).frame(width: 38, height: 38).liquidGlass(radius: 999, tone: .dark)
                    }.buttonStyle(.plain)
                    StGlass(radius: 999) {
                        HStack(spacing: 8) {
                            Circle().fill(Color(hex: "#7FD9A6")).frame(width: 7, height: 7)
                            Text("Gaussian Splat").font(.sf(14, .semibold)).foregroundStyle(.white)
                            Text(controller.status).font(.mono(11)).foregroundStyle(.white.opacity(0.6))
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14).frame(height: 38)
                    }
                    Button { importing = true } label: {
                        StIcon(name: "folder", size: 17, color: .white).frame(width: 38, height: 38).liquidGlass(radius: 999, tone: .dark)
                    }.buttonStyle(.plain)
                }
                Spacer()
                HStack(spacing: 8) {
                    StIcon(name: "lock", size: 13, color: Color(hex: "#7FD9A6"))
                    Text("100% on-device · no cloud upload").font(.sf(12.5, .semibold)).foregroundStyle(.white)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .liquidGlass(radius: 99, tone: .dark)
                .padding(.bottom, 20)
            }
            .padding(.horizontal, 16).padding(.top, 8)
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.init(filenameExtension: "ply")!, .init(filenameExtension: "splat") ?? .data]) { result in
            if case .success(let url) = result {
                let ok = url.startAccessingSecurityScopedResource()
                controller.url = url
                controller.status = "Loading \(url.lastPathComponent)…"
                if ok { /* keep access for the render session */ }
            }
        }
        .onAppear {
            guard controller.url == nil, let assetURL else { return }
            controller.url = assetURL
            controller.status = "Loading \(assetURL.lastPathComponent)…"
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.white.opacity(0.06))
                .frame(width: 72, height: 72)
                .overlay(StIcon(name: "sparkle", size: 30, color: Color(hex: "#9FC0FF")))
            Text("No Splat Preview Available").font(.sf(20, .bold)).foregroundStyle(.white)
            Text("This scan does not have a geometry-derived .ply preview yet. You can open a compatible PLY file to inspect it offline.")
                .font(.sf(14)).foregroundStyle(.white.opacity(0.65)).multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Button { importing = true } label: {
                Text("Open .ply").font(.sf(15, .semibold)).foregroundStyle(.black)
                    .padding(.horizontal, 22).frame(height: 46).background(Capsule().fill(.white))
            }.buttonStyle(.plain)
        }
    }
}

/// MTKView host that drives MetalSplatter's `SplatRenderer`.
struct GaussianSplatMetalView: UIViewRepresentable {
    let controller: SplatController

    func makeCoordinator() -> Coordinator { Coordinator(controller: controller) }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = MTLCreateSystemDefaultDevice()
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .depth32Float
        view.sampleCount = 1
        view.clearColor = MTLClearColorMake(0.02, 0.02, 0.03, 1)
        view.delegate = context.coordinator
        view.preferredFramesPerSecond = 60
        context.coordinator.configure(view: view)
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.loadIfNeeded()
    }

    final class Coordinator: NSObject, MTKViewDelegate {
        private let controller: SplatController
        private let logger = Logger(subsystem: "com.adamnolle.3DSeen", category: "Splat")
        private var device: MTLDevice?
        private var queue: MTLCommandQueue?
        private var renderer: SplatRenderer?
        private var loadedURL: URL?
        private var viewportSize = CGSize(width: 1, height: 1)

        init(controller: SplatController) { self.controller = controller }

        func configure(view: MTKView) {
            device = view.device
            queue = view.device?.makeCommandQueue()
            do {
                renderer = try SplatRenderer(
                    device: view.device!,
                    colorFormat: view.colorPixelFormat,
                    depthFormat: view.depthStencilPixelFormat,
                    stencilFormat: .invalid,
                    sampleCount: view.sampleCount,
                    maxViewCount: 1,
                    maxSimultaneousRenders: 3
                )
            } catch {
                logger.error("SplatRenderer init failed: \(error.localizedDescription)")
                DispatchQueue.main.async { self.controller.status = "Renderer unavailable" }
            }
        }

        func loadIfNeeded() {
            guard let url = controller.url, url != loadedURL, let renderer else { return }
            loadedURL = url
            do {
                renderer.reset()
                try renderer.readPLY(from: url)
                DispatchQueue.main.async {
                    self.controller.splatCount = renderer.splatCount
                    self.controller.status = "\(renderer.splatCount) splats"
                }
            } catch {
                logger.error("readPLY failed: \(error.localizedDescription)")
                DispatchQueue.main.async { self.controller.status = "Could not read PLY" }
            }
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { viewportSize = size }

        func draw(in view: MTKView) {
            loadIfNeeded()
            guard let renderer, let queue,
                  let rpd = view.currentRenderPassDescriptor,
                  let drawable = view.currentDrawable,
                  let cmd = queue.makeCommandBuffer() else { return }

            let w = max(1, Float(viewportSize.width)), h = max(1, Float(viewportSize.height))
            let proj = Self.perspective(fovyRadians: 0.9, aspect: w / h, near: 0.05, far: 100)
            let viewM = Self.orbitView(yaw: controller.yaw, pitch: controller.pitch, distance: controller.distance)
            let cam = SplatRenderer.CameraDescriptor(projectionMatrix: proj, viewMatrix: viewM,
                                                     screenSize: SIMD2<Int>(Int(w), Int(h)))
            renderer.willRender(viewportCameras: [cam])
            guard let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else { return }
            renderer.render(viewportCameras: [cam], to: enc)
            enc.endEncoding()
            cmd.present(drawable)
            cmd.commit()
        }

        // MARK: matrices
        static func perspective(fovyRadians fovy: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
            let y = 1 / tan(fovy * 0.5)
            let x = y / aspect
            let z = far / (near - far)
            return simd_float4x4(columns: (
                SIMD4<Float>(x, 0, 0, 0),
                SIMD4<Float>(0, y, 0, 0),
                SIMD4<Float>(0, 0, z, -1),
                SIMD4<Float>(0, 0, z * near, 0)
            ))
        }

        static func orbitView(yaw: Float, pitch: Float, distance: Float) -> simd_float4x4 {
            let eye = SIMD3<Float>(distance * cos(pitch) * sin(yaw),
                                   distance * sin(pitch),
                                   distance * cos(pitch) * cos(yaw))
            return lookAt(eye: eye, center: .zero, up: SIMD3<Float>(0, 1, 0))
        }

        static func lookAt(eye: SIMD3<Float>, center: SIMD3<Float>, up: SIMD3<Float>) -> simd_float4x4 {
            let z = simd_normalize(eye - center)
            let x = simd_normalize(simd_cross(up, z))
            let y = simd_cross(z, x)
            return simd_float4x4(columns: (
                SIMD4<Float>(x.x, y.x, z.x, 0),
                SIMD4<Float>(x.y, y.y, z.y, 0),
                SIMD4<Float>(x.z, y.z, z.z, 0),
                SIMD4<Float>(-simd_dot(x, eye), -simd_dot(y, eye), -simd_dot(z, eye), 1)
            ))
        }
    }
}
