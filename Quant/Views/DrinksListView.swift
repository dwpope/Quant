import SwiftUI

/// Today's drinks, newest first, with Add drink (hydration design §7.6). Aware's own drinks can
/// be changed (tap) or deleted (swipe); drinks from the shortcut or other apps are read-only,
/// as Health lets an app change only what it saved, and a footnote says where to change them.
struct DrinksListView: View {
    @ObservedObject var hydration: HydrationModel

    @Environment(\.dismiss) private var dismiss
    @State private var editing: Drink?
    @State private var adding = false
    @State private var errorText: String?

    init(hydration: HydrationModel) {
        self.hydration = hydration
    }

    /// Shown under the list when some drinks can only be changed in the Health app.
    nonisolated static func footnote(for drinks: [Drink]) -> String? {
        drinks.contains { !$0.source.isEditableInAware }
            ? "Drinks from Shortcuts and other apps are changed in the Health app." : nil
    }

    private var drinks: [Drink] { Array(hydration.day.drinks.reversed()) }

    var body: some View {
        NavigationStack {
            Group {
                if drinks.isEmpty {
                    ContentUnavailableView("No drinks yet today", systemImage: "drop")
                } else {
                    List {
                        Section {
                            ForEach(drinks) { row($0) }
                        } footer: {
                            if let note = Self.footnote(for: drinks) {
                                Text(note).readableSecondary()
                            }
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let errorText {
                    Text(errorText)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                }
            }
            .navigationTitle("Today's drinks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Add drink") { adding = true }
                }
            }
            .sheet(item: $editing) { drink in
                DrinkAmountSheet(title: "Change amount", showsTime: false,
                                 millilitres: Self.clamped(drink.millilitres), time: drink.at) { amount, _ in
                    await run { try await hydration.changeAmount(of: drink, to: amount) }
                }
            }
            .sheet(isPresented: $adding) {
                DrinkAmountSheet(title: "Add drink", showsTime: true, millilitres: 250, time: .now) { amount, time in
                    await run { try await hydration.addDrink(millilitres: amount, at: time) }
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ drink: Drink) -> some View {
        let content = HStack(spacing: 12) {
            Text(drink.at.formatted(date: .omitted, time: .shortened))
                .monospacedDigit()
            Text(HydrationDay.volumeLabel(drink.millilitres))
                .fontWeight(.medium)
            Spacer(minLength: 8)
            Text(drink.source.label)
                .readableSecondary()
        }
        if drink.source.isEditableInAware {
            Button { editing = drink } label: {
                content.foregroundStyle(.primary).contentShape(Rectangle())
            }
            .swipeActions {
                Button("Delete", role: .destructive) {
                    Task { await run { try await hydration.delete(drink) } }
                }
            }
            .accessibilityHint("Changes the amount")
        } else {
            content.accessibilityElement(children: .combine)
        }
    }

    private func run(_ change: () async throws -> Void) async {
        do {
            try await change()
            errorText = nil
        } catch {
            errorText = "Couldn't save that to Apple Health. \(error.localizedDescription)"
        }
    }

    private static func clamped(_ millilitres: Double) -> Double {
        min(max(millilitres, HydrationModel.amountRange.lowerBound), HydrationModel.amountRange.upperBound)
    }
}

/// An amount in steps of 10 mL, and for a new drink its time, from midnight to now.
private struct DrinkAmountSheet: View {
    let title: String
    let showsTime: Bool
    @State var millilitres: Double
    @State var time: Date
    let save: (_ millilitres: Double, _ time: Date) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Stepper(value: $millilitres, in: HydrationModel.amountRange, step: 10) {
                    // Exact, so each 10 mL step shows, even past a litre.
                    Text("\(Int(millilitres.rounded())) mL")
                        .monospacedDigit()
                }
                if showsTime {
                    DatePicker("Time", selection: $time,
                               in: Calendar.current.startOfDay(for: .now)...Date.now,
                               displayedComponents: .hourAndMinute)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saving = true
                        Task {
                            await save(millilitres, time)
                            dismiss()
                        }
                    }
                    .disabled(saving)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
