# Custom Noctalia OSD

Open the toast with a JSON payload:

```sh
noctalia msg panel-open pschmitt/osd:toast \
  '{"summary":"Backup complete","body":"All files are current","severity":"info","category":"backup"}'
```

`summary` is required. The optional fields are `body`, `severity` (`info`,
`warn`, or `error`), `category`, `profile`, `command`, `timeout_ms`, and
`style`. Setting `timeout_ms` to zero keeps the toast open until it is closed.
`command` runs when the toast is clicked.

## Profiles

The advanced `profile_rules` setting is a JSON array of ordered rules. Every
matching rule is applied, and later rules override earlier ones, like mako's
criteria sections. Global plugin settings are the base; an inline payload
`style` object has final precedence. The shipped defaults color the `success`,
`warning`, `error`, and `failure` categories and provide a persistent named
`critical` profile.

```json
[
  {
    "match": { "category": ["success", "backup"] },
    "style": { "icon": "circle-check", "icon_color": "#A8D38D" }
  },
  {
    "match": { "summary_contains": "Mute" },
    "style": { "summary_color": "#E27978" }
  },
  {
    "name": "critical",
    "style": {
      "icon": "alert-circle",
      "icon_color": "error",
      "summary_color": "error",
      "timeout_ms": 0
    }
  }
]
```

Exact match criteria can reference any payload field. A criterion value may be
a scalar or an array of alternatives. A key ending in `_contains`, such as
`summary_contains`, performs a literal substring match. A named rule only
matches when the payload's `profile` has the same name; it can also have a
`match` object.

Profile `style` supports:

- `show_icon`, `icon`, `icon_size`, `icon_color`
- `icon_text_gap`, `line_gap`, `padding_h`, `padding_v`, `max_text_width`
- `summary_font_size`, `summary_font_weight`, `summary_color`
- `body_font_size`, `body_color`, `text_align`, `two_line_balance`
- `content_fill`, `content_border`, `content_border_width`, `content_radius`
- `timeout_ms`

Colors accept Noctalia theme roles (for example `error` or `on_surface`) and
hex colors. The content decoration and padding apply inside Noctalia's own
fixed panel padding.

Every one of those keys is also settable per call, with no plugin reload and no
settings change, by putting it in the payload's `style` object — that is the
highest-precedence layer. `pkgs/local/osd/osd.sh` exposes the two common ones
as `--icon` / `--icon-color`, plus `--profile` and a raw `--style JSON` escape
hatch for the rest:

```sh
osd -c bluetooth -i bluetooth-connected -d "Jabra Elite 7" "Bluetooth headset connected"
osd -S '{"summary_color":"error","content_border_width":1}' "Styled per call"
```

`icon` names come from Noctalia's bundled Tabler set (`assets/fonts/tabler.json`
upstream), so `bluetooth`, `bluetooth-connected`, `bluetooth-off`,
`bluetooth-x`, `headphones` and `headset` all resolve. An unknown name renders
nothing and logs `[WRN] [glyph] missing glyph: <name>` — there is no error, so
check the journal when an icon silently fails to appear.

## Window geometry

The outer `width` and `height` are static `[[panel]]` manifest properties.
Noctalia 5.0 has no runtime panel-resize API, so settings and profiles cannot
change the actual window dimensions. Change the manifest geometry and bump the
package/plugin version when a different outer size is needed. Likewise, the
outer card background, border, radius, and shadow come from Noctalia's global
panel theme; this plugin can style only its inset content tree.

Because the geometry is static but a toast is one *or* two lines, the manifest
declares four width buckets for each of the two line counts:

| Entry | Size | Content box | For |
| --- | --- | --- | --- |
| `pschmitt/osd:compact` | 252x48 | 224x20 | no `body`, short |
| `pschmitt/osd:compact-medium` | 320x48 | 292x20 | no `body`, medium |
| `pschmitt/osd:compact-wide` | 400x48 | 372x20 | no `body`, wide |
| `pschmitt/osd:compact-xwide` | 520x48 | 492x20 | no `body`, extra wide |
| `pschmitt/osd:toast` | 252x62 | 224x34 | with `body`, short |
| `pschmitt/osd:toast-medium` | 320x62 | 292x34 | with `body`, medium |
| `pschmitt/osd:toast-wide` | 400x62 | 372x34 | with `body`, wide |
| `pschmitt/osd:toast-xwide` | 520x62 | 492x34 | with `body`, extra wide |

`pkgs/local/osd/osd.sh` chooses the line count and smallest width bucket from
the longest displayed line. Direct `noctalia msg panel-open` calls use the
panel entry they name and do not get that wrapper-side width selection.
Opening any entry closes the other, since all share Noctalia's single
active-panel slot, so `dismiss`/`hide`/`status` address all ids.

The width buckets keep ordinary messages compact while allowing longer
messages such as ISO timestamps to expand without an explicit text-width cap.
The heights are bound by the host padding, not by the text: the panel host
insets the script's tree by `Style::panelPadding`, a fixed 14px per side a
plugin cannot turn off, so a 20px icon already needs 48px of panel.

`content_padding_h`/`content_padding_v` only *add* to that inset.
`max_text_width` defaults to `0`, which disables the explicit text-width cap;
set it from 80 to 462 to enable ellipsizing at a chosen width. The `osd`
wrapper estimates the required panel width and chooses the smallest available
bucket (252, 320, 400, or 520px) for each message.
