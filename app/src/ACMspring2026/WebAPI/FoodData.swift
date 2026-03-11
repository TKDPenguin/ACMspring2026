//
//  FoodData.swift
//  ACMspring2026
//
//  Created by Ruthvik Penubarthi on 3/2/26.

import Foundation

struct EssentialNutrients {
    static var shared = EssentialNutrients()

    var carbs: String = "0"
    var sugars: String = "0"
    var calories: String = "0"
    var unsatFat: String = "0"
    var protein: String = "0"
    var satFat: String = "0"
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

