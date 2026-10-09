import AppKit
import CoreBluetooth
import os
import ServiceManagement

let log = Logger(subsystem: "io.github.timofeykhodykin.BluetoothSwitcher", category: "main")

final class Controller: NSObject, ObservableObject {
    static let shared = Controller()
    static let delayOptions = [0, 1, 2, 5, 10, 15, 30, 60, 120]

    @Published var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Keys.enabled)
            updateLoginItem()
            evaluate("enabled changed")
        }
    }

    @Published var delayMinutes: Int {
        didSet {
            defaults.set(delayMinutes, forKey: Keys.delay)
            evaluate("delay changed")
        }
    }

    @Published var showMenuBarIcon: Bool {
        didSet { defaults.set(showMenuBarIcon, forKey: Keys.menuBarIcon) }
    }

    @Published private(set) var bluetoothAccessDenied = false

    private enum Keys {
        static let enabled = "enabled"
        static let delay = "delayMinutes"
        static let turnedOff = "turnedOffByApp"
        static let menuBarIcon = "showMenuBarIcon"
    }

    private let defaults = UserDefaults.standard
    private var monitor: PowerMonitor?
    private var countdown: DispatchSourceTimer?
    private var pollTimer: Timer?
    private var activity: NSObjectProtocol?
    private var bluetoothManager: CBCentralManager?

    /// When the current "lid closed, no external display" period started.
    private var closedSince: Date?
    /// The current lid-closed period has already been dealt with (Bluetooth turned off or was already off).
    private var closeHandled = false

    /// Bluetooth was on and we turned it off. Persisted so a restart doesn't lose it.
    private var turnedOffByApp: Bool {
        get { defaults.bool(forKey: Keys.turnedOff) }
        set { defaults.set(newValue, forKey: Keys.turnedOff) }
    }

    private override init() {
        defaults.register(defaults: [Keys.enabled: true, Keys.delay: 5, Keys.menuBarIcon: true])
        isEnabled = defaults.bool(forKey: Keys.enabled)
        delayMinutes = defaults.integer(forKey: Keys.delay)
        showMenuBarIcon = defaults.bool(forKey: Keys.menuBarIcon)
        super.init()

        // A menu bar app with no windows is a prime App Nap candidate; that would delay our timers.
        activity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "Watching the lid state")

        monitor = PowerMonitor { [weak self] event in
            self?.evaluate("\(event)")
        }
        monitor?.start()

        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.evaluate(name.rawValue)
            }
        }

        // Safety net in case a notification gets lost.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.evaluate(nil)
        }

        requestBluetoothAccessIfNeeded()
        updateLoginItem()
        evaluate("launch")
    }

    // MARK: - Core logic

    private func evaluate(_ reason: String?) {
        if let reason {
            log.info("evaluate: \(reason, privacy: .public)")
        }

        guard isEnabled, PowerMonitor.isLidClosed else {
            resetClosedPeriod()
            restoreBluetoothIfNeeded()
            return
        }

        if turnedOffByApp || closeHandled { return }

        if PowerMonitor.hasExternalDisplay {
            // Clamshell mode with an external monitor: Bluetooth keyboard/mouse are likely in use.
            if closedSince != nil { log.notice("External display connected, countdown cancelled") }
            resetClosedPeriod()
            return
        }

        let now = Date()
        if closedSince == nil {
            closedSince = now
            log.notice("Lid closed, Bluetooth turns off in \(self.delayMinutes) min")
        }

        let deadline = closedSince!.addingTimeInterval(TimeInterval(delayMinutes * 60))
        let remaining = deadline.timeIntervalSince(now)
        if remaining <= 0 {
            cancelCountdown()
            turnBluetoothOff()
        } else {
            scheduleCountdown(remaining)
        }
    }

    private func turnBluetoothOff() {
        closeHandled = true
        guard Bluetooth.isOn else {
            log.notice("Bluetooth already off, nothing to do")
            return
        }
        turnedOffByApp = true
        Bluetooth.setPower(false)
    }

    private func restoreBluetoothIfNeeded() {
        guard turnedOffByApp else { return }
        turnedOffByApp = false
        log.notice("Lid open, restoring Bluetooth")
        Bluetooth.setPower(true)
    }

    private func resetClosedPeriod() {
        closedSince = nil
        closeHandled = false
        cancelCountdown()
    }

    /// Uses wall-clock time, so the deadline keeps running while the Mac sleeps and the timer
    /// fires on the first (dark) wake after it has passed.
    private func scheduleCountdown(_ seconds: TimeInterval) {
        cancelCountdown()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(wallDeadline: .now() + seconds, leeway: .seconds(1))
        timer.setEventHandler { [weak self] in self?.evaluate("countdown") }
        timer.resume()
        countdown = timer
    }

    private func cancelCountdown() {
        countdown?.cancel()
        countdown = nil
    }

    // MARK: - System integration

    private func updateLoginItem() {
        let service = SMAppService.mainApp
        do {
            if isEnabled, service.status != .enabled {
                try service.register()
            } else if !isEnabled, service.status == .enabled {
                try service.unregister()
            }
        } catch {
            log.error("Login item update failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func requestBluetoothAccessIfNeeded() {
        updateBluetoothAccess()
        if CBCentralManager.authorization == .notDetermined {
            // Creating a manager triggers the system permission prompt.
            bluetoothManager = CBCentralManager(delegate: self, queue: .main)
        }
    }

    private func updateBluetoothAccess() {
        let status = CBCentralManager.authorization
        bluetoothAccessDenied = status == .denied || status == .restricted
    }
}

extension Controller: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        updateBluetoothAccess()
    }
}
