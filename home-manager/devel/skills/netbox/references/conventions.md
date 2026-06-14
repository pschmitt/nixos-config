# NetBox Conventions

## Access

NetBox is available at:
- `https://netbox.brkn.lol`

Credentials can be retrieved from the password manager with:

```bash
zhj rbw::get --json "Netbox (AI Agent)"
```

Notes:
- The `API Token` field contains the NetBox API token.
- Handle retrieved credentials as secrets and do not commit them to the
  repository.

## Purchase Information

Purchase metadata is stored in NetBox custom fields, not in the top-level
device attributes.

When purchase details or bills are missing, you can and should use the `bichon`
skill to search for order confirmations, invoices, and related purchase emails.

Use these custom fields:
- `purchase_store`
- `purchase_order_number`
- `purchase_date`
- `purchase_price`
- `purchase_currency`
- `purchase_notes`

Display order:
- `purchase_store`
- `purchase_order_number`
- `purchase_date`
- `purchase_price`
- `purchase_currency`
- `purchase_notes`

`purchase_notes` should use this Markdown structure:

```md
- Store: example.com
- Order number: [123456](https://example.com/order/123456)
- Order placed: 2025-11-23
- Purchase price: 49.90 EUR
- Notes: Optional extra context
```

Rules:
- Prefer a linked `Order number` over putting the order URL in `Notes`.
- Omit `Order number` if none is known.
- `purchase_store` should contain the `Store` line value from
  `purchase_notes`, preserving a Markdown link when present and using plain text
  otherwise.
- `purchase_order_number` should contain the `Order number` line value from
  `purchase_notes`, preserving the Markdown link.
- `Notes` is optional and should only be present when there is relevant extra
  information that does not fit the standard fields.
- Do not hide store or order details inside a `- Notes:` block if they can be
  normalized into `Store` and `Order number`.
- Normalize dates as `YYYY-MM-DD`.
- Keep the currency code in `purchase_notes` aligned with
  `purchase_currency`.

## Document Uploads (netbox-documents plugin)

NetBox has the `netbox-documents` plugin installed. Use it to attach purchase
orders, manuals, and other files to devices and other objects.

**Do not use the REST API to upload files.** The plugin's `document` field only
accepts base64-encoded strings, not multipart file uploads. When a file is sent
as base64 the plugin discards the original filename and saves the file under a
random UUID with no extension — the filename shown in NetBox will be wrong.

Use the **web UI form** instead. This preserves the original filename.

### Procedure

1. Get a session cookie and CSRF token by logging in:

```bash
# Credentials: username/password from rbw (same entry as the API token)
curl -sc /tmp/nb_cookies.txt -s "https://netbox.brkn.lol/login/" > /dev/null
CSRF=$(grep csrftoken /tmp/nb_cookies.txt | awk '{print $NF}')

curl -sb /tmp/nb_cookies.txt -sc /tmp/nb_cookies.txt -s \
  -X POST "https://netbox.brkn.lol/login/" \
  -H "Referer: https://netbox.brkn.lol/login/" \
  -F "csrfmiddlewaretoken=$CSRF" \
  -F "username=ai-agent" \
  -F "password=<password from rbw>" \
  -F "next=/" -o /dev/null
```

2. Find the content type ID for the target object type from its NetBox detail
   page. The "add document" button URL contains `?content_type=<id>&object_id=<id>`.
   Known IDs:
   - `dcim.device` → `12`

3. Refresh the CSRF token, then POST the file:

```bash
# Refresh CSRF
curl -sb /tmp/nb_cookies.txt -sc /tmp/nb_cookies.txt -s \
  "https://netbox.brkn.lol/plugins/documents/documents/add/?content_type=12&object_id=<DEVICE_ID>&return_url=/dcim/devices/<DEVICE_ID>" > /dev/null
CSRF=$(grep csrftoken /tmp/nb_cookies.txt | awk '{print $NF}')

# Upload — filename in the -F value is what gets stored
curl -sb /tmp/nb_cookies.txt -sc /tmp/nb_cookies.txt \
  -X POST "https://netbox.brkn.lol/plugins/documents/documents/add/?content_type=12&object_id=<DEVICE_ID>&return_url=/dcim/devices/<DEVICE_ID>" \
  -H "Referer: https://netbox.brkn.lol/plugins/documents/documents/add/?content_type=12&object_id=<DEVICE_ID>&return_url=/dcim/devices/<DEVICE_ID>" \
  -F "csrfmiddlewaretoken=$CSRF" \
  -F "name=" \
  -F "document=@/path/to/file.pdf;type=application/pdf;filename=file.pdf" \
  -F "external_url=" \
  -F "document_type=purchaseorder" \
  -F "comments=" \
  -F "_create=" \
  -w "%{http_code} -> %{redirect_url}\n" -o /dev/null
# Expect: 302 -> https://netbox.brkn.lol/dcim/devices/<DEVICE_ID>
```

