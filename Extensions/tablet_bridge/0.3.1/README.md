# MTT Input Bridge 0.3.1

Native REAPER extension for direct USB pen input and momentary macOS Force Touch trackpad performance. It needs no vendor tablet driver and no other application: it reads the tablet itself, with the device database and report parsers of [OpenTabletDriver](https://github.com/OpenTabletDriver/OpenTabletDriver) built in (see [otd/README.md](otd/README.md) for provenance and the LGPL-3.0 licence of that part, and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md), installed next to the module). It is independent of Wacom's driver API, Wintab, ReaImGui and SWS. The operating system's USB/HID facilities are still required.

This release compiles on macOS and implements a macOS IOHID backend. Other platforms return `unsupported`; they do not pretend to capture a device. All hardware support below is implemented and tested with synthetic input, **not yet verified with physical tablets or inside REAPER**.

## Product name and compatibility — 2026-10-20

MTT Input Bridge is the new product name of MTT Tablet Bridge. The diagnostics
action is now **MTT: Input Bridge - diagnostics**. This is a naming change;
the implemented input remains USB HID pen input and the version remains 0.2.

The source directory and CMake target remain `tablet_bridge`, the installed
module remains `reaper_tablet_bridge-<arch>`, and the diagnostics command identifier
remains `MTT_tablet_bridge_COMMAND`. Updating the same module avoids loading two
bridges; existing action shortcuts keep their identifier. The license directory
also stays `mtt-licenses/tablet_bridge`.

Protocol 1 retains every exact `MTT Tablet ...` parameter name, range, status,
ownership rule and heartbeat. Loon's slider indices and saved-state format are
unchanged. Consumers discover this schema by name, so renaming those fields would
break compatibility. No installation or removal of an installed module is part
of this source rename.

## Input-source architecture and future iPad support

The product name covers multiple performance-input sources. Keep acquisition
specific to each source and feed one normalized X/Y/pressure/contact stream to
the owning instrument. A future implementation must arbitrate sources explicitly;
the USB pen worker and another source must never publish competing frames to the
same consumer. Preserve the existing pen path and protocol-1 consumers, extending
the contract only where a new capability requires it.

- **Mac trackpad:** implemented in 0.3 using public AppKit/CoreGraphics APIs; see the operating instructions and validation limits below.
- **iPad with Apple Pencil:** a future input source, not a supported USB tablet
  profile. Design its sender and transport separately, including explicit
  connection/ownership, capability detection, timestamps, latency measurement,
  contact edges and release on disconnect. Do not assume every Pencil model has
  pressure, or expose tilt/hover before capability detection. Connection type,
  pairing and any network listener remain undecided; this rename adds none.

## FX-chain capture and startup diagnostics — 0.3.1

The user confirmed the failed 0.3 capture was attempted in the **FX chain
window**, which 0.3 did not support. Version 0.3.1 supports a Loon selected in
that window as well as a floating FX. With no floating handle, the bridge grants
a native key-window fallback only when `GetTouchedOrFocusedFX` reports that exact
FX as focused and `TrackFX_GetChainVisible` reports the same FX index selected.
A hidden chain, no selection, a different selected FX or missing API cannot
activate the fallback. Changing/hiding the selected chain releases capture.
The temporary view covers that window during capture; no titles are used to
identify the target. Native event delivery in the chain still needs hardware testing.

Each preflight rejection now names its cause: application/modifier state,
missing FX window, held button, unexpected native handle, detached view,
hidden/minimized window, keyboard focus or pointer outside the content. The
message includes a snapshot from the attempt (native class names, focus flags,
button/modifier state and local pointer/visible rectangle), without window titles.
It is preserved when the later diagnostics action takes focus. Responder and
cursor-lease failures are reported separately. `Source` reports `none` without
an owner, and `Last attempted source` preserves the trackpad/USB attempt.

Build/install the update and restart REAPER. Select Loon in the chain, click its
content, release the click, move over the XY pad and press Option alone. Release
Option, then run diagnostics and retain the full rejection/snapshot if it still
fails. The macOS ARM64 build and 44 synthetic tests passed; no automatic install
or live input test was performed. The additional host API was checked against
the official REAPER docs and fetched SDK; the corpus verifier remains unavailable.

## Trackpad performance — 0.3 (2026-10-23)

With the updated Loon consumer in Manual mode, open/focus its **floating FX or FX-chain
window**, leave USB pen capture off, place the pointer inside the window and
hold **Option alone**. Touch with one finger and press: the whole trackpad maps
to normalized X/Y (Y grows upward), and Force Touch primary-stage pressure maps
to Z. Release Option or press Escape to restore the pointer. No extra window,
ReaScript relay, driver, private API, network listener or iPad sender is used.

The pressure is AppKit's `NSPressureBehaviorPrimaryGeneric` stage-1 value. Merely
resting a finger supplies position but no sounding contact. A non-Force-Touch
trackpad has no pressure fallback. A second finger cancels the gesture until
all fingers lift. Lift fingers before starting; moved contacts without a fresh
begin are ignored. Take/input FX and containers are not supported. Docked-chain behavior remains unverified.

A transparent, temporary `NSView` over the floating FX receives indirect
`NSTouch` positions and pressure events and consumes clicks/scroll/gestures.
`CGAssociateMouseAndMouseCursorPosition(false)` freezes the system pointer,
including a separate mouse, only during capture. Loon also suppresses its mouse
controls/hover preview and waits for physical buttons up before resuming clicks.
The view is removed and the previous responder restored on exit. System-level
multifinger gestures still need real-device validation; this is a one-finger mode.

The bridge releases on Option up, Escape, other modifiers, focus/window loss,
bypass/deletion/schema change, project change, stale consumer, failed publication,
queue overflow and unload. An independent 10 ms watchdog restores cursor
association when Option is released or the main-thread lease exceeds 500 ms;
AppKit cleanup and publication resume when the main thread can run. A held
Option key on startup or after cancellation never retries capture: release and
press again. Returning to REAPER with Option still held does not reacquire.

USB ownership is never preempted. Optional host APIs `GetTouchedOrFocusedFX` and
`TrackFX_GetFloatingWindow` select the focused floating consumer, then the
existing GUID/heartbeat checks apply. Missing APIs disable trackpad capture while
leaving USB support intact. Frames retain the protocol-1 transaction and timer
transport; no latency improvement or sample-accurate delivery is claimed.

Loon advertises optional hidden fields `MTT Input Trackpad` (capability 1, range
0–1) and `MTT Input Source` (live 0 = USB pen, 1 = trackpad, range 0–1), at sliders
246/247. Existing protocol-1 fields and status codes are unchanged. Consumers
without both fields are never captured as a trackpad target. Older bridge
versions ignore them. The existing module filename/action identity is preserved.

Build uses one private Objective-C++ source on macOS (ARC, C++17), linked with
AppKit and CoreGraphics; other platforms compile an inert backend. Native device
acquisition stays out of the audio thread. iPad/Apple Pencil remains future work.

Validation: the macOS ARM64 module and test executable compiled against the
installed Apple SDK; all **41 tests passed** (original USB/host coverage plus
trackpad pressure/contact, modifier, arbitration, release, timeout, failed start,
optional-API and source-reset cases). The tests substitute native acquisition:
**no physical trackpad or REAPER event delivery has been verified**. The fetched
REAPER SDK verified both optional C signatures; the separate docs-corpus tool is
unavailable. Effects `make check` passed 45 checks; ysfx is unavailable, so no
JSFX compilation/audio claim is made. No installation or REAPER launch occurred.

Manual acceptance: check XY corners, stationary pressure, light/heavy presses,
rapid taps, second-finger cancellation, press while releasing Option, Escape,
app/window switching, deletion/bypass, project switches, stalled processing,
multiple Loons and USB competition. Confirm pointer and click recovery with no
fader edits; record/replay/save an XYZ gesture and measure contact-to-audio latency.
Check native touch delivery through REAPER's floating-window hierarchy before
calling this backend validated. Apple source references:
[trackpad events](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/HandlingTouchEvents/HandlingTouchEvents.html),
[pressure](https://developer.apple.com/documentation/appkit/nsevent/pressure),
[cursor association](https://developer.apple.com/documentation/coregraphics/cgassociatemouseandmousecursorposition(_:)).

## Implemented device scope

- **Tablets in the OpenTabletDriver database** (360 tablet profiles at the imported commit: Wacom, Huion, Gaomon, XP-Pen, Veikk, XenceLabs, UGEE and about twenty other brands). A HID interface is matched like OpenTabletDriver does: vendor/product ID, report lengths, USB interface number and USB device strings where the profile requires them. The profile's initialisation (string reads, feature and output reports) switches the tablet from mouse emulation to its pen reports, and its parser and digitizer ranges decode them. The list of models is OpenTabletDriver's `TABLETS.md` at the imported commit.
- **Any other USB HID pen**: a pen collection with absolute X, Y and pressure together in an input report, decoded from the report descriptor. Wacom's vendor usage page `0xFF0D` counts as the standard Digitizers page (as in Linux `wacom_equivalent_usage`). Touchscreens, relative mice and split-axis reports are rejected.
- When a tablet matches a profile, a generic pen interface of the same product is ignored, so one tablet is never counted twice.
- Only the pen tip is used: X, Y, pressure, contact (pressure above zero) and range. Erasers, pen buttons, pad buttons, wheels, touch, pucks, tilt and rotation are ignored.
- Bluetooth, serial/ADB and Windows/Linux capture are not implemented. A vendor driver that already holds the tablet may refuse exclusive access ("access denied").
- Exactly one eligible tablet must be connected. Several produce a clear error, without choosing one silently.
- When no tablet is found, the diagnostics action lists the USB HID interfaces that look like tablets (known tablet vendors, Digitizers usage page, or a known product whose interface did not match), with their report sizes, interface number and report descriptor, so support can be added.

## Capture and lifecycle

The checkbox in a protocol-1 consumer requests capture. The worker opens the selected interface with `kIOHIDOptionsTypeSeizeDevice`. Only successful exclusive acquisition followed by a valid input report produces active status. A pen already pressed at acquisition must be lifted before it can trigger sound.

The ordinary separate mouse is never opened or grabbed. Capture of a composite tablet's other interfaces is outside this release; verify that no pen mouse-emulation interface escapes capture on real hardware before calling a model validated.

Unchecking, deleting or bypassing the owner, changing project, losing the consumer heartbeat, device removal, or extension unload releases acquisition. The worker also releases if the REAPER timer stops renewing its lease for 500 ms. A failed attempt resets the request; there is no automatic retry/capture loop. With no decodable data after 10 seconds, the capture is released.

A feature report changed by a profile's initialisation is read first and restored on release when that read succeeds. Like OpenTabletDriver, capture continues when an initialisation report fails or the previous value cannot be read; the diagnostics list such failures. Many tablets only leave their vendor mode when unplugged. Restoration is best effort on disconnect/crash. Returning to ordinary tablet-as-mouse behavior depends on the system's own support; this extension does not emulate a desktop pointer.

## Connection to an instrument

The extension discovers protocol-1 parameters by their exact names, validates their ranges and follows the FX GUID across reordering. Only normal, top-level track FX (including the master) in the active project are scanned. Take FX, input FX, containers and inactive project tabs are excluded. Newly discovered saved requests are cleared, so initial discovery may require the checkbox to be enabled again. Discovery runs every 500 ms.

X, Y, pressure and state are published through documented `TrackFX_GetParam` / `TrackFX_SetParam` calls on REAPER's timer thread. All normalized axes retain floating-point precision. No native `gmem` allocator or private EEL ABI is used. No relay script, virtual MIDI port or background app is required.

**Performance limitation:** delivery is timer-rate, typically around UI refresh speed but not guaranteed. It is not sample-accurate and has no measured latency guarantee. Motion is coalesced, contact transitions are queued (up to 64 states) and delivered one per timer tick. Rapid taps can therefore be delayed/stretched; overflow releases capture. Do not advertise this first transport as a finished low-latency performance solution. Measure it with Loon before deciding whether a higher-rate transport is necessary.

Do not automate, MIDI-learn or parameter-modulate protocol parameters. The consumer must manage its own gesture recording. Host automation modes and project dirty-state behavior of frequent parameter writes still need REAPER validation.

The action **MTT: Input Bridge - diagnostics** reports discovered consumers and the latest acquisition status. It does not capture hardware by itself.

The exact contract and Loon implementation instructions are in [LOON_INTEGRATION.md](LOON_INTEGRATION.md).

## Build and tests

From the repository root:

```sh
cmake --preset macos-debug -DMTT_INSTALL_TO_REAPER=OFF
cmake --build --preset macos-debug
ctest --preset macos-debug
```

The macOS ARM64 artifact is `build/macos-debug/extensions/tablet_bridge/reaper_tablet_bridge-arm64.dylib`. Build with the appropriate macOS architecture for another host; Intel has not been built in this task. No installer is run by these commands with the option OFF.

Tests cover the imported database (ranges, regular expressions), profile matching (report lengths, interfaces, USB strings), the CTL-471 and Intuos V1 parsers (contact, hover, eraser, out of range, tool state), unnumbered reports, bounded parsing of random reports for every parser, Wacom vendor usages in descriptors, parser bounds, malformed descriptors, pressure precision, signed axes, contact edges, overflow, activation guard, heartbeats, parameter transactions, competing owners, saved requests, FX reorder/delete, bypass, registration failures and unload. Host tests substitute a deterministic device and **never access hardware**.

`tests/reaper/tablet_probe.jsfx` is a standalone pass-through diagnostic consumer for manual testing after installation is separately authorized. Run it on an actively processing, top-level track and use its Request parameter. Loon 0.20 and later are protocol consumers (the Wacom check box).

`tests/reaper/tablet_inspect.lua` is a read-only ReaScript that repeats the bridge's consumer-discovery checks for every top-level track FX and prints which one fails.

`tools/update_otd.sh [git-ref]` (Zed task *Input Bridge: update OpenTabletDriver tablets*) fetches OpenTabletDriver and regenerates the tablet database `src/otd/otd_devices.cpp` with `tools/import_otd.py`; see [otd/README.md](otd/README.md).

## Source references

- [REAPER extension SDK](https://www.reaper.fm/sdk/plugin/plugin.php) and the repository's fetched SDK headers: public host signatures and registration lifecycle.
- [Apple IOHIDDeviceOpen](https://developer.apple.com/documentation/iokit/1588670-iohiddeviceopen) and installed Apple SDK headers: direct exclusive HID access.
- [USB HID specifications](https://www.usb.org/hid): descriptor item and digitizer usage definitions.
- [OpenTabletDriver](https://github.com/OpenTabletDriver/OpenTabletDriver) (LGPL-3.0): tablet configurations, report parsers and matching rules, imported and ported as described in [otd/README.md](otd/README.md).
- [Linux Wacom driver](https://github.com/torvalds/linux/blob/master/drivers/hid/wacom_wac.c): the vendor usage page equivalence used by the generic HID decoder.
- [Apple IOUSBLib](https://developer.apple.com/documentation/iokit/iousblib_h): USB string descriptors through `DeviceRequest`.
- [Native gmem experiment](https://gist.github.com/cfillion/ade31c6cacbd18bd4accbad36aa88e96): its author explicitly warns about private allocator compatibility; this extension does not use that approach.

## Remaining validation and development

Test on real hardware: no desktop pen motion/clicks while captured, separate mouse unaffected, mode restoration, permission denial, driver conflict, unplug/replug, USB hubs, stationary contact, UI closed, multiple instances, transport/automation, CPU and end-to-end latency. Also check the OpenTabletDriver profiles on real tablets under macOS: interface-number lookup, USB string reads for UC-Logic tablets (Huion, Gaomon), report sizes of unnumbered devices, and initialisation without a vendor driver. Windows/Linux backends are future work, not claimed compatibility.

## Verification record — 2026-10-20 (product rename)

- macOS ARM64 Debug module and test executable built successfully against the
  installed Apple SDK, including the IOHID backend and OpenTabletDriver parsers.
- All 31 bridge tests passed (12 host tests and 19 core/database/parser tests).
  Tests use synthetic input and do not capture real hardware.
- clang-format and `git diff --check` passed. API symbol verification was skipped:
  only product strings changed; no API name, signature or control flow changed.
- Effects workspace `make check`: all 45 structural/tooling tests passed. Loon
  differs from the pre-rename working copy only by three product-name substitutions.
- Auto-install was disabled; no REAPER launch or resource-directory change.
  The renamed action/help still need visual confirmation in REAPER; physical input
  behavior remains unverified. Trackpad and iPad sources are not implemented.

## Verification record — 2026-10-17 (OpenTabletDriver import)

- All 31 tests (19 core/OpenTabletDriver tests and 12 host tests) compiled and passed on Linux with GCC against the fetched REAPER SDK (`-DNOMINMAX` was needed there for SWELL with libstdc++); the core tests also passed with Clang and under AddressSanitizer/UndefinedBehaviorSanitizer.
- The macOS backend (`tablet_device.cpp`) was only syntax-checked against stub IOKit headers: it has **not** been compiled with the macOS SDK, linked or run. Build and run `ctest` on macOS before use.

## Verification record — 2026-10-17 (first release)

- macOS ARM64 Debug module compiled; links only Apple system frameworks and C/C++ runtime libraries.
- Full workspace CTest: 27 passed, including 25 tablet tests and 2 existing library tests.
- The 25 tablet tests also passed AddressSanitizer and UndefinedBehaviorSanitizer, including 5,000 malformed-descriptor cases. Device access is replaced by a fake in the host tests.
- clang-format check passed. All 16 requested REAPER API symbols were found in the fetched SDK declarations; the separate `reaper_cpp_docs_verify` corpus tool was unavailable.
- Effects workspace `make check`: 36 passed. This is structural/tooling verification, not EEL2 compilation or audio validation.
- Auto-install was OFF. No REAPER resource-directory modification or REAPER launch occurred. The diagnostic JSFX has not been executed in REAPER.
