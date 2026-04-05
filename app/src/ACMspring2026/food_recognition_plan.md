# Food Recognition iOS App — Implementation Plan

## Overview

A Swift iOS application that accepts a food photo and returns the name and details of the food using a RAG (Retrieval-Augmented Generation) pipeline. The entire pipeline runs on-device in Swift — there is no external backend server. The app encodes the image using Apple's Vision framework, searches a bundled food knowledge base for the closest matches, and sends the retrieved context to the Claude API to generate the final response.

---

## Architecture

```
[iOS Swift App]
      |
      |-- [PhotosUI / AVFoundation] --> captured image
      |
      |-- [Vision Framework] --> VNFeaturePrintObservation (image embedding)
      |
      |-- [FoodRetriever] <-- food_knowledge_base.json (bundled in app)
      |       |
      |       | computeDistance() per entry
      |       v
      |   top-k food candidates (name, category, description)
      |
      |-- [Claude API via URLSession] --> food identification response
      |
      v
[Result displayed in SwiftUI]
```

---

## Component Breakdown

### 1. Image Capture (`ImagePicker.swift`)

Wraps `PHPickerViewController` (photo library) and `UIImagePickerController` (camera) in a `UIViewControllerRepresentable` so they can be used in SwiftUI.

```swift
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    var sourceType: UIImagePickerController.SourceType

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        return picker
    }
    // ...
}
```

---

### 2. Vision Encoder (`ImageEncoder.swift`)

Uses Apple's `Vision` framework to convert a `UIImage` into a `VNFeaturePrintObservation` — a compact, high-dimensional feature vector produced by a built-in on-device neural network.

**Why `VNGenerateImageFeaturePrintRequest`:**
- Fully on-device, no model download required
- Apple's built-in image understanding network, optimized for the Neural Engine
- `VNFeaturePrintObservation` supports direct distance computation via `computeDistance(_:to:)`
- No third-party dependencies

```swift
import Vision

class ImageEncoder {
    func encode(image: UIImage) throws -> VNFeaturePrintObservation {
        guard let cgImage = image.cgImage else { throw EncoderError.invalidImage }

        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        guard let observation = request.results?.first as? VNFeaturePrintObservation else {
            throw EncoderError.noResult
        }
        return observation
    }
}
```

**Serializing embeddings for the knowledge base:**

Feature prints are serialized with `NSKeyedArchiver` for storage in the bundled JSON file:

```swift
let data = try NSKeyedArchiver.archivedData(
    withRootObject: observation,
    requiringSecureCoding: true
)
let base64String = data.base64EncodedString()
```

And deserialized at retrieval time:

```swift
let data = Data(base64Encoded: base64String)!
let observation = try NSKeyedUnarchiver.unarchivedObject(
    ofClass: VNFeaturePrintObservation.self,
    from: data
)!
```

---

### 3. Food Retriever (`FoodRetriever.swift`)

Loads the bundled `food_knowledge_base.json`, deserializes each entry's stored feature print, and finds the top-k most similar entries to the query image using `VNFeaturePrintObservation.computeDistance(_:to:)`. Lower distance means higher similarity.

```swift
struct FoodEntry: Codable {
    let id: String
    let name: String
    let category: String
    let description: String
    let embeddingBase64: String
}

class FoodRetriever {
    private let entries: [FoodEntry]

    init() {
        let url = Bundle.main.url(forResource: "food_knowledge_base", withExtension: "json")!
        let data = try! Data(contentsOf: url)
        entries = try! JSONDecoder().decode([FoodEntry].self, from: data)
    }

    func topMatches(for query: VNFeaturePrintObservation, k: Int = 3) -> [FoodEntry] {
        var scored: [(FoodEntry, Float)] = []

        for entry in entries {
            guard
                let embData = Data(base64Encoded: entry.embeddingBase64),
                let stored = try? NSKeyedUnarchiver.unarchivedObject(
                    ofClass: VNFeaturePrintObservation.self, from: embData)
            else { continue }

            var distance: Float = 0
            try? query.computeDistance(&distance, to: stored)
            scored.append((entry, distance))
        }

        return scored
            .sorted { $0.1 < $1.1 }  // ascending: lower distance = more similar
            .prefix(k)
            .map { $0.0 }
    }
}
```

