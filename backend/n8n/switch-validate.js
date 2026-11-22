// 1) paste config.js (the ROOMS block) here
// Allow-list is generated from the config: only 'switch', 'climate', 'cover' and 'button' devices can be controlled. 'meter' plugs are read-only.
const A = {};
for (const k of ORDER) { A[k] = {}; for (const dv of ROOMS[k].dev) if (dv.type !== 'meter') A[k][dv.e] = dv.type; }
const b = $('POST Schalten').first().json.body || {};
const room = String(b.room || ''), entity = String(b.entity || ''), action = String(b.action || '');
const r = A[room];
if (!r) throw new Error('Unknown room');
const dv = r[entity] ? { type: r[entity] } : null;
if (!dv) throw new Error('Device not allowed');
const dom = entity.split('.')[0];
let domain, service, k2 = 'entity_id', v2 = entity;
if (dv.type === 'switch' && action === 'toggle' && (dom === 'light' || dom === 'switch')) { domain = dom; service = 'toggle'; }
else if (dv.type === 'climate' && action === 'temp') {
  const v = Math.round(parseFloat(b.value) * 2) / 2;
  if (!isFinite(v) || v < 16 || v > 24) throw new Error('Temperature outside 16-24 C');
  domain = 'climate'; service = 'set_temperature'; k2 = 'temperature'; v2 = String(v);
}
else if (dv.type === 'cover' && ['open', 'close', 'stop'].includes(action)) { domain = 'cover'; service = action + '_cover'; }
else if (dv.type === 'button' && action === 'press') { domain = 'button'; service = 'press'; }
else throw new Error('Action not allowed');
return [{ json: { domain, service, entity, k2, v2 } }];
