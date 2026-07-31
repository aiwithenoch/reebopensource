import SwiftUI

struct ContentView: View {
    @StateObject private var store = ScriptStore()
    @State private var path: [Script.ID] = []

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                LinearGradient(colors: [Color(red: 0.07, green: 0.07, blue: 0.10),
                                        Color(red: 0.02, green: 0.02, blue: 0.04)],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                if store.scripts.isEmpty {
                    emptyState
                } else {
                    scriptList
                }
            }
            .navigationTitle("Reeb")
            .navigationDestination(for: Script.ID.self) { id in
                if let index = store.scripts.firstIndex(where: { $0.id == id }) {
                    ScriptEditorView(store: store, scriptID: store.scripts[index].id)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        let script = store.add()
                        path.append(script.id)
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(.yellow)
    }

    private var scriptList: some View {
        List {
            ForEach(store.scripts) { script in
                Button {
                    path.append(script.id)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(script.title.isEmpty ? "Untitled" : script.title)
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text(script.text.isEmpty ? "Empty script" : script.text)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(2)
                        HStack(spacing: 12) {
                            Label("\(script.text.split(whereSeparator: \.isWhitespace).count) words",
                                  systemImage: "text.word.spacing")
                            Label(script.updatedAt.formatted(date: .abbreviated, time: .omitted),
                                  systemImage: "clock")
                        }
                        .font(.caption2)
                        .foregroundStyle(.yellow.opacity(0.8))
                    }
                    .padding(.vertical, 6)
                }
                .listRowBackground(Color.white.opacity(0.06))
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        store.delete(id: script.id)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .contextMenu {
                    Button {
                        store.duplicate(script)
                    } label: {
                        Label("Duplicate", systemImage: "plus.square.on.square")
                    }
                    Button(role: .destructive) {
                        store.delete(id: script.id)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "text.viewfinder")
                .font(.system(size: 52))
                .foregroundStyle(.yellow)
            Text("No scripts yet")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            Text("Tap + to write your first script.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.5))
        }
    }
}

#Preview {
    ContentView()
}
