import SwiftUI

extension CalendarColor {
    var color: Color {
        Color(red: red, green: green, blue: blue)
    }
}

/// Compact : pastille et titre court à gauche, délai à droite (« dans 12 min », « en cours »).
struct CalendarCompactView: View {
    let event: CalendarEvent
    let notch: NotchGeometry

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Circle()
                    .fill(event.color.color)
                    .frame(width: 8, height: 8)
                Text(event.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, 12)
            .frame(width: IslandMetrics.calendarWingWidth, alignment: .leading)
            Spacer()
                .frame(width: notch.size.width)
            TimelineView(.everyMinute) { context in
                Text(EventTiming.shortLabel(for: event, now: context.date))
                    .monospacedDigit()
            }
            .frame(width: IslandMetrics.calendarWingWidth)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.white)
        .frame(height: notch.size.height)
    }
}

/// Alerte de réunion imminente : titre, horaire et bouton « Rejoindre » si un lien de visio est détecté.
struct CalendarAlertView: View {
    let event: CalendarEvent
    let notch: NotchGeometry
    let join: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Image(systemName: "calendar")
                    .foregroundStyle(event.color.color)
                    .frame(width: IslandMetrics.calendarWingWidth)
                Spacer()
                    .frame(width: notch.size.width)
                TimelineView(.everyMinute) { context in
                    Text(EventTiming.shortLabel(for: event, now: context.date))
                        .monospacedDigit()
                }
                .frame(width: IslandMetrics.calendarWingWidth)
            }
            .font(.system(size: 12, weight: .semibold))
            .frame(height: notch.size.height)

            HStack(spacing: 12) {
                Capsule()
                    .fill(event.color.color)
                    .frame(width: 4, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    Text(EventRow.detail(of: event, includingRange: true))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if event.meetingLink != nil {
                    JoinButton(action: join)
                }
            }
            .padding(.horizontal, 20)
            .frame(maxHeight: .infinity)
        }
        .foregroundStyle(.white)
    }
}

/// Onglet Calendrier : événements d'aujourd'hui ou de demain, avec l'heure courante.
struct CalendarTabView: View {
    let calendar: CalendarService
    let notchHeight: CGFloat

    @State private var showsTomorrow = false

    var body: some View {
        switch calendar.access {
        case .notDetermined:
            AccessPrompt(
                symbol: "calendar.badge.plus",
                title: "Afficher votre agenda",
                message: "LetsWork lit les calendriers des comptes ajoutés à macOS (iCloud, Google, Exchange…).",
                buttonTitle: "Autoriser l'accès"
            ) {
                Task { await calendar.requestAccess() }
            }
            .padding(.top, notchHeight)
        case .denied:
            AccessPrompt(
                symbol: "calendar.badge.exclamationmark",
                title: "Accès au calendrier refusé",
                message: "Autorisez LetsWork dans Réglages Système › Confidentialité et sécurité › Calendriers.",
                buttonTitle: "Ouvrir Réglages Système",
                action: calendar.openSystemSettings
            )
            .padding(.top, notchHeight)
        case .granted:
            TimelineView(.everyMinute) { context in
                eventList(now: context.date)
            }
            .overlay(alignment: .topTrailing) {
                dayPicker
                    .frame(height: notchHeight)
                    .padding(.trailing, 22)
            }
        }
    }

    private var dayPicker: some View {
        HStack(spacing: 4) {
            dayButton("Aujourd'hui", isSelected: !showsTomorrow) { showsTomorrow = false }
            dayButton("Demain", isSelected: showsTomorrow) { showsTomorrow = true }
            Button {
                let day = showsTomorrow ? Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now : .now
                calendar.requestNewEvent(on: day)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 22)
                    .background(Capsule().fill(.white.opacity(0.16)))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(calendar.writableCalendars.isEmpty)
            .help("Nouvel événement")
            .accessibilityLabel("Nouvel événement")
        }
    }

    private func dayButton(_ title: LocalizedStringKey, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isSelected ? .white : .secondary)
                .padding(.horizontal, 10)
                .frame(height: 22)
                .background(Capsule().fill(.white.opacity(isSelected ? 0.16 : 0)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func eventList(now: Date) -> some View {
        let day = showsTomorrow ? Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now : now
        let dayEvents = CalendarSchedule.events(on: day, in: calendar.events)
        // La ligne « Maintenant » se place avant le premier événement à venir.
        let nowIndex = showsTomorrow ? nil : (dayEvents.firstIndex { !$0.isAllDay && $0.start > now } ?? dayEvents.endIndex)
        return Group {
            if dayEvents.isEmpty {
                Text(showsTomorrow ? "Aucun événement demain" : "Aucun événement aujourd'hui")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(dayEvents.enumerated()), id: \.element.id) { index, event in
                            if index == nowIndex {
                                NowIndicator(now: now)
                            }
                            EventRow(event: event, now: now) {
                                calendar.join(event)
                            }
                        }
                        if nowIndex == dayEvents.endIndex {
                            NowIndicator(now: now)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
                }
                .scrollIndicators(.never)
            }
        }
        .padding(.top, notchHeight + 6)
    }
}

/// Une ligne de l'agenda ; les événements passés sont estompés.
struct EventRow: View {
    let event: CalendarEvent
    let now: Date
    let join: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .trailing, spacing: 0) {
                if event.isAllDay {
                    Text("Journée")
                        .font(.system(size: 11, weight: .semibold))
                } else {
                    Text(EventTiming.time(of: event.start))
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    Text(EventTiming.time(of: event.end))
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 46, alignment: .trailing)
            Capsule()
                .fill(event.color.color)
                .frame(width: 3, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.system(size: 13, weight: .semibold))
                let detail = Self.detail(of: event, includingRange: false)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            Spacer(minLength: 0)
            if event.meetingLink != nil, !event.hasEnded(at: now) {
                JoinButton(action: join)
            }
        }
        .foregroundStyle(.white)
        .frame(height: 36)
        .opacity(event.hasEnded(at: now) ? 0.45 : 1)
    }

    /// « 14:00 – 15:00 · Teams · Salle B », selon ce qui est connu.
    static func detail(of event: CalendarEvent, includingRange: Bool) -> String {
        var parts: [String] = []
        if includingRange {
            parts.append(EventTiming.range(of: event))
        }
        if let service = event.meetingLink?.service {
            parts.append(service.name)
        }
        if let location = event.location, event.meetingLink.map({ !location.contains($0.url.absoluteString) }) ?? true {
            parts.append(location)
        }
        return parts.joined(separator: " · ")
    }
}

private struct NowIndicator: View {
    let now: Date

    var body: some View {
        HStack(spacing: 6) {
            Text(EventTiming.time(of: now))
                .font(.system(size: 10, weight: .bold).monospacedDigit())
                .foregroundStyle(.red)
                .frame(width: 46, alignment: .trailing)
            Circle()
                .fill(.red)
                .frame(width: 6, height: 6)
            Rectangle()
                .fill(.red)
                .frame(height: 1)
        }
        .frame(height: 12)
        .accessibilityLabel("Maintenant")
    }
}

private struct JoinButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Rejoindre", systemImage: "video.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(Capsule().fill(.green.opacity(0.85)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct AccessPrompt: View {
    let symbol: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let buttonTitle: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title3.weight(.semibold))
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(buttonTitle, action: action)
                .controlSize(.small)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
