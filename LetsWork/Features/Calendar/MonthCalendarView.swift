import SwiftUI

/// Grille d'un mois en semaines complètes, alignées sur le premier jour de la semaine du calendrier
/// (le lundi en France) ; les cases hors du mois sont vides.
struct MonthGrid: Equatable {
    var weeks: [[Date?]]
    /// Initiales des jours, dans l'ordre des colonnes : « L M M J V S D ».
    var weekdaySymbols: [String]

    init(containing date: Date, calendar: Calendar = .current) {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        weekdaySymbols = Array(symbols[shift...] + symbols[..<shift])

        guard
            let monthStart = calendar.dateInterval(of: .month, for: date)?.start,
            let dayCount = calendar.range(of: .day, in: .month, for: date)?.count
        else {
            weeks = []
            return
        }
        let leadingBlanks = (calendar.component(.weekday, from: monthStart) - calendar.firstWeekday + 7) % 7
        var cells: [Date?] = Array(repeating: nil, count: leadingBlanks)
        cells += (0..<dayCount).map { calendar.date(byAdding: .day, value: $0, to: monthStart) }
        cells += Array(repeating: nil, count: (7 - cells.count % 7) % 7)
        weeks = stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }
}

/// Mini-calendrier du mois à la manière du widget Calendrier de macOS :
/// mois en rouge, week-ends en gris, jour actuel dans une pastille rouge.
struct MonthCalendarView: View {
    let date: Date

    private static let cellSize = CGSize(width: 20, height: 18)

    var body: some View {
        let calendar = Calendar.current
        let grid = MonthGrid(containing: date, calendar: calendar)
        VStack(alignment: .leading, spacing: 5) {
            Text(date.formatted(.dateTime.month(.wide)).uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.red)
                .padding(.leading, 3)
            Grid(horizontalSpacing: 2, verticalSpacing: 1) {
                GridRow {
                    ForEach(grid.weekdaySymbols.indices, id: \.self) { column in
                        Text(grid.weekdaySymbols[column])
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Self.isWeekendColumn(column, in: grid, calendar: calendar) ? .secondary : .primary)
                            .frame(width: Self.cellSize.width, height: Self.cellSize.height)
                    }
                }
                ForEach(grid.weeks.indices, id: \.self) { week in
                    GridRow {
                        ForEach(0..<7, id: \.self) { column in
                            dayCell(grid.weeks[week][column], calendar: calendar)
                        }
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.07)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(date, format: .dateTime.weekday(.wide).day().month(.wide).year()))
    }

    @ViewBuilder
    private func dayCell(_ day: Date?, calendar: Calendar) -> some View {
        if let day {
            let isToday = calendar.isDate(day, inSameDayAs: date)
            Text("\(calendar.component(.day, from: day))")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(isToday ? .white : calendar.isDateInWeekend(day) ? .secondary : .primary)
                .frame(width: Self.cellSize.width, height: Self.cellSize.height)
                .background {
                    if isToday {
                        Circle()
                            .fill(.red)
                            .frame(width: 19, height: 19)
                    }
                }
        } else {
            Color.clear
                .frame(width: Self.cellSize.width, height: Self.cellSize.height)
        }
    }

    /// Une colonne est un week-end si ses jours le sont (chaque colonne contient au moins un jour du mois).
    private static func isWeekendColumn(_ column: Int, in grid: MonthGrid, calendar: Calendar) -> Bool {
        grid.weeks.lazy.compactMap { $0[column] }.first.map(calendar.isDateInWeekend) ?? false
    }
}
