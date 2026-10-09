// Private IOBluetooth API (the same one blueutil uses) for toggling the Bluetooth controller power.
// 1 = on, 0 = off.
int IOBluetoothPreferenceGetControllerPowerState(void);
void IOBluetoothPreferenceSetControllerPowerState(int state);
