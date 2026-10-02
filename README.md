# Goat Milk

A small native SwiftUI iPhone/iPad app for recording individual goats’ morning and evening milk weights. The draft targets iOS 16 or later and uses Apple’s system SQLite library, with no third-party dependencies.

## Open and run

1. Copy this folder to a Mac with Xcode 15 or later and an installed iOS simulator runtime.
2. Open `GoatMilk.xcodeproj` in Xcode. Choose the **GoatMilk** scheme and an iPhone simulator, then press **Run** (⌘R).
3. For a physical iPhone, select the GoatMilk target → **Signing & Capabilities**, choose your development team, and replace `com.example.GoatMilk` with your own unique bundle identifier. Select the connected phone and run.

The project has a shared scheme and generates its Info.plist through build settings. No package installation is needed. A custom app icon and App Store distribution setup are intentionally left for a later iteration.

## Try a milking

1. Open **Goats**, enter a name, and tap **Add goat**. Repeat for each goat currently being milked.
2. Open **Milk**, check the date/time and Morning/Evening selection, then enter each weight in **whole grams** (e.g. `1250` for 1.25 kg).
3. Tap **Save milking**. Blank fields skip those goats; an explicit `0` records zero milk. Each weight must be between 0 and 100,000 grams.
4. Open **History** to see saved entries, newest first. Swipe and confirm deletion to remove an incorrect entry, then re-enter it with its original date/session.

Only one record per goat, local calendar day, and session is allowed. If any entered goat already has a record for that session, the entire save is rejected and the form stays filled in. To add a previously skipped goat, enter only that goat’s weight.

The initial session is chosen from the current hour (before noon = morning). You can override it independently of the time. Tap **Now** to refresh the date/time and session when beginning another milking. The recorded timestamp is the time selected on the form, not the moment Save is pressed.

Swipe a goat in **Goats** and choose **Retire** to remove it from future entry forms while keeping its history. Adding the same name after retirement creates a new goat identity; this draft does not have a restore or rename screen.

## How the Swift code fits together

| File | Responsibility |
| --- | --- |
| `GoatMilkApp.swift` | App entry point, opening persistent storage, and recoverable startup errors. |
| `ContentView.swift` | Three SwiftUI tabs. `@State` holds form values and loaded data; bindings connect text fields to those values. |
| `Models.swift` | Goat, session, record, and entry types, plus whole-gram validation. |
| `Database.swift` | Opening SQLite, creating schema, binding values, querying records, and atomic saves. |
| `Tests/DatabaseTests.swift` | Storage persistence, validation, transaction rollback, local-day boundaries, and correction tests. |

The central flow is **text field → `WeightInput.parse` → `MilkEntry` → `Database.save` → refresh History**. Follow `save()` in `ContentView.swift` to see the UI and database connect. SQLite statements are finalized with `defer`, and user-supplied strings are bound as parameters.

For this small draft, database operations run synchronously on the UI thread and History loads all records. A larger herd or years of records would benefit from a background database actor and paginated history.

## Stored data

The database lives inside the app sandbox at **Application Support/GoatMilk/milk.sqlite**. It persists across app launches; deleting the app removes its local data. The draft has no cloud sync, export, or backup UI, and unsaved form values do not survive app termination.

The `goats` table stores a name, normalized name key, and active/retired status. The `milk_records` table contains:

| Column | Meaning |
| --- | --- |
| `id` | Integer record identifier. |
| `recorded_at` | Selected milking datetime as an ISO 8601 UTC string, to the second. |
| `local_day` | Gregorian `yyyy-MM-dd` in the device timezone when saved. |
| `timezone_id` | Timezone used to determine the local day. |
| `session` | `morning` or `evening`. |
| `goat_id` | Reference to the goat. |
| `goat_name` | Name snapshot for this record. |
| `weight_grams` | Integer milk weight, explicitly in grams. |

History displays timestamps in the device’s current timezone. Duplicate detection uses the saved local day. The schema version is recorded in `PRAGMA user_version` for future migrations.

## Validation

On a Mac, run the storage tests from this folder:

```sh
swift test
```

`Package.swift` builds just the Foundation/SQLite storage code for macOS. These tests are separate from the iOS Xcode scheme.

To compile the iOS app without device signing:

```sh
xcodebuild -project GoatMilk.xcodeproj -scheme GoatMilk \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

Manual simulator checks: add two goats; save morning weights; quit and reopen; confirm persistence; attempt a duplicate; save evening weights; retire a goat and verify its history remains; delete an entry and enter a correction. Also check large text and dark mode.

This draft was authored on Windows. The SQL schema and project references were checked locally, but Swift compilation, XCTest execution, and simulator/UI validation still need to be performed on a Mac.

## Learning references

- [Apple’s SwiftUI documentation](https://developer.apple.com/documentation/swiftui)
- [SQLite table definitions and constraints](https://www.sqlite.org/lang_createtable.html)
- [SQLite connection API](https://www.sqlite.org/c3ref/open.html)
