import Foundation

struct Goat: Identifiable, Equatable {
    let id: Int64
    let name: String
    var isActive: Bool = true
}

struct DailyMilkTotal: Identifiable {
    let localDay: String
    let date: Date
    let weightGrams: Int64
    let sessionCount: Int
    var id: String { localDay }
    var isEstimated: Bool { sessionCount == 1 }
    var chartWeightGrams: Int64 { isEstimated ? weightGrams * 2 : weightGrams }
}

enum MilkingSession: String, CaseIterable, Identifiable {
    case morning, evening
    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    static func current(at date: Date = Date()) -> Self {
        Calendar.current.component(.hour, from: date) < 12 ? .morning : .evening
    }
}

struct MilkDistribution: Identifiable {
    struct DensityPoint: Identifiable {
        let id: Int
        let grams: Double
        let width: Double
    }

    let goatID: Int64
    let session: MilkingSession
    let weights: [Double]
    let density: [DensityPoint]
    var id: String { "\(goatID)-\(session.rawValue)" }
    var median: Double? {
        guard !weights.isEmpty else { return nil }
        let middle = weights.count / 2
        return weights.count.isMultiple(of: 2) ? (weights[middle - 1] + weights[middle]) / 2 : weights[middle]
    }

    init(goatID: Int64, session: MilkingSession, weights: [Int64]) {
        self.goatID = goatID
        self.session = session
        let values = weights.map(Double.init).sorted()
        self.weights = values
        // Sparse or constant samples have no meaningful smooth distribution.
        guard values.count >= 3, let low = values.first, let high = values.last, low < high else {
            density = []
            return
        }
        let count = Double(values.count)
        let mean = values.reduce(0, +) / count
        let variance = values.reduce(0) { $0 + pow($1 - mean, 2) } / (count - 1)
        let bandwidth = max(1, 1.06 * sqrt(variance) * pow(count, -0.2))
        // Gaussian KDE, clipped to observed weights and normalized to equal peak width.
        let grid = (0...80).map { low + (high - low) * Double($0) / 80 }
        let densities = grid.map { grams in
            values.reduce(0) { sum, value in
                sum + exp(-0.5 * pow((grams - value) / bandwidth, 2))
            }
        }
        let peak = densities.max() ?? 1
        density = grid.indices.map { DensityPoint(id: $0, grams: grid[$0], width: densities[$0] / peak) }
    }
}

struct MilkRecord: Identifiable {
    let id: Int64
    let recordedAt: Date
    let goatName: String
    let weightGrams: Int64
    let session: MilkingSession
    var inHeat: Bool = false
}

struct MilkEntry {
    let goat: Goat
    let weightGrams: Int64
    var inHeat: Bool = false
}

struct HayReplacement: Identifiable {
    let id: Int64
    let recordedAt: Date
    let session: MilkingSession
}

enum MilkError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let message): return message }
    }
}

enum WeightInput {
    /// Whole grams avoid floating-point rounding in measurements and totals.
    static func parse(_ input: String) throws -> Int64? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        guard trimmed.utf8.allSatisfy({ (48...57).contains($0) }),
              let grams = Int64(trimmed), (0...100_000).contains(grams) else {
            throw MilkError.message("Enter a whole number from 0 to 100,000 grams. Leave a goat blank to skip it.")
        }
        return grams
    }
}
