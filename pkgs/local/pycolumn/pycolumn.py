# /// script
# requires-python = ">=3.9"
# dependencies = [
#   "regex",
#   "wcwidth",
# ]
# ///
from __future__ import annotations

import argparse
import re
import sys
from typing import List

import wcwidth

ANSI_CSI_RE = re.compile(r"\x1B[@-_][0-?]*[ -/]*[@-~]")
ANSI_OSC8_RE = re.compile(r"\x1B]8;;.*?(?:\x07|\x1B\\)")


def strip_ansi(text: str) -> str:
    """Remove OSC8 hyperlinks and general ANSI escape sequences."""
    text = ANSI_OSC8_RE.sub("", text)
    text = ANSI_CSI_RE.sub("", text)
    return text


def _is_emoji_cluster(cluster: str) -> bool:
    """Heuristic to detect emoji-like grapheme clusters."""
    if "\u200d" in cluster:  # ZWJ
        return True
    if "\ufe0f" in cluster:  # VS16 (emoji presentation)
        return True
    return any(
        0x1F000 <= ord(char) <= 0x1FAFF
        or 0x2600 <= ord(char) <= 0x27BF
        or 0x2300 <= ord(char) <= 0x23FF
        for char in cluster
    )


def _cluster_width(cluster: str) -> int:
    """Width of a single grapheme cluster."""
    w = wcwidth.wcswidth(cluster)
    if w < 0:
        w = 0
    if _is_emoji_cluster(cluster):
        # Most terminals render emoji clusters as double-width.
        return 2 if w < 2 else w
    return w


def visible_width(text: str) -> int:
    """Display width of text, measured by grapheme clusters."""
    clean = strip_ansi(text)
    return sum(_cluster_width(g) for g in wcwidth.iter_graphemes(clean))


def main() -> None:
    parser = argparse.ArgumentParser(description="Columnize input lines")
    parser.add_argument(
        "-s",
        "--separator",
        default="\t",
        type=str,  # input separator (split)
        help="Column separator to split lines (default: TAB)",
    )
    parser.add_argument(
        "-S",
        "--out-separator",
        default="  ",
        type=str,  # output separator (join)
        help="Column separator to join columns (default: two spaces)",
    )
    args = parser.parse_args()

    lines: List[str] = [line.rstrip("\n") for line in sys.stdin]
    if not lines:
        return

    # Split lines on the specified input separator.
    rows: List[List[str]] = [line.split(args.separator) for line in lines]
    ncols = max(len(row) for row in rows)

    # Ensure each row has the same number of columns.
    for row in rows:
        if len(row) < ncols:
            row.extend([""] * (ncols - len(row)))

    # First pass: determine maximum visible width for each column.
    max_widths = [0] * ncols
    for row in rows:
        for i, field in enumerate(row):
            w = visible_width(field)
            if w > max_widths[i]:
                max_widths[i] = w

    # Second pass: output each row, padding fields to the max width.
    for row in rows:
        out_fields: List[str] = []
        for i, field in enumerate(row):
            pad = max_widths[i] - visible_width(field)
            out_fields.append(str(field) + (" " * pad))
        print(args.out_separator.join(out_fields))


if __name__ == "__main__":
    main()

# vim: set ft=python :
