//
//  ContentView.swift
//  ACMspring2026
//
//  Created by Ruthvik Penubarthi on 2/5/26.
// -

import SwiftUI
import AVFoundation
import CoreML

struct ContentView: View {
    
    @State private var showCamera = false
    @State private var selectedImage: UIImage?
    @State private var prediction: String = ""
    @State private var showFoodInfo = false
    @State private var isLoading = false
    @State private var identificationSource = ""

    private let confidenceThreshold: Float = 0.75
    
    
    func pixelBuffer(from image: UIImage, size: CGSize) -> CVPixelBuffer? {
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue!,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue!
        ] as CFDictionary
        
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(size.width),
            Int(size.height),
            kCVPixelFormatType_32ARGB,
            attrs,
            &pixelBuffer
        )
        
        guard status == kCVReturnSuccess,
              let buffer = pixelBuffer,
              let cgImage = image.cgImage else { return nil }
        
        CVPixelBufferLockBaseAddress(buffer, [])
        
        let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        )
        
        context?.draw(cgImage, in: CGRect(origin: .zero, size: size))
        
        CVPixelBufferUnlockBaseAddress(buffer, [])
        
        return buffer
    }
    
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
                let pointer = multiArray.dataPointer.bindMemory(to: Float32.self, capacity: multiArray.count)
                let logits = Array(UnsafeBufferPointer(start: pointer, count: multiArray.count))

                // Softmax
                let maxLogit = logits.max() ?? 0
                let exps = logits.map { exp($0 - maxLogit) }
                let expSum = exps.reduce(0, +)
                let probs = exps.map { $0 / expSum }

                // Top-3
                let indexed = probs.enumerated().sorted { $0.element > $1.element }
                let topK = Array(indexed.prefix(3))
                let topLabel = FoodLabels.all[topK[0].offset]
                let topConfidence = topK[0].element

                if topConfidence >= confidenceThreshold {
                    prediction = topLabel
                    identificationSource = "classifier"
                } else {
                    let candidates = topK.map { (label: FoodLabels.all[$0.offset],
                                                 confidence: $0.element) }
                    prediction = try await ClaudeClient.shared.identify(image: uiImage,
                                                                        candidates: candidates)
                    identificationSource = "claude"
                }

            } catch {
                prediction = "Prediction failed: \(error.localizedDescription)"
                print("Error:", error)
            }
        }
    }
    
            
    
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.white
                    .edgesIgnoringSafeArea(.all)

                VStack(spacing: 20) {

                    // Camera button
                    Button("Show Camera") {
                        showCamera = true
                    }
                    .sheet(isPresented: $showCamera) {
                        CameraView(image: $selectedImage)
                    }
                    .onChange(of: selectedImage) { newImage in
                        if let newImage = newImage {
                            classifyImage(newImage)
                        }
                    }
                

                    
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

                    Spacer()
                }
                .padding()
            }


            .background(Color.white.edgesIgnoringSafeArea(.all))
        }
    }
}

#Preview {
    ContentView()
}
