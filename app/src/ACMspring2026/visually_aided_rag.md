# Visually-Aided RAG — iOS Implementation Plan

## Overview
claude --resume ea41d2a3-a0a8-4efa-971e-8cb232dd2c18

Extend the existing SwiftUI app (`app/src/ACMspring2026`) to add a two-stage food
identification pipeline:

1. **Stage 1 — Core ML classifier (already working):** Run `FoodClassifier.mlpackage`
   and extract softmax confidence scores alongside the top prediction.
2. **Stage 2 — Claude vision API (new):** If the classifier confidence is below a
   threshold, send the image and the top-3 candidates to Claude's vision API, which
   sees the actual photo and refines the answer.

```
[Photo from CameraView]
        |
        v
[FoodClassifier.mlpackage]  ──── confidence ≥ 0.75 ──→  use classifier label (fast path)
        |
        | confidence < 0.75
        v
[Claude Vision API]  ← image (base64) + top-3 candidates
        |
        v
[Refined food label]
        |
        v  (either path)
[FoodInformationView — existing nutrition display]
```

---

## Current State of the App

| File | What it does | Action |
|---|---|---|
| `ContentView.swift` | Runs CoreML, shows prediction, links to nutrition | Modify — add softmax + Claude routing |
| `CameraView.swift` | Camera + photo library picker | Keep as-is |
| `FoodInfo.swift` | Older USDA fetch + nutrition UI (completion-handler style) | Remove — superseded by WebAPI/ |
| `FoodInformation.swift` | Nutrition display view using `WebAPI` | Keep as-is |
| `WebAPI/FoodData.swift` | `WebAPI` + `EssentialNutrients` | Keep as-is |
| `WebAPI/USDAAPI.swift` | `USDAFoodData` async implementation | Keep as-is |
| `FoodClassifier.mlpackage` | Bundled EfficientNetV2-S model (input: 384×384) | Keep as-is |

---

## What Needs to Change in `ContentView.swift`

The current classifier call uses raw argmax on logits with no confidence:

```swift
// CURRENT — no confidence, no routing
let output = try model.prediction(x_1: buffer)
let multiArray = output.var_2422
let pointer = multiArray.dataPointer.bindMemory(to: Float32.self, capacity: multiArray.count)
let values = Array(UnsafeBufferPointer(start: pointer, count: multiArray.count))
if let maxIndex = values.firstIndex(of: values.max() ?? 0) {
    prediction = labels[maxIndex]
}
```

It needs to:
1. Apply softmax to convert logits to probabilities
2. Extract the top-3 predictions with confidence scores
3. Route to Claude if the top confidence is below the threshold

---

## Implementation Steps

### Step 1 — Move the label list out of `ContentView.swift`

The 101 labels are currently hardcoded in `ContentView`. Move them to a dedicated file
so `ClaudeClient.swift` can also access them.

**Create `FoodLabels.swift`:**

```swift
// FoodLabels.swift
enum FoodLabels {
    static let all: [String] = [
        "apple_pie", "baby_back_ribs", "baklava", "beef_carpaccio", "beef_tartare",
        "beet_salad", "beignets", "bibimbap", "bread_pudding", "breakfast_burrito",
        "bruschetta", "caesar_salad", "cannoli", "caprese_salad", "carrot_cake",
        "ceviche", "cheese_plate", "cheesecake", "chicken_curry", "chicken_quesadilla",
        "chicken_wings", "chocolate_cake", "chocolate_mousse", "churros", "clam_chowder",
        "club_sandwich", "crab_cakes", "creme_brulee", "croque_madame", "cup_cakes",
        "deviled_eggs", "donuts", "dumplings", "edamame", "eggs_benedict", "escargots",
        "falafel", "filet_mignon", "fish_and_chips", "foie_gras", "french_fries",
        "french_onion_soup", "french_toast", "fried_calamari", "fried_rice",
        "frozen_yogurt", "garlic_bread", "gnocchi", "greek_salad",
        "grilled_cheese_sandwich", "grilled_salmon", "guacamole", "gyoza",
        "hamburger", "hot_and_sour_soup", "hot_dog", "huevos_rancheros", "hummus",
        "ice_cream", "lasagna", "lobster_bisque", "lobster_roll_sandwich",
        "macaroni_and_cheese", "macarons", "miso_soup", "mussels", "nachos",
        "omelette", "onion_rings", "oysters", "pad_thai", "paella", "pancakes",
        "panna_cotta", "peking_duck", "pho", "pizza", "pork_chop", "poutine",
        "prime_rib", "pulled_pork_sandwich", "ramen", "ravioli", "red_velvet_cake",
        "risotto", "samosa", "sashimi", "scallops", "seaweed_salad",
        "shrimp_and_grits", "spaghetti_bolognese", "spaghetti_carbonara",
        "spring_rolls", "steak", "strawberry_shortcake", "sushi", "tacos",
        "takoyaki", "tiramisu", "tuna_tartare", "waffles"
    ]
}
```

