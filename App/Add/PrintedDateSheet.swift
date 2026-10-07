import HearthstockCore
import SwiftUI

/// Picks a printed date: any day past or future, a month (many packages print only "MAR 2025"), or no date.
struct PrintedDateSheet: View {
    @Binding var printed: AddLotModel.PrintedDate
    let dateType: ShelfLifeDateType
    let today: CalendarDate

    @Environment(\.dismiss) private var dismiss
    @State private var monthOnly = true
    @State private var year: Int
    @State private var month: Int
    @State private var day: CalendarDate

    init(printed: Binding<AddLotModel.PrintedDate>, dateType: ShelfLifeDateType, today: CalendarDate) {
        _printed = printed
        self.dateType = dateType
        self.today = today
        let start = printed.wrappedValue.date ?? today
        _year = State(initialValue: start.year)
        _month = State(initialValue: start.month)
        _day = State(initialValue: start)
        _monthOnly = State(initialValue: printed.wrappedValue.date.map { $0.day == 1 } ?? true)
    }

    private static let monthNames = Calendar(identifier: .gregorian).shortMonthSymbols

    var body: some View {
        NavigationStack {
            Form {
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

                Section {
                    Button("No date on the package") {
                        printed = .none
                        dismiss()
                    }
                } footer: {
                    Text("For honey, salt and the like. Items with no date count as Good.")
                }
            }
            .hearthList()
            .navigationTitle(dateType.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if monthOnly {
                            if let date = CalendarDate(year: year, month: month, day: 1) { printed = .day(date) }
                        } else {
                            printed = .day(day)
                        }
                        dismiss()
                    }
                }
            }
        }
    }
}
