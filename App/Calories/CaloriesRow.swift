import HearthstockCore
import SwiftUI

/// A new food product's calories (Slice 5 Task 5), on the walk card and the add forms: what's known and where from,
/// else the serving line with **Servings per container** (or **Net weight**), and **Scan the label**. Empty is fine:
/// the save still works, and the product shows as missing calories.
struct CaloriesRow: View {
    let entry: CalorieEntry
    let unitKind: UnitKind
    let update: ((inout CalorieEntry) -> Void) -> Void
    let scanLabel: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var netUnit: QuantityUnit = .ounce
    /// The person tapped Edit, so the typed field stays while they clear it to retype.
    @State private var editing = false

    private static let netUnits: [QuantityUnit] = [.ounce, .pound, .gram, .kilogram, .fluidOunce, .liter, .gallon]

    /// Label and field side by side, or stacked at accessibility text sizes (Slice 4 Task 12).
    private var row: AnyLayout {
        typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(spacing: 8))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            valueLine
            if let kind = entry.switchedUnitKind {
                Label(CalorieText.switched(to: kind), systemImage: "scalemass")
                    .font(.caption).foregroundStyle(Color.hsInk2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if entry.asksQuestion(unitKind: unitKind) { question }
            if showsTypedField { typedField }
            Button(action: scanLabel) {
                Label("Scan the label", systemImage: "text.viewfinder")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Color.hsTint)
        }
        .onAppear {
            if let unit = entry.netWeight?.unit { netUnit = unit }
        }
    }

    @ViewBuilder
    private var valueLine: some View {
        if let known = entry.kcal(unitKind: unitKind) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                (Text(CalorieText.value(known.value, unitKind: unitKind)).fontWeight(.semibold).foregroundStyle(Color.hsInk)
                    + Text(" · \(CalorieText.origin(known.origin))").foregroundStyle(Color.hsInk2))
                    .font(.subheadline)
                    .numeric()
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if !showsTypedField {
                    Button("Edit") {
                        editing = true
                        update { $0.typedKcal = known.value }
                    }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.borderless)
                    .foregroundStyle(Color.hsTint)
                }
            }
        } else {
            Label("No calories yet", systemImage: "exclamationmark.circle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.hsAmber)
        }
    }

    /// Servings per container, or the net weight when that's the answer (or the only one).
    @ViewBuilder
    private var question: some View {
        let usesNet = entry.usesNetWeight || !entry.canAskServings
        if let line = CalorieText.servingLine(entry.lookedUp) {
            Text(line).font(.subheadline).foregroundStyle(Color.hsInk2)
        }
        row {
            Text(usesNet ? "Net weight" : "Servings per container").foregroundStyle(Color.hsInk)
                .fixedSize(horizontal: false, vertical: true)
            if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
            if usesNet {
                HStack(spacing: 6) {
                    field("15.25", value: Binding(
                        get: { entry.netWeight?.value },
                        set: { value in
                            let unit = netUnit
                            update {
                                $0.usesNetWeight = true
                                $0.netWeight = value.map { Quantity(value: $0, unit: unit) }
                            }
                        }))
                    Picker("Unit", selection: Binding(get: { netUnit }, set: { unit in
                        netUnit = unit
                        update { $0.netWeight = $0.netWeight.map { Quantity(value: $0.value, unit: unit) } }
                    })) {
                        ForEach(Self.netUnits, id: \.self) { Text($0.symbol).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            } else {
                field("3.5", value: Binding(get: { entry.servings }, set: { value in update { $0.servings = value } }))
            }
        }
        if entry.canAskServings && entry.canAskNetWeight {
            Toggle("Net weight instead", isOn: Binding(
                get: { entry.usesNetWeight },
                set: { on in update { $0.usesNetWeight = on } }))
                .font(.subheadline)
                .tint(Color.hsTint)
        }
    }

    /// Typed calories: shown when nothing else can give them, or once typed.
    private var showsTypedField: Bool {
        editing || entry.typedKcal != nil || (entry.kcal(unitKind: unitKind) == nil && !entry.asksQuestion(unitKind: unitKind))
    }

    private var typedField: some View {
        row {
            Text("kcal per \(unitKind.perUnit)").foregroundStyle(Color.hsInk)
            if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
            field("Optional", value: Binding(
                get: { entry.typedKcal },
                set: { value in update { $0.typedKcal = value } }))
        }
    }

    private func field(_ prompt: String, value: Binding<Double?>) -> some View {
        TextField(prompt, value: value, format: .number)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .numeric()
            .frame(maxWidth: 110)
            .padding(.vertical, 6).padding(.horizontal, 10)
            .background(Color.hsTrack, in: RoundedRectangle(cornerRadius: 10))
    }
}

/// "Guessed from the name: Canned, low acid · Change" (Slice 5 Task 7). Change opens the profile picker; a pick
/// stops the name from moving the profile, and the line then reads "Shelf life: …".
struct NameGuessLine: View {
    let profileKey: ShelfLifeProfileKey
    let guessed: Bool
    let profiles: ShelfLifeProfileTable
    let pick: (ShelfLifeProfileKey) -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(guessed ? "Guessed from the name" : "Shelf life"): \(profiles[profileKey]?.name ?? "")")
                .font(.subheadline).foregroundStyle(Color.hsInk2)
                .fixedSize(horizontal: false, vertical: true)
            Menu {
                Picker("Shelf life", selection: Binding(get: { profileKey }, set: { pick($0) })) {
                    ForEach(profiles.profiles) { Text($0.name).tag($0.key) }
                }
            } label: {
                Text("Change").font(.subheadline.weight(.semibold)).foregroundStyle(Color.hsTint)
            }
        }
    }
}

/// Scan the label (Slice 5 Task 6): reads the Nutrition Facts panel live, shows what it read and the calories per
/// item (or lb) it gives. **Use this** hands the reading back; nothing is saved until Add or Save.
struct NutritionLabelScannerSheet: View {
    /// What a reading would give: calories per base unit and the unit kind they're per (a bag's net weight can switch
    /// a new product to lb, Decision 8).
    let preview: (NutritionReading) -> (kcal: Double, unitKind: UnitKind)?
    let onUse: (NutritionReading) -> Void

    var body: some View {
        TextScannerSheet(
            title: "Scan the label",
            hint: "Point at the Nutrition Facts panel: Calories, Servings per container and Net Wt.",
            fallback: "type the calories", initial: NutritionReading(),
            read: { old, text in old.merging(NutritionLabelParser.read(text)) }
        ) { reading, close in
            if !reading.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(CalorieText.reading(reading), id: \.self) { Text($0) }
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color.hsCameraControl, in: RoundedRectangle(cornerRadius: 14))
                if let result = preview(reading) {
                    Button {
                        onUse(reading)
                        close()
                    } label: {
                        VStack(spacing: 4) {
                            Text("Use this").font(.caption.weight(.semibold)).opacity(0.8)
                            Text(CalorieText.value(result.kcal, unitKind: result.unitKind)).font(.title3.bold())
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(CameraPillStyle(prominent: true))
                }
            }
        }
    }
}
