import ServiceManagement
import SwiftUI

struct SettingsView: View {
    let media: MediaService
    @Bindable var hud: HUDService
    @Bindable var calendar: CalendarService

    @AppStorage(AppSettings.displayTargetKey) private var displayTarget: DisplayTarget = .notchScreen
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchAtLoginStatus = LaunchAtLogin.status
    @State private var launchAtLoginError: String?

    var body: some View {
        Form {
            Section("Général") {
                Toggle("Ouvrir LetsWork à l'ouverture de session", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        updateLaunchAtLogin(enabled)
                    }
                if launchAtLoginStatus == .requiresApproval {
                    HStack {
                        Text("À autoriser dans Réglages Système › Général › Ouverture.")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Ouvrir") { SMAppService.openSystemSettingsLoginItems() }
                    }
                }
                if let launchAtLoginError {
                    Text(launchAtLoginError)
                        .foregroundStyle(.red)
                }
            }
            Section("Island") {
                Picker("Afficher sur", selection: $displayTarget) {
                    ForEach(DisplayTarget.allCases) { target in
                        Text(target.title).tag(target)
                    }
                }
            }
            Section("Médias") {
                LabeledContent("Source") {
                    Text(media.status.title)
                }
                if let detail = media.status.detail {
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Volume et luminosité") {
                Toggle("Remplacer les indicateurs de macOS", isOn: $hud.isEnabled)
                LabeledContent("Autorisation Accessibilité") {
                    if hud.isAccessibilityGranted {
                        Label("Accordée", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Autoriser…", action: hud.requestAccessibility)
                    }
                }
                LabeledContent("Interception des touches") {
                    Text(hud.isIntercepting ? "Active" : "Inactive")
                        .foregroundStyle(hud.isIntercepting ? .primary : .secondary)
                }
                if !hud.isAccessibilityGranted {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Sans cette autorisation, LetsWork ne peut pas intercepter les touches : les indicateurs de macOS restent affichés.")
                        Text("LetsWork est déjà coché dans Réglages Système ? Une version recompilée n'est plus reconnue : retirez LetsWork de la liste avec « − », puis cliquez sur « Autoriser… ».")
                        Button("Ouvrir Réglages Système › Accessibilité") { AccessibilityPermission.openSystemSettings() }
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            }
            Section("Calendrier") {
                LabeledContent("Accès aux calendriers") {
                    switch calendar.access {
                    case .granted:
                        Label("Accordé", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .notDetermined:
                        Button("Autoriser…") {
                            Task { await calendar.requestAccess() }
                        }
                    case .denied:
                        Button("Réglages Système", action: calendar.openSystemSettings)
                    }
                }
                if calendar.access == .granted {
                    Toggle("Masquer les événements sur la journée entière", isOn: $calendar.hidesAllDayEvents)
                    Picker("Alerte avant une réunion", selection: $calendar.alertLeadMinutes) {
                        ForEach(CalendarService.alertLeadChoices, id: \.self) { minutes in
                            Text("\(minutes) min").tag(minutes)
                        }
                    }
                }
            }
            if calendar.access == .granted, !calendar.calendars.isEmpty {
                Section("Calendriers affichés") {
                    ForEach(calendar.calendars) { info in
                        Toggle(isOn: visibilityBinding(for: info.id)) {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(info.color.color)
                                    .frame(width: 9, height: 9)
                                Text(info.title)
                                Text(info.sourceTitle)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func visibilityBinding(for calendarID: String) -> Binding<Bool> {
        Binding {
            !calendar.hiddenCalendarIDs.contains(calendarID)
        } set: { isVisible in
            if isVisible {
                calendar.hiddenCalendarIDs.remove(calendarID)
            } else {
                calendar.hiddenCalendarIDs.insert(calendarID)
            }
        }
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        // Le retour à l'état réel après une erreur redéclenche onChange : rien à faire dans ce cas.
        guard enabled != LaunchAtLogin.isEnabled else { return }
        do {
            try LaunchAtLogin.setEnabled(enabled)
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
            launchAtLogin = LaunchAtLogin.isEnabled
        }
        launchAtLoginStatus = LaunchAtLogin.status
    }
}

private extension MediaService.Status {
    var title: LocalizedStringKey {
        switch self {
        case .stopped: "Arrêtée"
        case .adapter: "Now Playing de macOS"
        case .appleScriptFallback: "Repli AppleScript (Musique, Spotify)"
        }
    }

    var detail: LocalizedStringKey? {
        switch self {
        case .stopped, .adapter:
            nil
        case .appleScriptFallback(adapterMissing: true):
            "L'adaptateur média n'est pas embarqué : lancer « make adapter » puis recompiler. Les vidéos des navigateurs ne sont pas détectées."
        case .appleScriptFallback(adapterMissing: false):
            "L'adaptateur média a échoué à plusieurs reprises, probablement après une mise à jour de macOS. Les vidéos des navigateurs ne sont pas détectées."
        }
    }
}
