//
//  ContentView.swift
//  ACMspring2026
//
//  Created by Ruthvik Penubarthi on 2/5/26.
//

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
               ZStack(alignment: .bottom) {
                   Color(.systemGray6).edgesIgnoringSafeArea(.all)

                   ScrollView {
                       VStack(alignment: .leading, spacing: 24) {

                           // Header
                           HStack {
                               VStack(alignment: .leading, spacing: 4) {
                                   Text("Nutrition Scanner")
                                       .font(.largeTitle.bold())
                                   Text("Scan your food to get nutrition info")
                                       .font(.subheadline)
                                       .foregroundColor(.secondary)
                               }
                               Spacer()
                               Circle()
                                   .fill(Color(.systemGray4))
                                   .frame(width: 40, height: 40)
                                   .overlay(
                                       Image(systemName: "person.fill")
                                           .foregroundColor(.gray)
                                   )
                           }
                           .padding(.horizontal, 20)
                           .padding(.top, 16)

                           // Camera / Image card
                           Button {
                               showCamera = true
                           } label: {
                               ZStack {
                                   RoundedRectangle(cornerRadius: 20)
                                       .fill(Color.white)
                                       .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)

                                   if let img = selectedImage {
                                       Image(uiImage: img)
                                           .resizable()
                                           .scaledToFill()
                                           .frame(maxWidth: .infinity)
                                           .frame(height: 260)
                                           .clipShape(RoundedRectangle(cornerRadius: 20))
                                   } else {
                                       VStack(spacing: 12) {
                                           ZStack {
                                               Circle()
                                                   .fill(Color.orange.opacity(0.12))
                                                   .frame(width: 70, height: 70)
                                               Image(systemName: "camera.fill")
                                                   .font(.system(size: 28))
                                                   .foregroundColor(.orange)
                                           }
                                           Text("Tap to scan food")
                                               .font(.headline)
                                               .foregroundColor(.primary)
                                           Text("Point your camera at any food item")
                                               .font(.subheadline)
                                               .foregroundColor(.secondary)
                                       }
                                       .frame(height: 260)
                                   }
                               }
                           }
                           .padding(.horizontal, 20)
                           .sheet(isPresented: $showCamera) {
                               CameraView(image: $selectedImage)
                           }
                           .onChange(of: selectedImage) { newImage in
                               if let newImage = newImage {
                                   debugLines = []
                                   classifyImage(newImage)
                               }
                           }

                           // Result card
                           if isLoading {
                               HStack(spacing: 14) {
                                   ProgressView().tint(.orange)
                                   VStack(alignment: .leading, spacing: 2) {
                                       Text("Identifying food...")
                                           .font(.headline)
                                       Text("Powered by Claude AI")
                                           .font(.caption)
                                           .foregroundColor(.secondary)
                                   }
                                   Spacer()
                               }
                               .padding(20)
                               .background(Color.white)
                               .cornerRadius(16)
                               .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
                               .padding(.horizontal, 20)

                           } else if !prediction.isEmpty {
                               VStack(spacing: 0) {
                                   // Food result row
                                   Button {
                                       showFoodInfo = true
                                   } label: {
                                       HStack(spacing: 14) {
                                           ZStack {
                                               Circle()
                                                   .fill(Color.orange.opacity(0.12))
                                                   .frame(width: 48, height: 48)
                                               Image(systemName: "fork.knife")
                                                   .foregroundColor(.orange)
                                                   .font(.system(size: 18))
                                           }
                                           VStack(alignment: .leading, spacing: 3) {
                                               Text(prediction.replacingOccurrences(of: "_", with: " ").capitalized)
                                                   .font(.headline)
                                                   .foregroundColor(.primary)
                                               Text("Tap to view nutrition info")
                                                   .font(.caption)
                                                   .foregroundColor(.secondary)
                                           }
                                           Spacer()
                                           Image(systemName: "chevron.right")
                                               .foregroundColor(.secondary)
                                               .font(.caption.bold())
                                       }
                                       .padding(20)
                                   }

                                   Divider().padding(.leading, 20)

                                   // Try again row
                                   Button {
                                       selectedImage = nil
                                       prediction = ""
                                       debugLines = []
                                       showCamera = true
                                   } label: {
                                       HStack(spacing: 8) {
                                           Image(systemName: "camera.rotate")
                                               .foregroundColor(.orange)
                                           Text("Try Again")
                                               .font(.subheadline.bold())
                                               .foregroundColor(.orange)
                                       }
                                       .frame(maxWidth: .infinity)
                                       .padding(.vertical, 14)
                                   }
                               }
                               .background(Color.white)
                               .cornerRadius(16)
                               .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
                               .padding(.horizontal, 20)

                               NavigationLink(
                                   destination: FoodInformationView(name: prediction, usdaQuery: usdaQuery, dataType: usdaDataType),
                                   isActive: $showFoodInfo
                               ) { EmptyView() }
                           }

                           Spacer(minLength: 80)
                       }
                   }

                   // water bottle
                   VStack {
                       Spacer()
                       HStack {
                           Button { showWaterLog = true } label: {
                               WaterBottleButton(fillFraction: waterStore.log.fillFraction)
                           }
                           .padding([.leading, .bottom], 20)
                           Spacer()
                       }
                   }
               }
               .sheet(isPresented: $showWaterLog) {
                   NavigationStack { WaterLogView() }
                       .environmentObject(waterStore)
               }
               .navigationBarHidden(true)
           }
       }
   }
#Preview {
    ContentView()
        .environmentObject(WaterStore())
}
