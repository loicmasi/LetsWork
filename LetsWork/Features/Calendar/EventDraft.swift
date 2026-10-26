import Foundation

/// Événement en cours de saisie dans la fenêtre « Nouvel événement ».
struct EventDraft: Equatable {
    var title = ""
    var calendarID: String?
    var isAllDay = false
    var start: Date
    var end: Date
    var location = ""
    var urlText = ""
    var notes = ""

    /// Aujourd'hui : début à la prochaine demi-heure ; un autre jour : 9:00. Durée d'une heure.
    init(day: Date, now: Date, calendarID: String?, calendar: Calendar = .current) {
        self.calendarID = calendarID
        let start: Date
        if calendar.isDate(day, inSameDayAs: now) {
            let minutes = calendar.component(.minute, from: now)
            let hour = calendar.date(bySettingHour: calendar.component(.hour, from: now), minute: 0, second: 0, of: now) ?? now
            start = calendar.date(byAdding: .minute, value: minutes < 30 ? 30 : 60, to: hour) ?? now
        } else {
            start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
        }
        self.start = start
        end = start.addingTimeInterval(60 * 60)
    }

    /// Déplace le début en gardant la durée, comme l'app Calendrier.
    mutating func moveStart(to newStart: Date) {
        let duration = end.timeIntervalSince(start)
        start = newStart
        end = newStart.addingTimeInterval(max(duration, 0))
    }

    var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Lien http(s) saisi, ou `nil` si le champ est vide ou invalide.
    var url: URL? {
        let text = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), url.host != nil else {
            return nil
        }
        return url
    }

    /// Raison qui empêche l'enregistrement, ou `nil` si le brouillon est valide.
    var validationMessage: String? {
        if trimmedTitle.isEmpty {
            return String(localized: "Ajoutez un titre.")
        }
        if calendarID == nil {
            return String(localized: "Choisissez un calendrier.")
        }
        if !isAllDay, end <= start {
            return String(localized: "La fin doit être après le début.")
        }
        if !urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, url == nil {
            return String(localized: "Le lien doit commencer par https://.")
        }
        return nil
    }

    /// Dates à enregistrer : un événement sur la journée entière va du début du premier jour au début du dernier.
    func normalizedDates(calendar: Calendar = .current) -> (start: Date, end: Date) {
        guard isAllDay else { return (start, end) }
        let firstDay = calendar.startOfDay(for: start)
        return (firstDay, max(firstDay, calendar.startOfDay(for: end)))
    }
}
