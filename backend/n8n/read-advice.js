// 1) paste config.js (the ROOMS block) here

const room = $('Build template').first().json.room;
const EN = (($('GET Luft').first().json.query || {}).lang) === 'en';
const T = (de, en) => EN ? en : de;
const nm = (k) => (EN && ROOMS[k].nameEn) ? ROOMS[k].nameEn : ROOMS[k].name;
const dn = (dv) => (EN && dv.nEn) ? dv.nEn : dv.n;
const raw = $input.first().json;
let d = raw.renderedTemplate || {};
if (typeof d === 'string') { try { d = JSON.parse(d); } catch (e) { d = {}; } }
const M = {};
for (const x of (d.e || [])) M[x.i] = x;
const W = d.w || {};
const st = (id) => (id && M[id]) ? M[id].s : null;
const num = (v) => { const n = parseFloat(v); return isFinite(n) ? n : null; };
const f0 = (v, dg) => v === null ? '–' : (EN ? v.toFixed(dg) : v.toFixed(dg).replace('.', ','));
const lv = (v, g, f) => v === null ? null : v < g ? 0 : v < f ? 1 : 2;
const rng = (v, g1, g2, f1, f2) => v === null ? null : (v >= g1 && v <= g2) ? 0 : (v >= f1 && v <= f2) ? 1 : 2;
const colors = ['#2e9e5b', '#e8a317', '#d9472b'];
const names = ['gut', 'mittel', 'schlecht'];
const condDe = { 'clear-night': 'klar', cloudy: 'bewölkt', partlycloudy: 'teils bewölkt', sunny: 'sonnig', rainy: 'Regen', pouring: 'Starkregen', snowy: 'Schnee', 'snowy-rainy': 'Schneeregen', fog: 'Nebel', windy: 'windig', 'windy-variant': 'windig', hail: 'Hagel', lightning: 'Gewitter', 'lightning-rainy': 'Gewitter mit Regen', exceptional: 'Unwetter' };
const condEn = { 'clear-night': 'clear', cloudy: 'cloudy', partlycloudy: 'partly cloudy', sunny: 'sunny', rainy: 'rain', pouring: 'heavy rain', snowy: 'snow', 'snowy-rainy': 'sleet', fog: 'fog', windy: 'windy', 'windy-variant': 'windy', hail: 'hail', lightning: 'thunderstorm', 'lightning-rainy': 'thunderstorm with rain', exceptional: 'severe weather' };
const cname = (c) => (EN ? condEn : condDe)[c];
const icons = { 'clear-night': '🌙', cloudy: '☁️', partlycloudy: '⛅', sunny: '☀️', rainy: '🌧️', pouring: '🌧️', snowy: '🌨️', 'snowy-rainy': '🌨️', fog: '🌫️', windy: '💨', 'windy-variant': '💨', hail: '🌨️', lightning: '⛈️', 'lightning-rainy': '⛈️', exceptional: '⚠️' };
const ot = num(W.t);
const cond = W.c;
const badOut = ['pouring', 'lightning', 'lightning-rainy', 'hail', 'snowy-rainy', 'exceptional'].includes(cond);

function evalRoom(r) {
  const co2 = num(st(r.co2)), pm = num(st(r.pm)), t = num(st(r.t)), h = num(st(r.h));
  const L = { co2: lv(co2, 1000, 1500), pm: lv(pm, 20, 50), hum: rng(h, 30, 60, 25, 70), t: rng(t, 17, 23, 13, 25) };
  const known = [L.co2, L.pm, L.hum, L.t].filter((x) => x !== null);
  const worst = known.length ? Math.max(...known) : null;
  return { co2, pm, t, h, L, worst };
}
const rooms = ORDER.map((k) => { const e = evalRoom(ROOMS[k]); return { key: k, name: nm(k), level: e.worst === null ? 'unbekannt' : names[e.worst], color: e.worst === null ? '#7a8594' : colors[e.worst], co2: e.co2 === null ? '' : String(Math.round(e.co2)) }; });

