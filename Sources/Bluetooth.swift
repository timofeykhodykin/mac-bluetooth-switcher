import Foundation

enum Bluetooth {
    static var isOn: Bool {
        IOBluetoothPreferenceGetControllerPowerState() != 0
    }

    /// Sets the controller power state and re-checks it a few times, because right after
    /// wake the controller sometimes ignores the first request.
    static func setPower(_ on: Bool, attempt: Int = 1) {
        IOBluetoothPreferenceSetControllerPowerState(on ? 1 : 0)
        log.notice("Bluetooth -> \(on ? "on" : "off", privacy: .public) (attempt \(attempt))")

        guard attempt < 5 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if isOn != on {
                setPower(on, attempt: attempt + 1)
            }
        }
    }
}
