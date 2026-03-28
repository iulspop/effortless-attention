import Foundation

/// Talks to a local Ollama instance to judge whether the user is distracted.
struct OllamaClient: Sendable {
    let baseURL: URL
    let model: String

    init(model: String, baseURL: URL = URL(string: "http://localhost:11434")!) {
        self.model = model
        self.baseURL = baseURL
    }

    struct DistractionQuery: Sendable {
        let intention: String
        let contextLabel: String
        let activeApp: String
        let windowTitle: String
        let allowedItems: [String] // "not distracted" feedback for this context
    }

    struct DistractionResult: Sendable {
        let isDistracted: Bool
        let raw: String // full LLM response for debugging
    }

    /// Ask the LLM whether the user is distracted. Returns nil if Ollama is unreachable.
    func assess(_ query: DistractionQuery) async -> DistractionResult? {
        let messages = buildMessages(query)
        let url = baseURL.appendingPathComponent("api/chat")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "stream": false,
            "options": ["temperature": 0.1, "num_predict": 3, "num_ctx": 2048]
        ]

        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        request.httpBody = httpBody

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return nil }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let message = json["message"] as? [String: Any],
                  let content = message["content"] as? String else { return nil }

            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let isDistracted = trimmed.hasPrefix("DISTRACTED") || trimmed.contains("DISTRACTED")

            return DistractionResult(isDistracted: isDistracted, raw: content)
        } catch {
            return nil
        }
    }

    /// Check if Ollama is running and the model is available.
    func isAvailable() async -> Bool {
        let url = baseURL.appendingPathComponent("api/tags")
        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return false }
            return httpResponse.statusCode == 200
        } catch {
            return false
        }
    }

    /// Fetch the list of locally available models, sorted largest first (bigger = smarter).
    static func availableModels(baseURL: URL = URL(string: "http://localhost:11434")!) async -> [String] {
        let url = baseURL.appendingPathComponent("api/tags")
        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let models = json["models"] as? [[String: Any]] else { return [] }
            let sorted = models.sorted {
                ($0["size"] as? Int ?? 0) > ($1["size"] as? Int ?? 0)
            }
            return sorted.compactMap { $0["name"] as? String }
        } catch {
            return []
        }
    }

    private func buildMessages(_ query: DistractionQuery) -> [[String: String]] {
        let windowDesc = query.windowTitle.isEmpty ? query.activeApp : query.windowTitle

        let systemPrompt = "Classify the user's screen as DISTRACTED or FOCUSED relative to their task. Reply with ONLY one word. Be strict: the screen must be DIRECTLY helping the task to be FOCUSED. However, if the user has previously marked something as FOCUSED, always trust that — the user knows best."

        var messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt],
            // Few-shot examples from different domains
            ["role": "user", "content": "Task: \"Write Q3 report\" Screen: \"YouTube - Google Chrome\""],
            ["role": "assistant", "content": "DISTRACTED"],
            ["role": "user", "content": "Task: \"Write Q3 report\" Screen: \"Q3 Report.docx - Word\""],
            ["role": "assistant", "content": "FOCUSED"],
            ["role": "user", "content": "Task: \"Study on duolingo.com\" Screen: \"Reddit - Google Chrome\""],
            ["role": "assistant", "content": "DISTRACTED"],
            ["role": "user", "content": "Task: \"Study on duolingo.com\" Screen: \"Duolingo - Learn Spanish - Google Chrome\""],
            ["role": "assistant", "content": "FOCUSED"],
        ]

        // Inject allowlisted items as few-shot FOCUSED examples so the model learns them
        for item in query.allowedItems {
            messages.append(["role": "user", "content": "Task: \"\(query.intention)\" Screen: \"\(item)\""])
            messages.append(["role": "assistant", "content": "FOCUSED"])
        }

        // Actual query
        messages.append(["role": "user", "content": "Task: \"\(query.intention)\" Screen: \"\(windowDesc)\""])

        return messages
    }
}
