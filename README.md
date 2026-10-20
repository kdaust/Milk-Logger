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
3. Check **In heat** under any affected goat and **Hay replaced** under **Whole herd** if applicable, then tap **Save milking**. Blank fields skip those goats; an explicit `0` records zero milk. Each weight must be between 0 and 100,000 grams. A checked heat observation requires that goat’s weight. Hay is saved once for the herd alongside a milking with at least one weight.
4. Open **History** to see saved entries, newest first. Swipe and confirm deletion to remove an incorrect entry, then re-enter it with its original date/session.

Only one record per goat, local calendar day, and session is allowed. If any entered goat already has a record for that session, the entire save is rejected and the form stays filled in. To add a previously skipped goat, enter only that goat’s weight.

The initial session is chosen from the current hour (before noon = morning). Date/time and session refresh whenever you return to the Milk tab or the app becomes active (including returning from the background). Entered weights and checkboxes are kept. You can override the time/session while staying on the form, or tap **Now**. The recorded timestamp is the time selected on the form, not the moment Save is pressed.

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

## Comparing goats in Data

The Data tab starts with one goat selected. Use **Add a goat** to choose from goats not already on the chart. Each goat has a separate colored line and a legend label. You can change a selected goat with its picker or remove additional goats with the minus button. Retired goats remain available for comparison, and goats with no records show an empty-state message in their daily totals section.

When a day has only a morning or evening record and two milkings were scheduled, the chart doubles that weight as a full-day estimate. Once-daily goats use the recorded weight. With both sessions recorded, it always uses their actual sum. The daily totals list labels estimates and shows the original recorded amount. Stored weights and History are unchanged. Selections last for the current app session.

Choose **Once** or **Twice** when adding a goat. Tap an existing goat in **Goats** to change its frequency and choose **Effective from** (today by default). Set Luna to Once with the day her schedule changed. Earlier days retain their old schedule; subsequent saved schedule changes still apply. The setting affects daily graph estimates and heat markers, not which sessions may be entered or the violin chart's raw weights.

🔥 appears above a goat's daily point only when both morning and evening records are marked in heat on a twice-daily day. A missing session or one unchecked heat box suppresses the marker. On once-daily days, a recorded heat observation qualifies. 🍃 appears once per hay-replacement day in a separate row above the lines, within the displayed date range; it belongs to the herd. The graph uses saved local calendar days, so these markers summarize days rather than exact event times.

**Export all data as CSV** in Data opens **Share CSV** and **Save to Files** actions. It includes every milk record, including retired goats, regardless of chart selection, and every hay replacement. Columns are `goat_name,date,time,weight,in_heat,hay_replaced`. Weight is actual grams (never a daily estimate); flags are `0`/`1`; date is the saved local day and time includes its UTC offset. Herd hay events are separate rows with blank goat name and weight, `in_heat=0`, and `hay_replaced=1`; milk rows have `hay_replaced=0`. This preserves independent hay events even after a milk record is deleted. Names containing commas, quotes or newlines are CSV-escaped. Empty databases export the header. This is a measurement/event export, not a full database backup of goat settings and schedule history.

On a simulator, compare two goats with different date ranges; add and remove goats; check that the add menu excludes selected goats and disables when all are selected. Verify a single-session day is doubled, then add its second session and confirm the chart switches to the actual sum. Check a zero yield, a goat without records, retired goats, large text, and VoiceOver.

The Data tab also compares **Morning vs evening** with a violin chart using all saved individual milkings for the same selected goats. Each session has one violin per goat, arranged side by side with colors shared across both charts. A violin uses a Gaussian kernel density estimate (81 samples, bandwidth `max(1 g, 1.06 × sample standard deviation × n^(-0.2))`), restricted to the observed weight range. Each violin has the same peak width, so width describes relative frequency within that distribution, not the number of records. The chart includes median dots and text summaries with sample counts. Fewer than three observations or identical weights are shown as recorded-value dots, and missing sessions are explicitly labeled. Zero yields are included; doubled daily estimates are excluded. No schema change is required.

