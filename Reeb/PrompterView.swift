import SwiftUI

struct PrompterView: View {
    let script: String
    let fontSize: Double
    let mirrored: Bool

    @Environment(\.dismiss) private var dismiss
    @StateObject private var tracker = SpeechTracker()
    @StateObject private var pip = PipController()
    /// Word indices grouped into display rows — computed once, not per frame.
    @State private var rows: [[Int]] = []

    private func buildRows() {
        var built: [[Int]] = []
        var row: [Int] = []
        var length = 0
        let maxChars = max(12, Int(950 / fontSize))
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

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: fontSize * 0.35) {
                        Color.clear.frame(height: 250)
                        ForEach(rows.indices, id: \.self) { r in
                            rowText(rows[r])
                                .id(r)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    // Tap a line to jump the prompter there.
                                    if let first = rows[r].first {
                                        tracker.setPosition(first)
                                    }
                                }
                        }
                        Color.clear.frame(height: 400)
                    }
                    .padding(.horizontal, 24)
                }
                .onChange(of: tracker.position) { _, newPosition in
                    pip.update(words: tracker.words, position: newPosition)
                    guard let r = rows.firstIndex(where: { $0.contains(newPosition) }) ?? rows.indices.last else { return }
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(r, anchor: UnitPoint(x: 0.5, y: 0.3))
                    }
                }
            }
            .scaleEffect(x: mirrored ? -1 : 1, y: 1)

            VStack {
                HStack {
                    statusBadge
                    Spacer()
                    Button {
                        tracker.stop()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .padding()
                Spacer()
                floatingControls
            }
        }
        .statusBarHidden()
        .task {
            tracker.load(script: script)
            buildRows()
            pip.setUp()
            pip.onSkip = { forward in
                tracker.nudge(byWords: forward ? 8 : -8)
            }
            pip.update(words: tracker.words, position: 0)
            await tracker.start()
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            tracker.stop()
            pip.tearDown()
        }
    }

    /// Small live preview of the floating window + instructions. Keeping the
    /// layer visible on screen is what allows PiP to take over when the user
    /// switches to the Camera app.
    private var floatingControls: some View {
        VStack(spacing: 10) {
            if pip.isSupported {
                SampleBufferLayerView(displayLayer: pip.displayLayer)
                    .frame(width: 150, height: 188)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(.yellow.opacity(pip.isActive ? 0.8 : 0.25), lineWidth: 1.5))

                Button {
                    pip.start()
                } label: {
                    Label(pip.isActive ? "Floating — open your Camera" :
                          pip.canFloat ? "Float over Camera" : "Preparing float…",
                          systemImage: "pip.enter")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(pip.canFloat || pip.isActive ? .yellow : .white.opacity(0.15), in: Capsule())
                        .foregroundStyle(pip.canFloat || pip.isActive ? .black : .white.opacity(0.6))
                }
                .disabled(!pip.canFloat && !pip.isActive)

                Text(pip.isActive
                     ? "Switch to the Camera app now — the script stays on top and follows your voice."
                     : "Tap Float first, then open your Camera app.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
        .padding(.bottom, 24)
    }

    private func rowText(_ indices: [Int]) -> Text {
        indices.reduce(Text("")) { acc, i in
            let word = tracker.words[i]
            let color: Color =
                i < tracker.position ? .white.opacity(0.35) :
                i == tracker.position ? .yellow : .white
            let t = Text(word)
                .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                .foregroundColor(color)
            return acc == Text("") ? t : acc + Text(" ")
                .font(.system(size: fontSize, weight: .semibold, design: .rounded)) + t
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch tracker.status {
        case .listening:
            Label("Listening", systemImage: "mic.fill")
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.green.opacity(0.25), in: Capsule())
                .foregroundStyle(.green)
        case .idle:
            Label("Starting…", systemImage: "mic")
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.gray.opacity(0.25), in: Capsule())
                .foregroundStyle(.gray)
        case .denied(let message), .error(let message):
            Text(message)
                .font(.footnote)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.red.opacity(0.25), in: Capsule())
                .foregroundStyle(.red)
        }
    }
}
