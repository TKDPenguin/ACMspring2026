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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // Title
                HStack(spacing: 8) {
                    Text(name.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.largeTitle.bold())
                   
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                if let food = foodData {
                    // serving size
                    if let serving = food.servingSizeG {
                        Text("Per \(Int(serving))g serving")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 20)
                    }

                    // nutrition grid
                    let nutrients: [(label: String, value: String, icon: String, color: Color)] = [
                        ("Calories",   formatted(food.caloriesKcal),         "flame.fill",        .orange),
                        ("Carbs",      formatted(food.totalCarbsG) + "g",    "chart.bar.fill",    .blue),
                        ("Protein",    formatted(food.proteinG) + "g",       "bolt.fill",         Color(red: 0.4, green: 0.7, blue: 0.3)),
                        ("Total Fat",  formatted(food.totalFatG) + "g",      "drop.fill",         .purple),
                        ("Sugars",     formatted(food.totalSugarsG) + "g",   "cube.fill",         .pink),
                        ("Sat. Fat",   formatted(food.saturatedFatG) + "g",  "exclamationmark.circle.fill", Color(red: 1, green: 0.45, blue: 0.45)),
                    ]

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(nutrients, id: \.label) { n in
                            NutrientCard(label: n.label, value: n.value, icon: n.icon, color: n.color)
                        }
                    }
                    .padding(.horizontal, 16)

                    // Extra nutrients card
                    VStack(spacing: 0) {
                        NutrientRow(label: "Dietary Fiber", value: formatted(food.dietaryFiberG) + "g")
                        Divider().padding(.leading, 16)
                        NutrientRow(label: "Sodium", value: formatted(food.sodiumMg) + "mg")
                        Divider().padding(.leading, 16)
                        NutrientRow(label: "Cholesterol", value: formatted(food.cholesterolMg) + "mg")
                        Divider().padding(.leading, 16)
                        NutrientRow(label: "Potassium", value: formatted(food.potassiumMg) + "mg")
                        Divider().padding(.leading, 16)
                        NutrientRow(label: "Calcium", value: formatted(food.calciumMg) + "mg")
                        Divider().padding(.leading, 16)
                        NutrientRow(label: "Iron", value: formatted(food.ironMg) + "mg")
                    }
                    .background(Color.white)
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
                    .padding(.horizontal, 16)

                } else {
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(.orange)
                        Text("Loading nutrition info...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
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


                Spacer(minLength: 30)
            }
        }
        .background(Color(.systemGray6).edgesIgnoringSafeArea(.all))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if !usdaQuery.isEmpty {
                foodData = try? await NutritionAPI.shared.getNutrition(for: usdaQuery, dataType: dataType)
            }
        }
    }

    func formatted(_ val: Double?) -> String {
        guard let v = val else { return "—" }
        return v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }
}

struct NutrientCard: View {
    let label: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.system(size: 14))
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .tracking(0.3)
            }
            Text(value)
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .minimumScaleFactor(0.5)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)
    }
}

struct NutrientRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.primary)
            Spacer()
            Text(value)
                .font(.subheadline.bold())
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

#Preview {
    NavigationView {
        FoodInformationView(name: "Banana", usdaQuery: "banana raw", dataType: "Foundation")
    }
}
