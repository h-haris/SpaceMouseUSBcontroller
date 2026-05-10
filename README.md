# SpaceMouseUSBcontroller

macOS app that bridges a **3Dconnexion SpaceMouse Compact** (USB HID) to the
Quesa 3D controller API.  Ported from `SpaceMouseController` (RS-232).

## Device

| Property   | Value  |
|------------|--------|
| Vendor ID  | 0x256F |
| Product ID | 0xC635 |

## Architecture

| File | Role |
|------|------|
| `SPUSBObject.{h,m}` | ObjC model — opens `IOHIDManager`, receives HID reports |
| `SPUSBdeliverQuesa.{h,m}` | Delivers translation / rotation / buttons to Quesa controller API |
| `SpaceMouseUSBViewModel.swift` | SwiftUI ObservableObject wrapping the ObjC model |
| `ContentView.swift` | SwiftUI UI (status indicator + scale settings) |
| `SpaceMouseUSBControllerApp.swift` | `@main` app entry point |

## Differences from RS-232 version

| RS-232 (`SpaceMouseController`) | USB (`SpaceMouseUSBcontroller`) |
|---------------------------------|---------------------------------|
| Serial port + `termios` | `IOHIDManager` |
| ASCII packet protocol | Binary HID reports (IDs 1/2/3) |
| Single `d` event carries all 6 axes | Translation (report 1) and rotation (report 2) arrive separately; each delivered with zeros for the other group |
| Commands sent back to device (mode, quality, null-radius, beep) | No commands — device is read-only |
| Port picker UI | Auto-connects when device is plugged in |
| Scale base 4000 (RS-232 raw counts at full deflection) | Scale base 350 (USB raw counts at full deflection) |
| Quesa signature `Magellan SpaceMouse:Logitech:` | Quesa signature `SpaceMouseCompact:3Dconnexion:` |

## Building

Open `SpaceMouseUSBcontroller.xcodeproj` in Xcode and build the
`Development` configuration.  `Quesa.framework` must be present at
`~/Library/Frameworks/Quesa.framework` (the top-level `build.sh` sets
this up).

## Log file

NSLog output is redirected to `/tmp/SpaceMouseUSBController.log`.
Enable `SPUSB_DEBUG 1` in `SPUSBObject.m` to log raw HID values.
