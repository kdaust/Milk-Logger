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
}

enum MilkingSession: String, CaseIterable, Identifiable {
    case morning, evening
    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    static func current(at date: Date = Date()) -> Self {
        Calendar.current.component(.hour, from: date) < 12 ? .morning : .evening
    }
}

struct MilkRecord: Identifiable {
    let id: Int64
    let recordedAt: Date
    let goatName: String
    let weightGrams: Int64
    let session: MilkingSession
}

struct MilkEntry {
    let goat: Goat
    let weightGrams: Int64
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
