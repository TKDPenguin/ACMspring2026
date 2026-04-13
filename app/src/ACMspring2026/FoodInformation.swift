//
//  FoodInformation.swift
//  ACMspring2026
//
//  Created by Ruthvik Penubarthi on 3/10/26.
//
import SwiftUI

struct FoodInformationView: View {
    let name: String
    let usdaQuery: String
    let dataType: String
    @State private var foodData: NutritionInfo?
    
    var body: some View {
        ZStack {
            Color.white
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 12) {

                HStack(spacing: 12) {
                    Text(name.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.black)
                        .lineLimit(2)
                    
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                
                Text("Serving size: \(foodData?.servingSizeG.map { String(format: "%.0f", $0) } ?? "100") g")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.gray)
                    .padding(.horizontal, 20)
                
                
                VStack(spacing: 12) {
                    HStack(spacing: 16) {
                        NutritionBox(
                            label: "CALORIES",
                            value: foodData?.caloriesKcal.map { String(format: "%.1f", $0) } ?? "N/A",
                            unit: "",
                            color: Color.green
                        )
                        
                        NutritionBox(
                            label: "PROTEIN",
                            value: foodData?.proteinG.map { String(format: "%.1f", $0) } ?? "N/A",
                            unit: "g",
                            color: Color(red: 0.9, green: 0.6, blue: 0.3)
                        )
                    }
                    
                    HStack(spacing: 16) {
                        NutritionBox(
                            label: "CARBS",
                            value: foodData?.totalCarbsG.map { String(format: "%.1f", $0) } ?? "N/A",
                            unit: "g",
                            color: Color(red: 0.1, green: 0.1, blue: 0.8)
                        )
                        
                        NutritionBox(
                            label: "FAT",
                            value: foodData?.totalFatG.map { String(format: "%.1f", $0) } ?? "N/A",
                            unit: "g",
                            color: Color(red: 0.95, green: 0.4, blue: 0.4)
                        )
                    }
                }
                .padding(.horizontal, 20)
                
                Spacer()
                
                RoundedRectangle(cornerRadius: 25)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    .frame(height: 30)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)
            }
            
        }.task {
            if !usdaQuery.isEmpty {
                foodData = try? await NutritionAPI.shared.getNutrition(for: usdaQuery, dataType: dataType)
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
                Spacer()
                
                HStack(spacing: 2) {
                
                    Text(value)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(color)
                    
                    if !unit.isEmpty {
                        Text(unit)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(color)
                    }
                }
                
                Spacer()
            }
            .frame(maxWidth: .infinity, minHeight: 120)
            .padding(20)
            .background(Color(UIColor(red: 0.97, green: 0.97, blue: 0.97, alpha: 1.0)))
            .cornerRadius(16)
        }
    }
    
}


