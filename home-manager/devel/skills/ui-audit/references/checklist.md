# UI audit checklist

What to look for, how it shows in the script output, and the usual fix.

## Things that move

| Symptom | How it shows | Usual fix |
| --- | --- | --- |
| Content jumps sideways between pages or after load | layout-shift sources move about 15px in x; some pages have a scrollbar and others not | `html { scrollbar-gutter: stable; }` |
| Title and actions land somewhere new on every page | H1 `x`/`y` and `contentW` differ per route | one page-header component; 2 or 3 container widths; one alignment |
| Headline size differs per page | H1 `fs` varies | one size per page type |
| A column pops in late | layout-shift entries for a side column | reserve its space (min-height, skeleton) |
| Buttons lift on hover in some places only | hover result `moves -2.0px` | drop the lift or use it everywhere |

## Button system

- Group `sigs` by role (primary, secondary, ghost, danger). More than one signature per role is drift: different height, radius, weight, padding, border or text colour.
- The same class rendering differently on two pages means page-level overrides.
- Destructive actions not in the danger style (for example a blue "Remove"), or a danger button more prominent than the primary next to it.
- `NO hover feedback` on most buttons, or a low `hoverRules` count.
- `focusMissing` not empty: keyboard focus is invisible there.
- Fix: one Button component with variant and size props, shared icon slot, 44px or more, one radius token, all states (hover, active, focus-visible, disabled); delete the per-feature button CSS.

## Wrapping and deformed controls

- `tall` buttons (more than 52px high): the label wrapped. In a row, a long sibling text squeezed the button; fix with `flex-shrink: 0; white-space: nowrap` on actions and `min-width: 0; overflow-wrap: anywhere` on the text.
- Header actions that wrap under a long title: put the actions on their own row, or move rare actions into a menu.
- Segmented controls with uneven items on mobile.
- Adjacent buttons with different heights.

## Placement and consistency

- Sibling entities (for example projects and yarns) should share: back link wording and glyph, eyebrow style, where Edit, Delete and Favourite sit, read vs edit mode for media, Cancel on forms, card padding.
- Two back controls (app header and page) at once.
- Destructive actions on read pages, or Delete right next to Save.
- Long forms with the only Save at the bottom: sticky action bar.
- Two action areas on one page (toolbar above the title and buttons beside it).

## Forms

- Input heights, radii and font sizes from `inputs`; one token each.
- Inputs under 16px font make iOS Safari zoom on focus.
- Unstyled native controls: monospace textarea, "Choose File" inputs.
- Picker UIs that list the same items twice (available and selected).

## Layout

- Multi-column detail pages where one column is much taller: the short column leaves an empty strip. Make it sticky or move to one reading column (about 70 characters) with a summary row.
- The same content rendered twice on one page.
- Nested cards on mobile that leave less than about 35 characters per line.
- Mobile forms that keep a desktop grid and truncate selects and placeholders.
