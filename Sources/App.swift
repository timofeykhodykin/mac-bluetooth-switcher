import SwiftUI

private let isRussian = Locale.preferredLanguages.first?.hasPrefix("ru") ?? false

private func L(_ en: String, _ ru: String) -> String {
    isRussian ? ru : en
}

@main
struct BluetoothSwitcherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var controller = Controller.shared

    var body: some Scene {
        MenuBarExtra(isInserted: menuBarIconBinding) {
            ContentView(controller: controller)
        } label: {
            Image(systemName: controller.isEnabled ? "laptopcomputer" : "laptopcomputer.slash")
        }
        .menuBarExtraStyle(.window)
    }

    /// MenuBarExtra writes the status item's visibility back into the binding on every scene
    /// update. Passing identical values through would republish the controller, update the
    /// scene again and spin forever, so only real changes are forwarded.
    private var menuBarIconBinding: Binding<Bool> {
        Binding(
            get: { controller.showMenuBarIcon },
            set: { newValue in
                if newValue != controller.showMenuBarIcon {
                    controller.showMenuBarIcon = newValue
                }
            })
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow?
    private static var quitRequested = false

    /// Really quits the app (the Quit button). Cmd+Q only closes the window.
    static func quit() {
        quitRequested = true
        NSApp.terminate(nil)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Opened by the user → show the window; started at login → stay in the background.
        if !wasLaunchedAtLogin {
            showWindow()
        }
    }

    /// Opening the app again (Finder, Launchpad, Spotlight) brings the window back,
    /// which is the only way to reach it when the menu bar icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Quit button, or a quit Apple Event (Dock menu, logout, restart, shutdown).
        if Self.quitRequested || NSAppleEventManager.shared().currentAppleEvent != nil {
            return .terminateNow
        }
        // Cmd+Q: keep running in the background, just close the window.
        window?.close()
        return .terminateCancel
    }

    func showWindow() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: ContentView(controller: .shared)))
            window.title = "Bluetooth Switcher"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        // Show in the Dock and app switcher while the window is open.
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    private var wasLaunchedAtLogin: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        return event.eventID == kAEOpenApplication
            && event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }
}

struct ContentView: View {
    @ObservedObject var controller: Controller

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Bluetooth Switcher")
                .font(.headline)

            Text(L(
                "Turns Bluetooth off when the lid has been closed for the chosen time and back on when the lid is opened, if it was on before. Wakes with the lid closed (Power Nap) don't turn it on. Does nothing while an external display is connected.",
                "Выключает Bluetooth, если крышка закрыта дольше заданного времени, и включает обратно при открытии крышки, если он был включён. Пробуждения с закрытой крышкой (Power Nap) его не включают. Пока подключён внешний монитор, ничего не делает."
            ))
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            if controller.bluetoothAccessDenied {
                Text(L(
                    "No Bluetooth access. Allow it in System Settings → Privacy & Security → Bluetooth.",
                    "Нет доступа к Bluetooth. Разрешите его в Системных настройках → Конфиденциальность и безопасность → Bluetooth."
                ))
                .font(.callout)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            Toggle(L("Enabled", "Включено"), isOn: $controller.isEnabled)
                .toggleStyle(.switch)

            Picker(L("Turn off after", "Выключать через"), selection: $controller.delayMinutes) {
                ForEach(Controller.delayOptions, id: \.self) { minutes in
                    Text(delayLabel(minutes)).tag(minutes)
                }
            }
            .disabled(!controller.isEnabled)

            VStack(alignment: .leading, spacing: 4) {
                Toggle(L("Show in menu bar", "Значок в строке меню"), isOn: $controller.showMenuBarIcon)
                    .toggleStyle(.switch)
                if !controller.showMenuBarIcon {
                    Text(L(
                        "To open this window, launch the app again.",
                        "Чтобы открыть это окно, запустите приложение ещё раз."
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider()

            HStack {
                Spacer()
                Button(L("Quit", "Выйти")) {
                    AppDelegate.quit()
                }
            }
        }
        .padding()
        .frame(width: 320)
    }

    private func delayLabel(_ minutes: Int) -> String {
        switch minutes {
        case 0: return L("Immediately", "Сразу")
        case let m where m % 60 == 0: return L("\(m / 60) h", "\(m / 60) ч")
        default: return L("\(minutes) min", "\(minutes) мин")
        }
    }
}
