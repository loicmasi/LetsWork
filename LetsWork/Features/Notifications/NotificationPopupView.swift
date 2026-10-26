import AppKit
import SwiftUI

/// Pop-up de notification, au style de l'aperçu de piste : icône de l'app dans l'aile gauche,
/// nom de l'app à droite, puis titre et texte centrés sous l'encoche.
struct NotificationPopupView: View {
    let notification: SystemNotification
    let notch: NotchGeometry

    var body: some View {
        let app = NotificationApp(bundleIdentifier: notification.bundleIdentifier)
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Group {
                    if let icon = app.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 22, height: 22)
                    } else {
                        Image(systemName: "bell.fill")
                    }
                }
                .frame(width: IslandMetrics.compactWingWidth)
                Spacer()
                    .frame(width: notch.size.width)
                Text(app.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .frame(width: IslandMetrics.compactWingWidth)
            }
            .frame(height: notch.size.height)

            VStack(spacing: 2) {
                Text(notification.headline(appName: app.name))
                    .font(.system(size: 12, weight: .semibold))
                if let detail = notification.detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 22)
            .frame(maxHeight: .infinity)
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .combine)
    }
}

/// Nom et icône de l'app qui a émis la notification.
struct NotificationApp {
    let name: String
    let icon: NSImage?

    @MainActor
    init(bundleIdentifier: String) {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            name = (FileManager.default.displayName(atPath: url.path) as NSString).deletingPathExtension
            icon = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            name = bundleIdentifier.split(separator: ".").last.map(String.init) ?? bundleIdentifier
            icon = nil
        }
    }

    /// Ouvre l'app qui a émis la notification (macOS ne permet pas d'ouvrir la notification elle-même).
    @MainActor
    static func open(bundleIdentifier: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}
