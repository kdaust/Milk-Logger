import Foundation
import SQLite3

/// A small synchronous SQLite wrapper. The UI calls it on the main actor;
/// transactions are short and all values are bound, never interpolated into SQL.
final class Database {
    private var handle: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    static func defaultURL() throws -> URL {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ).appendingPathComponent("GoatMilk", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("milk.sqlite")
    }

    init(url: URL) throws {
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            let error = databaseError()
            sqlite3_close(handle)
            handle = nil
            throw error
        }
        do {
            sqlite3_busy_timeout(handle, 3_000)
            try execute("PRAGMA foreign_keys = ON;")
            guard try schemaVersion() <= 1 else {
                throw MilkError.message("This database was created by a newer app version.")
            }
            try execute(Self.schema)
        } catch {
            sqlite3_close(handle)
            handle = nil
            throw error
        }
    }

    deinit { sqlite3_close(handle) }

    private func schemaVersion() throws -> Int32 {
        let statement = try prepare("PRAGMA user_version;")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw databaseError() }
        return sqlite3_column_int(statement, 0)
    }

    // Names in milk_records are snapshots: retiring a goat never removes history.
    static let schema = """
    BEGIN;
    CREATE TABLE IF NOT EXISTS goats (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        name_key TEXT NOT NULL,
        active INTEGER NOT NULL DEFAULT 1 CHECK(active IN (0, 1))
    );
    CREATE UNIQUE INDEX IF NOT EXISTS active_goat_names ON goats(name_key) WHERE active = 1;
    CREATE TABLE IF NOT EXISTS milk_records (
        id INTEGER PRIMARY KEY,
        recorded_at TEXT NOT NULL,
        local_day TEXT NOT NULL,
        timezone_id TEXT NOT NULL,
        session TEXT NOT NULL CHECK(session IN ('morning', 'evening')),
        goat_id INTEGER NOT NULL REFERENCES goats(id),
        goat_name TEXT NOT NULL,
        weight_grams INTEGER NOT NULL CHECK(weight_grams BETWEEN 0 AND 100000),
        UNIQUE(goat_id, local_day, session)
    );
    CREATE INDEX IF NOT EXISTS milk_record_dates ON milk_records(recorded_at DESC);
    PRAGMA user_version = 1;
    COMMIT;
    """

    func goats(includeRetired: Bool = false) throws -> [Goat] {
        let statement = try prepare("SELECT id, name, active FROM goats WHERE active = 1 OR ? = 1 ORDER BY name COLLATE NOCASE, id;")
        defer { sqlite3_finalize(statement) }
        try bind(Int64(includeRetired ? 1 : 0), to: 1, in: statement)
        var result: [Goat] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return result }
            guard status == SQLITE_ROW else { throw databaseError() }
            result.append(Goat(id: sqlite3_column_int64(statement, 0), name: string(statement, 1),
                               isActive: sqlite3_column_int(statement, 2) == 1))
        }
    }

    /// Use saved local days and stable goat IDs, not names or UTC timestamp dates.
    func dailyTotals(for goatID: Int64) throws -> [DailyMilkTotal] {
        let statement = try prepare("""
        SELECT local_day, SUM(weight_grams), COUNT(*)
        FROM milk_records WHERE goat_id = ?
        GROUP BY local_day ORDER BY local_day;
        """)
        defer { sqlite3_finalize(statement) }
        try bind(goatID, to: 1, in: statement)
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        // Treat date-only values as UTC for chart layout and format axes in UTC too.
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        var result: [DailyMilkTotal] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return result }
            guard status == SQLITE_ROW else { throw databaseError() }
            let day = string(statement, 0)
            guard let date = formatter.date(from: day) else {
                throw MilkError.message("A saved milking date could not be read.")
            }
            result.append(DailyMilkTotal(localDay: day, date: date,
                                         weightGrams: sqlite3_column_int64(statement, 1),
                                         sessionCount: Int(sqlite3_column_int(statement, 2))))
        }
    }

    func addGoat(name: String) throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 60 else {
            throw MilkError.message("Give your goat a name between 1 and 60 characters.")
        }
        let statement = try prepare("INSERT INTO goats(name, name_key) VALUES (?, ?);")
        defer { sqlite3_finalize(statement) }
        try bind(name, to: 1, in: statement)
        try bind(name.precomposedStringWithCanonicalMapping.lowercased(), to: 2, in: statement)
        let status = sqlite3_step(statement)
        if status == SQLITE_CONSTRAINT {
            throw MilkError.message("An active goat already has that name.")
        }
        guard status == SQLITE_DONE else { throw databaseError() }
    }

    func retireGoat(id: Int64) throws {
        let statement = try prepare("UPDATE goats SET active = 0 WHERE id = ?;")
        defer { sqlite3_finalize(statement) }
        try bind(id, to: 1, in: statement)
        try finish(statement)
    }

    func save(entries: [MilkEntry], at date: Date, session: MilkingSession, timeZone: TimeZone = .current) throws {
        guard !entries.isEmpty else { throw MilkError.message("Enter a weight for at least one goat.") }
        guard entries.allSatisfy({ (0...100_000).contains($0.weightGrams) }) else {
            throw MilkError.message("Weights must be between 0 and 100,000 grams.")
        }
        let dayFormatter = DateFormatter()
        dayFormatter.calendar = Calendar(identifier: .gregorian)
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.timeZone = timeZone
        dayFormatter.dateFormat = "yyyy-MM-dd"
        let day = dayFormatter.string(from: date)
        let timestamp = ISO8601DateFormatter().string(from: date)

        try execute("BEGIN IMMEDIATE;")
        do {
            for entry in entries {
                let statement = try prepare("""
                INSERT INTO milk_records(recorded_at, local_day, timezone_id, session, goat_id, goat_name, weight_grams)
                VALUES (?, ?, ?, ?, ?, ?, ?);
                """)
                defer { sqlite3_finalize(statement) }
                try bind(timestamp, to: 1, in: statement)
                try bind(day, to: 2, in: statement)
                try bind(timeZone.identifier, to: 3, in: statement)
                try bind(session.rawValue, to: 4, in: statement)
                try bind(entry.goat.id, to: 5, in: statement)
                try bind(entry.goat.name, to: 6, in: statement)
                try bind(entry.weightGrams, to: 7, in: statement)
                let status = sqlite3_step(statement)
                if status == SQLITE_CONSTRAINT && sqlite3_extended_errcode(handle) == 2067 {
                    throw MilkError.message("\(entry.goat.name) already has a \(session.rawValue) entry for \(day). Nothing was saved. To correct it, delete the old entry in History first.")
                }
                guard status == SQLITE_DONE else { throw databaseError() }
            }
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    func records() throws -> [MilkRecord] {
        let statement = try prepare("SELECT id, recorded_at, goat_name, weight_grams, session FROM milk_records ORDER BY recorded_at DESC, id DESC;")
        defer { sqlite3_finalize(statement) }
        let formatter = ISO8601DateFormatter()
        var result: [MilkRecord] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return result }
            guard status == SQLITE_ROW else { throw databaseError() }
            guard let date = formatter.date(from: string(statement, 1)),
                  let session = MilkingSession(rawValue: string(statement, 4)) else {
                throw MilkError.message("A saved record could not be read.")
            }
            result.append(MilkRecord(id: sqlite3_column_int64(statement, 0), recordedAt: date,
                                     goatName: string(statement, 2), weightGrams: sqlite3_column_int64(statement, 3), session: session))
        }
    }

    func deleteRecord(id: Int64) throws {
        let statement = try prepare("DELETE FROM milk_records WHERE id = ?;")
        defer { sqlite3_finalize(statement) }
        try bind(id, to: 1, in: statement)
        try finish(statement)
    }

    private func databaseError() -> MilkError {
        let detail = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "Could not open storage."
        return .message("SQLite: \(detail)")
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw databaseError() }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw databaseError()
        }
        return statement
    }

    private func bind(_ value: String, to index: Int32, in statement: OpaquePointer) throws {
        guard sqlite3_bind_text(statement, index, value, -1, transient) == SQLITE_OK else { throw databaseError() }
    }

    private func bind(_ value: Int64, to index: Int32, in statement: OpaquePointer) throws {
        guard sqlite3_bind_int64(statement, index, value) == SQLITE_OK else { throw databaseError() }
    }

    private func finish(_ statement: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else { throw databaseError() }
    }

    private func string(_ statement: OpaquePointer, _ column: Int32) -> String {
        String(cString: sqlite3_column_text(statement, column))
    }
}
