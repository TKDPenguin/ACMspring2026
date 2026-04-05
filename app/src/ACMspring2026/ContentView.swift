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
    
    @State private var showCamera = false
    @State private var selectedImage: UIImage?
    @State private var prediction: String = ""
    @State private var rawPrediction: String = ""
    @State private var showFoodInfo = false
    @State private var triggerCapture = false
    
    
    
    let labels = [
            "apple_pie","baby_back_ribs","baklava","beef_carpaccio","beef_tartare",
            "beet_salad","beignets","bibimbap","bread_pudding","breakfast_burrito",
            "bruschetta","caesar_salad","cannoli","caprese_salad","carrot_cake",
            "ceviche","cheese_plate","cheesecake","chicken_curry","chicken_quesadilla",
            "chicken_wings","chocolate_cake","chocolate_mousse","churros","clam_chowder",
            "club_sandwich","crab_cakes","creme_brulee","croque_madame","cup_cakes",
            "deviled_eggs","donuts","dumplings","edamame","eggs_benedict",
            "escargots","falafel","filet_mignon","fish_and_chips","foie_gras",
            "french_fries","french_onion_soup","french_toast","fried_calamari","fried_rice",
            "frozen_yogurt","garlic_bread","gnocchi","greek_salad","grilled_cheese_sandwich",
            "grilled_salmon","guacamole","gyoza","hamburger","hot_and_sour_soup",
            "hot_dog","huevos_rancheros","hummus","ice_cream","lasagna","lobster_bisque",
            "lobster_roll_sandwich","macaroni_and_cheese","macarons","miso_soup","mussels",
            "nachos","omelette","onion_rings","oysters","pad_thai","paella","pancakes",
            "panna_cotta","peking_duck","pho","pizza","pork_chop","poutine","prime_rib",
            "pulled_pork_sandwich","ramen","ravioli","red_velvet_cake","risotto","samosa",
            "sashimi","scallops","seaweed_salad","shrimp_and_grits","spaghetti_bolognese",
            "spaghetti_carbonara","spring_rolls","steak","strawberry_shortcake","sushi",
            "tacos","takoyaki","tiramisu","tuna_tartare","waffles"
        ]
    
    
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
        do {
            let model = try FoodClassifier()
            
            guard let buffer = pixelBuffer(from: uiImage, size: CGSize(width: 384, height: 384)) else {
                prediction = "Failed to process image"
                return
            }
            
            let output = try model.prediction(x_1: buffer)
            let multiArray = output.var_2422
            print(multiArray)
            let pointer = multiArray.dataPointer.bindMemory(to: Float32.self, capacity: multiArray.count)
            let values = Array(UnsafeBufferPointer(start: pointer, count: multiArray.count))
            
            if let maxIndex = values.firstIndex(of: values.max() ?? 0) {
                let raw = labels[maxIndex]
                
                rawPrediction = raw
                prediction = raw.replacingOccurrences(of: "_", with: " ").capitalized
            }
            
        } catch {
            prediction = "Prediction failed"
            print("CoreML Error:", error)
        }
    }
    
            
    
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Camera Feed
                    CameraView(image: $selectedImage, triggerCapture: $triggerCapture)
                        .frame(maxWidth: .infinity)
                        .frame(height: UIScreen.main.bounds.height * 0.65)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .onChange(of: selectedImage) { newImage in
                            if let image = newImage {
                                classifyImage(image)
                            }
                        }
                    
                    Spacer()
                    
                    
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
                    
                    
                    if !prediction.isEmpty {
                        NavigationLink(
                            destination: FoodInformationView(name: rawPrediction)
                        ) {
                            Text(prediction)
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(Color.orange.opacity(0.7))
                                .cornerRadius(25)
                        }
                        .padding(.horizontal, 30)
                        .padding(.bottom, 30)
                    }
                    
                    Spacer()
                }
            }
            .navigationBarHidden(true)
        }
    }
}

#Preview {
    ContentView()
}
