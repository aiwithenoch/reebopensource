import AVFoundation
import SwiftUI

/// Hosts the AVSampleBufferDisplayLayer in SwiftUI. The layer must be visible
/// on screen for iOS to allow Picture-in-Picture to start from it.
struct SampleBufferLayerView: UIViewRepresentable {
    let displayLayer: AVSampleBufferDisplayLayer

    func makeUIView(context: Context) -> LayerHostView {
        LayerHostView(displayLayer: displayLayer)
    }

    func updateUIView(_ uiView: LayerHostView, context: Context) {}

    final class LayerHostView: UIView {
        private let displayLayer: AVSampleBufferDisplayLayer

        init(displayLayer: AVSampleBufferDisplayLayer) {
            self.displayLayer = displayLayer
            super.init(frame: .zero)
            layer.addSublayer(displayLayer)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func layoutSubviews() {
            super.layoutSubviews()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            displayLayer.frame = bounds
            CATransaction.commit()
        }
    }
}
