//
//  WaterLogView.swift
//  ACMspring2026
//

import SwiftUI

struct WaterLogView: View {
    @EnvironmentObject var store: WaterStore
    @Environment(\.dismiss) private var dismiss
    @State private var customText = ""
    @State private var goalText = ""
    @State private var animatedFill: Double = 0

    private var unit: WaterUnit { store.log.unitPreference }

    private var sortedEntries: [WaterEntry] {
        store.log.entries.sorted { $0.timestamp > $1.timestamp }
    }

    private var quickAmounts: [(label: String, ml: Double)] {
        switch unit {
        case .ml:
            return [("250 mL", 250), ("500 mL", 500), ("750 mL", 750)]
        case .cups:
            return [("½ cup", 118.294), ("1 cup", 236.588), ("2 cups", 473.176)]
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {

                    // Unit toggle
                    Picker("Unit", selection: Binding(
                        get: { store.log.unitPreference },
                        set: { newUnit in
                            store.setUnit(newUnit)
                            goalText = formatGoalText(for: newUnit)
                        }
                    )) {
                        Text("mL").tag(WaterUnit.ml)
                        Text("cups").tag(WaterUnit.cups)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                    // Big bottle hero
                    VStack(spacing: 16) {
                        BigWaterBottle(fillFraction: animatedFill)
                            .frame(width: 120, height: 200)
                            .onAppear {
                                withAnimation(.easeInOut(duration: 1.0)) {
                                    animatedFill = store.log.fillFraction
                                }
                            }
                            .onChange(of: store.log.fillFraction) { newVal in
                                withAnimation(.easeInOut(duration: 0.5)) {
                                    animatedFill = newVal
                                }
                            }

                        VStack(spacing: 4) {
                            Text(unit.format(store.log.totalTodayMl))
                                .font(.system(size: 36, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                            Text("of \(unit.format(store.log.dailyGoalMl)) goal")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        // Progress bar
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(.systemGray5))
                                    .frame(height: 10)
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.blue.gradient)
                                    .frame(width: geo.size.width * CGFloat(animatedFill), height: 10)
                                    .animation(.easeInOut(duration: 0.5), value: animatedFill)
                            }
                        }
                        .frame(height: 10)
                        .padding(.horizontal, 40)
                    }
                    .padding(.vertical, 8)

                    // Quick add buttons
                    VStack(alignment: .leading, spacing: 12) {
                        Text("QUICK ADD")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 20)

                        HStack(spacing: 12) {
                            ForEach(quickAmounts, id: \.label) { item in
                                Button {
                                    store.addEntry(amountMl: item.ml)
                                } label: {
                                    VStack(spacing: 4) {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.title2)
                                            .foregroundColor(.blue)
                                        Text(item.label)
                                            .font(.caption.bold())
                                            .foregroundColor(.primary)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color.white)
                                    .cornerRadius(14)
                                    .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }

                    // Custom entry
                    VStack(alignment: .leading, spacing: 12) {
                        Text("CUSTOM AMOUNT")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 20)

                        HStack(spacing: 12) {
                            TextField("Amount (\(unit.label))", text: $customText)
                                .keyboardType(.decimalPad)
                                .padding(14)
                                .background(Color.white)
                                .cornerRadius(12)
                                .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)

                            Button {
                                if let value = Double(customText), value > 0 {
                                    store.addEntry(amountMl: unit.toMl(value))
                                    customText = ""
                                }
                            } label: {
                                Text("Add")
                                    .font(.subheadline.bold())
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 14)
                                    .background(Double(customText) != nil ? Color.blue : Color.gray)
                                    .cornerRadius(12)
                            }
                            .disabled(Double(customText) == nil)
                        }
                        .padding(.horizontal, 20)
                    }

                    // Daily goal
                    VStack(alignment: .leading, spacing: 12) {
                        Text("DAILY GOAL")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 20)

                        HStack {
                            TextField("Goal", text: $goalText)
                                .keyboardType(.decimalPad)
                                .onSubmit { commitGoal() }
                            Text(unit.label)
                                .foregroundColor(.secondary)
                        }
                        .padding(14)
                        .background(Color.white)
                        .cornerRadius(12)
                        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
                        .padding(.horizontal, 20)
                    }

                    // Today's log
                    VStack(alignment: .leading, spacing: 12) {
                        Text("TODAY'S LOG")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 20)

