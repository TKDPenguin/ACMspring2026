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
    
    
    let labels = [
        "apple_pie",
        "baby_back_ribs",
        "baklava",
        "beef_carpaccio",
        "beef_tartare",
        "beet_salad",
        "beignets",
        "bibimbap",
        "bread_pudding",
        "breakfast_burrito",
        "bruschetta",
        "caesar_salad",
        "cannoli",
        "caprese_salad",
        "carrot_cake",
        "ceviche",
        "cheese_plate",
        "cheesecake",
        "chicken_curry",
        "chicken_quesadilla",
        "chicken_wings",
        "chocolate_cake",
        "chocolate_mousse",
        "churros",
        "clam_chowder",
        "club_sandwich",
        "crab_cakes",
        "creme_brulee",
        "croque_madame",
        "cup_cakes",
        "deviled_eggs",
        "donuts",
        "dumplings",
        "edamame",
        "eggs_benedict",
        "escargots",
        "falafel",
        "filet_mignon",
        "fish_and_chips",
        "foie_gras",
        "french_fries",
        "french_onion_soup",
        "french_toast",
        "fried_calamari",
        "fried_rice",
        "frozen_yogurt",
        "garlic_bread",
        "gnocchi",
        "greek_salad",
        "grilled_cheese_sandwich",
        "grilled_salmon",
        "guacamole",
        "gyoza",
        "hamburger",
        "hot_and_sour_soup",
        "hot_dog",
        "huevos_rancheros",
        "hummus",
        "ice_cream",
        "lasagna",
        "lobster_bisque",
        "lobster_roll_sandwich",
        "macaroni_and_cheese",
        "macarons",
        "miso_soup",
        "mussels",
        "nachos",
        "omelette",
        "onion_rings",
        "oysters",
        "pad_thai",
        "paella",
        "pancakes",
        "panna_cotta",
        "peking_duck",
        "pho",
        "pizza",
        "pork_chop",
        "poutine",
        "prime_rib",
        "pulled_pork_sandwich",
        "ramen",
        "ravioli",
        "red_velvet_cake",
        "risotto",
        "samosa",
        "sashimi",
        "scallops",
        "seaweed_salad",
        "shrimp_and_grits",
        "spaghetti_bolognese",
        "spaghetti_carbonara",
        "spring_rolls",
        "steak",
        "strawberry_shortcake",
        "sushi",
        "tacos",
        "takoyaki",
        "tiramisu",
        "tuna_tartare",
        "waffles"
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
                prediction = labels[maxIndex]
            }
            
        } catch {
            prediction = "Prediction failed"
            print("CoreML Error:", error)
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
                

                    
                    if !prediction.isEmpty {
                        VStack(spacing: 10) {
                            Text("Prediction:")
                                .font(.headline)
                                .foregroundColor(.black)
                                .multilineTextAlignment(.center)

                            Text(prediction)
                                .font(.title2)
                                .bold()
                                .foregroundColor(.black)
                                .multilineTextAlignment(.center)
                            
                            Button("View Nutrition Info") {
                                showFoodInfo = true
                            }
                            .padding(.top, 10)
                            .foregroundColor(.blue)
                        }
                        .frame(maxWidth: .infinity)
                        
                        NavigationLink(destination: FoodInformationView(name: prediction), isActive: $showFoodInfo) {
                            EmptyView()
                        }
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
