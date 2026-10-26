# /// script
# requires-python = ">=3.9"
# dependencies = [
#   "wcwidth",
# ]
# ///
import argparse
import re
import sys
from wcwidth import wcswidth

# Custom mapping of background color names (including dim variants)
BG_COLORS = {
    "black": "\033[40m",
    "red": "\033[41m",
    "green": "\033[42m",
    "yellow": "\033[43m",
    "blue": "\033[44m",
    "magenta": "\033[45m",
    "cyan": "\033[46m",
    "white": "\033[47m",
    # Dim variants using 256-color escape codes for a darker shade.
    "dimblack": "\033[48;5;234m",
    "dimred": "\033[48;5;52m",
    "dimgreen": "\033[48;5;22m",
    "dimyellow": "\033[48;5;94m",
    "dimblue": "\033[48;5;17m",
    "dimmagenta": "\033[48;5;90m",
    "dimcyan": "\033[48;5;23m",
    "dimwhite": "\033[48;5;252m",
}

RESET = "\033[00m"

# Regex to match ANSI reset sequences
RESET_PATTERN = re.compile(r"\033\[[0;]*0m")


def get_bg_ansi(color):
    # Accept color names like "red" or "dimred" (without a prefix).
    return BG_COLORS.get(color.lower(), BG_COLORS["black"])


def remove_ansi_escape_sequences(text):
    ansi_escape = re.compile(r"\x1B[@-_][0-?]*[ -/]*[@-~]")
    return ansi_escape.sub("", text)


def remove_bg_escape_sequences(text):
    bg_escape = re.compile(r"\x1b\[(?:4[0-7]|48;[0-9;]+)m")
    return bg_escape.sub("", text)


def patch_resets(line, bg_ansi):
    """
    Replace every RESET sequence with itself immediately followed by bg_ansi.
    """
    return RESET_PATTERN.sub(lambda m: m.group(0) + bg_ansi, line)


def zebra_colorize(
    input_lines,
    debug=False,
    color="black",
    force=False,
    ignore_header=False,
    ignore_footer=False,
):
    # Expand tabs in all lines so that TABs are converted to spaces.
    expanded = [line.expandtabs() for line in input_lines]

    header = None
    footer = None
    content = expanded[:]
    if ignore_header and content:
        header = content[0].rstrip("\n")
        content = content[1:]
    if ignore_footer and content:
        footer = content[-1].rstrip("\n")
        content = content[:-1]

    if force:
        content = [remove_bg_escape_sequences(line) for line in content]
        if header is not None:
            header = remove_bg_escape_sequences(header)
        if footer is not None:
            footer = remove_bg_escape_sequences(footer)

    bg_ansi = get_bg_ansi(color)

    # Prepare a list of all lines to be considered for width calculation.
    candidates = []
    if header is not None:
        candidates.append(header)
    candidates.extend([line.rstrip("\n") for line in content])
    if footer is not None:
        candidates.append(footer)

    max_width = max(
        (wcswidth(remove_ansi_escape_sequences(line)) for line in candidates), default=0
    )

    # Pad header, content lines, and footer to the same visible width.
    def pad_line(line):
        line = line.rstrip("\n")
        visible = wcswidth(remove_ansi_escape_sequences(line))
        padding = max_width - visible
        return line + (" " * padding)

    if header is not None:
        header = pad_line(header)
    content = [pad_line(line) for line in content]
    if footer is not None:
        footer = pad_line(footer)

    # If debug is enabled, replace the padding spaces with "x" characters.
    if debug:

        def debug_pad(line):
            stripped = remove_ansi_escape_sequences(line)
            current = len(stripped)
            pad = max_width - current
            return line.rstrip() + ("x" * pad)

        if header is not None:
            header = debug_pad(header)
        content = [debug_pad(line) for line in content]
        if footer is not None:
            footer = debug_pad(footer)

    # For zebra lines (every second content line), patch resets so the background sticks.
    zebra_content = []
    for i, line in enumerate(content):
        if i % 2 == 1:
            fixed_line = patch_resets(line, bg_ansi)
            zebra_content.append(bg_ansi + fixed_line + RESET)
        else:
            zebra_content.append(line)

    # Print header, then content, then footer.
    if header is not None:
        print(header)
    for line in zebra_content:
        print(line)
    if footer is not None:
        print(footer)


def main():
    parser = argparse.ArgumentParser(description="Zebra-colorize input lines.")
    parser.add_argument(
        "--debug", action="store_true", help='Show padding with "x" characters.'
    )
    parser.add_argument(
        "--color",
        type=str,
        default="black",
        help="Background color for zebra lines (e.g. red, blue, dimred, etc.).",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Strip background ANSI escapes from input so that the applied color is enforced.",
    )
    parser.add_argument(
        "-H",
        "--ignore-header",
        action="store_true",
        help="Ignore the first line (print it unchanged, but still pad it).",
    )
    parser.add_argument(
        "-F",
        "--ignore-footer",
        action="store_true",
        help="Ignore the last line (print it unchanged, but still pad it).",
    )
    args = parser.parse_args()

    input_lines = sys.stdin.readlines()
    zebra_colorize(
        input_lines,
        debug=args.debug,
        color=args.color,
        force=args.force,
        ignore_header=args.ignore_header,
        ignore_footer=args.ignore_footer,
    )


if __name__ == "__main__":
    main()

# vim: set ft=python :
