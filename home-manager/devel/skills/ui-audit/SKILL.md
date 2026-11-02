---
name: ui-audit
description: Review the usability, layout and visual consistency of a running web app with measurements instead of impressions - button and input variants, page-header and container drift, layout shift, hover and focus states, wrapping labels, mobile layout and vertical space, busy pages, navigation, and save/error feedback. Use when asked to review, audit, critique or simplify a web UI or a redesign, or when the user says pages are busy or cluttered, buttons shift around, are placed oddly, are styled inconsistently, or that saving gives no visible feedback.
---

# UI audit

Look at the real app with real data and measure it. A screenshot shows that something feels off; computed styles and bounding boxes show what exactly, and give the implementer numbers to act on.

## Before you start

- Load `browser-daemon` (and `browser-login` for the sign-in). Sign in with `browser_fill_secret`; search the vault with the rbw `search` tool by domain. An agent account with an empty library shows only empty states: use an account with real content, and stay read-only on it.
- Read-only means: never submit a form, never click Save, Delete, Remove, Revoke or Disable. Navigating, hovering, tabbing and resizing are fine.
- The feedback step needs writes: do them only as a throwaway or agent account, on records you create for the test and name recognisably (for example "UX test (agent) - delete me"). Check the name before every delete, and delete them all at the end.
- If another agent owns the code (check Concord `inspect_work`), review only and send it the findings; do not edit its files.

## Workflow

1. **Collect the routes.** Start from the nav and the list pages and collect detail, edit and new routes with a `browser_evaluate` over `a[href]`. Include at least: each list, one detail page with long content, one with a long title, each edit and new form, settings/account, admin.
2. **Inventory** ([references/inventory.js](references/inventory.js)): set `BASE` and `ROUTES` at the top, then pass the whole file as `code` to `browser_run_code_unsafe` (paste it; the tool's `filename` resolves on the browser node, not here). It visits every route at 1440x900 and 390x844 and returns:
   - `sigs`: every distinct button style (background, colour, border, radius, height, font size and weight, padding) with the buttons that use it. Many signatures for one role = a fragmented button system.
   - per page: H1 position and size, heading sizes, input height/radius/font size, container radii, content widths, and every button with class, position and size. Buttons much taller than 44-48px have wrapped labels.
3. **Motion and states** ([references/motion.js](references/motion.js)), same way, at desktop width: layout-shift entries with the elements that moved, which buttons change on hover (full computed-style diff) and whether focus is visible.
4. **Density** ([references/density.js](references/density.js)), same way: per route at phone and desktop width, where the first content item starts, how many controls and words come before it, the fixed chrome share, and an itemised list of everything above the content. This is the measure for "busy" pages and wasted vertical space.
5. **Look at the outliers.** Take viewport screenshots of whatever the numbers flag: wrapped buttons, odd positions, long titles, the bottom of long forms, the phone layout.
6. **Navigation:** test the back controls and the header as described in the checklist (deep link in a new tab, side paths, top-level pages; spacing of chevron, logo and title). Navigation only, no clicks on actions.
7. **Feedback** ([references/feedback.js](references/feedback.js)) on a test record: success, simulated server error, offline, and slow save with a double click. It reports whether messages are inside the viewport, where focus lands and how many writes went out. Then walk create, save and delete for each entity and note where each lands and what it says.
8. **Compare sibling pages** (for example projects vs yarns): back links, eyebrows, where Edit, Delete and Favourite sit, read vs edit mode for photos, Cancel on forms, card padding, confirmation dialogs.
9. **Report** grouped by cause, most impactful first, each with measured values and a concrete fix, then a suggested fix order. See [the checklist](references/checklist.md) for what to look for and the usual fixes.

## Pitfalls

- **Full-page screenshots** of app shells with a sticky sidebar or header come out broken (the rail appears halfway down the page). Use viewport screenshots and scroll instead.
- **Which element scrolls:** `window.scrollTo` may do nothing when an inner element scrolls, and a hash in the URL (for example `#step-3`) can land you mid-page. Find the scroller with `[...document.querySelectorAll('*')].filter(e => e.scrollTop > 0)`.
- **After `browser_resize`**, the first screenshot is sometimes blank or misplaced. Navigate or reload once before you trust it.
- **Headless desktop Chromium** shows a 15px classic scrollbar even at 390px; an `overflow` of -15 is that scrollbar, not a bug. A 15px horizontal jump of header items in layout-shift entries means the scrollbar appeared after load (fix: `scrollbar-gutter: stable`).
- **Hover:** compare the full computed style, not only the background; colour, border or filter changes count. The script does this.
- **Dirty forms block the browser MCP:** a page left with unsaved changes fires `beforeunload` on the next navigation, the MCP reports a modal state, and every later call on that page fails. Do writes in tabs from `page.context().newPage()` and close them with `close({ runBeforeUnload: false })`; if the main page is stuck, `browser_use` starts a fresh browser (sign in again).
- **Data vs design:** imported or messy data (wrong types, raw `&nbsp;`, Markdown in plain text) makes a design look worse. Report it separately so it is not blamed on the layout.
