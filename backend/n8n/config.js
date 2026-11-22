// =====================================================================
// EXAMPLE room configuration. Replace every entity ID with your own
// Home Assistant entities. Paste the SAME block at the top of every
// Code node of the workflow (read-build-template.js, read-advice.js,
// switch-validate.js).
//
// Per room:  name / nameEn   display names (German / English UI)
//            co2, pm, t, h   sensor entity IDs (CO2 ppm, PM2.5 ug/m3, temperature C, humidity %)
//            win             optional window contact (binary_sensor, on = open)
//            mold            optional binary_sensor that is on when mold risk is high
//            dev             devices shown in the slide-out panel (allow-list!)
//   device:  g     group, one of 'Licht' | 'Strom' | 'Heizung' | 'Rollo'
//            e     entity ID
//            type  'switch' (light/switch, toggle) | 'meter' (plug, shows watts only)
//                  | 'climate' (thermostat) | 'cover' (blind) | 'button'
//            n/nEn display name (German / English)
//            w     optional power sensor (watts) for 'switch'/'meter'
// Only devices listed here can ever be switched from the widget.
// =====================================================================
const ROOMS = {
  living: {
    name: 'Wohnzimmer', nameEn: 'Living room',
    co2: 'sensor.living_room_co2', pm: 'sensor.living_room_pm25', t: 'sensor.living_room_temperature', h: 'sensor.living_room_humidity',
    win: 'binary_sensor.living_room_window', mold: null,
    dev: [
      { g: 'Licht', e: 'light.living_room_lamp', type: 'switch', n: 'Lampe', nEn: 'Lamp' },
      { g: 'Strom', e: 'switch.living_room_tv_plug', type: 'switch', n: 'TV-Steckdose', nEn: 'TV plug', w: 'sensor.living_room_tv_plug_power' },
      { g: 'Strom', e: 'switch.living_room_plug_2', type: 'meter', n: 'Steckdose 2', nEn: 'Plug 2', w: 'sensor.living_room_plug_2_power' },
      { g: 'Heizung', e: 'climate.living_room', type: 'climate', n: 'Heizung', nEn: 'Heating' },
      { g: 'Rollo', e: 'cover.living_room_blind', type: 'cover', n: 'Rollo', nEn: 'Blind' }
    ]
  },
  office: {
    name: 'Büro', nameEn: 'Office',
    co2: 'sensor.office_co2', pm: 'sensor.office_pm25', t: 'sensor.office_temperature', h: 'sensor.office_humidity',
    win: null, mold: null,
    dev: [
      { g: 'Licht', e: 'light.office_desk_lamp', type: 'switch', n: 'Schreibtischlampe', nEn: 'Desk lamp' },
      { g: 'Heizung', e: 'climate.office', type: 'climate', n: 'Heizung', nEn: 'Heating' }
    ]
  }
};
const ORDER = Object.keys(ROOMS);
