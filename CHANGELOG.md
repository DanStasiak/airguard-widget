# Changelog

All notable changes. Format: [Semantic Versioning](https://semver.org). The text of each release section is shown to users in the in-app update dialog.

## [4.2.0] - 2026-11-22
- New: rain-aware ventilation advice. The widget reads the hourly forecast from Home Assistant; when rain, snow or a thunderstorm is due within 6 hours it says so ("Ventilate soon: rain from 15:00") in the advice and in the weather tip.
- Improved: the history curve zooms to the data you have, so a new curve is readable right away instead of squeezed to the right edge.
- Improved: cleaner device names ("Plug 01 plug01 - Schalter" becomes "Plug 01"; a heater named like the room is called "Heating").
- Fix: the blinds group icon no longer shows an empty box on older Windows fonts.

## [4.1.0] - 2026-11-22
- New: hide devices. Right-click a device row and choose Hide; "n hidden - show all" at the bottom of the panel brings them back. Your choice is remembered.
- New: typical setting switches from Home Assistant (child lock, internet access, calibration, notifications, display ...) are hidden automatically. Set "showAllDevices": true in config.json to see everything.
- Fix: the curve title no longer runs into "now" on the right.

## [4.0.0] - 2026-11-22
- New: direct connection to Home Assistant. Rooms are found automatically (areas with a CO2 or fine-dust sensor), together with readings, window contacts, lights, plugs, heaters, blinds and the weather. No server needed.
- New: the installer searches your network for Home Assistant and asks for a long-lived access token; the token is stored encrypted for your Windows account. Right-click: Connect to Home Assistant (with a Find button).
- Optional label "airguard" in Home Assistant to choose which devices appear. Server mode (url/switchUrl) still works.

## [3.15.0] - 2026-11-22
- New: the four value tiles (CO2, fine dust, temperature, humidity) are now buttons. Tap one and the history curve shows that value (own color and reference lines, plus today's min/max). Your choice is remembered.
- The history now stores all four values per room (older entries keep working; the new curves fill up from now on).

## [3.14.2] - 2026-11-22
- New: a Start menu entry "Luftwächter" is created by the installer (and re-created at program start if missing). Use it, or type Luftwächter in the Start menu, to start the program again at any time.
- Start (Start menu, autostart) now always ends a stuck or hidden old copy first, so starting never silently fails.

## [3.14.1] - 2026-11-22
- Fix: quitting via the tray icon or the menu now ends the program completely (it could stay running invisibly and block a restart). Quit always releases the tray icon and the single-instance lock.

## [3.14.0] - 2026-11-22
- New: tray icon next to the clock. A colored dot shows the air in the current room (green good, yellow fair, red poor); hover for room, CO2 and advice. Click it to bring the widget to the front, even when it is behind other windows or minimized. Right-click for Open / Exit.
- New: a small Windows notification appears when ventilation is needed (07:00-22:00, at most every 30 minutes).
- Option "Icon in the notification area" in the right-click menu to switch it off. New Help section.

## [3.13.1] - 2026-11-22
- Fix: the window is no longer always in front. It now behaves like a normal window: other programs can cover it, and it has a taskbar button. "Always on top" is an option in the right-click menu (off by default; the old forced setting is reset once).
- New: when ventilation is needed (open / close the window) the widget briefly comes to the front for a few seconds without stealing focus. Can be switched off in the menu ("Bring to front briefly ...").

## [3.13.0] - 2026-11-22
First public release.
- Open source under the MIT License (c) 2026 Dan Stasiak.
- New: **Update button**. Checks GitHub for a newer release, shows what changed, installs it after your confirmation and restarts itself. Keeps your settings, makes a backup, verifies the download (SHA-256) and the script syntax first. Silent check every few hours turns the button green.
- New: copyright / license / GitHub links next to the version label; clicking the version opens all releases.
- New: setup state and "Open configuration" menu entry for first-time users; `config.example.json`.
- New: generic configuration (`place`, `footer`, `roomShort`, `roomShortEn`). No personal data in the code.
- New: reference backend for n8n + Home Assistant in `backend/n8n/`, API description in `docs/API.md`.

## [3.12] - 2026-11-22
- New: ? help panel, DE | EN language toggle (UI and server texts), crisper rendering.

## [3.11] - 2026-11-22
- New: daily summary (peak, average, share of time below 1000 ppm).

## [3.10] - 2026-11-22
- New: Pill mode (tiny colored dot with room and CO2 value).

## [3.9] - 2026-11-22
- New: error log and "Open log" menu entry.

## [3.0 - 3.8] - 2026-11
- Multi-room support, slide-out device panel (light, power, heating, blinds), weather row, CO2 curve with trend and forecast, ventilation timer, room overview strip, autostart with Windows, state restore, multi-monitor support, night dimming, version label.
