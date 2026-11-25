# Changelog

All notable changes. Format: [Semantic Versioning](https://semver.org). The text of each release section is shown to users in the in-app update dialog.

## [5.21.0] - 2026-11-25
- New: right-click → "What's new? (release notes)" opens the notes of your version on GitHub.
- New: right-click → "Report a problem or suggest an idea (GitHub)" opens the issue form.
- New: right-click → More → "Open the data folder" opens the folder with your settings and log in Explorer.
- New: the tray icon menu has "Open Home Assistant" (when connected).
- Improved: "Copy diagnostics" also lists the time zone, autostart, whether Home Assistant is set up, tray and quiet time, so most problems can be understood from one paste.
- Improved: bug reports and feature requests are now GitHub forms with the right questions (version, connection mode, diagnostics), so reports arrive complete.
- Improved: the repository keeps the right line endings automatically (Windows scripts stay CRLF, even when edited on another system).
- Improved: the build checks also look for broken links between the documents, and the checks can be started by hand on GitHub.
- Improved: a "Quick start in 3 steps" and contents list at the top of the README, a SUPPORT page that says where to ask what, and an updated contributing guide.
- Improved: two more self-tests cover the new menu items and the richer diagnostics.
- DE: Neu: Rechtsklick → „Was ist neu? (Versionshinweise)“ öffnet die Hinweise deiner Version auf GitHub.
- DE: Neu: Rechtsklick → „Problem melden oder Idee vorschlagen (GitHub)“ öffnet das Meldeformular.
- DE: Neu: Rechtsklick → Erweitert → „Datenordner öffnen“ zeigt den Ordner mit Einstellungen und Protokoll im Explorer.
- DE: Neu: Das Tray-Menü hat „Home Assistant öffnen“ (wenn verbunden).
- DE: Verbessert: „Diagnose kopieren“ nennt jetzt auch Zeitzone, Autostart, ob Home Assistant eingerichtet ist, Tray und Ruhezeit. So lassen sich die meisten Probleme aus einem Einfügen verstehen.
- DE: Verbessert: Fehlermeldungen und Wünsche sind jetzt GitHub-Formulare mit den richtigen Fragen (Version, Verbindung, Diagnose). Meldungen kommen so vollständig an.
- DE: Verbessert: Das Repository behält die richtigen Zeilenenden automatisch (Windows-Skripte bleiben CRLF, auch wenn sie auf einem anderen System bearbeitet werden).
- DE: Verbessert: Die Prüfungen suchen auch kaputte Verweise zwischen den Dokumenten und lassen sich auf GitHub von Hand starten.
- DE: Verbessert: „Schnellstart in 3 Schritten“ und Inhaltsverzeichnis oben in der README, eine SUPPORT-Seite, die sagt, wo man was fragt, und ein aktualisierter Leitfaden zum Mitmachen.
- DE: Verbessert: Zwei weitere Selbsttests decken die neuen Menüpunkte und die ausführlichere Diagnose ab.

## [5.20.0] - 2026-11-25
- New: right-click → More → "Open Home Assistant in the browser" and "Open the Luftwächter panel in Home Assistant" (only shown when you are connected to Home Assistant). The panel is the full-size view from the Luftwächter integration.
- New: right-click → More → "Copy diagnostics (for support)" copies the version, Windows and PowerShell version, mode, room count and the last 20 log lines, so a bug report needs one paste. It never includes your token or your Home Assistant address. Glance over the log lines before posting them publicly.
- Improved: the More submenu is grouped so the Home Assistant entries sit together at the top.
- Improved: the build checks are stricter (every text in the menu has a German and an English version, line endings, German release notes) and two new tests cover the new menu items, so mistakes are caught before a release.
- Improved: release pages now say how to install and how to verify the download with the checksum file. The GitHub page got a "which one do I need" table, badges and a troubleshooting section, and links to the Home Assistant integration.
- DE: Neu: Rechtsklick → Erweitert → „Home Assistant im Browser öffnen“ und „Luftwächter-Ansicht in Home Assistant öffnen“ (nur sichtbar, wenn du mit Home Assistant verbunden bist). Die Ansicht ist die Vollbild-Seite der Luftwächter-Integration.
- DE: Neu: Rechtsklick → Erweitert → „Diagnose kopieren (für Support)“ kopiert Version, Windows- und PowerShell-Version, Modus, Raumanzahl und die letzten 20 Protokollzeilen. So genügt bei einem Fehlerbericht ein Einfügen. Dein Token und deine Home-Assistant-Adresse sind nie enthalten. Schau die Protokollzeilen vor dem öffentlichen Posten kurz an.
- DE: Verbessert: Das Untermenü ist gruppiert, die Home-Assistant-Einträge stehen zusammen oben.
- DE: Verbessert: Die Prüfungen vor einer Version sind strenger (jeder Menütext hat Deutsch und Englisch, Zeilenenden, deutsche Versionshinweise) und zwei neue Tests decken die neuen Menüpunkte ab, damit Fehler vor dem Release auffallen.
- DE: Verbessert: Die Release-Seite erklärt jetzt Installation und Prüfsummen-Kontrolle. Die GitHub-Seite hat eine „Was brauche ich?“-Tabelle, Abzeichen und eine Hilfe bei Problemen und verweist auf die Home-Assistant-Integration.

## [5.19.0] - 2026-11-24
- New: the help now explains each of the four readings (CO₂, fine dust, temperature, humidity): what it is, which limits the widget uses, common causes of poor values and what helps.
- New: help sections fold open and closed with a click on the heading, plus "Expand all" and "Collapse all". The long list is now easy to scan.
- New: each reading's heading in the help shows the current value and rating, e.g. "CO₂ (carbon dioxide) · now 820 ppm (good)".
- New: right-click a value tile and the help opens directly at its explanation.
- Fixed: chart lines, chart captions and tile tooltips now match the limits the widget really uses (fine dust line at 20 instead of 15, humidity 30 to 60 %, CO₂ fair up to 1500, temperature 17 to 23 °C). Some of these were wrong since 5.16.
- DE: Neu: Die Hilfe erklärt jetzt jeden der vier Messwerte (CO₂, Feinstaub, Temperatur, Luftfeuchte): was er ist, welche Grenzen das Widget nutzt, häufige Ursachen für schlechte Werte und was hilft.
- DE: Neu: Hilfe-Abschnitte klappen per Klick auf die Überschrift auf und zu, dazu „Alle aufklappen“ und „Alle zuklappen“. Die lange Liste ist jetzt übersichtlich.
- DE: Neu: Die Überschrift jedes Messwerts in der Hilfe zeigt den aktuellen Wert und die Bewertung, z. B. „CO₂ (Kohlendioxid) · jetzt 820 ppm (Gut)“.
- DE: Neu: Rechtsklick auf eine Wert-Kachel öffnet die Hilfe direkt bei ihrer Erklärung.
- DE: Behoben: Kurven-Linien, Kurven-Beschriftungen und Kachel-Hinweise passen jetzt zu den Grenzen, die das Widget wirklich nutzt (Feinstaub-Linie bei 20 statt 15, Luftfeuchte 30 bis 60 %, CO₂ mittel bis 1500, Temperatur 17 bis 23 °C). Einige waren seit 5.16 falsch.

## [5.18.0] - 2026-11-24
- New: the size picker is now a clear button row. The current size is highlighted and each choice is a bigger target to click.
- New: buttons, value tiles and room buttons glow softly when the mouse is over them, so you see what you can click.
- New: switching rooms and bringing the widget back fades in smoothly instead of jumping.
- Improved: the right-click menu is sorted into groups (view, alerts, data, window, help). Rarely used items moved into "More".
- Improved: tooltips for the size choices, the time, and the open/close buttons of the device panel and help.
- DE: Neu: Die Größenwahl ist jetzt eine klare Knopfreihe. Die aktuelle Größe ist hervorgehoben und jede Auswahl ist ein größeres Ziel zum Anklicken.
- DE: Neu: Knöpfe, Wert-Kacheln und Raum-Knöpfe leuchten sanft, wenn die Maus darüber ist. So siehst du, was du anklicken kannst.
- DE: Neu: Beim Raumwechsel und beim Zurückholen des Widgets blendet es weich ein, statt zu springen.
- DE: Verbessert: Das Rechtsklick-Menü ist in Gruppen sortiert (Ansicht, Hinweise, Daten, Fenster, Hilfe). Selten genutzte Punkte stehen unter „Erweitert“.
- DE: Verbessert: Hinweistexte für die Größenwahl, die Uhrzeit und die Schließen-Knöpfe von Geräte-Fenster und Hilfe.

## [5.17.1] - 2026-11-24
- Fixed: the tray icon tooltip could be too long for Windows when another room had worse air, so the tray icon stopped updating. The text is now shortened to fit. This also fixes the problem that came with 5.16.0.
- DE: Behoben: Der Hinweis am Symbol in der Taskleiste konnte für Windows zu lang werden, wenn ein anderer Raum schlechtere Luft hatte, und das Symbol wurde nicht mehr aktualisiert. Der Text wird jetzt passend gekürzt. Das behebt auch das Problem, das mit 5.16.0 kam.
- Everything from 5.17.0 below is included in this release.
- DE: Alles aus 5.17.0 weiter unten ist in diesem Release enthalten.

## [5.17.0] - 2026-11-24
- New: hover a room button to see its CO₂ value and rating without switching to it.
- New: the window title (taskbar, Alt+Tab) shows the state of the whole house, e.g. "2 of 5 rooms poor".
- New: keys 1 to 9 jump straight to that room.
- New: "Copy all rooms" in the menu, or Ctrl+Shift+C, copies a one-line-per-room overview for a message.
- Improved: screen readers such as Narrator now read the room, rating and advice, and the room buttons by name.
- DE: Neu: Fährst du über einen Raum-Knopf, siehst du CO₂-Wert und Bewertung, ohne den Raum zu wechseln.
- DE: Neu: Der Fenstertitel (Taskleiste, Alt+Tab) zeigt den Zustand des ganzen Hauses, z. B. „2 von 5 Räumen schlecht“.
- DE: Neu: Die Tasten 1 bis 9 springen direkt zum jeweiligen Raum.
- DE: Neu: „Alle Räume kopieren“ im Menü oder Strg+Umschalt+C kopiert eine Übersicht mit einer Zeile pro Raum für eine Nachricht.
- DE: Verbessert: Bildschirmleser wie der Sprachausgabe-Assistent lesen Raum, Bewertung und Rat vor, und die Raum-Knöpfe mit Namen.

## [5.16.0] - 2026-11-24
- New: move the mouse over the curve and the line shows the time and value of that point, e.g. "07:40 · 169 µg".
- New: the daily summary of dust, temperature and humidity now names the times of the lowest and highest value.
- New: the tray icon tooltip also names the room with the worst air when it is worse than the one you are looking at.
- Improved: the four value tiles explain on hover what counts as good, fair or bad.
- Improved: the widget polls three times slower while it is minimized, which saves battery and network, and refreshes at once when you bring it back.
- DE: Neu: Fährst du mit der Maus über die Kurve, zeigt eine Linie Uhrzeit und Wert dieses Punkts, z. B. „07:40 · 169 µg“.
- DE: Neu: Die Tagesübersicht für Feinstaub, Temperatur und Luftfeuchte nennt jetzt auch die Uhrzeit des niedrigsten und des höchsten Werts.
- DE: Neu: Der Hinweis am Symbol in der Taskleiste nennt auch den Raum mit der schlechtesten Luft, wenn er schlechter ist als der, den du gerade ansiehst.
- DE: Verbessert: Die vier Wert-Kacheln erklären beim Darüberfahren, was gut, mittel oder schlecht ist.
- DE: Verbessert: Solange das Widget minimiert ist, fragt es dreimal seltener ab. Das spart Akku und Netz. Beim Zurückholen aktualisiert es sofort.

## [5.15.0] - 2026-11-23
- New: "Quiet until tomorrow morning" in the menu and the tray icon menu. Mutes alerts until 07:00.
- New: quiet time is remembered. If you restart the widget or the PC, it stays quiet until the set time.
- New: more shortcuts. Ctrl+C copies the readings, Q switches quiet time on/off, T switches the theme, F1 opens help.
- Fixed: if a screen is unplugged or the resolution changes, the widget no longer ends up off-screen. It moves back by itself.
- Fixed: the tray icon turns grey and says "offline" when the connection is lost, instead of showing the last colour.
- DE: Neu: „Ruhe bis morgen früh“ im Menü und im Menü am Taskleisten-Symbol. Schaltet Hinweise bis 7:00 Uhr stumm.
- DE: Neu: Die Ruhezeit wird gemerkt. Nach einem Neustart von Widget oder PC bleibt es bis zur eingestellten Zeit ruhig.
- DE: Neu: Mehr Tastenkürzel. Strg+C kopiert die Werte, Q schaltet Ruhe an/aus, T wechselt das Design, F1 öffnet die Hilfe.
- DE: Behoben: Wird ein Bildschirm abgesteckt oder die Auflösung geändert, landet das Widget nicht mehr außerhalb des Bildes. Es holt sich selbst zurück.
- DE: Behoben: Das Symbol in der Taskleiste wird bei Verbindungsverlust grau und zeigt „offline“, statt die letzte Farbe zu behalten.

## [5.14.0] - 2026-11-23
- New: weekly score. Next to today's score the simple view shows how good the air was over the last 7 days, e.g. "week: 85 %".
- New: scroll the mouse wheel over the room buttons to switch rooms.
- New: right-click, "Copy readings" puts the current room's values and advice on the clipboard, ready to paste into a message.
- New: the tray icon menu has "Refresh now" and "Quiet for 1 hour", and its texts follow the widget language.
- Fixed: edge snapping now works on every monitor, also with display scaling, not only on the main screen.
- DE: Neu: Wochennote. Neben der Tagesnote zeigt die einfache Ansicht, wie gut die Luft in den letzten 7 Tagen war, z. B. „Woche: 85 %“.
- DE: Neu: Mit dem Mausrad über den Raum-Knöpfen wechselst du den Raum.
- DE: Neu: Rechtsklick → „Werte kopieren“ legt die Werte und den Rat des Raums in die Zwischenablage, fertig zum Einfügen in eine Nachricht.
- DE: Neu: Das Menü am Symbol in der Taskleiste hat „Jetzt aktualisieren“ und „Ruhe für 1 Stunde“ und folgt der Sprache des Widgets.
- DE: Behoben: Das Einrasten an den Rändern klappt jetzt auf jedem Bildschirm, auch mit Skalierung, nicht nur auf dem Hauptbildschirm.

## [5.13.0] - 2026-11-22
- New: keyboard. Click the widget once, then ← / → switches rooms, D switches simple/details, + / − resizes, F5 refreshes, Esc closes help and the device panel.
- New: the widget snaps to the screen edges when you move it close to them.
- New: while quiet time is on, the header shows "🔕 Quiet until 23:30", so you know alerts are muted.
- Improved: without a connection the widget says when the last values came in, e.g. "Last values from 22:31 (6 min ago)".
- Improved: "What's new" and the update window now show German notes in the German view.
- Quality: every push now starts the widget on Windows with demo data and checks every view automatically.
- DE: Neu: Tastatur. Einmal ins Widget klicken, dann: ← / → anderer Raum, D einfache Ansicht oder Details, + / − Größe, F5 aktualisieren, Esc schließt Hilfe und Geräte-Fenster.
- DE: Neu: Das Widget rastet beim Verschieben an den Bildschirmrändern ein.
- DE: Neu: Während der Ruhezeit steht oben „🔕 Ruhe bis 23:30“, damit du weißt, dass Hinweise stumm sind.
- DE: Besser: Ohne Verbindung zeigt das Widget, wann die letzten Werte kamen, z. B. „Letzte Werte von 22:31 (vor 6 Min)“.
- DE: Besser: „Neu in dieser Version“ und das Update-Fenster zeigen die Hinweise jetzt auf Deutsch.
- DE: Qualität: Bei jeder Änderung startet GitHub das Widget automatisch unter Windows und prüft alle Ansichten.

## [5.12.0] - 2026-11-22
- New: after an update, a small card at the top shows what is new in this version, so you never have to look it up. It shows once and goes away with "Got it".

## [5.11.0] - 2026-11-22
- New: export. Right-click, "Save history as CSV" writes the last 7 days (CO₂, fine dust, temperature, humidity, every 10 minutes, all rooms) to a CSV file in your Documents folder and shows it in Explorer. It opens directly in Excel.

## [5.10.0] - 2026-11-22
- New: double-click the title to switch between the simple view and the details view (the Details button still works).
- Docs: screenshots on the GitHub page now show the solid day and night design.

## [5.9.1] - 2026-11-22
- Changed: the title area at the top no longer opens GitHub, so you can grab it and move the window without surprises. The GitHub link stays in the footer.

## [5.9.0] - 2026-11-22
- New: quiet time. Right-click, "Quiet for 1 hour" silences the pop-up, the tray notice and the chime for an hour (for a call, a meeting or a nap). The widget keeps showing the air as usual; "End quiet time" brings the alerts back. It resets when the widget restarts.

## [5.8.1] - 2026-11-22
- Fixed: the crisp dark background flipped back to a brownish, milky tint after a second, because each refresh repainted the card with a status-coloured gradient. The card is now one solid colour; the status colour stays on the border, ring and panel.

## [5.8.0] - 2026-11-22
- New: a crisper look and a real day/night design. The window is always solid; night mode no longer fades anything. Tiles, room buttons and the advice panel use solid colours instead of see-through white, which removes the milky look. At night (22:00 to 07:00) the background switches to a deeper, darker tone. Right-click, "Theme" cycles Automatic, Day and Night.
- Removed: the `nightDim` setting from 5.7.2.

## [5.7.2] - 2026-11-22
- Improved: crisper at night. Night mode (22:00 to 07:00) now dims the content by only 8 % instead of 38 %, so text and colours stay sharp. Set `nightDim` in config.json (0 to 50, percent; 0 = no dimming).

## [5.7.1] - 2026-11-22
- Fixed: the milky, see-through look at night (22:00 to 07:00). Night mode made the whole window transparent, so a busy desktop wallpaper shone through. Now the window stays solid and only the content is dimmed.

## [5.7.0] - 2026-11-22
- Improved: the "not set up yet" screen now points to the demo, so first-time users see there is a way to look around before connecting Home Assistant.
- Docs: the demo is highlighted at the top of the GitHub page.

## [5.6.0] - 2026-11-22
- New: demo mode. Right-click, "Try the demo" shows three simulated rooms whose air gets stale and fresh again every 14 minutes, so anyone can try Luftwächter without Home Assistant. "Stop the demo" returns to your real rooms. Also useful for screenshots.

## [5.5.0] - 2026-11-22
- New: a thank-you to Home Assistant. The help has a new section and the right-click menu has "Support Home Assistant" (opens home-assistant.io). Text only, no logo; the widget states that it is an independent project, not affiliated with or endorsed by Home Assistant or the Open Home Foundation.

## [5.4.0] - 2026-11-22
- New: easier to read for everyone. Right-click offers "Make bigger" and "Make smaller" (also Ctrl + mouse wheel on the widget), with a new extra-large size. This works in the simple view too, where the size buttons are hidden.

## [5.3.0] - 2026-11-22
- New: the simple view shows a friendly daily air score under the advice, for example "Today: good air 92 % of the time ⭐". It counts the share of today's readings with CO₂ under 1000 ppm (needs about 20 minutes of data) and resets at midnight.

## [5.2.0] - 2026-11-22
- New: the widget now checks for updates by itself every 60 minutes (set `updateCheckMinutes` in config.json, 15 to 1440). When a new version exists, the Update button turns green, pulses gently and shows the version number, and a tray notice appears once. Hover the button to see when it was last checked.
- Docs: new screenshots and descriptions on the GitHub page.

## [5.1.0] - 2026-11-22
- New: a short welcome card in the simple view explains in three sentences what the face, the big sentence and the "Details" button are. It shows once and goes away with "Got it".

## [5.0.1] - 2026-11-22
- Fix: the "Details" button (and the clickable title and sensor warning) did not react, because the window grabbed the mouse for dragging. They work now.
- Fix: the Update button stays visible in the simple view.
- New: right-click menu entry "Show all details" / "Simple view" as a second way to switch.

## [5.0.0] - 2026-11-22
- New: simple view, now the default. The widget shows only what matters: the face, one clear sentence ("Please open the window") in larger text, the trend, and the rooms. Curve, numbers, weather, sizes and technical notes are one click away behind the "Details" button (top left); "Simple" goes back. Your choice is remembered.
- New: the device tab on the right edge now says "Lamps & plugs" instead of an arrow.
- Existing installs start in the simple view after this update; press "Details" once to get your old view back.

## [4.9.0] - 2026-11-22
- New: 7-day history. Tap the curve again after 24 hours to see the whole week (one point every 10 minutes, kept on your PC). Works for all four values. The week fills up from now on.

## [4.8.1] - 2026-11-22
- Fix: battery temperature and humidity sensors report only when the value changes, so they are no longer treated as "stale" after 30 minutes (now 6 hours). Air-quality monitors keep the strict limit.
- Improved: the sensor warning in the footer is shorter (room name left out) and clickable: a click opens "Choose sensors for this room".

## [4.8.0] - 2026-11-22
- New: setup wizard. Installieren.bat now opens one window (German or English) for the Home Assistant address (with network search), the access token, and the options "Start with Windows" and "Start menu entry". It tests the connection and tells you how many rooms with an air sensor it found. If the window cannot open, the old text setup is used.

## [4.7.2] - 2026-11-22
- Quality: automatic checks run on every change and before every release (script syntax, matching version numbers, all window controls present, no private data). A broken update can no longer be published. No change to the program itself.

## [4.7.1] - 2026-11-22
- Docs: README with screenshot, badges, a section on choosing sensors and a troubleshooting table. Issue and pull request templates on GitHub. No change to the program itself.

## [4.7.0] - 2026-11-22
- New: version history. The Update button now always opens a window with what is new (if an update is waiting) and the full history: every release of the current major version with its changes, and one summary paragraph for each earlier major version.

## [4.6.0] - 2026-11-22
- New: sensor watchdog. If a sensor stops reporting (20 minutes or more) or is ignored because its data is stale, the footer shows an amber warning with its name, so you never trust an old value without knowing.
- Improved: with Home Assistant the footer now says how many sensors feed the readings instead of a fixed text.

## [4.5.0] - 2026-11-22
- New: weather outlook. "More" now shows the next 12 hours (every 2 hours: time, weather symbol, temperature) from your Home Assistant weather entity.

## [4.4.0] - 2026-11-22
- Fix: a room's temperature could jump to nonsense (a dew-point sensor of the room showed 9.4 °C and turned the whole ring red). Dew point, device (chip) temperature, absolute humidity and sensors that stopped reporting are now ignored.
- New: with several sensors of one kind in a room, the widget shows their average (a sensor labelled "airguard" still takes priority).
- New: right-click, "Choose sensors for this room": pick exactly which sensor delivers CO2, fine dust, temperature and humidity, or leave it on Automatic. Saved per room.

## [4.3.0] - 2026-11-22
- Fix: when a room has several sensors of the same kind (e.g. an old and a new CO2 sensor), the widget now uses the one with the label "airguard", otherwise the one that reported most recently. Before, it could show a stale sensor (1051 ppm instead of 1258 ppm).
- New: the room drop-down in the header is gone (rooms are switched with the chips). The header now shows the app name "Luftwächter", the current room and "free & open source - by Dan Stasiak"; click it to open the project page.

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
