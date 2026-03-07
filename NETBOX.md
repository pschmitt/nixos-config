# NetBox Conventions

## Purchase Information

Purchase metadata is stored in NetBox custom fields, not in the top-level device
attributes.

Use these custom fields:
- `purchase_info`
- `purchase_date`
- `purchase_price`
- `purchase_currency`

`purchase_info` should use this Markdown structure:

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
- `Notes` is optional and should only be present when there is relevant extra
  information that does not fit the standard fields.
- Do not hide store/order details inside a `- Notes:` block if they can be
  normalized into `Store` and `Order number`.
- Normalize dates as `YYYY-MM-DD`.
- Keep the currency code in `purchase_info` aligned with
  `purchase_currency`.

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
- `AUK` = Aukey
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
- `EYO` = Eyoyo
- `FIB` = Fibaro
- `FLS` = FlexiSpot
- `FUJ` = Fujitsu
- `GEN` = Generic
- `GGL` = Google
- `GPD` = GPD
- `ICY` = ICY BOX
- `IKE` = IKEA of Sweden
- `INT` = Intel
- `IRO` = iRobot
- `ITL` = Intellinet
- `KEY` = Keyestudio
- `KIN` = Kingston
- `KIO` = Kioxia
- `LEN` = Lenovo
- `LGC` = LG
- `LNK` = Linksys
- `MER` = Meross
- `NOU` = Nous
- `NBC` = Nabu Casa
- `NEL` = nello
- `NET` = Netac
- `NTG` = Netgear
- `NUK` = Nuki
- `ORI` = ORICO
- `PKV` = PiKVM
- `POE` = PoE injectors and PoE splitters
- `PRC` = PROCET
- `QUE` = Quectel
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

Exceptions:
- `Rack Bottom (U1)` is a virtual grouping device and should stay untagged.

## Radio / Wireless Modeling

Conventions used in this inventory:
- Zigbee IEEE goes in the `zigbee_ieee` custom field.
- LoRaWAN DevEUI goes in the `lorawan_eui` custom field.
- 433.92 MHz devices may be modeled as `other (wireless)` interfaces so
  NetBox wireless links can be used.

## Notes

When changing existing purchase or asset-tag data:
- prefer a dry-run first if many objects are affected
- take a backup before bulk normalization
- avoid rewriting ambiguous freeform notes without review
