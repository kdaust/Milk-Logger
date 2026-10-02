import SwiftUI
import Charts

struct ContentView: View {
    let database: Database
    @State private var goats: [Goat] = []
    @State private var records: [MilkRecord] = []
    @State private var hayReplacements: [HayReplacement] = []
    @State private var selectedTab = 0
    @State private var dataGoats: [Goat] = []
    @State private var selectedDataGoatIDs: [Int64] = []
    @State private var dailyTotalsByGoat: [Int64: [DailyMilkTotal]] = [:]
    @State private var newGoatName = ""
    @State private var weights: [Int64: String] = [:]
    @State private var inHeat: [Int64: Bool] = [:]
    @State private var hayReplaced = false
    @State private var date = Date()
    @State private var session = MilkingSession.current()
    @State private var errorMessage: String?
    @State private var confirmation: String?
    @State private var goatToRetire: Goat?
    @State private var recordToDelete: MilkRecord?
    @State private var hayToDelete: HayReplacement?
    @FocusState private var focusedGoat: Int64?

    var body: some View {
        TabView(selection: $selectedTab) {
            entryView.tabItem { Label("Milk", systemImage: "drop.fill") }.tag(0)
            historyView.tabItem { Label("History", systemImage: "clock") }.tag(1)
            goatsView.tabItem { Label("Goats", systemImage: "list.bullet") }.tag(2)
            dataView.tabItem { Label("Data", systemImage: "chart.xyaxis.line") }.tag(3)
        }
        .task { perform { try reload() } }
        .onChange(of: selectedDataGoatIDs) { _ in perform { try reloadDailyTotals() } }
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
                    inHeat[goat.id] = nil
                    try reload()
                }
                goatToRetire = nil
            }
        } message: { Text("Saved milk records will stay in History. Any unsaved weight and heat selection for this goat will be discarded.") }
        .confirmationDialog("Delete this milk record?", isPresented: Binding(
            get: { recordToDelete != nil }, set: { if !$0 { recordToDelete = nil } }
        ), titleVisibility: .visible) {
            Button("Delete record", role: .destructive) {
                guard let record = recordToDelete else { return }
                perform { try database.deleteRecord(id: record.id); try reload() }
                recordToDelete = nil
            }
        } message: { Text("This cannot be undone. You can enter a replacement from the Milk tab.") }
        .confirmationDialog("Delete this hay replacement?", isPresented: Binding(
            get: { hayToDelete != nil }, set: { if !$0 { hayToDelete = nil } }
        ), titleVisibility: .visible) {
            Button("Delete hay replacement", role: .destructive) {
                guard let event = hayToDelete else { return }
                perform { try database.deleteHayReplacement(id: event.id); try reload() }
                hayToDelete = nil
            }
        } message: { Text("This cannot be undone. Milk records will be kept.") }
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
                            VStack(alignment: .leading, spacing: 12) {
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
                                Toggle("In heat", isOn: Binding(
                                    get: { inHeat[goat.id, default: false] },
                                    set: { inHeat[goat.id] = $0; confirmation = nil }
                                ))
                                .toggleStyle(CheckboxToggleStyle())
                                .accessibilityLabel("\(goat.name), in heat")
                            }
                        }
                    } header: { Text("Milk weight · grams") }
                    footer: { Text("Use whole grams (1,000 g = 1 kg). Blank skips a goat; entering 0 saves a zero yield. In heat is saved with that goat’s weight.") }
                    Section {
                        Toggle("Hay replaced", isOn: Binding(
                            get: { hayReplaced },
                            set: { hayReplaced = $0; confirmation = nil }
                        ))
                        .toggleStyle(CheckboxToggleStyle())
                    } header: { Text("Whole herd") }
                    footer: { Text("Records one hay replacement at the selected date and time when you save this milking. Enter at least one goat’s weight.") }
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
                        if record.inHeat {
                            Text("In heat").font(.subheadline)
                        }
                    }
                    .padding(.vertical, 4)
                    .swipeActions(allowsFullSwipe: false) {
                        Button("Delete", role: .destructive) { recordToDelete = record }
                    }
                }
                if !hayReplacements.isEmpty {
                    Section("Hay replacements · whole herd") {
                        ForEach(hayReplacements) { event in
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Hay replaced").font(.headline)
                                Text("\(event.session.title) · \(event.recordedAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                            .swipeActions(allowsFullSwipe: false) {
                                Button("Delete", role: .destructive) { hayToDelete = event }
                            }
                        }
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
                    Section("Goats on chart") {
                        ForEach(selectedDataGoats) { selectedGoat in
                            HStack {
                                Picker("Goat", selection: Binding(
                                    get: { selectedGoat.id },
                                    set: { replacement in
                                        guard let index = selectedDataGoatIDs.firstIndex(of: selectedGoat.id),
                                              !selectedDataGoatIDs.contains(replacement) else { return }
                                        selectedDataGoatIDs[index] = replacement
                                    }
                                )) {
                                    ForEach(dataGoats.filter { $0.id == selectedGoat.id || !selectedDataGoatIDs.contains($0.id) }) { goat in
                                        Text(dataGoatLabel(goat)).tag(goat.id)
                                    }
                                }
                                if selectedDataGoatIDs.count > 1 {
                                    Button {
                                        selectedDataGoatIDs.removeAll { $0 == selectedGoat.id }
                                    } label: {
                                        Image(systemName: "minus.circle")
                                            .frame(minWidth: 44, minHeight: 44)
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel("Remove \(dataGoatLabel(selectedGoat)) from chart")
                                }
                            }
                        }
                        Menu {
                            ForEach(remainingDataGoats) { goat in
                                Button(dataGoatLabel(goat)) { selectedDataGoatIDs.append(goat.id) }
                            }
                        } label: {
                            Label("Add a goat", systemImage: "plus.circle")
                        }
                        .disabled(remainingDataGoats.isEmpty)
                    }
                    if chartTotals.isEmpty {
                        Section {
                            Text("No milk recorded for the selected goats yet.").font(.headline)
                            Text("Save a milking in the Milk tab to see production over time.")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Section {
                            productionChart
                                .frame(height: 260)
                                .padding(.vertical, 12)
                        } header: { Text("Daily milk production · grams") }
                        footer: {
                            Text("Morning and evening weights are added together. When only one session is recorded, its weight is doubled to estimate the full day. Dots show recorded days; connecting lines do not imply measurements on missing days.")
                        }
                    }
                    ForEach(selectedDataGoats) { goat in
                        Section("Daily totals · \(dataGoatLabel(goat))") {
                            if dailyTotalsByGoat[goat.id, default: []].isEmpty {
                                Text("No milk recorded for this goat yet.").foregroundStyle(.secondary)
                            }
                            ForEach(dailyTotalsByGoat[goat.id, default: []].reversed()) { total in
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(total.date, format: chartDateFormat)
                                        Text(total.isEstimated ? "Estimated · 2 × \(total.weightGrams.formatted()) g recorded" : "Morning + evening")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text("\(total.chartWeightGrams.formatted()) g").monospacedDigit()
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
        Chart {
            ForEach(selectedDataGoats) { goat in
                ForEach(dailyTotalsByGoat[goat.id, default: []]) { total in
                    LineMark(x: .value("Date", total.date), y: .value("Milk (g)", total.chartWeightGrams), series: .value("Goat ID", String(goat.id)))
                        .foregroundStyle(by: .value("Goat", dataGoatLabel(goat)))
                        .interpolationMethod(.catmullRom)
                    PointMark(x: .value("Date", total.date), y: .value("Milk (g)", total.chartWeightGrams))
                        .foregroundStyle(by: .value("Goat", dataGoatLabel(goat)))
                        .accessibilityLabel("\(dataGoatLabel(goat)), \(total.date.formatted(chartDateFormat))")
                        .accessibilityValue("\(total.chartWeightGrams) grams, \(total.isEstimated ? "estimated from one session" : "morning and evening recorded")")
                }
            }
        }
        .chartLegend(position: .bottom)
        .chartYScale(domain: 0...max(1, Double(chartTotals.map(\.chartWeightGrams).max() ?? 0) * 1.1))
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
        let first = chartTotals.map(\.date).min() ?? Date()
        let last = chartTotals.map(\.date).max() ?? first
        // A single recorded day still needs a nonzero axis range and a visible dot.
        return first.addingTimeInterval(-43_200)...last.addingTimeInterval(43_200)
    }

    private var selectedDataGoats: [Goat] {
        selectedDataGoatIDs.compactMap { id in dataGoats.first { $0.id == id } }
    }

    private var remainingDataGoats: [Goat] {
        dataGoats.filter { !selectedDataGoatIDs.contains($0.id) }
    }

    private var chartTotals: [DailyMilkTotal] {
        selectedDataGoatIDs.flatMap { dailyTotalsByGoat[$0, default: []] }
    }

    private func dataGoatLabel(_ goat: Goat) -> String {
        goat.isActive ? goat.name : "\(goat.name) (retired #\(goat.id))"
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
                guard let grams = try WeightInput.parse(weights[goat.id, default: ""]) else {
                    if inHeat[goat.id, default: false] {
                        throw MilkError.message("Enter a milk weight for \(goat.name) to save In heat, or uncheck it. Enter 0 only for a zero yield.")
                    }
                    return nil
                }
                return MilkEntry(goat: goat, weightGrams: grams, inHeat: inHeat[goat.id, default: false])
            }
            try database.save(entries: entries, at: date, session: session, hayReplaced: hayReplaced)
            weights = [:] // Clear only after the transaction succeeds.
            confirmation = "Saved \(entries.count) \(entries.count == 1 ? "entry" : "entries") · \(entries.reduce(Int64(0)) { $0 + $1.weightGrams }.formatted()) g"
            if hayReplaced { confirmation = (confirmation ?? "") + " · Hay replaced" }
            inHeat = [:]
            hayReplaced = false
            try reload()
        }
    }

    private func reload() throws {
        goats = try database.goats()
        records = try database.records()
        hayReplacements = try database.hayReplacements()
        dataGoats = try database.goats(includeRetired: true)
        selectedDataGoatIDs.removeAll { id in !dataGoats.contains { $0.id == id } }
        if selectedDataGoatIDs.isEmpty, let first = dataGoats.first(where: \.isActive) ?? dataGoats.first {
            selectedDataGoatIDs = [first.id]
        }
        try reloadDailyTotals()
    }

    private func reloadDailyTotals() throws {
        var loaded: [Int64: [DailyMilkTotal]] = [:]
        do {
            for id in selectedDataGoatIDs {
                loaded[id] = try database.dailyTotals(for: id)
            }
            dailyTotalsByGoat = loaded
        } catch {
            dailyTotalsByGoat = [:]
            throw error
        }
    }

    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { errorMessage = error.localizedDescription }
    }
}

private struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .font(.title2)
                    .accessibilityHidden(true)
                configuration.label
            }
            .frame(minHeight: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "Checked" : "Unchecked")
        .accessibilityAddTraits(configuration.isOn ? [.isSelected] : [])
    }
}
