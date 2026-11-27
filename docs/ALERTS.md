# Alerts and quiet hours

Luftwächter alerts you when the advice for the selected room changes to **open** or **close** the window.

| Channel | Option | Quiet during |
| --- | --- | --- |
| Soft sound | *Sound* | quiet hours and *Quiet for an hour* |
| Balloon next to the clock | *Tray icon* | quiet hours and *Quiet for an hour* |
| Pop-up | *Pop-up on change* | quiet hours and *Quiet for an hour* |

At most one sound, balloon and pop-up every 30 minutes.

## Quiet hours

Right-click → **Quiet hours** cycles through `22–07`, `23–06`, `21–08`, `20–09` and *off*. The default is `22–07`. Settings: `quietOn`, `quietFrom`, `quietTo` in [`SETTINGS.md`](SETTINGS.md).

## Last alerts

Key **A** or Advanced → *Last alerts…* lists the last 15 changes with time. Changes that happened during quiet hours are listed too, so nothing is lost.

## Test

Advanced → *Send a test alert* plays the sound and shows a balloon. If you hear and see nothing, check the Windows notification settings (focus assist / do not disturb).

The menu entry shows how many alerts are listed; *Clear the alert list* (Advanced) empties it. Key **N** keeps the widget quiet until tomorrow morning (07:00), key **Q** for an hour.