4. Verify via API:

```bash
curl -sf -H "Authorization: Token $NB_TOKEN" \
  "https://netbox.brkn.lol/api/plugins/documents/documents/?object_id=<DEVICE_ID>" \
  | jq '.results[] | {id, filename, document_type}'
```

### document_type values

- `purchaseorder` — Purchase Order
- `manual` — Manual
- `diagram` — Network Diagram
- `floorplan` — Floor Plan
- `quote` — Quote
- `supportcontract` — Support Contract
- `contract` — Contract
- `other` — Other

## Product Information

The following custom fields are available on `dcim.devicetype` and
`dcim.moduletype`. All belong to the `Product Information` group in NetBox
and are displayed in this order:

| Field         | Type | Purpose |
|---------------|------|---------|
| `sku`         | text | Manufacturer or retailer Stock Keeping Unit — the catalog code used to order or identify the specific product variant (e.g. `SHSW-1`, `SC0194`, `910-005448`). |
| `product_url` | URL  | Official English-language product page from the manufacturer. |
| `support_url` | URL  | Official manufacturer support, documentation, or knowledge base URL. |

### SKU field rules

- A SKU is the manufacturer's own catalog/model code as used by retailers and
  distributors — not a marketing name, not an EAN barcode, and not a long
  internal configuration code.
- For many devices the model name and SKU are the same string (e.g. Arlo
  `VMA4600`, Fibaro `FGSD-002`). That is correct — record the string anyway.
- When the manufacturer uses a shorter product code than the full model name,
  prefer the shorter code (e.g. Shelly Dimmer 2 → `SHDM-2`, not `Dimmer 2`).
- For products with many hardware variants sharing one device type (e.g.
  Raspberry Pi CM4 with different RAM/eMMC options), leave `sku` blank rather
  than picking an arbitrary variant.
- Do not record EAN-13 barcodes as SKUs — those belong in comments if at all.
- Regional suffixes (e.g. `-US`, `-EU`) are acceptable when the manufacturer
  publishes them and no region-neutral code exists.
- When searching for an unknown SKU, check the manufacturer's official store
  or product page first, then major retailer listings.

### product_url / support_url rules

- Prefer the official manufacturer product page over reseller or marketplace
  pages.
- Prefer the English-language version of the product page when available.
- Use `support_url` for official manufacturer support, documentation, or
  knowledge base pages when a product page is unavailable or additional support
  context is useful.

## Device Type Synchronization

Device types should stay in sync with the physical connectivity modeled on
devices that use them.

Rules:
- When adding or changing physical interfaces, power ports, power outlets,
  console ports, rear ports, front ports, device bays, or module bays on a
  device, update the corresponding device type templates as well.
- Model the common physical shape on the device type first, then keep concrete
  devices aligned with that template.
- Do not add per-device-only logical or virtual constructs to the device type.
  Examples include VLAN-only interfaces, software-defined interfaces, temporary
  overlays, or similar non-physical endpoints.
- If a device intentionally deviates from its type because of a real physical
  difference, document the reason in the device comments or description.

## Asset Tags

Asset tags use this format:

```text
#ABC-0001
```

Rules:
- Reuse the same manufacturer prefix for devices and modules.
- Devices and modules share the same numeric sequence per prefix.
- Continue existing numbering; do not backfill gaps unless there is a reason.
- Virtual or grouping objects do not get asset tags.
- Keep the manufacturer-to-prefix mapping in this file up to date whenever a
  new prefix is introduced or an existing convention changes.

