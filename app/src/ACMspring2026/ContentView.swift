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

    @EnvironmentObject var waterStore: WaterStore

    @State private var showCamera = false
    @State private var selectedImage: UIImage?
    @State private var prediction: String = ""
    @State private var usdaQuery: String = ""
    @State private var usdaDataType: String = "Foundation"
    @State private var showFoodInfo = false
    @State private var showWaterLog = false
    @State private var isLoading = false
    @State private var identificationSource = ""
    @State private var debugLines: [String] = []
    @State private var triggerCapture = false
    
    
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
                // Debug: log ML results
                var debug: [String] = []
                debug.append("=== ML Classifier (top 3) ===")
                for (rank, item) in topK.enumerated() {
                    let label = FoodLabels.all[item.offset]
                    let pct = Int(item.element * 100)
                    let line = "\(rank + 1). \(label) — \(pct)%"
                    debug.append(line)
                    print("[ML] \(line)")
                }

                let candidates = topK.map { (label: FoodLabels.all[$0.offset],
                                             confidence: $0.element) }
                debug.append("→ Asking Claude to verify...")
                print("[ML] → Asking Claude to verify...")
                debugLines = debug
                let (claudeLabel, claudeQuery, claudeDataType, claudeDebug) = try await ClaudeClient.shared.identify(
                    image: uiImage, candidates: candidates)
                debugLines.append(contentsOf: claudeDebug)
                prediction = claudeLabel
                usdaQuery = claudeQuery
                usdaDataType = claudeDataType
                identificationSource = "claude"

            } catch {
                prediction = "Prediction failed: \(error.localizedDescription)"
                print("Error:", error)
            }
        }
    }
    
            
    
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black
                    .edgesIgnoringSafeArea(.all)

                VStack(spacing: 20) {
                    
                    CameraView(image: $selectedImage, triggerCapture: $triggerCapture, isActive: Binding(
                        get: { !showFoodInfo },
                        set: { _ in }
                    ))
                        .frame(maxWidth: .infinity)
                        .frame(height: UIScreen.main.bounds.height * 0.55)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .padding(.horizontal, 16)
                        .padding(.top, 70)
                        .onChange(of: selectedImage) { newImage in
                            if let newImage = newImage {
                                debugLines = []
                                classifyImage(newImage)
                            }
                        }
                    
//                    Spacer()
                    
                    
                    Button(action: {
                        triggerCapture = true
                    }) {
                        ZStack {
                            
                            Circle()
                                .fill(Color.white.opacity(0.3))
                                .frame(width: 60, height: 60)
                            
                          
                            Circle()
                                .fill(Color.white.opacity(0.7))
                                .frame(width: 48, height: 48)
                        }
                    }
                    .padding(.bottom, 20)

                    VStack(spacing: 12) {
                        if isLoading {
                            ProgressView("Identifying...")
                                .padding()
                        } else if !prediction.isEmpty {
                            VStack(spacing: 1) {
                                Text(prediction.replacingOccurrences(of: "_", with: " ").capitalized)
                                    .font(.title2.bold())
                                    .foregroundColor(.white)
                                    .multilineTextAlignment(.center)

        //                            if identificationSource == "claude" {
        //                                Text("Verified by Claude")
        //                                    .font(.caption)
        //                                    .foregroundStyle(.secondary)
        //                            }

                                Button("View Nutrition Info") {
                                    showFoodInfo = true
                                }
                                .padding(.top, 5)
                                .foregroundColor(.white)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(5)
                            .background(Color.blue)
                            .cornerRadius(12)
                        }
                        
                        Spacer()
                    }
                    .frame(height: 220)
                    .frame(maxWidth: .infinity)

//                    if !debugLines.isEmpty {
//                        VStack(alignment: .leading, spacing: 4) {
//                            Text("Debug")
//                                .font(.caption.bold())
//                                .foregroundColor(.secondary)
//                            ForEach(debugLines, id: \.self) { line in
//                                Text(line)
//                                    .font(.system(size: 11, design: .monospaced))
//                                    .foregroundColor(.primary)
//                            }
//                        }
//                        .padding(10)
//                        .frame(maxWidth: .infinity, alignment: .leading)
//                        .background(Color(.systemGray6))
//                        .cornerRadius(8)
//                    }

//                    Spacer()
                }
                .padding()

                // Water bottle — bottom-left
                VStack {
                    Spacer()
                    HStack {
                        Button {
                            showWaterLog = true
                        } label: {
                            WaterBottleButton(fillFraction: waterStore.log.fillFraction)
                        }
                        .padding(.leading, 20)
                        .padding(.bottom, 100)
                        Spacer()
                    }
                }
                .ignoresSafeArea(edges: .bottom)
            }
            .sheet(isPresented: $showWaterLog) {
                NavigationStack {
                    WaterLogView()
                }
                .environmentObject(waterStore)
            }
            .sheet(isPresented: $showFoodInfo) {
                NavigationStack {
                    FoodInformationView(name: prediction, usdaQuery: usdaQuery, dataType: usdaDataType)
                }
            }

            .background(Color.white.edgesIgnoringSafeArea(.all))
            .toolbarBackground(Color.white, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar).navigationBarHidden(true)
        }
    }
}

#Preview {
    ContentView()
}
