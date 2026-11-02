#!/usr/bin/env python3
"""Request phone approval for rbw unlock without exposing the webhook URL."""

from __future__ import annotations

import argparse
import json
import math
import os
import socket
import subprocess
import sys
import time
from pathlib import Path
from urllib.parse import urlsplit
from urllib.request import Request, urlopen

MAX_TIMEOUT = 3600.0
REQUEST_TIMEOUT = 10.0
POLL_INTERVAL = 2.0


class UnlockError(Exception):
    """An expected, safely reportable failure."""


def _is_unlocked(timeout: float = REQUEST_TIMEOUT) -> bool:
    try:
        result = subprocess.run(
            ["rbw", "unlocked"],
            capture_output=True,
            check=False,
            text=True,
            timeout=timeout,
        )
    except (OSError, subprocess.TimeoutExpired):
        return False
    return result.returncode == 0


def _read_endpoint() -> str:
    endpoint_file = os.environ.get("RBW_UNLOCK_WEBHOOK_URL_FILE")
    if not endpoint_file:
        raise UnlockError("webhook endpoint file is not configured")

    try:
        path = Path(endpoint_file)
        if path.stat().st_mode & 0o077:
            raise UnlockError("webhook endpoint file permissions are too broad")
        endpoint = path.read_text(encoding="utf-8").strip()
    except (OSError, UnicodeError):
        raise UnlockError("webhook endpoint file is unreadable") from None

    try:
        parsed = urlsplit(endpoint)
        valid = (
            parsed.scheme.lower() in {"http", "https"}
            and bool(parsed.hostname)
            and parsed.username is None
            and parsed.password is None
        )
        # Accessing .port also validates malformed port numbers.
        _ = parsed.port
    except ValueError:
        valid = False

    if not endpoint or not valid:
        raise UnlockError("webhook endpoint file must contain a valid HTTP(S) URL")
    return endpoint


def _request_unlock(endpoint: str, agent: str) -> None:
    payload = json.dumps(
        {"host": socket.gethostname().split(".")[0], "agent": agent}
    ).encode("utf-8")
    try:
        request = Request(
            endpoint,
            data=payload,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urlopen(request, timeout=REQUEST_TIMEOUT):
            pass
    except Exception:
        raise UnlockError("unlock notification failed") from None


def _wait_for_unlock(timeout: float) -> bool:
    deadline = time.monotonic() + timeout
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            return False
        if _is_unlocked(timeout=min(REQUEST_TIMEOUT, remaining)):
            return True
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            return False
        time.sleep(min(POLL_INTERVAL, remaining))


def _parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(prog="rbw-request-unlock")
    parser.add_argument(
        "--agent", default="AI agent", help="label shown in the approval request"
    )
    parser.add_argument(
        "--timeout", type=float, default=300.0, help="maximum wait in seconds (1–3600)"
    )
    args = parser.parse_args(argv)
    if not math.isfinite(args.timeout) or not 0 < args.timeout <= MAX_TIMEOUT:
        parser.error("--timeout must be finite and greater than 0 and at most 3600 seconds")
    return args


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(argv)

    if _is_unlocked():
        print("rbw is already unlocked")
        return 0

    try:
        endpoint = _read_endpoint()
        _request_unlock(endpoint, args.agent)
    except UnlockError as error:
        print(str(error), file=sys.stderr)
        return 1

    print("Unlock approval requested; waiting for rbw…")
    if _wait_for_unlock(args.timeout):
        print("rbw is unlocked")
        return 0

    print("Timed out waiting for rbw unlock", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
