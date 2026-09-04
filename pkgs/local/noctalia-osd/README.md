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
declares two panel entries running this same script:

| Entry | Size | Content box | For |
| --- | --- | --- | --- |
| `pschmitt/osd:compact` | 252x48 | 224x20 | no `body` |
| `pschmitt/osd:toast` | 252x62 | 224x34 | with `body` |

`pkgs/local/osd/osd.sh` picks between them by whether `--details` was given.
Opening either closes the other, since both share Noctalia's single
active-panel slot, so `dismiss`/`hide`/`status` address both ids.

252px is upstream's `cardWidth()` for a horizontal OSD
(`src/shell/osd/osd_overlay.cpp`). The heights are bound by the host padding,
not by the text: the panel host insets the script's tree by
`Style::panelPadding`, a fixed 14px per side a plugin cannot turn off, so a
20px icon already needs 48px of panel. A native OSD fits the same glyph in a
46px card only because its own `cardPadding` is `spaceMd` (12px).

`content_padding_h`/`content_padding_v` only *add* to that inset, and
`max_text_width` is capped at 194 (224 minus the icon and its gap) — raising
either past the content box clips the text rather than growing the window.
