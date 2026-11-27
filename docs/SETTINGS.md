# Settings reference

## What the widget remembers (`%APPDATA%\Luftwaechter\state.json`)

| Key | Meaning |
| --- | --- |
| `left`, `top` | window position |
| `size` | S / M / L / compact / pill / extra large |
| `theme` | `auto`, `day` or `night` |
| `lang` | `de` or `en` |
| `topmost` | always on top (key P) |
| `opacity` | 1.0, 0.85 or 0.7 (key O) |
| `hoverFull` | solid while the mouse is over the widget |
| `quietOn` | night quiet hours on / off (default on) |
| `quietFrom`, `quietTo` | start and end hour, 0–23 (default 22 and 7; may wrap past midnight) |
| `alerts` | the last 15 alerts (text only, written by the widget) |
| `locked` | position locked |
| `taskbar` | show in the taskbar |
| `snap` | snap to screen edges |
| `symbols` | ✓ ! ✕ shapes next to the colours (key Y, default off) |
| `emojiFaces` | emoji faces instead of the Luftwächter mascot in the window (key M, default off = mascot) |
| `reduceMotion` | no fades or pulsing (default off) |
| `startHidden` | start hidden in the tray |
| `popup`, `tray`, `sound` | pop-up alerts, tray icon, chime |
| `simple` | simple view instead of details |
| `room` | last room shown |
| `hist`, `hist7` | recent readings for the curves |

A damaged `state.json` is kept as `state.json.bad`. The log `protokoll.txt` is kept as `protokoll.txt.old` once it grows past 100 KB.

## What you can set yourself (`config.json`, next to the program)

See `config.example.json`. Typical entries: `haUrl`, `refreshSeconds` (2 to 10), `updateCheckMinutes` (15 to 1440), `defaultRoom`, `useIntegration` (`false` = ignore the Luftwächter integration and always use the widget's own advice). *Copy diagnostics* lists values outside the allowed range.

## Backups

*Back up settings…* writes only the look-and-feel keys (theme, language, transparency, lock, taskbar, hover, pop-up, tray, sound, simple, always on top, quiet hours, shapes, reduce motion) to `Luftwaechter-Einstellungen.json` in *Documents*. The Home Assistant token is never part of it.

## Resetting

Advanced → *Reset settings…* sets the look-and-feel keys back to the defaults after saving the old values as `settings-before-reset.json` in the data folder. Connection, rooms, sensor choices and history are not touched. To undo, use *Restore settings…* with that file.
