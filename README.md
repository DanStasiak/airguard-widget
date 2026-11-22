# Luftwächter (airguard-widget)

A small always-on-top **Windows desktop widget** that shows how good the air is in your rooms and tells you in plain words whether to ventilate. Free and open source (MIT).

- Traffic-light ring (CO₂), the four readings (CO₂, fine dust, temperature, humidity), a 3 h / 24 h curve with trend, forecast and daily summary
- Ventilation advice ("open the window", "close it", "wait") with a ventilation timer
- All rooms at a glance, weather row with a ventilation tip
- Slide-out device panel: lights, plugs (watts), heating, blinds
- Starts with Windows and restores its look and place exactly; sizes S / M / L / compact / pill
- German and English UI (toggle in the widget), built-in help (`?`)
- **Update button:** checks this repository for a newer release, shows what changed, updates itself after you confirm

Made by **Dan Stasiak** · MIT License · [github.com/DanStasiak/airguard-widget](https://github.com/DanStasiak/airguard-widget)

## How it works

The widget is only the display. It talks to a small **server** that you run, for example a workflow in [n8n](https://n8n.io) connected to your [Home Assistant](https://www.home-assistant.io). The widget asks the server for the data of a room and sends switch commands back. The server decides which rooms, sensors and devices exist, so nothing about your home is in the widget.

- [`docs/API.md`](docs/API.md): the JSON contract (any backend that speaks it works)
- [`backend/n8n/`](backend/n8n): ready-to-use reference backend for n8n + Home Assistant (with example entity IDs you replace by your own)

## Install (Windows 10/11)

1. Download `Luftwaechter-<version>.zip` from the [latest release](https://github.com/DanStasiak/airguard-widget/releases/latest) and unzip it.
2. Double-click `Installieren.bat`. The widget appears at the top right and starts with Windows from now on.
3. Right-click the widget → **Open configuration**, enter your server link as `url` (and `switchUrl` for switching), save, then right-click → Quit and start it again (or log in again).

`config.json` is your private file: it is kept during updates and is never uploaded.

| key | meaning |
| --- | --- |
| `url` | server link that returns the room data |
| `switchUrl` | server link that accepts switch commands (optional, without it the device panel is display-only) |
| `defaultRoom` | start room key (optional) |
| `refreshSeconds` | refresh interval, 2 to 10 |
| `place` | place name shown in the weather row (optional) |
| `footer` | source note at the bottom (optional) |
| `roomShort`, `roomShortEn` | short names for the room overview, e.g. `{"living": "Living"}` |

## Updating

Press **⟳ Update** at the bottom right (or right-click → *Check for updates*). The widget compares its version with the latest GitHub release, shows the changes and asks whether to proceed. It then downloads the release, verifies the SHA-256 checksum and the script syntax, keeps a backup of the old version and restarts itself. Your `config.json` and state are untouched. A silent check runs every few hours; the button turns green when a new version exists.

## Uninstall

Run `Deinstallieren.bat` (removes autostart) and delete the folder `%LOCALAPPDATA%\Luftwaechter` and `%APPDATA%\Luftwaechter`.

## License and credit

MIT License, Copyright (c) 2026 Dan Stasiak. You may use, change and share it freely, also commercially, as long as the copyright notice and license text stay with it. See [LICENSE](LICENSE). Contributions welcome: [CONTRIBUTING.md](CONTRIBUTING.md).

---

# Deutsch

**Luftwächter** ist ein kleines Windows-Widget, das zeigt, wie gut die Luft in deinen Räumen ist, und in einfachen Worten sagt, ob du lüften sollst. Kostenlos und quelloffen (MIT).

**Installieren:** ZIP von der [aktuellen Version](https://github.com/DanStasiak/airguard-widget/releases/latest) laden, entpacken, `Installieren.bat` doppelklicken. Danach Rechtsklick auf das Widget → *Konfiguration öffnen* und den Server-Link (`url`) eintragen. Das Widget zeigt nur an; Räume, Sensoren und Geräte kommen von deinem Server (siehe [`docs/API.md`](docs/API.md) und [`backend/n8n/`](backend/n8n)).

**Aktualisieren:** Knopf **⟳ Update** unten rechts. Das Widget vergleicht seine Version mit GitHub, zeigt die Änderungen, fragt nach deiner Bestätigung, prüft den Download und tauscht sich selbst aus. Einstellungen bleiben erhalten.

**Lizenz:** MIT, © 2026 Dan Stasiak. Frei nutzbar, änderbar und weitergebbar; der Urheberhinweis muss erhalten bleiben.