Delete the `let labels = [...]` array from `ContentView.swift` and replace all
references to `labels` with `FoodLabels.all`.

---

### Step 2 — Add softmax and top-k extraction to `ContentView.swift`

Replace the `classifyImage(_:)` function with a version that returns confidence scores
and routes to Claude when uncertain.

The softmax of a raw logit array is:

```
softmax(x)[i] = exp(x[i]) / sum(exp(x[j]) for all j)
```

Apply it in Swift before picking the top label:

```swift
// Replace classifyImage(_:) in ContentView.swift

private let confidenceThreshold: Float = 0.75

func classifyImage(_ uiImage: UIImage) {
    Task {
        isLoading = true
        defer { isLoading = false }

        do {
            let model = try FoodClassifier()
            guard let buffer = pixelBuffer(from: uiImage, size: CGSize(width: 384, height: 384)) else {
                prediction = "Failed to process image"
                return
            }

            let output = try model.prediction(x_1: buffer)
            let multiArray = output.var_2422
            let pointer = multiArray.dataPointer.bindMemory(to: Float32.self,
                                                            capacity: multiArray.count)
            let logits = Array(UnsafeBufferPointer(start: pointer, count: multiArray.count))

            // Softmax
            let maxLogit = logits.max() ?? 0
            let exps = logits.map { exp($0 - maxLogit) }   // subtract max for numerical stability
            let expSum = exps.reduce(0, +)
            let probs = exps.map { $0 / expSum }

            // Top-3
            let indexed = probs.enumerated().sorted { $0.element > $1.element }
            let topK = Array(indexed.prefix(3))
            let topLabel = FoodLabels.all[topK[0].offset]
            let topConfidence = topK[0].element

            if topConfidence >= confidenceThreshold {
                // Fast path — classifier is confident
                prediction = topLabel
                identificationSource = "classifier"
            } else {
                // Slow path — ask Claude
                let candidates = topK.map { (label: FoodLabels.all[$0.offset],
                                             confidence: $0.element) }
                prediction = try await ClaudeClient.shared.identify(image: uiImage,
                                                                    candidates: candidates)
                identificationSource = "claude"
            }

        } catch {
            prediction = "Prediction failed: \(error.localizedDescription)"
        }
    }
}
```

Also add `@State private var isLoading = false` and
`@State private var identificationSource = ""` to the `ContentView` state properties,
and wire `isLoading` to a `ProgressView` in the body.

---

### Step 3 — Create `ClaudeClient.swift`

This file owns the Claude API call. It receives the image and the classifier's top-3
candidates, sends both to Claude's vision endpoint, and returns the food name as a
plain `String`.

```swift
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
```

---

### Step 4 — Add `Secrets.plist` for the API key

The Claude API key must never be hardcoded in source code.

1. In Xcode, go to **File → New → File → Property List**. Name it `Secrets.plist`.
2. Add one entry: Key = `ANTHROPIC_API_KEY`, Type = `String`, Value = your key.
3. Add `Secrets.plist` to `.gitignore` immediately:

```
# .gitignore
Secrets.plist
```

4. Add a `Secrets.plist.template` (safe to commit) so teammates know what's expected:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>ANTHROPIC_API_KEY</key>
    <string>REPLACE_WITH_YOUR_KEY</string>
</dict>
</plist>
```

---

### Step 5 — Remove `FoodInfo.swift`

`FoodInfo.swift` is an older, parallel implementation of the USDA nutrition fetch that
uses completion handlers and `USDANutritionService`. The app now uses `WebAPI/FoodData.swift`
and `WebAPI/USDAAPI.swift` with async/await instead.

- Delete `FoodInfo.swift` from the Xcode project (Move to Trash).
- Confirm nothing imports `USDANutritionService` or `FoodImageView` elsewhere before deleting.

---

### Step 6 — Update the `ContentView` body to show loading state and source

Add a loading indicator and a small badge showing whether the result came from the
classifier or Claude:

```swift
// Add inside the VStack in ContentView.body, replacing the existing prediction block

