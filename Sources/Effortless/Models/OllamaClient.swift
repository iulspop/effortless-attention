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
        let prompt = buildPrompt(query)
        let url = baseURL.appendingPathComponent("api/generate")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30 // first call loads model into GPU — can take 10-15s

        let body: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "stream": false,
            "options": ["temperature": 0.1, "num_predict": 20, "num_ctx": 2048]
        ]

        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        request.httpBody = httpBody

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return nil }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let responseText = json["response"] as? String else { return nil }

            let trimmed = responseText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let isDistracted = trimmed.hasPrefix("yes")

            return DistractionResult(isDistracted: isDistracted, raw: responseText)
        } catch {
            return nil // Ollama unreachable — nudge system goes dormant
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

    private func buildPrompt(_ query: DistractionQuery) -> String {
        var prompt = """
        You are an attention monitor. The user has declared an intention and you must judge \
        whether their current app/window is relevant to that intention.

        User's intention: "\(query.intention)"
        Context: "\(query.contextLabel)"
        Currently active app: "\(query.activeApp)"
        Current window title: "\(query.windowTitle)"
        """

        if !query.allowedItems.isEmpty {
            prompt += "\nUser marked as NOT distracting for this context: \(query.allowedItems)"
        }

        prompt += """

        
        Is the user distracted from their intention? Answer only "yes" or "no".
        """

        return prompt
    }
}