---

### 4. Claude API Client (`FoodIdentifier.swift`)

Sends the retrieved food candidates as context to the Claude API and returns a natural-language food identification.

```swift
import Foundation

class FoodIdentifier {
    private let apiKey: String = "YOUR_API_KEY"
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    func identify(candidates: [FoodEntry]) async throws -> String {
        let context = candidates.enumerated().map { i, entry in
            "\(i + 1). \(entry.name) (\(entry.category)): \(entry.description)"
        }.joined(separator: "\n")

        let prompt = """
        You are a food identification assistant.

        The user uploaded a photo of food. Based on visual similarity search, \
        the most likely candidates are:

        \(context)

        Identify the most likely food in the image. Respond with the food name, \
        a brief description, and your confidence level (high/medium/low).
        """

        let body: [String: Any] = [
            "model": "claude-sonnet-4-6",
            "max_tokens": 256,
            "messages": [["role": "user", "content": prompt]]
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(ClaudeResponse.self, from: data)
        return response.content.first?.text ?? "Could not identify food."
    }
}

struct ClaudeResponse: Codable {
    struct Content: Codable { let text: String }
    let content: [Content]
}
```

---

### 5. Main UI (`ContentView.swift`)

Ties everything together with a SwiftUI view.

```swift
struct ContentView: View {
    @State private var selectedImage: UIImage?
    @State private var result: String = ""
    @State private var isLoading = false
    @State private var showPicker = false

    private let encoder = ImageEncoder()
    private let retriever = FoodRetriever()
    private let identifier = FoodIdentifier()

    var body: some View {
        VStack(spacing: 20) {
            if let image = selectedImage {
                Image(uiImage: image)
                    .resizable().scaledToFit().frame(height: 300)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 300)
                    .overlay(Text("No image selected"))
            }

            Button("Choose Photo") { showPicker = true }
                .buttonStyle(.borderedProminent)

            Button("Identify Food") {
                Task { await identifyFood() }
            }
            .buttonStyle(.bordered)
            .disabled(selectedImage == nil || isLoading)

            if isLoading {
                ProgressView()
            } else if !result.isEmpty {
                Text(result).padding()
            }
        }
        .padding()
        .sheet(isPresented: $showPicker) {
            ImagePicker(selectedImage: $selectedImage, sourceType: .photoLibrary)
        }
    }

    func identifyFood() async {
        guard let image = selectedImage else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let embedding = try encoder.encode(image: image)
            let candidates = retriever.topMatches(for: embedding, k: 3)
            result = try await identifier.identify(candidates: candidates)
        } catch {
            result = "Error: \(error.localizedDescription)"
        }
    }
}
```

---

## Knowledge Base

### Schema (`food_knowledge_base.json`)

Each entry stores the food metadata and a pre-computed Vision feature print:

```json
[
  {
    "id": "margherita_pizza",
    "name": "Margherita Pizza",
    "category": "Italian",
    "description": "A classic Neapolitan pizza with tomato sauce, fresh mozzarella, and basil on a thin crust.",
    "embeddingBase64": "<NSKeyedArchiver base64 string>"
  }
]
```

### Building the Knowledge Base (Offline)

The `embeddingBase64` values must be pre-computed before shipping the app. Write a Swift command-line tool or macOS Swift Playground that:

1. Loads each representative food image from disk
2. Runs `VNGenerateImageFeaturePrintRequest` on it
3. Serializes the resulting `VNFeaturePrintObservation` with `NSKeyedArchiver`
4. Writes the base64 string into the JSON file

