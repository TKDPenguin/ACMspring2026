//
//  FoodInfo.swift
//  ACMspring2026
//
//  Created by Ruthvik Penubarthi on 2/18/26.
//

import SwiftUI

struct NutritionData {
    var carbs: String = "0"
    var sugars: String = "0"
    var calories: String = "0"
    var unsatFat: String = "0"
    var protein: String = "0"
    var satFat: String = "0"
}

protocol NutritionService {
    static var shared: NutritionService { get }
    func fetchNutrition(for food: String, completion: @escaping (NutritionData) -> Void) ;
}


class USDANutritionService : NutritionService {
    static let shared: NutritionService = USDANutritionService()
    
    private let apiKey = "DEMO_KEY"
    private let apiURL = "https://api.nal.usda.gov/fdc/v1/foods/search"
    
    func fetchNutrition(for food: String, completion: @escaping (NutritionData) -> Void) {
        
        guard let url = URL(string: "\(apiURL)?api_key=\(apiKey)") else {
            completion(NutritionData())
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "query": food.replacingOccurrences(of: "_", with: " "),
            "dataType": ["Foundation", "SR Legacy"],
            "pageSize": 1
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            
            var nutritionData = NutritionData()
            
            guard let data = data else {
                DispatchQueue.main.async {
                    completion(nutritionData)
                }
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let foods = json["foods"] as? [[String: Any]],
                   let firstFood = foods.first,
                   let nutrients = firstFood["foodNutrients"] as? [[String: Any]] {
                    
                    for nutrient in nutrients {
                        print(json)
                        guard let id = nutrient["nutrientId"] as? Int,
                              let value = nutrient["value"] as? Double else { continue }
                        
                        switch id {
                        case 1008: // Energy (kcal)
                            nutritionData.calories = String(format: "%.0f", value)
                            
                        case 1005: // Carbohydrate
                            nutritionData.carbs = String(format: "%.0f", value)
                            
                        case 2000: // Sugars
                            nutritionData.sugars = String(format: "%.0f", value)
                            
                        case 1003: // Protein
                            nutritionData.protein = String(format: "%.0f", value)
                            
                        case 1004: // Total Fat
                            let totalFat = value
                            nutritionData.unsatFat = String(format: "%.0f", totalFat)
                            
                        case 1258: // Saturated Fat
                            nutritionData.satFat = String(format: "%.0f", value)
                            
                        default:
                            break
                        }
                    }
                    
                    // Adjust unsaturated fat (total - saturated)
                    if let total = Double(nutritionData.unsatFat),
                       let sat = Double(nutritionData.satFat) {
                        nutritionData.unsatFat = String(format: "%.0f", max(total - sat, 0))
                    }
                }
            } catch {
                print("Error parsing USDA data:", error)
            }
            
            DispatchQueue.main.async {
                completion(nutritionData)
            }
            
        }.resume()
    }
}


struct FoodImageView: View {
    let name: String
    @State private var nutritionData = NutritionData()
    @State private var isLoading = true
    @State private var nutritionService: NutritionService = USDANutritionService()
    
    
    var body: some View {
        ZStack {
            Color.white
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 24) {
                // Header with food name and status dot
                HStack(spacing: 12) {
                    Text(name)
                        .font(.system(size: 40, weight: .bold))
                        .foregroundColor(.black)
                    
                    Circle()
                        .fill(Color.green)
                        .frame(width: 16, height: 16)
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                
//                // Tab bar
//                HStack(spacing: 16) {
//                    TabBarItem(icon: "📈", label: "Stats")
//                    TabBarItem(icon: "⚡", label: "")
//                    TabBarItem(icon: "⚠️", label: "")
//                    TabBarItem(icon: "☰", label: "")
//                    Spacer()
//                }
//                .padding(.horizontal, 20)
                
                VStack(spacing: 16) {
                    HStack(spacing: 16) {
                        NutritionBox(
                            label: "CARBS",
                            value: nutritionData.carbs,
                            unit: "g",
                            color: Color(red: 0.1, green: 0.1, blue: 0.8)
                        )
                        
                        NutritionBox(
                            label: "SUGARS",
                            value: nutritionData.sugars,
                            unit: "g",
                            color: Color(red: 0.9, green: 0.4, blue: 0.6)
                        )
                    }
                    
                    HStack(spacing: 16) {
                        NutritionBox(
                            label: "CALORIES",
                            value: nutritionData.calories,
                            unit: "",
                            color: Color.green
                        )
                        
                        NutritionBox(
                            label: "UNSAT FAT",
                            value: nutritionData.unsatFat,
                            unit: "g",
                            color: Color(red: 0.6, green: 0.3, blue: 0.9)
                        )
                    }
                    
                    HStack(spacing: 16) {
                        NutritionBox(
                            label: "PROTEIN",
                            value: nutritionData.protein,
                            unit: "g",
                            color: Color(red: 0.9, green: 0.6, blue: 0.3)
                        )
                        
                        NutritionBox(
                            label: "SAT FAT",
                            value: nutritionData.satFat,
                            unit: "g",
                            color: Color(red: 0.95, green: 0.4, blue: 0.4)
                        )
                    }
                }
                .padding(.horizontal, 20)
                
                Spacer()
                
                RoundedRectangle(cornerRadius: 25)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    .frame(height: 50)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
            }
            
            if isLoading {
                ProgressView()
                    .scaleEffect(1.5)
            }
        }
        .onAppear {
            nutritionService.fetchNutrition(for: name) { data in
                self.nutritionData = data
                self.isLoading = false
            }
        }
        .onChange(of: name) { newName in
            isLoading = true
            nutritionService.fetchNutrition(for: newName) { data in
                self.nutritionData = data
                self.isLoading = false
            }
        }
    }
}


struct NutritionBox: View {
    let label: String
    let value: String
    let unit: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color.gray)
                .tracking(0.5)
            
            HStack(spacing: 2) {
                Text(value)
                    .font(.system(size: 50, weight: .bold))
                    .foregroundColor(color)
                
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(color)
                }
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 160)
        .padding(20)
        .background(Color(UIColor(red: 0.97, green: 0.97, blue: 0.97, alpha: 1.0)))
        .cornerRadius(16)
    }
}

struct TabBarItem: View {
    let icon: String
    let label: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text(icon)
                .font(.system(size: 20))
            
            if !label.isEmpty {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.gray)
            }
        }
        .frame(width: 60, height: 56)
        .background(Color(UIColor(red: 0.97, green: 0.97, blue: 0.97, alpha: 1.0)))
        .cornerRadius(16)
    }
}

#Preview {
//    FoodImageView(name: "Apple Pie")
}
