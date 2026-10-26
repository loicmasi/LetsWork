import ServiceManagement
import SwiftUI

struct SettingsView: View {
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
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
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
