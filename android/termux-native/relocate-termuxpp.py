#!/usr/bin/env python3
"""Relocate a staged generation before hashing/signing, never a signed archive."""

import os
from pathlib import Path
import sys

OLD = b"/data/data/com.termux"
NEW = b"/data/data/dev.pschmitt.termux"


def relocate(root):
    for directory, directories, files in os.walk(root, followlinks=False):
        for name in directories + files:
            path = Path(directory) / name
            if path.is_symlink():
                target = os.readlink(path)
                replacement = target.replace(OLD.decode(), NEW.decode())
                if replacement != target:
                    path.unlink()
                    path.symlink_to(replacement)
            elif path.is_file():
                data = path.read_bytes()
                if b"\0" in data:
                    continue
                try:
                    data.decode("utf-8")
                except UnicodeDecodeError:
                    continue
                replacement = data.replace(OLD, NEW)
                if path.relative_to(root).as_posix() == "home/.config/nixpp/config.toml":
                    replacement = replacement.replace(b"termux-native-", b"termuxpp-native-")
                if replacement != data:
                    mode = path.stat().st_mode
                    path.chmod(mode | 0o200)
                    path.write_bytes(replacement)
                    path.chmod(mode)


if __name__ == "__main__":
    relocate(Path(sys.argv[1]))