Simulator checks for this chart: add multiple goats, including a retired goat with a reused name; verify colors match the production chart and sessions stay separate. Check empty sessions, one or two records, repeated identical weights, zero yields, and a varied distribution. Save/delete a milking and confirm the distribution and count refresh. Check large text and VoiceOver.

Chart updates publish the selected goats, daily totals, and distributions as one snapshot. Color categories and violin positions use that same snapshot. Both Charts views are recreated without animation when the snapshot changes, avoiding stale category/series state during selection changes. If loading fails, the previous selection and chart data remain together. Regression checks: repeatedly switch between goats with a full violin, sparse dots, and no data; add/remove goats; switch away from and back to Data; save/delete records while multiple goats are selected.

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
| `in_heat` | `0` (unchecked) or `1` (checked), specific to this goat and milking. |

History displays timestamps in the device’s current timezone. Duplicate detection uses the saved local day. The schema version is recorded in `PRAGMA user_version` for future migrations.

### SQLite migration plan: version 1 → 2

The app runs `Database.migrationToVersion2` when opening a version 1 database, then continues to version 3 below. Fresh installs follow the same path. Version 2 databases skip this step. Databases newer than version 3 are rejected rather than modified.

```sql
BEGIN IMMEDIATE;
ALTER TABLE milk_records
  ADD COLUMN in_heat INTEGER NOT NULL DEFAULT 0 CHECK(in_heat IN (0, 1));
CREATE TABLE hay_replacements (
  id INTEGER PRIMARY KEY,
  recorded_at TEXT NOT NULL,
  local_day TEXT NOT NULL,
  timezone_id TEXT NOT NULL,
  session TEXT NOT NULL CHECK(session IN ('morning', 'evening'))
);
CREATE INDEX hay_replacement_dates ON hay_replacements(recorded_at DESC);
PRAGMA user_version = 2;
COMMIT;
```

Existing goats and milk records stay intact. Existing milk records get `in_heat = 0`, meaning no heat observation was recorded, not proof the goat was not in heat. There are no inferred historical hay events. Migration failures roll back the version 2 changes and present the existing startup error screen.

Each checked **Hay replaced** save inserts one herd event, with the form’s selected timestamp, local day, timezone, and session; it has no goat foreign key. An unchecked box inserts nothing. Multiple replacements in the same day/session are allowed. When adding a skipped goat later, leave Hay replaced unchecked unless hay was replaced again.

Milk rows (including heat flags) and the optional hay event commit in one transaction. A duplicate or failed write rolls everything back and leaves the form filled in. Successful saves clear weights and both types of checkbox. History shows heat on milk records and hay in a separate herd section. Deleting a milk record does not delete a hay event; hay events have their own confirmed delete action.

Before shipping, back up a copy of an existing database, open it with the new app, verify the old rows and version 2, then save/reopen a milking with mixed heat flags and one hay event. Check an unchecked save and a duplicate rejection, and confirm independent history deletion. The storage tests cover migration, reopening, persistence, and rollback; simulator checks should also verify checkbox accessibility and that failed saves retain the form.

## Validation

### SQLite version 3: milking schedules

The automatic transactional migration adds `milking_schedules(goat_id, effective_day, milkings_per_day)`, with primary key `(goat_id, effective_day)`, a goat foreign key, and a constraint allowing 1 or 2 milkings. Existing goats receive a baseline of twice daily (`0001-01-01`); existing milk/hay rows are preserved. New goats receive the chosen baseline. Edits insert or replace the schedule for the selected effective date. Daily totals use the latest schedule on or before the recorded local day. A failed migration rolls back; the version becomes 3 only after success.

Additional simulator checks: export and share/save CSV with retired goats and hay-only rows; cancel sharing/export; add a once-daily goat; change Luna's schedule from a past date; verify older estimates stay doubled while later single-session totals do not. Check the heat cases (missing evening, one checked session, both checked, once-daily checked) and hay markers with multiple selected goats. Enter unsaved weights/checkboxes, switch tabs, then background/reopen the app and verify time/session refresh while inputs remain. Swift storage tests cover schedule boundaries, heat logic, and CSV escaping/timezones; Windows SQL checks do not replace simulator validation.

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
