# Changelog

All notable changes. Format: [Semantic Versioning](https://semver.org). The text of each release section is shown to users in the in-app update dialog.

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
