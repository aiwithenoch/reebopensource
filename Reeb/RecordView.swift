import AVFoundation
import SwiftUI

/// Shoot inside Reeb: full camera preview, script scrolling near the lens,
/// voice tracking running the whole time, recordings saved to Photos.
struct RecordView: View {
    let script: String
    let fontSize: Double

    @Environment(\.dismiss) private var dismiss
    @StateObject private var tracker = SpeechTracker()
    @StateObject private var recorder = CameraRecorder()
    @State private var rows: [[Int]] = []

    private var overlayFontSize: Double { max(17, fontSize * 0.62) }

    var body: some View {
        ZStack {
            CameraPreviewView(session: recorder.session)
                .ignoresSafeArea()

            // Script overlay near the top (close to the lens) over a gradient.
            VStack(spacing: 0) {
                scriptOverlay
                    .frame(maxHeight: 330)
                Spacer()
            }

            VStack {
                HStack {
                    statusBadge
                    Spacer()
                    Button {
                        recorder.shutdown()
                        tracker.stop()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white.opacity(0.8))
                            .shadow(radius: 3)
                    }
                }
                .padding()

                Spacer()

                bottomBar
            }

            if recorder.justSaved {
                Text("Saved to Photos ✓")
                    .font(.headline)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.7), in: Capsule())
                    .foregroundStyle(.green)
            }
        }
        .statusBarHidden()
        .task {
            tracker.load(script: script)
            buildRows()
            recorder.onAudioBuffer = { [weak tracker] buffer in
                tracker?.ingest(buffer)
            }
            await recorder.startPreview()
            await tracker.start(externalAudio: true)
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            recorder.shutdown()
            tracker.stop()
        }
    }

    private var scriptOverlay: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: overlayFontSize * 0.3) {
                    Color.clear.frame(height: 70)
                    ForEach(rows.indices, id: \.self) { r in
                        rowText(rows[r])
                            .id(r)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if let first = rows[r].first { tracker.setPosition(first) }
                            }
                    }
                    Color.clear.frame(height: 200)
                }
                .padding(.horizontal, 20)
            }
            .onChange(of: tracker.position) { _, newPosition in
                guard let r = rows.firstIndex(where: { $0.contains(newPosition) }) ?? rows.indices.last else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(r, anchor: UnitPoint(x: 0.5, y: 0.25))
                }
            }
        }
        .background(
            LinearGradient(colors: [.black.opacity(0.75), .black.opacity(0.55), .clear],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .top)
        )
    }

    private var bottomBar: some View {
        HStack {
            Spacer()
                .frame(width: 60)
            Spacer()
            Button {
                recorder.isRecording ? recorder.stopRecording() : recorder.startRecording()
            } label: {
                ZStack {
                    Circle()
                        .stroke(.white, lineWidth: 4)
                        .frame(width: 76, height: 76)
                    RoundedRectangle(cornerRadius: recorder.isRecording ? 8 : 33)
                        .fill(.red)
                        .frame(width: recorder.isRecording ? 34 : 64,
                               height: recorder.isRecording ? 34 : 64)
                        .animation(.easeInOut(duration: 0.2), value: recorder.isRecording)
                }
            }
            Spacer()
            Button {
                recorder.flipCamera()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath.camera")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 60, height: 60)
                    .background(.black.opacity(0.4), in: Circle())
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 30)
    }

    private func buildRows() {
        var built: [[Int]] = []
        var row: [Int] = []
        var length = 0
        let maxChars = max(14, Int(760 / overlayFontSize))
        for (i, word) in tracker.words.enumerated() {
            if length > 0 && length + word.count + 1 > maxChars {
                built.append(row)
                row = []
                length = 0
            }
            row.append(i)
            length += word.count + 1
        }
        if !row.isEmpty { built.append(row) }
        rows = built
    }

    private func rowText(_ indices: [Int]) -> Text {
        indices.reduce(Text("")) { acc, i in
            let word = tracker.words[i]
            let color: Color =
                i < tracker.position ? .white.opacity(0.4) :
                i == tracker.position ? .yellow : .white
            let t = Text(word)
                .font(.system(size: overlayFontSize, weight: .bold, design: .rounded))
                .foregroundColor(color)
            return acc == Text("") ? t : acc + Text(" ")
                .font(.system(size: overlayFontSize, weight: .bold, design: .rounded)) + t
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch tracker.status {
        case .listening:
            Label(recorder.isRecording ? "REC • following your voice" : "Listening",
                  systemImage: recorder.isRecording ? "record.circle" : "mic.fill")
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.black.opacity(0.5), in: Capsule())
                .foregroundStyle(recorder.isRecording ? .red : .green)
        case .idle:
            EmptyView()
        case .denied(let message), .error(let message):
            Text(message)
                .font(.footnote)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.red.opacity(0.4), in: Capsule())
                .foregroundStyle(.white)
        }
    }
}

/// UIKit host for the live camera preview layer.
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewHostView {
        let view = PreviewHostView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewHostView, context: Context) {}

    final class PreviewHostView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
