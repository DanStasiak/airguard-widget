# Backend API

The widget needs two HTTPS endpoints that you provide (see `backend/n8n/` for a ready-made implementation). Both links go into `config.json` (`url`, `switchUrl`).

## Read: `GET {url}?room=<key>&lang=<de|en>`

`room` may be empty (the server then picks its first room). `lang` is `de` or `en`; the server should return all user-visible text in that language. Response (JSON):

```json
{
  "room": { "key": "office", "name": "Office" },
  "rooms": [ { "key": "living", "name": "Living room", "level": "gut", "color": "#2e9e5b", "co2": "612" } ],
  "level": "mittel",
  "color": "#e8a317",
  "headline": "Please ventilate",
  "detail": "Open fully, ventilate for 10 minutes.",
  "action": "oeffnen",
  "window": "zu",
  "hasWindow": false,
  "ventMin": 10,
  "values": [
    { "key": "CO₂", "value": "1200", "unit": "ppm", "level": 1 },
    { "key": "Feinstaub", "value": "8", "unit": "µg", "level": 0 },
    { "key": "Temperatur", "value": "22.1", "unit": "°C", "level": 0 },
    { "key": "Luftfeuchte", "value": "45", "unit": "%", "level": 0 }
  ],
  "colors": ["#2e9e5b", "#e8a317", "#d9472b"],
  "mold": false,
  "outside": { "temp": "7", "cond": "cloudy", "icon": "☁️", "wind": "12", "windDir": "SW", "hum": "80", "cloud": "90", "press": "1012", "tip": "Good time to ventilate." },
  "devices": [
    { "group": "Heizung", "entity": "climate.office", "name": "Heating", "type": "climate", "state": "heat", "detail": "Now 20.5 °C", "target": 21, "value": "" }
  ],
  "updated": "19:14:03"
}
```

Field notes
- `level` / `rooms[].level`: `gut` (good), `mittel` (fair), `schlecht` (poor) or `unbekannt`. `color`: hex color of the worst level. `values[].level`: index 0..2 into `colors`, or `null`.
- `values` must contain exactly four entries in this order: CO₂, fine dust, temperature, humidity. `value` is a display string (already localized, with decimal comma or point).
- `action`: `oeffnen` (open), `schliessen` (close), `offen_lassen` (keep open), `zu_lassen` (keep closed), `warten` (wait), `unbekannt`. The widget pulses on `oeffnen` and shows a progress bar on `offen_lassen`.
- `window`: `offen`, `zu` or `unbekannt`. `ventMin`: suggested ventilation minutes (used by the timer).
- `outside` may be `null`.
- `devices[].group` must be one of `Licht`, `Strom`, `Heizung`, `Rollo` (the widget localizes the group titles). `type`: `switch` (toggle), `meter` (shows `value`, read-only), `climate` (`target` in °C), `cover`, `button`.

## Switch: `POST {switchUrl}` (JSON)

```json
{ "room": "office", "entity": "climate.office", "action": "temp", "value": 21.5 }
```

`action`: `toggle` (switch), `temp` (climate, `value` in °C, 0.5 steps), `open` / `close` / `stop` (cover), `press` (button). **The server must validate against an allow-list** (the reference backend does): only listed entities, sensible ranges. Return HTTP 200 on success.

## Security

There is no authentication in the protocol. Use a long unguessable URL path, HTTPS, and an allow-list. Do not expose controls for alarms, locks or other critical devices.
