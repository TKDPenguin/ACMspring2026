//
//  FoodData.swift
//  ACMspring2026
//
//  Created by Ruthvik Penubarthi on 3/2/26.

import Foundation

struct EssentialNutrients {
    var carbs: String = "N/A"
    var sugars: String = "N/A"
    var calories: String = "N/A"
    var transFat: String = "N/A"
    var protein: String = "N/A"
    var satFat: String = "N/A"
}

protocol FoodData {
    func getData(query: String) async throws -> EssentialNutrients
}

struct WebAPI {
    static let foodAPI = USDAFoodData() // Works with any food API that has the essential nutrition facts
    
    static func getFoodData(_ foodName: String) async throws -> EssentialNutrients {
        return try await foodAPI.getData(query: foodName)
    }
    
}

