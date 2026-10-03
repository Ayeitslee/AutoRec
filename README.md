# AutoRec / AutoM8 (Dopamine / rootless)

AutoRec is a SpringBoard touch recorder and replayer. AutoM8 is its companion settings application.

Author: AYeLee

The floating dock is fail-closed: safe mode is always enabled and disables the dock after an unclean SpringBoard launch. The dock can be re-enabled from AutoM8 after checking the log.

## Build
    export THEOS=~/theos


Copy the .deb to the phone and install it with Sileo/Filza, or `dpkg -i`, then respring.

## Use
- Floating panel: Record (red = stop), Play, Stop, library, AutoM8 settings (gear), minimise (–).
- AutoM8 controls the floating dock and Loop playback. Safe mode is always enabled.
- Library: tap to select, swipe left to delete. Settings: speed, loop count, loop delay, start delay.
- AutoM8's Export button saves recordings and shared settings as a JSON backup through the iOS document picker.
- AutoM8's Import button restores a validated backup, preserves existing recordings, and suffixes duplicate names.
- Loop playback off always plays once. When enabled, loop count 0 means forever.
- Recordings stop automatically after 20 minutes.
- Start delay gives you time to switch to the target app before recording/playback begins.
- Touches on the panel itself are never recorded.
- Hotkeys from a shortcut/terminal:
    notifyutil -p com.local.autorec.toggleRecord
    notifyutil -p com.local.autorec.togglePlay
- Recordings: /var/mobile/Library/AutoRec/*.json

## Build without a Mac (GitHub Actions)
1. Create a new GitHub repo and push this folder to it (including `.github/`).
2. Open the repo's Actions tab, run "Build AutoRec .deb" (it also runs on every push).
3. When it finishes, download the `AutoRec-deb` artifact, unzip it, and install the .deb on your phone.
4. The package includes the AutoM8 application; launch it from the Home Screen after installation.

## Troubleshooting (log: /var/mobile/Library/AutoRec/log.txt)
| Symptom | Meaning |
|---|---|
| Panel never appears | AutoM8 may have disabled the dock; check Floating dock and Safe mode. Otherwise, log has no "overlay installed" -> window/hook problem; log has "AutoRec loaded" only -> SpringBoard hook not firing |
| "Can't open HID client" | `IOHIDEventSystemClientCreate` returned NULL (entitlement) |
| "No touch events received" | client opened but SpringBoard isn't allowed to monitor HID events |
| Replay does nothing, log shows "first event dispatched" | dispatch is being refused (entitlement) or the digitizer fields need adjusting in HID.h |
| Replay taps land in the wrong place | orientation: record and replay in the same orientation |
| Dock disabled after respring | Safe mode detected an unclean SpringBoard launch; open AutoM8 and re-enable the dock after checking the log |
