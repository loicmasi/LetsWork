import SwiftUI

/// État étendu : la page de l'onglet choisi, et la barre d'onglets dans l'espace à gauche de l'encoche.
struct ExpandedIslandView: View {
    let model: IslandModel
    let media: MediaService
    let calendar: CalendarService
    let notchHeight: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            Group {
                switch model.selectedTab {
                case .home:
                    HomeView(
                        media: media,
                        calendar: calendar,
                        notchHeight: notchHeight,
                        openMedia: { model.selectTab(.media) },
                        openCalendar: { model.selectTab(.calendar) }
                    )
                case .media:
                    MediaExpandedView(media: media, notchHeight: notchHeight)
                case .calendar:
                    CalendarTabView(calendar: calendar, notchHeight: notchHeight)
                case .game:
                    GamesView(model: model, notchHeight: notchHeight)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .id(model.selectedTab)
            .transition(.opacity)

            IslandTabBar(selection: model.selectedTab, select: model.selectTab)
                .frame(height: notchHeight)
                .padding(.leading, 22)
        }
        .animation(.easeInOut(duration: 0.2), value: model.selectedTab)
    }
}

/// Icônes des onglets ; une pastille glisse sous l'onglet sélectionné.
private struct IslandTabBar: View {
    let selection: IslandTab
    let select: (IslandTab) -> Void

    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(IslandTab.allCases) { tab in
                let isSelected = tab == selection
                Button {
                    select(tab)
                } label: {
                    Image(systemName: tab.symbolName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : .secondary)
                        .frame(width: 32, height: 22)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(.white.opacity(0.16))
                                    .matchedGeometryEffect(id: "selection", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(tab.title)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

/// Page d'accueil : date, heure, puis la lecture en cours et le prochain événement, qui mènent à leur onglet.
struct HomeView: View {
    let media: MediaService
    let calendar: CalendarService
    let notchHeight: CGFloat
    let openMedia: () -> Void
    let openCalendar: () -> Void

    var body: some View {
        TimelineView(.everyMinute) { context in
            HStack(alignment: .top, spacing: 16) {
                summary(now: context.date)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: openCalendar) {
                    MonthCalendarView(date: context.date)
                }
                .buttonStyle(.plain)
                .help("Ouvrir l'onglet Calendrier")
            }
            .padding(.horizontal, 24)
            .padding(.top, notchHeight + 8)
        }
    }

    /// Colonne de gauche : date, heure, lecture en cours et prochain événement.
    private func summary(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(now, format: .dateTime.weekday(.wide).day().month(.wide))
                .font(.headline)
                .foregroundStyle(.white)
            Text(now, format: .dateTime.hour().minute())
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            if let nowPlaying = media.nowPlaying {
                Button(action: openMedia) {
                    HStack(spacing: 6) {
                        Image(systemName: nowPlaying.isPlaying ? "waveform" : "pause.fill")
                            .foregroundStyle(media.accent)
                        Text(Self.mediaSummary(of: nowPlaying))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Ouvrir l'onglet Multimédia")
            }
            if let event = CalendarSchedule.next(in: calendar.events, at: now) {
                Button(action: openCalendar) {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .foregroundStyle(event.color.color)
                        Text(Self.eventSummary(of: event, now: now))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Ouvrir l'onglet Calendrier")
            }
            if media.nowPlaying == nil, CalendarSchedule.next(in: calendar.events, at: now) == nil {
                Text("Aucune activité pour le moment")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// « En cours : Titre », ou « Prochain : Titre · dans 12 min ».
    static func eventSummary(of event: CalendarEvent, now: Date) -> String {
        if event.isOngoing(at: now) {
            return String(localized: "En cours : \(event.title)")
        }
        return String(localized: "Prochain : \(event.title) · \(EventTiming.shortLabel(for: event, now: now))")
    }

    /// « En lecture : Titre — Artiste », ou « En pause : … ».
    static func mediaSummary(of nowPlaying: NowPlaying) -> String {
        let track = [nowPlaying.title, nowPlaying.artist].compactMap { $0 }.joined(separator: " — ")
        let status = nowPlaying.isPlaying ? String(localized: "En lecture") : String(localized: "En pause")
        return "\(status) : \(track)"
    }
}
