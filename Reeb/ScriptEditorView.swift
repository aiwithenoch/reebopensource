import SwiftUI

struct ScriptEditorView: View {
    @ObservedObject var store: ScriptStore
    let scriptID: Script.ID

    @AppStorage("fontSize") private var fontSize: Double = 34
    @AppStorage("mirrored") private var mirrored: Bool = false
    @State private var title: String = ""
    @State private var text: String = ""
    @State private var showPrompter = false
    @State private var showRecorder = false
    @State private var confirmDelete = false
    @FocusState private var textFocused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.07, green: 0.07, blue: 0.10),
                                    Color(red: 0.02, green: 0.02, blue: 0.04)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                TextField("Title", text: $title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                TextEditor(text: $text)
                    .font(.body)
                    .foregroundStyle(.white)
                    .focused($textFocused)
                    .padding(8)
                    .scrollContentBackground(.hidden)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty {
                            Text("Paste or write your script here…")
                                .foregroundStyle(.white.opacity(0.3))
                                .padding(16)
                                .allowsHitTesting(false)
                        }
                    }

                VStack(spacing: 10) {
                    HStack {
                        Image(systemName: "textformat.size")
                            .foregroundStyle(.yellow)
                        Slider(value: $fontSize, in: 20...60, step: 2)
                        Text("\(Int(fontSize))")
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(width: 32)
                    }
                    Toggle(isOn: $mirrored) {
                        Label("Mirror (for beam splitter rigs)",
                              systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                .padding(14)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                HStack(spacing: 10) {
                    Button {
                        textFocused = false
                        saveNow()
                        showRecorder = true
                    } label: {
                        Label("Record Video", systemImage: "video.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.yellow)
                    .foregroundStyle(.black)

                    Button {
                        textFocused = false
                        saveNow()
                        showPrompter = true
                    } label: {
                        Label("Prompter", systemImage: "mic.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                    .tint(.yellow)
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
        .navigationTitle(title.isEmpty ? "Script" : title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
            }
        }
        .confirmationDialog("Delete this script?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                store.delete(id: scriptID)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear {
            if let script = store.scripts.first(where: { $0.id == scriptID }) {
                title = script.title
                text = script.text
            }
        }
        .onDisappear { saveNow() }
        .onChange(of: title) { _, _ in saveNow() }
        .onChange(of: text) { _, _ in saveNow() }
        .fullScreenCover(isPresented: $showPrompter) {
            PrompterView(script: text, fontSize: fontSize, mirrored: mirrored)
        }
        .fullScreenCover(isPresented: $showRecorder) {
            RecordView(script: text, fontSize: fontSize)
        }
    }

    private func saveNow() {
        guard var script = store.scripts.first(where: { $0.id == scriptID }) else { return }
        guard script.title != title || script.text != text else { return }
        script.title = title
        script.text = text
        store.update(script)
    }
}