This script is run once by the developer and the resulting JSON is bundled into the app target.

### Recommended Source Dataset
- **Food-101** — 101 food categories, 1000 images each. Use one representative image per class to generate 101 embeddings for the initial knowledge base.

---

## Project Structure

```
FoodApp/
├── FoodApp.xcodeproj
└── FoodApp/
    ├── App/
    │   └── FoodAppApp.swift
    ├── Views/
    │   ├── ContentView.swift
    │   └── ResultView.swift
    ├── Services/
    │   ├── ImageEncoder.swift       # VNGenerateImageFeaturePrintRequest wrapper
    │   ├── FoodRetriever.swift      # Knowledge base loader + similarity search
    │   └── FoodIdentifier.swift    # Claude API client
    ├── Models/
    │   └── FoodEntry.swift         # Codable struct matching JSON schema
    └── Resources/
        └── food_knowledge_base.json  # Bundled pre-computed embeddings
```

---

## Implementation Steps

### Phase 1 — Knowledge Base
- [ ] Download Food-101 dataset and select one representative image per class
- [ ] Write a Swift command-line tool or Playground to generate embeddings via Vision
- [ ] Output `food_knowledge_base.json` with metadata and `embeddingBase64` fields
- [ ] Add the JSON file to the Xcode project bundle

### Phase 2 — Core Pipeline
- [ ] Implement `ImageEncoder.swift` using `VNGenerateImageFeaturePrintRequest`
- [ ] Implement `FoodRetriever.swift` to load the JSON and run similarity search
- [ ] Implement `FoodIdentifier.swift` to call the Claude API with retrieved candidates
- [ ] Unit test the retriever with known food images

### Phase 3 — SwiftUI App
- [ ] Build `ContentView.swift` with image picker and identify button
- [ ] Implement `ImagePicker.swift` for camera and photo library support
- [ ] Wire encoder → retriever → identifier into the view's async action
- [ ] Add loading state, error handling, and result display

### Phase 4 — Polish
- [ ] Secure the Claude API key using Xcode's environment config or a local secrets file excluded from git
- [ ] Test on physical device (Vision framework performs best on Neural Engine hardware)
- [ ] Test with a variety of food photos across the 101 classes
- [ ] (Optional) Expand the knowledge base beyond Food-101

---

## Key Dependencies

All dependencies are either Apple frameworks or the Claude API — no third-party Swift packages are required.

| Dependency       | Source          | Purpose                              |
|------------------|-----------------|--------------------------------------|
| `Vision`         | Apple framework | On-device image feature extraction   |
| `PhotosUI`       | Apple framework | Photo library picker                 |
| `AVFoundation`   | Apple framework | Camera capture                       |
| `URLSession`     | Apple framework | Claude API HTTP requests             |
| Claude API       | Anthropic       | Natural-language food identification |

**Minimum deployment target:** iOS 16

---

## Notes & Considerations

- **On-device embedding:** `VNGenerateImageFeaturePrintRequest` runs entirely on-device via the Neural Engine — no image data is sent for the retrieval step, only the final text prompt goes to Claude.
- **API key security:** Never hardcode the Claude API key in source code. Store it in a `Secrets.plist` excluded from version control, or fetch it from a lightweight config endpoint at startup.
- **Knowledge base size:** 101 entries load and search in milliseconds. The JSON file will be a few MB due to the serialized feature prints. For larger knowledge bases (1000+ entries), consider storing embeddings in a local SQLite database using `GRDB` or CoreData.
- **Latency:** Vision encoding takes ~50–150ms on device. Similarity search over 101 entries is near-instant. Claude API adds 1–3s. Total round-trip should be under 5 seconds.
- **Accuracy:** `VNFeaturePrintObservation` is a general-purpose visual feature extractor, not food-specific. For higher accuracy, a fine-tuned Core ML classification model (e.g., exported from CreateML on the Food-101 dataset) could replace or supplement the retrieval step.
