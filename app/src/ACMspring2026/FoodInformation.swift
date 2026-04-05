//
//  FoodInformation.swift
//  ACMspring2026
//
//  Created by Ruthvik Penubarthi on 3/10/26.
//
import SwiftUI

struct FoodInformationView: View {
    let name: String
    @State private var foodData: EssentialNutrients?
    
    var body: some View {
        ZStack {
            Color.white
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 24) {

                HStack(spacing: 12) {
                    Text(name.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.system(size: 40, weight: .bold))
                        .foregroundColor(.black)
                    
                    Circle()
                        .fill(Color.green)
                        .frame(width: 16, height: 16)
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                
                
                VStack(spacing: 16) {
                    HStack(spacing: 16) {
                        NutritionBox(
                            label: "CARBS",
                            value: foodData?.carbs ?? "N/A",
                            unit: "g",
                            color: Color(red: 0.1, green: 0.1, blue: 0.8)
                        )
                        
                        NutritionBox(
                            label: "SUGARS",
                            value: "21.0",
                            unit: "g",
                            color: Color(red: 0.9, green: 0.4, blue: 0.6)
                        )
                    }
                    
                    HStack(spacing: 16) {
                        NutritionBox(
                            label: "CALORIES",
                            value: foodData?.calories ?? "N/A",
                            unit: "",
                            color: Color.green
                        )
                        
                        NutritionBox(
                            label: "TRANS FAT",
                            value: foodData?.transFat ?? "N/A",
                            unit: "g",
                            color: Color(red: 0.6, green: 0.3, blue: 0.9)
                        )
                    }
                    
                    HStack(spacing: 16) {
                        NutritionBox(
                            label: "PROTEIN",
                            value: foodData?.protein ?? "N/A",
                            unit: "g",
                            color: Color(red: 0.9, green: 0.6, blue: 0.3)
                        )
                        
                        NutritionBox(
                            label: "SAT FAT",
                            value: foodData?.satFat ?? "N/A",
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
            
        }.task(id: name) {
            guard !name.isEmpty else { return }
            let cleanedName = name.replacingOccurrences(of: "_", with: " ")
            foodData = try? await WebAPI.getFoodData(cleanedName)
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
            .frame(maxWidth: .infinity, minHeight: 160)
            .padding(20)
            .background(Color(UIColor(red: 0.97, green: 0.97, blue: 0.97, alpha: 1.0)))
            .cornerRadius(16)
        }
    }
    
}


#Preview {
    FoodInformationView(name: "apple pie")
}


