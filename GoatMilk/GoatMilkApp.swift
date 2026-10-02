import SwiftUI

@main
struct GoatMilkApp: App {
    var body: some Scene {
        WindowGroup { AppRootView() }
    }
}

struct AppRootView: View {
    @State private var database: Database?
    @State private var startupError: String?

    var body: some View {
        Group {
            if let database {
                ContentView(database: database)
            } else if let startupError {
                VStack(spacing: 20) {
                    Image(systemName: "externaldrive.badge.exclamationmark").font(.largeTitle)
                    Text("Unable to open milk records").font(.headline)
                    Text(startupError).multilineTextAlignment(.center)
                    Button("Try again", action: openDatabase).buttonStyle(.borderedProminent)
                }.padding()
            } else {
                ProgressView("Opening milk records…")
            }
        }
        .tint(.teal)
        .task { if database == nil { openDatabase() } }
    }

    private func openDatabase() {
        do {
            database = try Database(url: Database.defaultURL())
            startupError = nil
        } catch { startupError = error.localizedDescription }
    }
}
