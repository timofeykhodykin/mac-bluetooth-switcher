# Bluetooth Switcher

A tiny macOS app that turns Bluetooth off when the MacBook lid has been closed for a set time, and turns it back on when the lid is opened.

## How it works

- **Lid closed** → after the chosen delay (immediately, 1 min … 2 h) Bluetooth is turned off.
- **Lid opened** → Bluetooth is turned back on, but only if it was on before and this app turned it off.
- **Wakes with the lid closed** (Power Nap, maintenance wakes) don't turn Bluetooth back on.
- **External display connected** (clamshell mode) → nothing happens, so a Bluetooth keyboard or mouse keeps working.

A sleeping Mac can't run timers, so the delay is counted in wall-clock time: if it runs out while the Mac is asleep, Bluetooth is turned off on the next wake (Bluetooth devices can only connect during those wakes anyway).

The app starts at login in the background while it's enabled. Its window has an on/off switch, the delay setting and an option to show a menu bar icon. With the icon hidden, launch the app again to open the window. Cmd+Q only closes the window and the app keeps running; use the Quit button to really quit.

## Install

Requires macOS 13 or later.

Download `Bluetooth-Switcher.zip` from [Releases](https://github.com/timofeykhodykin/mac-bluetooth-switcher/releases), unzip it and move the app to `/Applications`. Or build it yourself:

```sh
xcode-select --install   # if the Command Line Tools aren't installed yet
./build.sh install       # builds a universal app, copies it to /Applications and launches it
```

Allow Bluetooth access when macOS asks.

The app is ad-hoc signed. A downloaded build isn't notarized, so macOS blocks the first launch. After the first attempt, click **Open Anyway** in System Settings → Privacy & Security, or run `xattr -dr com.apple.quarantine "/Applications/Bluetooth Switcher.app"`.

## Logs

```sh
log stream --info --predicate 'subsystem == "io.github.timofeykhodykin.BluetoothSwitcher"'
```

## Notes

Bluetooth power is switched through the private `IOBluetoothPreferenceSetControllerPowerState` API (the one [blueutil](https://github.com/toy/blueutil) uses). There's no public API for this.

---

**По-русски:** приложение выключает Bluetooth, если крышка MacBook закрыта дольше заданного времени, и включает обратно при открытии крышки, если он был включён. Пробуждения с закрытой крышкой (Power Nap) Bluetooth не включают. При подключённом внешнем мониторе приложение ничего не делает.
