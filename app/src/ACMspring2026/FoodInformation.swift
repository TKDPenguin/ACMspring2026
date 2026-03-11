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
        VStack {
                if let food = foodData {
                    Text(name)
                    Text("Calories: \(food.calories)")
                    Text("Protein: \(food.protein)")
                    Text("Carbs: \(food.carbs)")
                    Text("Protein: \(food.protein)")
                } else {
                    Text("Loading...")
                }
            }.task {
                if name != "" {
                    foodData = try? await WebAPI.getFoodData(name)
                }

                }
        }

    
    
}

#Preview {
    FoodInformationView(name: "")
}


