//
//  USDAAPI.swift
//  ACMspring2026
//
//  Created by Ruthvik Penubarthi on 3/9/26.
//
import Foundation

class USDAFoodData: FoodData {
    let APIKEY = "DEMO_KEY"

    struct FoodResponse: Codable {
        let foods: [Food]
    }

    struct Food: Codable {
        let description: String
        let foodNutrients: [Nutrient]
    }

    struct Nutrient: Codable {
        let nutrientName: String
        let value: Double
    }


    func getData(query: String) async throws -> EssentialNutrients {
        let endpoint = "https://api.nal.usda.gov/fdc/v1/foods/search?api_key=\(APIKEY)&query=\(query)"
        let url = URL(string: endpoint)!
        let urlRequest = URLRequest(url: url)
        let (data, _) = try await URLSession.shared.data(for: urlRequest)
        let decoded = try JSONDecoder().decode(FoodResponse.self, from: data)
        for nutrient in decoded.foods[0].foodNutrients {
                switch nutrient.nutrientName {
                case "Carbohydrates":
                    EssentialNutrients.shared.carbs = String(format: "%.1f", nutrient.value)
                case "Sugars":
                    EssentialNutrients.shared.sugars = String(format: "%.1f", nutrient.value)
                case "Calories":
                    EssentialNutrients.shared.calories = String(format: "%.1f", nutrient.value)
                case "Unsaturated Fat":
                    EssentialNutrients.shared.unsatFat = String(format: "%.1f", nutrient.value)
                case "Protein":
                    EssentialNutrients.shared.protein = String(format: "%.1f", nutrient.value)
                case "Saturated Fat":
                    EssentialNutrients.shared.satFat = String(format: "%.1f", nutrient.value)
                default:
                    break
                }
        }
        return EssentialNutrients.shared
    }
}