                        if sortedEntries.isEmpty {
                            Text("No entries yet — start drinking! 💧")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(20)
                                .background(Color.white)
                                .cornerRadius(14)
                                .padding(.horizontal, 20)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(Array(sortedEntries.enumerated()), id: \.element.id) { i, entry in
                                    HStack {
                                        Image(systemName: "drop.fill")
                                            .foregroundColor(.blue)
                                            .font(.caption)
                                        Text(entry.timestamp, style: .time)
                                            .foregroundColor(.secondary)
                                            .font(.subheadline)
                                        Spacer()
                                        Text(unit.format(entry.amountMl))
                                            .font(.subheadline.bold())
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)

                                    if i < sortedEntries.count - 1 {
                                        Divider().padding(.leading, 16)
                                    }
                                }
                            }
                            .background(Color.white)
                            .cornerRadius(14)
                            .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
                            .padding(.horizontal, 20)
                        }
                    }

                    // Clear all
                    Button(role: .destructive) {
                        store.clearAllEntries()
                    } label: {
                        Text("Clear All Entries")
                            .font(.subheadline)
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.white)
                            .cornerRadius(12)
                            .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 30)
                }
            }
            .background(Color(.systemGray6).edgesIgnoringSafeArea(.all))
            .navigationTitle("Water Intake")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .onAppear {
                store.resetIfNewDay()
                goalText = formatGoalText(for: unit)
            }
        }
    }

    private func formatGoalText(for unit: WaterUnit) -> String {
        let value = unit.fromMl(store.log.dailyGoalMl)
        if unit == .ml {
            return "\(Int(value.rounded()))"
        } else {
            return value.truncatingRemainder(dividingBy: 1) == 0
                ? "\(Int(value))"
                : String(format: "%.1f", value)
        }
    }

    private func commitGoal() {
        if let value = Double(goalText), value > 0 {
            store.setGoal(amountMl: unit.toMl(value))
        } else {
            goalText = formatGoalText(for: unit)
        }
    }
}

// big animated waterbottle
struct BigWaterBottle: View {
    let fillFraction: Double

    private let lightBlue  = Color(red: 0.72, green: 0.93, blue: 0.98)
    private let fillBlue   = Color(red: 0.10, green: 0.58, blue: 0.85)
    private let strokeBlue = Color(red: 0.08, green: 0.45, blue: 0.70)

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack(alignment: .top) {
                // bottl background
                BottleShape()
                    .fill(lightBlue)
                    .frame(width: w, height: h)

                // Water fill rises from bottom through entire bottle
                BottleShape()
                    .fill(fillBlue)
                    .frame(width: w, height: h)
                    .mask(
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            Rectangle()
                                .frame(height: h * CGFloat(fillFraction))
                        }
                        .frame(width: w, height: h)
                    )
                    .animation(.easeInOut(duration: 0.6), value: fillFraction)

                // outline on top
                BottleShape()
                    .stroke(strokeBlue, lineWidth: 2)
                    .frame(width: w, height: h)

                // percent label
                Text("\(Int(fillFraction * 100))%")
                    .font(.system(size: w * 0.22, weight: .bold, design: .rounded))
                    .foregroundColor(fillFraction > 0.45 ? .white : fillBlue)
                    .frame(width: w)
                    .offset(y: h * 0.55)
                    .animation(.easeInOut(duration: 0.3), value: fillFraction)
            }
        }
    }
}

struct BottleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        // start at very top center-left (open top, no cap)
        path.move(to: CGPoint(x: w * 0.36, y: 0))
        path.addLine(to: CGPoint(x: w * 0.64, y: 0))
        // neck right down
        path.addLine(to: CGPoint(x: w * 0.64, y: h * 0.10))
        // right shoulder curve out to body
        path.addCurve(
            to: CGPoint(x: w * 0.93, y: h * 0.26),
            control1: CGPoint(x: w * 0.68, y: h * 0.14),
            control2: CGPoint(x: w * 0.93, y: h * 0.18)
        )
        path.addLine(to: CGPoint(x: w * 0.93, y: h * 0.88))
        // bottom curve
        path.addQuadCurve(
            to: CGPoint(x: w * 0.07, y: h * 0.88),
            control: CGPoint(x: w * 0.50, y: h * 1.04)
        )
        // left body up
        path.addLine(to: CGPoint(x: w * 0.07, y: h * 0.26))
        // left shoulder curve in to neck
        path.addCurve(
            to: CGPoint(x: w * 0.36, y: h * 0.10),
            control1: CGPoint(x: w * 0.07, y: h * 0.18),
            control2: CGPoint(x: w * 0.32, y: h * 0.14)
        )
        path.closeSubpath()
        return path
    }
}


#Preview {
    NavigationStack {
        WaterLogView()
    }
    .environmentObject(WaterStore())
}
