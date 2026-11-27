# Direct connection to Home Assistant

Since v4 the widget talks straight to Home Assistant (HA). No server in between.

## Connect

- The installer (`Installieren.bat`) searches your local network for HA (`homeassistant.local` and port 8123 on your subnet), lets you confirm the address and asks for a **long-lived access token**.
- Create the token in HA: your profile → **Security** → **Long-lived access tokens** → *Create token*.
- The address is saved in `config.json` (`haUrl`). The token is **not** in that file: it is stored encrypted with the Windows data protection of your user account (`%APPDATA%\Luftwaechter\ha-token.bin`) and can only be read by your Windows login on that PC.
- Change it any time: right-click the widget → *Connect to Home Assistant…* (it has a *Find* button for the network search).
- Use `http://` on your local network, or `https://` with a valid certificate (self-signed certificates are not accepted).

## What is found automatically

| in the widget | in Home Assistant |
| --- | --- |
| room | an **area** that contains a sensor with device class `carbon_dioxide` or `pm25` |
| CO₂ / fine dust / temperature / humidity | sensors of the area with device class `carbon_dioxide`, `pm25`, `temperature`, `humidity` (first one that has a value) |
| window open/closed | `binary_sensor` with device class `window` in the area (any open window counts as open) |
| devices | `light`, `switch`, `climate`, `cover` entities of the area |
| weather | the first `weather.*` entity (or `weatherEntity` in `config.json`) |

Assign your devices to areas in HA (Settings → Areas) and the rooms appear by themselves.

### Rain sensor

If you have a rain sensor, the widget uses it automatically: any `binary_sensor` whose name or entity id ends in `rain` or `regen` (for example "Solar Rain Sensor Rain") counts. While it is on, the widget treats it as raining at your house instead of relying on the weather forecast alone. An open window then gets the advice to close it, and a room with stale air is told to wait for the rain to stop. With no rain sensor, the weather entity decides.

### Speaker and sound for window reminders

The widget itself speaks nothing. Window reminders by phone and speaker come from the Home Assistant integration; see "Where to set up reminders, speaker, sound and rain sensor" in the [integration README](https://github.com/DanStasiak/luftwaechter-ha#where-to-set-up-reminders-speaker-sound-and-rain-sensor). If that integration is installed, the widget shows its advice (setting `useIntegration`, see [SETTINGS](SETTINGS.md)).

### Show only some devices

If an area has many switches you do not want in the widget, give the **label `airguard`** to the entities you do want (HA: Settings → Labels, then add to entities). As soon as at least one entity has that label, only labelled devices are shown (and `button` entities become possible).

## Safety

- The widget only switches entities it showed you in the current room, and only with `toggle` (light, switch), `set_temperature` (climate, limited to 5 to 30 °C), `open/close/stop` (cover) and `press` (button).
- Alarms, locks and cameras are never offered because only the domains above are read.
- Use a token for this purpose only. You can revoke it in HA at any time (profile → Security).

## How it works (for developers)

One call per refresh: `POST /api/template` renders a Jinja template (see `$script:HaTpl` in `Luftwaechter.ps1`) that returns all areas with their relevant entities as JSON. The ventilation advice is computed in the widget (`Build-HaData`). Switching uses `POST /api/services/<domain>/<service>`.
