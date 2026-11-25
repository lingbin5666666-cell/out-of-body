import MetalKit
import SwiftUI

struct ContentView: View {
    @StateObject private var model = AppModel()
    /// 记在设置里：下次打开还是上次的样子。
    @AppStorage("hideUI") private var hideUI = false

    var body: some View {
        ZStack {
            MetalView(model: model)
                .ignoresSafeArea()

            VStack {
                HStack(alignment: .top) {
                    if !hideUI {
                        Text(model.hud)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
                    }
                    Spacer()
                    // 一键藏起/显示全部界面。藏起来以后它自己留着、调得很淡，不然没法再点回来。
                    Button {
                        hideUI.toggle()
                        DebugLog.write(hideUI ? "UI 藏起" : "UI 显示")
                    } label: {
                        Image(systemName: hideUI ? "eye.slash" : "eye")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white.opacity(hideUI ? 0.35 : 1))
                            .frame(width: 44, height: 44)
                            .background(.black.opacity(hideUI ? 0.15 : 0.45), in: Circle())
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(hideUI ? "显示界面" : "隐藏界面")
                }
                Spacer()
                if !hideUI {
                HStack(spacing: 12) {
                    Button("清空地图") { model.map.reset() }
                    Button(model.showLive ? "实时层：开" : "实时层：关") { model.showLive.toggle() }
                    Button(model.recording ? "停止录制" : "录制") { model.toggleRecording() }
                        .tint(model.recording ? .red : .white)
                    Button(model.neuralLabel) { model.toggleNeural() }
                        .tint(model.neuralMode > 0 ? .cyan : .white)
                    Spacer()
                }
                .font(.system(size: 14, weight: .semibold))
                .buttonStyle(.bordered)
                .tint(.white)
                }
            }
            .padding(14)
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
    }
}

struct MetalView: UIViewRepresentable {
    let model: AppModel

    func makeCoordinator() -> Renderer? {
        Renderer(model: model)
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: model.device)
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .invalid
        view.preferredFramesPerSecond = 60
        // 要回读画面存图时，drawable 不能是 framebufferOnly。
        view.framebufferOnly = Renderer.shotIntervalSetting <= 0
        if let r = context.coordinator {
            view.delegate = r
            view.addGestureRecognizer(
                UIPanGestureRecognizer(target: r, action: #selector(Renderer.handlePan(_:))))
            view.addGestureRecognizer(
                UIPinchGestureRecognizer(target: r, action: #selector(Renderer.handlePinch(_:))))
            let tap = UITapGestureRecognizer(
                target: r, action: #selector(Renderer.handleDoubleTap(_:)))
            tap.numberOfTapsRequired = 2
            view.addGestureRecognizer(tap)
        }
        // 折叠机的铰链（iOS 27.1 起）：虚拟手机要和真机开合得一样。
        #if !OOB_NO_HINGE_API
        if #available(iOS 27.1, *) {
            let model = self.model
            var logged = -1
            view.addInteraction(UIHingeInteraction { _, update in
                guard let hinge = update.hinge else {
                    model.hingeOpen = nil
                    return
                }
                switch hinge.status {
                case .closed: model.hingeOpen = 0
                case .fullyOpen: model.hingeOpen = 1
                case .partiallyOpen:
                    // 角度是弧度；按「合上是 0、摊平是 π」换算，夹在中间一段，别和两头混了。
                    model.hingeOpen = min(0.92, max(0.08, Float(hinge.angle) / .pi))
                default: model.hingeOpen = nil
                }
                if hinge.status.rawValue != logged {
                    logged = hinge.status.rawValue
                    DebugLog.write(String(
                        format: "HINGE 状态 %d · 角度 %.2f 弧度", hinge.status.rawValue, hinge.angle))
                }
            })
        }
        #endif
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {}
}
