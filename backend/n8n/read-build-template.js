// 1) paste config.js (the ROOMS block) here

const q = $('GET Luft').first().json.query || {};
let room = String(q.room || '');
if (!ROOMS[room]) room = ORDER[0];
const ids = [];
const add = (x) => { if (x && !ids.includes(x)) ids.push(x); };
for (const k of ORDER) {
  const r = ROOMS[k];
  [r.co2, r.pm, r.t, r.h, r.win, r.mold].forEach(add);
  for (const d of r.dev) { add(d.e); add(d.w); }
}
const tpl = "{% set ids = " + JSON.stringify(ids).split('"').join("'") + " %}{% set ns = namespace(l=[]) %}{% for e in ids %}{% set ns.l = ns.l + [{'i': e, 's': states(e), 'n': state_attr(e,'friendly_name'), 't': state_attr(e,'temperature'), 'c': state_attr(e,'current_temperature'), 'a': state_attr(e,'hvac_action'), 'p': state_attr(e,'current_position')}] %}{% endfor %}{{ {'e': ns.l, 'w': {'c': states('weather.home'), 't': state_attr('weather.home','temperature'), 'h': state_attr('weather.home','humidity'), 'ws': state_attr('weather.home','wind_speed'), 'wb': state_attr('weather.home','wind_bearing'), 'p': state_attr('weather.home','pressure'), 'cl': state_attr('weather.home','cloud_coverage')}} | tojson }}";
const lang = q.lang === 'en' ? 'en' : 'de';
return [{ json: { tpl, room, lang } }];
