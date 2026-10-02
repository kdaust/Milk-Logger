import SwiftUI
import Charts

struct ContentView: View {
    let database: Database
    @State private var goats: [Goat] = []
    @State private var records: [MilkRecord] = []
    @State private var selectedTab = 0
    @State private var dataGoats: [Goat] = []
    @State private var selectedDataGoatID: Int64?
    @State private var dailyTotals: [DailyMilkTotal] = []
    @State private var newGoatName = ""
    @State private var weights: [Int64: String] = [:]
    @State private var date = Date()
    @State private var session = MilkingSession.current()
    @State private var errorMessage: String?
    @State private var confirmation: String?
    @State private var goatToRetire: Goat?
    @State private var recordToDelete: MilkRecord?
    @FocusState private var focusedGoat: Int64?

    var body: some View {
        TabView(selection: $selectedTab) {
            entryView.tabItem { Label("Milk", systemImage: "drop.fill") }.tag(0)
            historyView.tabItem { Label("History", systemImage: "clock") }.tag(1)
            goatsView.tabItem { Label("Goats", systemImage: "list.bullet") }.tag(2)
            dataView.tabItem { Label("Data", systemImage: "chart.xyaxis.line") }.tag(3)
        }
        .task { perform { try reload() } }
        .onChange(of: selectedDataGoatID) { _ in perform { try reloadDailyTotals() } }
        .alert("Something needs attention", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
        .confirmationDialog("Retire \(goatToRetire?.name ?? "this goat")?", isPresented: Binding(
            get: { goatToRetire != nil }, set: { if !$0 { goatToRetire = nil } }
        ), titleVisibility: .visible) {
            Button("Retire goat", role: .destructive) {
                guard let goat = goatToRetire else { return }
                perform {
                    try database.retireGoat(id: goat.id)
                    weights[goat.id] = nil
                    try reload()
                }
                goatToRetire = nil
            }
        } message: { Text("Saved milk records will stay in History. Any unsaved weight for this goat will be discarded.") }
        .confirmationDialog("Delete this milk record?", isPresented: Binding(
            get: { recordToDelete != nil }, set: { if !$0 { recordToDelete = nil } }
        ), titleVisibility: .visible) {
            Button("Delete record", role: .destructive) {
                guard let record = recordToDelete else { return }
                perform { try database.deleteRecord(id: record.id); try reload() }
                recordToDelete = nil
            }
        } message: { Text("This cannot be undone. You can enter a replacement from the Milk tab.") }
    }

    private var entryView: some View {
        NavigationStack {
            Form {
                if goats.isEmpty {
                    Section {
                        Text("Start by adding the goats you’re milking.")
                        Button("Set up your goats") { selectedTab = 2 }
                    }
                } else {
                    Section("Milking details") {
                        DatePicker("Date & time", selection: $date, in: ...Date())
                        Picker("Session", selection: $session) {
                            ForEach(MilkingSession.allCases) { Text($0.title).tag($0) }
                        }.pickerStyle(.segmented)
                    }
                    Section {
                        ForEach(goats) { goat in
                            HStack {
                                Text(goat.name).frame(maxWidth: .infinity, alignment: .leading)
                                TextField("0", text: Binding(
                                    get: { weights[goat.id, default: ""] },
                                    set: { weights[goat.id] = $0; confirmation = nil }
                                ))
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(minWidth: 70, maxWidth: 120)
                                .focused($focusedGoat, equals: goat.id)
                                .accessibilityLabel("\(goat.name), milk weight in grams")
                                Text("g").foregroundStyle(.secondary)
                            }
                        }
                    } header: { Text("Milk weight · grams") }
                    footer: { Text("Use whole grams (1,000 g = 1 kg). Blank skips a goat; entering 0 saves a zero yield.") }
                    Section {
                        Button(action: save) {
                            Label("Save milking", systemImage: "checkmark.circle.fill")
                                .frame(maxWidth: .infinity).font(.headline)
                        }
                        .disabled(!goats.contains { !(weights[$0.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
                    }
                }
                if let confirmation {
                    Section { Label(confirmation, systemImage: "checkmark.circle").foregroundStyle(.green) }
                }
            }
            .navigationTitle("Data Entry").foregroundStyle(Color(.purple))
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedGoat = nil }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Now") { date = Date(); session = .current(); confirmation = nil }
                }
            }
        }
    }

    private var goatsView: some View {
        NavigationStack {
            Form {
                Section("Add a goat") {
                    TextField("Goat’s name", text: $newGoatName)
                        .textInputAutocapitalization(.words).autocorrectionDisabled()
                        .onSubmit(addGoat)
                    Button("Add goat", action: addGoat)
                        .disabled(newGoatName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Section {
                    if goats.isEmpty { Text("Your goats will appear here.").foregroundStyle(.secondary) }
                    ForEach(goats) { goat in
                        Text(goat.name)
                            .swipeActions(allowsFullSwipe: false) {
                                Button("Retire", role: .destructive) { goatToRetire = goat }
                            }
                    }
                } header: { Text("Currently milking · \(goats.count)") }
                footer: { Text("Swipe a goat to retire it from the entry form. Its saved records are kept.") }
            }.navigationTitle("Your goats")
        }
    }

    private var historyView: some View {
        NavigationStack {
            List {
                if records.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No milk recorded yet").font(.headline)
                        Text("Saved morning and evening entries will appear here.").foregroundStyle(.secondary)
                    }.padding(.vertical)
                }
                ForEach(records) { record in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(record.goatName).font(.headline)
                            Spacer()
                            Text("\(record.weightGrams.formatted()) g").font(.headline).monospacedDigit()
                        }
                        Text("\(record.session.title) · \(record.recordedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    .swipeActions(allowsFullSwipe: false) {
                        Button("Delete", role: .destructive) { recordToDelete = record }
                    }
                }
            }
            .navigationTitle("Milk history")
            .refreshable { perform { try reload() } }
        }
    }

    private var dataView: some View {
        NavigationStack {
            List {
                if dataGoats.isEmpty {
                    Section {
                        Text("Add a goat to get started.").font(.headline)
                        Button("Set up your goats") { selectedTab = 2 }
                    }
                } else {
                    Section {
                        Picker("Goat", selection: $selectedDataGoatID) {
                            ForEach(dataGoats) { goat in
                                Text(goat.isActive ? goat.name : "\(goat.name) (retired #\(goat.id))")
                                    .tag(Optional(goat.id))
                            }
                        }
                    }
                    if dailyTotals.isEmpty {
                        Section {
                            Text("No milk recorded for this goat yet.").font(.headline)
                            Text("Save a milking in the Milk tab to see its production over time.")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Section {
                            productionChart
                                .frame(height: 260)
                                .padding(.vertical, 12)
                        } header: { Text("Daily milk production · grams") }
                        footer: {
                            Text("Morning and evening weights are added together. A day with one entry is a partial total. Dots show recorded days; connecting lines do not imply measurements on missing days.")
                        }
                        Section("Daily totals") {
                            ForEach(dailyTotals.reversed()) { total in
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(total.date, format: chartDateFormat)
                                        Text(total.sessionCount == 2 ? "Morning + evening" : "1 session · partial total")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text("\(total.weightGrams.formatted()) g").monospacedDigit()
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Data")
            .refreshable { perform { try reload() } }
        }
    }

    private var chartDateFormat: Date.FormatStyle {
        Date.FormatStyle(date: .abbreviated, time: .omitted,
                         calendar: Calendar(identifier: .gregorian), timeZone: TimeZone(secondsFromGMT: 0)!)
    }

    private var productionChart: some View {
        Chart(dailyTotals) { total in
            LineMark(x: .value("Date", total.date), y: .value("Milk (g)", total.weightGrams))
                .foregroundStyle(.teal)
                .interpolationMethod(.linear)
            PointMark(x: .value("Date", total.date), y: .value("Milk (g)", total.weightGrams))
                .foregroundStyle(.teal)
                .accessibilityLabel(total.date.formatted(chartDateFormat))
                .accessibilityValue("\(total.weightGrams) grams, \(total.sessionCount) sessions")
        }
        .chartYScale(domain: 0...max(1, Double(dailyTotals.map(\.weightGrams).max() ?? 0) * 1.1))
        .chartXScale(domain: chartDateRange)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date, format: chartDateFormat)
                    }
                }
            }
        }
        .chartYAxisLabel("Milk (g)")
        .chartXAxisLabel("Date")
        .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
        .environment(\.calendar, Calendar(identifier: .gregorian))
    }

    private var chartDateRange: ClosedRange<Date> {
        let first = dailyTotals.first?.date ?? Date()
        let last = dailyTotals.last?.date ?? first
        // A single recorded day still needs a nonzero axis range and a visible dot.
        return first.addingTimeInterval(-43_200)...last.addingTimeInterval(43_200)
    }

    private func addGoat() {
        perform {
            try database.addGoat(name: newGoatName)
            newGoatName = ""
            try reload()
        }
    }

    private func save() {
        focusedGoat = nil
        perform {
            let entries = try goats.compactMap { goat -> MilkEntry? in
                guard let grams = try WeightInput.parse(weights[goat.id, default: ""]) else { return nil }
                return MilkEntry(goat: goat, weightGrams: grams)
            }
            try database.save(entries: entries, at: date, session: session)
            weights = [:] // Clear only after the transaction succeeds.
            confirmation = "Saved \(entries.count) \(entries.count == 1 ? "entry" : "entries") · \(entries.reduce(Int64(0)) { $0 + $1.weightGrams }.formatted()) g"
            try reload()
        }
    }

    private func reload() throws {
        goats = try database.goats()
        records = try database.records()
        dataGoats = try database.goats(includeRetired: true)
        if !dataGoats.contains(where: { $0.id == selectedDataGoatID }) {
            selectedDataGoatID = dataGoats.first(where: \.isActive)?.id ?? dataGoats.first?.id
        }
        try reloadDailyTotals()
    }

    private func reloadDailyTotals() throws {
        dailyTotals = []
        if let selectedDataGoatID {
            dailyTotals = try database.dailyTotals(for: selectedDataGoatID)
        }
    }

    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { errorMessage = error.localizedDescription }
    }
}