if isLoading {
    ProgressView("Identifying...")
        .padding()
} else if !prediction.isEmpty {
    VStack(spacing: 10) {
        Text(prediction.replacingOccurrences(of: "_", with: " ").capitalized)
            .font(.title2.bold())
            .foregroundColor(.black)
            .multilineTextAlignment(.center)

        if identificationSource == "claude" {
            Text("Verified by Claude")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Button("View Nutrition Info") {
            showFoodInfo = true
        }
        .padding(.top, 10)
        .foregroundColor(.blue)
    }
    .frame(maxWidth: .infinity)

    NavigationLink(
        destination: FoodInformationView(name: prediction),
        isActive: $showFoodInfo
    ) { EmptyView() }
}
```

---

## File Changes Summary

| File | Action | What changes |
|---|---|---|
| `FoodLabels.swift` | **Create** | Extracts the 101-label array from ContentView |
| `ClaudeClient.swift` | **Create** | Claude vision API call with confidence routing |
| `Secrets.plist` | **Create** (git-ignored) | Holds `ANTHROPIC_API_KEY` |
| `Secrets.plist.template` | **Create** | Safe-to-commit placeholder for teammates |
| `ContentView.swift` | **Modify** | Add softmax, top-k, Claude routing, loading state |
| `FoodInfo.swift` | **Delete** | Superseded by WebAPI/ |
| `.gitignore` | **Modify** | Add `Secrets.plist` |

All other files (`CameraView.swift`, `FoodInformation.swift`, `WebAPI/`, `FoodClassifier.mlpackage`,
`ACMspring2026App.swift`) remain unchanged.

---

## Final File Structure

```
app/src/ACMspring2026/
├── ACMspring2026App.swift          (unchanged)
├── ContentView.swift               (modified)
├── CameraView.swift                (unchanged)
├── FoodLabels.swift                (new)
├── ClaudeClient.swift              (new)
├── FoodInformation.swift           (unchanged)
├── Secrets.plist                   (new, git-ignored)
├── Secrets.plist.template          (new, committed)
├── Info.plist                      (unchanged)
├── Assets.xcassets/                (unchanged)
├── FoodClassifier.mlpackage/       (unchanged)
└── WebAPI/
    ├── FoodData.swift              (unchanged)
    └── USDAAPI.swift               (unchanged)
```

---

## Implementation Checklist

- [x] Create `FoodLabels.swift` and remove the `labels` array from `ContentView.swift`
- [x] Replace `classifyImage(_:)` in `ContentView.swift` with the softmax + routing version
- [x] Add `@State private var isLoading` and `@State private var identificationSource` to `ContentView`
- [x] Update the `ContentView` body to show `ProgressView` and the "Verified by Claude" badge
- [x] Create `ClaudeClient.swift`
- [x] Delete `FoodInfo.swift` (file removed from disk)
- [ ] **[Xcode]** Add `FoodLabels.swift` and `ClaudeClient.swift` to the Xcode project target
- [ ] **[Xcode]** Remove the dangling `FoodInfo.swift` reference from the Xcode project navigator (Move to Trash was not done via Xcode)
- [ ] **[Xcode]** Create `Secrets.plist` (File → New → File → Property List), add key `ANTHROPIC_API_KEY` with your key, and add the file to the app target
- [ ] **[Xcode]** Add `Secrets.plist` to `.gitignore`
- [ ] **[Xcode]** Create and commit `Secrets.plist.template`
- [ ] Build and run on a physical device; test with a clearly identifiable food (fast path)
- [ ] Test with an ambiguous or unusual food photo (Claude path)
- [ ] Verify the prediction flows correctly into `FoodInformationView`

---

## Notes

- **Input size:** The existing `pixelBuffer(from:size:)` call already uses `384×384`,
  matching the model. No change needed there.
- **Model output:** `output.var_2422` is a raw logit array. Softmax must be applied in
  Swift before reading confidence — the model does not apply it internally.
- **Confidence threshold:** `0.75` is a reasonable starting point. Lower it to call
  Claude more often; raise it to call Claude less. Tune based on real-world testing.
- **Claude cost:** At ~1 cent per Claude call and a 0.75 threshold, roughly 15–25% of
  photos will hit Stage 2. At typical usage this is negligible.
- **Physical device:** Test on a real iPhone; `FoodClassifier.mlpackage` runs on the
  Neural Engine and will be significantly faster than the Simulator.
