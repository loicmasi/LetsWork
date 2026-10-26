import AppKit
import SwiftUI

/// Fenêtre « Nouvel événement ». La saisie se fait hors de l'Island : son panneau ne prend pas
/// le clavier et se referme quand la souris s'éloigne.
@MainActor
final class EventEditorWindowController {
    private let calendar: CalendarService
    private var window: NSWindow?

    init(calendar: CalendarService) {
        self.calendar = calendar
    }

    func show(day: Date) {
        window?.close()
        let editor = EventEditorView(calendar: calendar, day: day) { [weak self] in
            self?.window?.close()
        }
        let window = NSWindow(contentViewController: NSHostingController(rootView: editor))
        window.title = String(localized: "Nouvel événement")
        window.styleMask = [.titled, .closable]
        window.level = .floating
        window.isReleasedWhenClosed = false
        placeBelowIsland(window)
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// Centrée sous l'Island, sur l'écran à encoche s'il y en a un.
    private func placeBelowIsland(_ window: NSWindow) {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main else {
            window.center()
            return
        }
        let width = window.frame.width
        window.setFrameTopLeftPoint(NSPoint(x: screen.frame.midX - width / 2, y: screen.visibleFrame.maxY - 12))
    }
}

struct EventEditorView: View {
    let calendar: CalendarService
    let close: () -> Void

    @State private var draft: EventDraft
    @State private var errorMessage: String?
    @State private var isSaving = false
    @FocusState private var isTitleFocused: Bool

    init(calendar: CalendarService, day: Date, close: @escaping () -> Void) {
        self.calendar = calendar
        self.close = close
        _draft = State(initialValue: EventDraft(day: day, now: .now, calendarID: calendar.defaultCalendarIDForNewEvents))
    }

    var body: some View {
        VStack(spacing: 0) {
            if calendar.access == .granted {
                form
            } else {
                accessPrompt
            }
            Divider()
            HStack {
                if let message = errorMessage ?? draft.validationMessage {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(errorMessage == nil ? Color.secondary : Color.red)
                }
                Spacer()
                Button("Annuler", action: close)
                    .keyboardShortcut(.cancelAction)
                Button("Ajouter", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(calendar.access != .granted || draft.validationMessage != nil || isSaving)
            }
            .padding(16)
        }
        .frame(width: 440)
        .onChange(of: calendar.writableCalendars.map(\.id), initial: true) { _, ids in
            // Les calendriers arrivent après le chargement : on choisit le calendrier par défaut dès qu'ils sont là.
            if draft.calendarID.map(ids.contains) != true {
                draft.calendarID = calendar.defaultCalendarIDForNewEvents
            }
        }
    }

    private var form: some View {
        Form {
            TextField("Titre", text: $draft.title)
                .focused($isTitleFocused)
            if accountGroups.isEmpty {
                Text("Aucun calendrier modifiable : ajoutez un compte dans Réglages Système › Comptes internet.")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Calendrier", selection: $draft.calendarID) {
                    ForEach(accountGroups) { group in
                        Section(group.account) {
                            ForEach(group.calendars) { info in
                                Text(info.title).tag(Optional(info.id))
                            }
                        }
                    }
                }
            }
            Toggle("Toute la journée", isOn: $draft.isAllDay)
            DatePicker("Début", selection: startBinding, displayedComponents: dateComponents)
            DatePicker("Fin", selection: $draft.end, in: draft.start..., displayedComponents: dateComponents)
            TextField("Lieu", text: $draft.location)
            TextField("Lien de visio (Teams, Meet, Zoom…)", text: $draft.urlText)
            TextField("Notes", text: $draft.notes, axis: .vertical)
                .lineLimit(2...5)
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { isTitleFocused = true }
    }

    private var accessPrompt: some View {
        VStack(spacing: 10) {
            Text("LetsWork a besoin de l'accès aux calendriers pour ajouter un événement.")
                .multilineTextAlignment(.center)
            Button("Autoriser l'accès") {
                Task { await calendar.requestAccess() }
            }
        }
        .padding(24)
    }

    /// Le début déplace la fin pour garder la durée.
    private var startBinding: Binding<Date> {
        Binding {
            draft.start
        } set: { newStart in
            draft.moveStart(to: newStart)
        }
    }

    private var dateComponents: DatePickerComponents {
        draft.isAllDay ? [.date] : [.date, .hourAndMinute]
    }

    /// Calendriers modifiables regroupés par compte (iCloud, Google, Exchange…).
    private var accountGroups: [AccountGroup] {
        Dictionary(grouping: calendar.writableCalendars, by: \.sourceTitle)
            .map { AccountGroup(account: $0.key, calendars: $0.value) }
            .sorted { $0.account < $1.account }
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await calendar.createEvent(draft)
                close()
            } catch {
                errorMessage = error.localizedDescription
                isSaving = false
            }
        }
    }
}

private struct AccountGroup: Identifiable {
    var account: String
    var calendars: [CalendarInfo]

    var id: String { account }
}
