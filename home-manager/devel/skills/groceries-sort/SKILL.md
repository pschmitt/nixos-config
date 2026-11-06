---
name: groceries-sort
description: Sort the Todoist grocery list "🛒 Groceries" in walking order through the supermarket and remove duplicate items. Use when the user asks to sort, order or tidy the groceries / Einkaufsliste / shopping list in Todoist.
---

# groceries-sort

Project: **🛒 Groceries** (id `6Crcx5cJrWQ6w4cG`), shared. Tasks are German, prefixed with an emoji.

## Rules

- Only touch tasks **without a `sectionId`**. Sections (🟨 Lidl, 🟧 Rossmann, 🟥 REWE, 🇰🇷 korea, 🇸🇪 IKEA) are per-store lists: leave their tasks alone.
- **Deduplication**: Remove duplicate items across the unsectioned list using `delete-object` (keep the older task, delete the newer duplicate). Do not merge or rename items.
- Order: **Brot / Backwaren first** (first thing one sees upon entering), followed by **Obst & Gemüse**, then keep items together in walking order through the supermarket:
  1. Brot / Backwaren (Brot, Brötchen, Baguette, ...)
  2. Obst & Gemüse (Äpfel, Zitronen, Tomaten, Gurken, Frühlingszwiebeln, ...)
  3. Kühlregal: Tofu, Käse, Milchprodukte, Eier, frische Pasta
  4. Trockenware: Nudeln, Reis, Gnocchi, Mehl
  5. Konserven (Sardinen, ...)
  6. Öl, Essig, Soßen
  7. Gewürze (Kurkuma, Kümmel, ...)
  8. Süßes / Backzutaten / Snacks (Schoki, Kakao Nibs)
  9. Nicht-Lebensmittel last (Tempoboxen, Haushalt)

## How

1. `find-tasks` with `projectId` and `limit: 100`; keep those without `sectionId`.
2. Find duplicates (case-insensitive item match) and remove extra copies using `delete-object` (`type: "task"`, `id: "<task_id>"`).
3. `update-tasks` with `{id, order}` for each remaining task, using consecutive numbers 1..N in the desired sequence (one call, max 25 per call).
4. Re-run `find-tasks` to verify: unsectioned tasks come back deduplicated and in the new order.
