// ClaudeClient.swift
import Foundation
import UIKit

actor ClaudeClient {
    static let shared = ClaudeClient()

    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    // Load API key from Secrets.plist — never hardcode
    private let apiKey: String = {
        guard let path = Bundle.main.path(forResource: "Secrets", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path),
              let key  = dict["ANTHROPIC_API_KEY"] as? String
        else { fatalError("Missing Secrets.plist or ANTHROPIC_API_KEY key") }
        return key
    }()

    func identify(image: UIImage,
                  candidates: [(label: String, confidence: Float)]) async throws -> String {

        guard let imageData = image.jpegData(compressionQuality: 0.85) else {
            throw ClaudeError.imageEncodingFailed
        }
        let base64Image = imageData.base64EncodedString()

        let candidateLines = candidates.enumerated().map { i, c in
            "\(i + 1). \(c.label.replacingOccurrences(of: "_", with: " ")) " +
            "(classifier confidence: \(Int(c.confidence * 100))%)"
        }.joined(separator: "\n")

        let prompt = """
        A food classifier's top candidates for this image are:
        \(candidateLines)

        Look at the image. Identify the food shown.
        - If one of the candidates matches, respond with exactly that candidate's label \
        (underscores, no spaces), e.g.: apple_pie
        - If none match, respond with the closest Food-101 label from the classifier \
        list that best fits what you see.
        - Respond with the label only. No other text.
        """

        let body: [String: Any] = [
            "model": "claude-sonnet-4-6",
            "max_tokens": 32,
            "messages": [[
                "role": "user",
                "content": [
                    [
                        "type": "image",
                        "source": [
                            "type": "base64",
                            "media_type": "image/jpeg",
                            "data": base64Image
                        ]
                    ],
                    ["type": "text", "text": prompt]
                ]
            ]]
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ClaudeError.badResponse
        }

        let decoded = try JSONDecoder().decode(ClaudeResponse.self, from: data)
        let label = decoded.content.first?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        // Validate that Claude returned a known label; fall back to top candidate if not
        return FoodLabels.all.contains(label) ? label : candidates[0].label
    }
}

// MARK: - Response model

private struct ClaudeResponse: Codable {
    struct Content: Codable { let text: String }
    let content: [Content]
}

// MARK: - Errors

enum ClaudeError: Error {
    case imageEncodingFailed
    case badResponse
}
