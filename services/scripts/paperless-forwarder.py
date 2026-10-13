"""Forward new documents from a library tree into the Paperless consume dir.

Paperless deletes whatever it consumes, so mirroring a library into the
consume dir re-feeds everything on every sync restart. Instead, remember
every file (path, size, mtime, sha256) and forward a file only once: when
it is new or changed and its content has never been seen before.

The first run needs --init: it records the current tree as already imported
without forwarding anything.

Only the top-level folder is kept (`Banking/x/y.pdf` -> `Banking/y.pdf`), so
with PAPERLESS_CONSUMER_SUBDIRS_AS_TAGS the top-level folder becomes a tag.
"""

import argparse
import hashlib
import json
import os
import pathlib
import shutil
import sys
import time


def log(msg):
    print(msg, flush=True)


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def load_state(path):
    try:
        with open(path) as f:
            state = json.load(f)
    except FileNotFoundError:
        return None
    return {"files": state["files"], "hashes": set(state["hashes"])}


def save_state(path, state):
    tmp = path.with_suffix(".tmp")
    with open(tmp, "w") as f:
        json.dump(
            {"files": state["files"], "hashes": sorted(state["hashes"])},
            f,
        )
    os.replace(tmp, path)


def walk(source, excludes, extensions):
    for root, dirs, files in os.walk(source):
        rel_root = pathlib.Path(root).relative_to(source)
        dirs[:] = sorted(
            d
            for d in dirs
            if not d.startswith(".") and str(rel_root / d) not in excludes
        )
        for name in sorted(files):
            if name.startswith((".", "~$")):
                continue
            if pathlib.Path(name).suffix.lower().lstrip(".") not in extensions:
                continue
            yield rel_root / name


def destination(consume, rel):
    parts = rel.parts
    target_dir = consume / parts[0] if len(parts) > 1 else consume
    target = target_dir / rel.name
    n = 1
    while target.exists():
        target = target_dir / f"{rel.stem}.{n}{rel.suffix}"
        n += 1
    return target


def forward(src, target, staging):
    staging.mkdir(parents=True, exist_ok=True)
    tmp = staging / f"{os.getpid()}-{target.name}"
    try:
        shutil.copyfile(src, tmp)
        target.parent.mkdir(parents=True, exist_ok=True)
        # Rename so Paperless never sees a partially written file.
        os.replace(tmp, target)
    finally:
        tmp.unlink(missing_ok=True)


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--source", type=pathlib.Path, required=True)
    p.add_argument("--consume", type=pathlib.Path, required=True)
    p.add_argument("--staging", type=pathlib.Path, required=True)
    p.add_argument("--state", type=pathlib.Path, required=True)
    p.add_argument("--exclude", action="append", default=[])
    p.add_argument("--extensions", default="pdf,png,jpg,jpeg,tif,tiff,gif,webp,heic")
    p.add_argument("--min-age", type=int, default=60, help="skip files modified within this many seconds")
    p.add_argument("--init", action="store_true", help="record the current tree without forwarding")
    p.add_argument("--dry-run", action="store_true")
    args = p.parse_args()

    state = load_state(args.state)
    if state is None:
        if not args.init:
            log(f"no state at {args.state}; run once with --init")
            return 1
        state = {"files": {}, "hashes": set()}
    elif args.init:
        log(f"state already exists at {args.state}; refusing --init")
        return 1

    extensions = set(args.extensions.lower().split(","))
    now = time.time()
    seen = {}
    forwarded = recorded = failed = 0

    for rel in walk(args.source, set(args.exclude), extensions):
        src = args.source / rel
        try:
            st = src.stat()
        except FileNotFoundError:
            continue
        if now - st.st_mtime < args.min_age:
            continue

        key = str(rel)
        prev = state["files"].get(key)
        if prev and prev[0] == st.st_size and prev[1] == st.st_mtime_ns:
            seen[key] = prev
            continue

        try:
            digest = sha256(src)
        except OSError as e:
            # Not recorded, so it is retried on the next run.
            log(f"skip {key}: {e}")
            continue
        seen[key] = [st.st_size, st.st_mtime_ns, digest]
        if args.init or digest in state["hashes"]:
            recorded += 1
        else:
            target = destination(args.consume, rel)
            log(f"forward {key} -> {target.relative_to(args.consume)}")
            if not args.dry_run:
                try:
                    forward(src, target, args.staging)
                except OSError as e:
                    # Not recorded, so it is retried on the next run.
                    log(f"failed {key}: {e}")
                    seen.pop(key)
                    failed += 1
                    continue
            forwarded += 1
        state["hashes"].add(digest)

    state["files"] = seen
    log(f"{len(seen)} files tracked, {forwarded} forwarded, {recorded} recorded without forwarding, {failed} failed")
    if not args.dry_run:
        args.state.parent.mkdir(parents=True, exist_ok=True)
        save_state(args.state, state)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
