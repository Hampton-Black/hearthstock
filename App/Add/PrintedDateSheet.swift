import HearthstockCore
import SwiftUI

/// Picks a printed date: any day past or future, a month (many packages print only "MAR 2025"), or "No date on the
/// package", which ages the lot from an estimate (Slice 4 Decisions 1–2) whose months can be changed for this lot.
struct PrintedDateSheet: View {
    @Binding var printed: AddLotModel.PrintedDate
    /// This lot's estimate months; nil uses the profile's.
    @Binding var estimateMonths: Int?
    let profile: ShelfLifeProfile?
    let today: CalendarDate
    /// The estimated usable-by date for a given number of months (nil: the profile's).
    let estimate: (Int?) -> CalendarDate?

    @Environment(\.dismiss) private var dismiss
    @State private var noDate: Bool
    @State private var months: Int
    @State private var monthOnly = true
    @State private var year: Int
    @State private var month: Int
    @State private var day: CalendarDate

    init(
        printed: Binding<AddLotModel.PrintedDate>, estimateMonths: Binding<Int?>, profile: ShelfLifeProfile?,
        today: CalendarDate, estimate: @escaping (Int?) -> CalendarDate?
    ) {
        _printed = printed
        _estimateMonths = estimateMonths
        self.profile = profile
        self.today = today
        self.estimate = estimate
        let start = printed.wrappedValue.date ?? today
        _year = State(initialValue: start.year)
        _month = State(initialValue: start.month)
        _day = State(initialValue: start)
        _monthOnly = State(initialValue: printed.wrappedValue.date.map { $0.day == 1 } ?? true)
        _noDate = State(initialValue: printed.wrappedValue.isNoPrintedDate)
        _months = State(initialValue: estimateMonths.wrappedValue ?? profile?.rotationMonths ?? 12)
    }

    private static let monthNames = Calendar(identifier: .gregorian).shortMonthSymbols

    private var dateType: ShelfLifeDateType { profile?.dateType ?? .bestBy }
    /// Only dated profiles can be marked "no printed date"; honey and stored tap water don't need a date at all.
    private var offersNoDate: Bool { dateType != .none && profile?.rotationMonths != nil }
    private var defaultMonths: Int? { profile?.rotationMonths }

    var body: some View {
        NavigationStack {
            Form {
                if offersNoDate {
                    Section {
                        Toggle("No date on the package", isOn: $noDate.animation())
                    } footer: {
                        if !noDate {
                            Text("Leave the date unset if you'll add it later; the item shows as needing a date until then.")
                        }
                    }
                }

                if noDate {
                    estimateSection
                } else {
                    datePicker
                    if printed != .unset {
                        Section {
                            Button("Clear the date", role: .destructive) {
                                printed = .unset
                                dismiss()
                            }
                        }
                    }
                }
            }
            .hearthList()
            .navigationTitle(dateType.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { done() } }
            }
        }
    }

    @ViewBuilder
    private var estimateSection: some View {
        Section {
            LabeledContent("Est. usable by") {
                Text(estimate(months == defaultMonths ? nil : months)?.monthYear ?? "–")
                    .fontWeight(.semibold).foregroundStyle(Color.hsInk)
            }
            Stepper(value: $months, in: 1...240) {
                LabeledContent("Estimate") {
                    Text(ProfileText.duration(months)).numeric().foregroundStyle(Color.hsInk)
                }
            }
            if let defaultMonths, months != defaultMonths {
                Button("Use the default (\(ProfileText.duration(defaultMonths)))") { months = defaultMonths }
            }
        } header: {
            Text("Estimate for this item")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if let profile, let defaultMonths {
                    Text("\(profile.name) without a printed date: \(ProfileText.duration(defaultMonths)) from when you got it, shortened for hot or unconditioned storage.")
                }
                Text("Set Acquired to when you bought it, or the estimate runs from today.")
            }
        }
    }

    @ViewBuilder
    private var datePicker: some View {
        Section {
            Picker("Precision", selection: $monthOnly) {
                Text("Month").tag(true)
                Text("Exact day").tag(false)
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }

        if monthOnly {
            Section {
                HStack {
                    Button { year -= 1 } label: { Image(systemName: "chevron.left") }
                        .accessibilityLabel("Previous year")
                    Spacer()
                    Text(String(year)).font(.title3.bold()).numeric()
                    Spacer()
                    Button { year += 1 } label: { Image(systemName: "chevron.right") }
                        .accessibilityLabel("Next year")
                }
                .buttonStyle(.borderless)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(1...12, id: \.self) { value in
                        Button {
                            month = value
                        } label: {
                            Text(Self.monthNames[value - 1])
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .foregroundStyle(month == value ? Color.hsOnTint : Color.hsInk)
                                .background(month == value ? Color.hsTint : Color.hsTrack,
                                            in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(month == value ? .isSelected : [])
                    }
                }
            } footer: {
                Text("A month-only date is saved as the 1st, the earlier and safer end of the month.")
            }
        } else {
            Section {
                DatePicker(
                    dateType.label,
                    selection: Binding(get: { day.pickerDate }, set: { day = CalendarDate(pickerDate: $0) }),
                    displayedComponents: .date)
                    .datePickerStyle(.graphical)
            }
        }
    }

    private func done() {
        if noDate {
            printed = .noPrintedDate
            estimateMonths = months == defaultMonths ? nil : months
        } else if monthOnly {
            if let date = CalendarDate(year: year, month: month, day: 1) { printed = .day(date) }
        } else {
            printed = .day(day)
        }
        dismiss()
    }
}

/// How the printed-date row reads on the add form and lot edit.
enum PrintedDateText {
    static func row(_ printed: AddLotModel.PrintedDate, profile: ShelfLifeProfile?, estimate: CalendarDate?) -> String {
        switch printed {
        case .unset:
            profile?.dateType == ShelfLifeDateType.none ? "Not needed" : "Not set"
        case .noPrintedDate:
            estimate.map { "No printed date · est. \($0.monthYear)" } ?? "No printed date"
        case .day(let date):
            "\((profile?.dateType ?? .bestBy).label) \(date.medium)"
        }
    }

    /// The row's text shows in amber when a dated profile's date hasn't been set: the lot will be flagged.
    static func isMissing(_ printed: AddLotModel.PrintedDate, profile: ShelfLifeProfile?) -> Bool {
        printed == .unset && profile.map { $0.dateType != .none } == true
    }
}
