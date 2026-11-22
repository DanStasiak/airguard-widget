# Reference backend: n8n + Home Assistant

Two small n8n workflows turn your Home Assistant data into the [widget API](../../docs/API.md).

## 1. Configure
Edit `config.js`: your rooms, sensor entity IDs and the devices that may be shown/switched (the example uses made-up IDs). The same `ROOMS` block is pasted at the top of each Code node.

## 2. Read workflow (`GET`)
`Webhook (GET, response mode "Using Respond to Webhook node", long random path)` → `Code: read-build-template.js` → `Home Assistant node (Resource: Template, Operation: Create, Template: {{ $json.tpl }})` → `Code: read-advice.js` → `Respond to Webhook (First incoming item)`.
- Name the webhook node `GET Luft` and the first Code node `Build template` (the scripts reference these names).
- The Home Assistant node needs a Home Assistant credential (long-lived access token) that you create in n8n.

## 3. Switch workflow (`POST`)
`Webhook (POST, long random path, name it "POST Schalten")` → `Code: switch-validate.js` → `Home Assistant node (Resource: Service, Operation: Call, Domain: {{ $json.domain }}, Service: {{ $json.service }}, one field: name {{ $json.k2 }} value {{ $json.v2 }})` → `Respond to Webhook`.
- Only devices in `config.js` that are not `meter` can be switched; climate is limited to 16-24 °C.

## 4. Connect the widget
Put both production webhook URLs into the widget's `config.json` as `url` and `switchUrl`.

Thresholds (CO₂ 1000/1500 ppm, fine dust 20/50 µg/m³, comfort ranges for temperature and humidity) are in `read-advice.js`; change them to your taste.
