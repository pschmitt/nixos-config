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

Purchase metadata is stored in NetBox custom fields, not in the top-level device
attributes.

When purchase details or bills are missing, you can and should search the
mailbox via `bichon.brkn.lol` for order confirmations, invoices, and related
purchase emails. The service configuration lives in
[`services/bichon.nix`](/etc/nixos/services/bichon.nix).

Safety rule:
- Under no circumstances perform destructive actions in `bichon.brkn.lol`.
- Use it for read-only lookup of purchase information and documents.

API access:
- Retrieve the API token with:

```bash
zhj rbw::get --field "API Token" bichon.brkn.lol
```

- API specification:

```text
https://bichon.brkn.lol/api-docs/spec.yaml
```

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
- `purchase_store` should contain the `Store` line value from `purchase_notes`,
  preserving a Markdown link when present and using plain text otherwise.
- `purchase_order_number` should contain the `Order number` line value from
  `purchase_notes`, preserving the Markdown link.
- `Notes` is optional and should only be present when there is relevant extra
  information that does not fit the standard fields.
- Do not hide store/order details inside a `- Notes:` block if they can be
  normalized into `Store` and `Order number`.
- Normalize dates as `YYYY-MM-DD`.
- Keep the currency code in `purchase_notes` aligned with
  `purchase_currency`.

## Product Information

Official product and support URLs are stored in these custom fields on:
- `dcim.devicetype`
- `dcim.moduletype`

Both fields belong to the `Product Information` group in NetBox.
- `product_url`
- `support_url`

Rules:
- Prefer the official manufacturer product page over reseller or marketplace
  pages.
- Prefer the English-language version of the product page when available.
- Use `support_url` for official manufacturer support, documentation, or
  knowledge base pages when a product page is unavailable or additional support
  context is useful.
- Keep `product_url` before `support_url` in the grouped display order.

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
- Virtual/grouping objects do not get asset tags.
- Keep the manufacturer-to-prefix mapping in this file up to date whenever a
  new prefix is introduced or an existing convention changes.

Current prefixes:
- `AEO` = Aeotec / Everspring
- `AHL` = Adam Hall
- `AQA` = Aqara
- `ANK` = Anker
- `ASU` = ASUS
- `AUK` = Aukey
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
- `ESS` = Essential
- `FAI` = Fairphone
- `ESP` = Espressif / LOLIN / D1 Mini family
- `EYO` = Eyoyo
- `FIB` = Fibaro
- `FLS` = FlexiSpot
 - `FLC` = Flic / Shortcut Labs
- `FUJ` = Fujitsu
- `GEN` = Generic
- `GLI` = GL.iNet
- `GOG` = Google
- `GPD` = GPD
- `ICY` = ICY BOX
- `IKE` = IKEA of Sweden
- `INT` = Intel
- `IRO` = iRobot
- `I36` = Insta360
- `ITL` = Intellinet
- `KEY` = Keyestudio
- `KSM` = KingSmith
- `KIN` = Kingston
- `KIO` = Kioxia
- `LEN` = Lenovo
- `LGC` = LG
- `LOG` = Logitech
- `LTX` = Lantronix
- `LNK` = Linksys
- `MER` = Meross
- `MOT` = Motorola
- `NOU` = Nous
- `NBC` = Nabu Casa
- `NEL` = nello
- `NET` = Netac
- `NTG` = Netgear
- `NUK` = Nuki
- `ORB` = Oral-B
- `ORI` = ORICO
- `APL` = Apple
- `APB` = Appbot
- `PFU` = PFU
- `PKV` = PiKVM
- `POE` = PoE injectors and PoE splitters
- `WAV` = WAVLINK
- `PRC` = PROCET
- `QUE` = Quectel
- `REO` = Reolink
- `RBR` = Roborock
- `RFX` = RFXtrx
- `RKM` = Rackmatic
- `RPI` = Raspberry Pi
- `RVT` = Revotech
- `SAL` = Salcar
- `SAM` = Samsung
- `SSM` = Samson
- `SDK` = SanDisk
- `SEA` = Seagate
- `SED` = Seeed Studio
- `SMP` = Smappee
- `SNF` = Sonoff / ITEAD
- `TLD` = Telldus
- `TOS` = Toshiba
- `TPL` = TP-Link
- `TSM` = Tesmart
- `VDF` = Vodafone
- `WDC` = Western Digital
- `XIA` = Xiaomi
- `YEL` = Yeelight
- `ZTE` = ZTE

