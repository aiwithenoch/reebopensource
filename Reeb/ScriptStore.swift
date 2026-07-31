import Foundation

struct Script: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var text: String
    var updatedAt = Date()
}

/// All scripts live in UserDefaults as JSON — no backend, everything on the phone.
@MainActor
final class ScriptStore: ObservableObject {
    @Published var scripts: [Script] {
        didSet { save() }
    }

    private static let key = "scripts.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([Script].self, from: data) {
            scripts = decoded
        } else {
            scripts = []
        }
        migrateLegacyScript()
        if scripts.isEmpty {
            scripts = [Script(title: "Welcome", text: Self.sampleText)]
        }
    }

    func add() -> Script {
        let script = Script(title: "New Script", text: "")
        scripts.insert(script, at: 0)
        return script
    }

    func update(_ script: Script) {
        guard let i = scripts.firstIndex(where: { $0.id == script.id }) else { return }
        var updated = script
        updated.updatedAt = Date()
        scripts[i] = updated
    }

    func delete(_ offsets: IndexSet) {
        scripts.remove(atOffsets: offsets)
    }

    func delete(id: Script.ID) {
        scripts.removeAll { $0.id == id }
    }

    func duplicate(_ script: Script) {
        var copy = script
        copy.id = UUID()
        copy.title += " copy"
        copy.updatedAt = Date()
        if let i = scripts.firstIndex(where: { $0.id == script.id }) {
            scripts.insert(copy, at: i + 1)
        } else {
            scripts.append(copy)
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(scripts) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    /// Carry over the single script from the first version of the app.
    private func migrateLegacyScript() {
        guard scripts.isEmpty,
              let old = UserDefaults.standard.string(forKey: "script"),
              !old.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        scripts = [Script(title: "My Script", text: old)]
        UserDefaults.standard.removeObject(forKey: "script")
    }

    static let sampleText = """
    Welcome to Reeb, your voice-controlled teleprompter. \
    As you read these words out loud, the text scrolls automatically to keep up with you. \
    There is no need to touch the screen or set a speed. \
    Just read at your own pace, pause whenever you like, and the prompter will wait for you. \
    When you are ready to record your next video, add your script and press start.
    """
}
