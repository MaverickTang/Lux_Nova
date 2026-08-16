//
//  HistoryManager.swift
//  Mindflow
//

import Combine
import Foundation

struct SavedThought: Identifiable, Codable {
    var id = UUID()
    let date: Date
    let topic: String
    let transcript: String
    let graphJSON: String
}

final class HistoryManager: ObservableObject {
    static let shared = HistoryManager()
    @Published var savedThoughts: [SavedThought] = []

    private let storageKey = "lux_nova_history_v1"

    private init() {
        load()
    }

    func saveThought(transcript: String, graphJSON: String) {
        var extractedTopic = "未命名意识"

        if let data = graphJSON.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let topic = dict["topic"] as? String {
            extractedTopic = topic
        }

        let newThought = SavedThought(
            date: Date(),
            topic: extractedTopic,
            transcript: transcript,
            graphJSON: graphJSON
        )

        savedThoughts.insert(newThought, at: 0)
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(savedThoughts) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([SavedThought].self, from: data) {
            savedThoughts = decoded
        }
    }
}
