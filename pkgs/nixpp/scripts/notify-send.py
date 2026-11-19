"""Send desktop-style notifications through TermuxPP's Android notification API."""

import argparse
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys

PRIORITIES = {"low": "low", "normal": "default", "critical": "high"}
ICONS = {
    "dialog-error": "error",
    "dialog-information": "info",
    "dialog-warning": "warning",
    "dialog-question": "help",
}


def main():
    parser = argparse.ArgumentParser(description="Show an Android notification.", add_help=False)
    parser.add_argument("-a", "--app-name")
    parser.add_argument("-u", "--urgency", choices=PRIORITIES, default="normal")
    parser.add_argument("-t", "--expire-time", type=int, default=-1, metavar="MS")
    parser.add_argument("-i", "--icon", metavar="NAME_OR_IMAGE")
    parser.add_argument("-c", "--category")
    parser.add_argument("-h", "--hint", action="append", default=[], metavar="TYPE:NAME:VALUE")
    parser.add_argument("-p", "--print-id", action="store_true")
    parser.add_argument("-r", "--replace-id", type=int, metavar="ID")
    parser.add_argument("-e", "--transient", action="store_true")
    parser.add_argument("--help", "-?", action="help")
    parser.add_argument("-v", "--version", action="version", version="TermuxPP notify-send 1")
    parser.add_argument("summary")
    parser.add_argument("body", nargs="?", default="")
    args = parser.parse_args()

    if not -1 <= args.expire_time <= (2**31 - 1):
        parser.error("expire time must be -1, 0, or a positive number of milliseconds")
    if args.replace_id is not None and not 0 <= args.replace_id < 2**32:
        parser.error("replacement ID must be a non-negative 32-bit integer")

    defaults = json.loads(os.environ["TERMUXPP_NOTIFY_TIMEOUTS"])
    timeout = defaults[args.urgency] if args.expire_time == -1 else args.expire_time
    if args.transient and args.expire_time == -1 and timeout == 0:
        timeout = 7000
    notification_id = args.replace_id or (1 + secrets.randbelow(2**31 - 1))
    command = [
        os.environ["TERMUXPP_NOTIFICATION_API"], "Notification",
        "--es", "id", str(notification_id),
        "--es", "title", args.summary,
        "--es", "priority", PRIORITIES[args.urgency],
        "--es", "desktop-urgency", args.urgency,
        "--el", "timeout-ms", str(timeout),
    ]
    if args.app_name:
        command += ["--es", "app-name", args.app_name]
    if args.category:
        command += ["--es", "category", args.category.split(",", 1)[0]]

    image = None
    for hint in args.hint:
        try:
            hint_type, name, value = hint.split(":", 2)
        except ValueError:
            parser.error("hint must have the form TYPE:NAME:VALUE")
        if not hint_type or not name:
            parser.error("hint type and name are required")
        if hint_type == "string" and name in ("image-path", "image_path"):
            image = value
        if hint_type == "boolean" and name == "suppress-sound" and value.lower() in ("true", "1"):
            command += ["--ez", "silent", "true"]

    if args.icon:
        icon = Path(args.icon).expanduser()
        if icon.is_file() or "/" in args.icon:
            image = str(icon)
        else:
            name = ICONS.get(args.icon, args.icon.replace("-", "_"))
            command += ["--es", "icon", name]

    if image:
        try:
            path = Path(image).expanduser().resolve(strict=True)
            if not path.is_file():
                parser.error("icon path must point to a file")
            android_path = subprocess.check_output(
                [os.environ["TERMUXPP_ANDROID_PATH"], path], text=True
            ).removesuffix("\n")
        except (OSError, subprocess.CalledProcessError) as error:
            parser.error(f"cannot resolve icon path: {error}")
        command += ["--es", "large-icon-path", android_path]

    result = subprocess.run(command, input=args.body.encode(), check=False)
    if result.returncode == 0 and args.print_id:
        print(notification_id)
    return result.returncode


if __name__ == "__main__":
    sys.exit(main())