Current prefixes:
- `AEO` = Aeotec / Everspring
- `AHL` = Adam Hall
- `ANK` = Anker
- `APB` = Appbot
- `APL` = Apple
- `AQA` = Aqara
- `ASU` = ASUS
- `AUK` = Aukey
- `AVM` = AVM
- `AYW` = AYWHP
- `BRO` = Brother
- `CRU` = Crucial
- `CZN` = CZ.NIC
- `DDC` = Dodocool
- `DEL` = Dell
- `DGT` = Digitus
- `DLK` = D-Link
- `DRG` = Dragino
- `EAT` = Eaton
- `EBD` = ebusd.eu
- `ECO` = EcoFlow
- `ELG` = Elgato
- `ESP` = Espressif / LOLIN / D1 Mini family
- `ESS` = Essential
- `EYO` = Eyoyo
- `FAI` = Fairphone
- `FIB` = Fibaro
- `FLC` = Flic / Shortcut Labs
- `FLS` = FlexiSpot
- `FUJ` = Fujitsu
- `GEN` = Generic
- `GLI` = GL.iNet
- `GOG` = Google
- `GPD` = GPD
- `I36` = Insta360
- `ICY` = ICY BOX
- `IKE` = IKEA of Sweden
- `INT` = Intel
- `IRO` = iRobot
- `ITL` = Intellinet
- `KEY` = Keyestudio
- `KIN` = Kingston
- `KIO` = Kioxia
- `KSM` = KingSmith
- `LEN` = Lenovo
- `LGC` = LG
- `LNK` = Linksys
- `LOG` = Logitech
- `M5S` = M5Stack
- `LTX` = Lantronix
- `MER` = Meross
- `MOT` = Motorola
- `NBC` = Nabu Casa
- `NEL` = nello
- `NET` = Netac
- `NOU` = Nous
- `NTG` = Netgear
- `NUK` = Nuki
- `ORB` = Oral-B
- `ORI` = ORICO
- `PFU` = PFU
- `PHX` = PHIXERO
- `PKV` = PiKVM
- `POE` = PoE injectors and PoE splitters
- `PRC` = PROCET
- `QUE` = Quectel
- `RBR` = Roborock
- `REO` = Reolink
- `RFX` = RFXtrx
- `RKM` = Rackmatic
- `RPI` = Raspberry Pi
- `RVT` = Revotech
- `SAL` = Salcar
- `SAM` = Samsung
- `SDK` = SanDisk
- `SEA` = Seagate
- `SED` = Seeed Studio
- `SLY` = Shelly
- `SMP` = Smappee
- `SNF` = Sonoff / ITEAD
- `SSM` = Samson
- `3RA` = THIRDREALITY
- `TLD` = Telldus
- `TOS` = Toshiba
- `TPL` = TP-Link
- `TSM` = Tesmart
- `VDF` = Vodafone
- `WAV` = WAVLINK
- `WDC` = Western Digital
- `WIT` = Withings / Nokia (legacy branding)
- `XIA` = Xiaomi
- `YEL` = Yeelight
- `ZTE` = ZTE

Exceptions:
- `Rack Bottom (U1)` is a virtual grouping device and should stay untagged.

## Radio And Wireless Modeling

Conventions used in this inventory:
- Generic app- or integration-level IDs go in the `device_identifier` custom
  field when there is no better hardware identifier to match on.
- Store the exact canonical identifier value exposed by the integration unless
  there is a documented namespaced convention for that integration.
- Zigbee IEEE goes in the `zigbee_ieee` custom field.
- LoRaWAN DevEUI goes in the `lorawan_eui` custom field.
- USB VID:PID and product string go in the markdown-enabled `usb_id`
  custom field on the device type, module type, or inventory item, not the
  device.
- Thread EUI-64 goes in the `thread_eui64` custom field.
- 433.92 MHz devices may be modeled as `other (wireless)` interfaces so
  NetBox wireless links can be used.

## Notes

Default location behavior:
- When a task needs a location assignment and the user does not specify one,
  prefer `gu5a`.
- Do not assume `ovm5`; it is historical and should not be used as the default
  location anymore.

When a user says "refer to my notes":
- Treat that as a reference to files under `~/Documents/notes`.
- Prefer those files over older note archives unless the active notes link to
  them.

When creating small-ish device types, such as IoT devices:
- Set rack height to `0U`, not `1U`.
- Do not mark them as full-depth unless they physically are.
- Exclude them from rack utilization so they do not distort capacity reporting.

When recording MAC addresses:
- Add the MAC address object to the correct interface instead of only writing it
  in comments.
- Set that MAC as the interface's primary MAC.
- Set the same MAC as the device's primary MAC when it is the main hardware
  address for the device.
