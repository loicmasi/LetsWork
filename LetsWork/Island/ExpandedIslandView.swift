import SwiftUI

/// État étendu : la page de l'onglet choisi, et la barre d'onglets dans l'espace à gauche de l'encoche.
struct ExpandedIslandView: View {
    let model: IslandModel
    let media: MediaService
    let notchHeight: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            Group {
                switch model.selectedTab {
                case .home:
                    HomeView(media: media, notchHeight: notchHeight) {
                        model.selectTab(.media)
                    }
                case .media:
                    MediaExpandedView(media: media, notchHeight: notchHeight)
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

/// Page d'accueil : date, heure, et la lecture en cours qui mène à l'onglet Multimédia.
struct HomeView: View {
    let media: MediaService
    let notchHeight: CGFloat
    let openMedia: () -> Void

    var body: some View {
        TimelineView(.everyMinute) { context in
            VStack(alignment: .leading, spacing: 6) {
                Text(context.date, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(context.date, format: .dateTime.hour().minute())
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
                } else {
                    Text("Aucune activité pour le moment")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, notchHeight + 8)
        }
    }

    /// « En lecture : Titre — Artiste », ou « En pause : … ».
    static func mediaSummary(of nowPlaying: NowPlaying) -> String {
        let track = [nowPlaying.title, nowPlaying.artist].compactMap { $0 }.joined(separator: " — ")
        let status = nowPlaying.isPlaying ? String(localized: "En lecture") : String(localized: "En pause")
        return "\(status) : \(track)"
    }
}