Exceptions:
- `Rack Bottom (U1)` is a virtual grouping device and should stay untagged.

## Radio / Wireless Modeling

Conventions used in this inventory:
- Zigbee IEEE goes in the `zigbee_ieee` custom field.
- LoRaWAN DevEUI goes in the `lorawan_eui` custom field.
- USB VID:PID and product string go in the markdown-enabled `usb_id`
  custom field on the device type, module type, or inventory item, not the
  device.
- Thread EUI-64 goes in the `thread_eui64` custom field.
- 433.92 MHz devices may be modeled as `other (wireless)` interfaces so
  NetBox wireless links can be used.

## Notes

When a user says "refer to my notes":
- treat that as a reference to files under `~/Documents/notes`
- prefer those files over older note archives unless the active notes link to them

When creating small-ish device types (such as IoT devices):
- set rack height to `0U`, not `1U`
- do not mark them as full-depth unless they physically are
- exclude them from rack utilization so they do not distort capacity reporting

When recording MAC addresses:
- add the MAC address object to the correct interface instead of only writing it in comments
- set that MAC as the interface's primary MAC
- set the same MAC as the device's primary MAC when it is the main hardware address for the device

When a device has an IP address:
- always try to determine its DNS name
- set the DNS name on the corresponding IP address object in NetBox when known
- prefer the actual hostname/FQDN used on the network over leaving DNS details only in comments or notes

Default wireless network assignments:
- Wi-Fi IoT devices should default to wireless LAN `brkn-iot`
- Wi-Fi media devices, laptops, smartphones, and other non-IoT clients should default to wireless LAN `brkn-lan` (the main Wi-Fi served by `brkn-ap`)
- Bluetooth devices should default to wireless LAN `hass-bluetooth`
- Zigbee devices should default to wireless LAN `zha`
- Thread devices should default to wireless LAN `thread`

Wireless links:
- create a wireless link between the coordinator and the end device for Bluetooth, Zigbee, and Thread when the relationship is known
- for Bluetooth, the default coordinator interface is `fnuc:bluetooth0`
- for Zigbee, the default coordinator interface is `Home Assistant Connect ZBT-2:zigbee0`
- for Thread at `ovm5`, the current coordinator / border router interface is `wolfgang-der-iii:thread0`
- always set a description on wireless links
- follow the existing description pattern: `<coordinator device> ↔ <end device>` for generic coordinator/end-device links
- example: `wolfgang-der-iii ↔ ALPSTUGA CO2 Sensor`
- when the network is proprietary or the link needs extra context, append a short qualifier in parentheses or use a concise technology-specific description matching existing links
- keep descriptions short and concrete; they should identify both endpoints without requiring the interface details in the description text

When changing existing purchase or asset-tag data:
- prefer a dry-run first if many objects are affected
- take a backup before bulk normalization
- avoid rewriting ambiguous freeform notes without review

## Documents

When uploading files via the `netbox-documents` plugin:
- Use the exact source filename, including extension, as the document `name`
  when uploading binary files.
- Keep the original file extension in the uploaded document name.
- Never strip the file extension from uploaded filenames.
- Do not replace the basename with a prettified title, because the plugin may
  derive the stored filename from the upload name.
- For example, upload a PDF manual as `Some Device Manual.pdf`, not
  `Some Device Manual`.

When adding new device types:
- Try to find an official manual, user guide, installation guide, or similar
  vendor documentation and upload it to the device type as a `Manual`
  document when available.

When adding new devices:
- If a bill, invoice, order confirmation, or similar purchase document is
  available, upload it to the device as a `Purchase Order` document.
- Upload purchase documents to devices, not device types.
- Re-uploading the same bill to multiple devices from the same order is fine
  and expected when that document applies to each device.
