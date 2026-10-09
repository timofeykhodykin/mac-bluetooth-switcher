import CoreGraphics
import Foundation
import IOKit
import IOKit.pwr_mgt

// IOKit message constants are C macros that Swift does not import.
private let kMsgCanSystemSleep: UInt32 = 0xE000_0270
private let kMsgSystemWillSleep: UInt32 = 0xE000_0280
private let kMsgSystemHasPoweredOn: UInt32 = 0xE000_0300
private let kMsgClamshellStateChange: UInt32 = 0xE003_4100

/// Watches lid state, sleep/wake (including dark wakes such as Power Nap) and display changes.
final class PowerMonitor {
    enum Event {
        case lidChanged
        case willSleep
        case poweredOn
        case displaysChanged
    }

    private let onEvent: (Event) -> Void
    private var rootPort: io_connect_t = 0
    private var notifyPort: IONotificationPortRef?
    private var sleepNotifier: io_object_t = 0
    private var lidNotifier: io_object_t = 0

    init(onEvent: @escaping (Event) -> Void) {
        self.onEvent = onEvent
    }

    func start() {
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        // Sleep / wake notifications. Unlike NSWorkspace, these also fire on dark wakes.
        rootPort = IORegisterForSystemPower(refcon, &notifyPort, { refcon, _, type, arg in
            guard let refcon else { return }
            Unmanaged<PowerMonitor>.fromOpaque(refcon).takeUnretainedValue().handlePower(type, arg)
        }, &sleepNotifier)

        guard rootPort != 0, let notifyPort else {
            log.error("IORegisterForSystemPower failed")
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(notifyPort).takeUnretainedValue(), .commonModes)

        // Lid open / close notifications from the power management root domain.
        let rootDomain = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        defer { IOObjectRelease(rootDomain) }
        let result = IOServiceAddInterestNotification(notifyPort, rootDomain, "IOGeneralInterest", { refcon, _, type, _ in
            guard let refcon, type == kMsgClamshellStateChange else { return }
            Unmanaged<PowerMonitor>.fromOpaque(refcon).takeUnretainedValue().onEvent(.lidChanged)
        }, refcon, &lidNotifier)
        if result != KERN_SUCCESS {
            log.error("Lid notification registration failed: \(result)")
        }

        CGDisplayRegisterReconfigurationCallback({ _, flags, refcon in
            guard let refcon, !flags.contains(.beginConfigurationFlag) else { return }
            Unmanaged<PowerMonitor>.fromOpaque(refcon).takeUnretainedValue().onEvent(.displaysChanged)
        }, refcon)
    }

    private func handlePower(_ type: UInt32, _ arg: UnsafeMutableRawPointer?) {
        switch type {
        case kMsgCanSystemSleep:
            IOAllowPowerChange(rootPort, Int(bitPattern: arg))
        case kMsgSystemWillSleep:
            // Handle synchronously so Bluetooth is off before the machine goes to sleep.
            onEvent(.willSleep)
            IOAllowPowerChange(rootPort, Int(bitPattern: arg))
        case kMsgSystemHasPoweredOn:
            onEvent(.poweredOn)
        default:
            break
        }
    }

    static var isLidClosed: Bool {
        let rootDomain = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        defer { IOObjectRelease(rootDomain) }
        let value = IORegistryEntryCreateCFProperty(rootDomain, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)
        return (value?.takeRetainedValue() as? Bool) ?? false
    }

    /// True when an external display is connected, i.e. the Mac is probably used in clamshell
    /// mode with an external keyboard/mouse that may well be Bluetooth.
    static var hasExternalDisplay: Bool {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return false }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else { return false }
        return displays.prefix(Int(count)).contains { CGDisplayIsBuiltin($0) == 0 }
    }
}