const r = ROOMS[room];
const e = evalRoom(r);
const { co2, pm, t, h, L, worst } = e;
const hasWindow = !!r.win;
const wst = hasWindow ? st(r.win) : null;
const win = wst === 'on' ? 'offen' : wst === 'off' ? 'zu' : 'unbekannt';
const mold = r.mold ? st(r.mold) === 'on' : false;
const needVent = (co2 !== null && co2 >= 1000) || (h !== null && h > 60) || mold || (t !== null && t >= 25 && ot !== null && ot < t - 2);
let action, headline, detail, ventMin = 0;
const how = ot !== null && ot < 5 ? [T('Ganz öffnen, 5 Minuten lüften.', 'Open fully, ventilate for 5 minutes.'), 5] : ot !== null && ot < 15 ? [T('Ganz öffnen, 10 Minuten lüften.', 'Open fully, ventilate for 10 minutes.'), 10] : [T('Fenster öffnen, ca. 15 Minuten lüften.', 'Open the window, ventilate for about 15 minutes.'), 15];
if (co2 === null && pm === null) {
  action = 'unbekannt'; headline = T('Keine Messwerte', 'No data'); detail = T('Der Sensor meldet gerade nichts. Bitte später nochmal schauen.', 'The sensor is not reporting right now. Please check again later.');
} else if (win === 'offen') {
  if (co2 !== null && co2 < 700 && !(t !== null && t >= 25) && !(h !== null && h > 60)) {
    action = 'schliessen'; headline = T('Bitte Fenster schließen', 'Please close the window'); detail = T('Die Luft ist wieder frisch.', 'The air is fresh again.') + (ot !== null && ot < 15 ? T(' Sonst wird es kalt im Zimmer.', ' Otherwise the room gets cold.') : '');
  } else {
    action = 'offen_lassen'; headline = T('Fenster offen lassen', 'Keep the window open'); detail = T('Die Luft wird gerade besser.', 'The air is getting better.'); ventMin = how[1];
  }
} else if (needVent) {
  if (badOut) {
    action = 'warten'; headline = T('Jetzt noch nicht lüften', 'Do not ventilate yet'); detail = T('Draußen ist ' + (condDe[cond] || 'Unwetter') + '. Später lüften.', 'Outside: ' + (condEn[cond] || 'severe weather') + '. Ventilate later.');
  } else {
    action = 'oeffnen'; headline = hasWindow ? T('Bitte Fenster öffnen', 'Please open the window') : T('Bitte lüften', 'Please ventilate'); detail = how[0] + (co2 !== null && co2 >= 1500 ? T(' Die Luft ist verbraucht.', ' The air is stale.') : '');
  }
} else if (pm !== null && pm >= 35) {
  action = 'zu_lassen'; headline = hasWindow ? T('Fenster zu lassen', 'Keep the window closed') : T('Nicht dauerhaft lüften', 'Do not ventilate continuously'); detail = T('Viel Feinstaub im Raum. Nicht dauerhaft lüften.', 'High fine dust in the room. Do not ventilate continuously.');
} else {
  action = 'zu_lassen'; headline = T('Alles in Ordnung', 'All good'); detail = hasWindow ? T('Das Fenster kann zu bleiben.', 'The window can stay closed.') : T('Die Luft ist in Ordnung.', 'The air is fine.');
}
const values = [
  { key: 'CO₂', value: f0(co2, 0), unit: 'ppm', level: L.co2 },
  { key: 'Feinstaub', value: f0(pm, 0), unit: 'µg', level: L.pm },
  { key: 'Temperatur', value: f0(t, 1), unit: '°C', level: L.t },
  { key: 'Luftfeuchte', value: f0(h, 0), unit: '%', level: L.hum }
];

// Wetter
const dirs = EN ? ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'] : ['N', 'NO', 'O', 'SO', 'S', 'SW', 'W', 'NW'];
const wb = num(W.wb);
const windDir = wb === null ? '' : dirs[Math.round(wb / 45) % 8];
let tip = T('Gute Zeit zum Lüften.', 'Good time to ventilate.');
if (cond === 'rainy' || cond === 'pouring') tip = T('Es regnet: Fenster nur kurz öffnen (Stoßlüften 3 Min) oder in einer Regenpause lüften.', 'It is raining: open the window only briefly (3 min burst) or wait for a break in the rain.');
else if (ot !== null && ot < 5) tip = T('Es ist kalt: lieber kurz und ganz öffnen (Stoßlüften 5 Min), das spart Heizenergie.', 'It is cold: better open fully for a short time (5 min burst), it saves heating energy.');
else if (ot !== null && ot >= 25) tip = T('Es ist warm draußen: morgens oder abends lüften, tagsüber Fenster zu lassen.', 'It is warm outside: ventilate in the morning or evening, keep windows closed during the day.');
else if (W.h !== undefined && num(W.h) !== null && num(W.h) > 90) tip = T('Draußen ist es feucht: kurz lüften, nicht dauerhaft kippen.', 'It is humid outside: ventilate briefly, do not leave the window tilted.');
const outside = ot === null ? null : { temp: f0(ot, 0), cond: cname(cond) || cond || '', icon: icons[cond] || '', wind: f0(num(W.ws), 0), windDir, hum: f0(num(W.h), 0), cloud: f0(num(W.cl), 0), press: f0(num(W.p), 0), tip };

// Geräte
const devices = [];
for (const dv of r.dev) {
  const x = M[dv.e];
  if (!x || x.s === 'unavailable' || x.s === 'unknown') continue;
  const o = { group: dv.g, entity: dv.e, name: dn(dv), type: dv.type, state: x.s, detail: '', target: null, value: '' };
  const w = dv.w ? num(st(dv.w)) : null;
  if (dv.type === 'meter') o.value = w === null ? '–' : Math.round(w) + ' W';
  if (dv.type === 'switch' && w !== null) o.detail = Math.round(w) + ' W';
  if (dv.type === 'climate') {
    const tg = num(x.t), cu = num(x.c);
    o.target = tg === null ? 21 : tg;
    o.detail = (cu === null ? '' : T('Ist ', 'Now ') + f0(cu, 1) + ' °C') + (x.a === 'heating' ? T(' · heizt', ' · heating') : x.a === 'idle' ? T(' · aus', ' · off') : '');
  }
  if (dv.type === 'cover') {
    const p = num(x.p);
    o.detail = x.s === 'open' ? T('offen', 'open') : x.s === 'closed' ? T('zu', 'closed') : x.s === 'opening' ? T('öffnet', 'opening') : x.s === 'closing' ? T('schließt', 'closing') : (p === null ? x.s : Math.round(p) + ' %');
  }
  devices.push(o);
}

const updated = new Date().toLocaleTimeString(EN ? 'en-GB' : 'de-DE', { timeZone: 'Europe/Berlin', hour: '2-digit', minute: '2-digit', second: '2-digit' });
return [{ json: {
  room: { key: room, name: nm(room) }, rooms,
  level: worst === null ? 'unbekannt' : names[worst], color: worst === null ? '#7a8594' : colors[worst],
  headline, detail, action, window: win, hasWindow, ventMin, values, colors, mold, outside, devices, updated
} }];
