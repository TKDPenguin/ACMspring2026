//
//  USDAAPI.swift
//  ACMspring2026
//
//  Created by Ruthvik Penubarthi on 3/9/26.
//
import Foundation

class USDAFoodData: FoodData {
    
    var APIKEY = ""
    // Make a private api key in a file called Secrets.plist
    init() {
        if let path = Bundle.main.path(forResource: "Secrets", ofType: "plist"),
           let dict = NSDictionary(contentsOfFile: path) as? [String: Any],
           let key = dict["USDA_API_KEY"] as? String {
            self.APIKEY = "DEMO_KEY"
            print("✓ API Key loaded successfully from Secrets.plist (length: \(key.count) characters)")
            if key.isEmpty {
                print("⚠️ Warning: API Key is empty!")
            }
        } else {
            // Use DEMO_KEY as fallback for testing
            self.APIKEY = "DEMO_KEY"
          
        }
    }

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
        var nutrients = EssentialNutrients()
        
        print("\n--- USDA API Request ---")
        print("Query: \(query)")
        
        // Check if API key is set
        if APIKEY.isEmpty {
            print("✗ Error: API Key is empty! Check Secrets.plist")
            return nutrients
        }
        
        print("API Key: \(String(repeating: "*", count: APIKEY.count)) (length: \(APIKEY.count))")
        
        // URL encode the query
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            print("✗ Error: Failed to URL encode query")
            return nutrients
        }
        
        print("Encoded Query: \(encodedQuery)")
        
        // Build the endpoint URL
        let endpoint = "https://api.nal.usda.gov/fdc/v1/foods/search?api_key=\(APIKEY)&query=\(encodedQuery)&pageSize=1"
        print("Endpoint: https://api.nal.usda.gov/fdc/v1/foods/search?api_key=[HIDDEN]&query=\(encodedQuery)&pageSize=1")
        
        guard let url = URL(string: endpoint) else {
            print("✗ Error: Failed to create URL from endpoint")
            return nutrients
        }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"
        
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        print("Response Status: \(statusCode)")
        
        // Print the response body for debugging
        if let responseString = String(data: data, encoding: .utf8) {
            print("Response Body: \(responseString)")
        }
        
        // Handle error status codes
        if statusCode == 403 {
            print("✗ 403 Forbidden - API key may be invalid or inactive")
            return nutrients
        }
        
        if statusCode == 401 {
            print("✗ 401 Unauthorized - Check your API key")
            return nutrients
        }
        
        if statusCode != 200 {
            print("✗ API Error: HTTP \(statusCode)")
            return nutrients
        }
        
        print("✓ Request successful")
        
        do {
            let decoded = try JSONDecoder().decode(FoodResponse.self, from: data)
            
            print("Foods found: \(decoded.foods.count)")

            if !decoded.foods.isEmpty {
                print("First food: \(decoded.foods[0].description)")
                print("Nutrients count: \(decoded.foods[0].foodNutrients.count)")
                
                for nutrient in decoded.foods[0].foodNutrients {
                    print("  • \(nutrient.nutrientName): \(nutrient.value)")
                    
                    switch nutrient.nutrientName {
                        case "Carbohydrate, by difference":
                            nutrients.carbs = String(format: "%.1f", nutrient.value)

                        case "Sugars, total including NLEA":
                            nutrients.sugars = String(format: "%.1f", nutrient.value)

                        case "Energy":
                            nutrients.calories = String(format: "%.0f", nutrient.value)

                        case "Protein":
                            nutrients.protein = String(format: "%.1f", nutrient.value)

                        case "Fatty acids, total saturated":
                            nutrients.satFat = String(format: "%.1f", nutrient.value)
                        
                        case "Fatty acids, total trans":
                            nutrients.transFat = String(format: "%.1f", nutrient.value)
                        
                        default:
                            break
                    }
                }
            } else {
                print("No foods found in API response")
            }
        } catch {
            print("✗ JSON Decode Error: \(error)")
        }
        
        print("--- End Request ---\n")
        return nutrients
    }
}
