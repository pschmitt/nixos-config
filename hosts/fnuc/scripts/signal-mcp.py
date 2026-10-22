"""Send Signal messages through a signal-cli JSON-RPC daemon.

Send and look-up only: the daemon belongs to the Hermes gateway, which
receives with it, so this server never consumes incoming messages.
"""

import argparse
import base64
import itertools
import json
import mimetypes
import pathlib
import urllib.error
import urllib.request

from mcp.server.fastmcp import FastMCP

ap = argparse.ArgumentParser()
ap.add_argument("--url", required=True, help="signal-cli daemon base URL")
ap.add_argument(
    "--recipient",
    action="append",
    default=[],
    metavar="ALIAS=FILE",
    help="name a recipient whose number is read from FILE on each use",
)
args = ap.parse_args()
aliases = dict(r.split("=", 1) for r in args.recipient)

mcp = FastMCP("signal")
ids = itertools.count(1)


def rpc(method, params=None):
    body = {"jsonrpc": "2.0", "id": next(ids), "method": method}
    if params:
        body["params"] = params
    req = urllib.request.Request(
        args.url.rstrip("/") + "/api/v1/rpc",
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            payload = json.load(resp)
    except urllib.error.URLError as exc:
        raise RuntimeError(f"signal-cli daemon unreachable: {exc}") from exc
    if "error" in payload:
        raise RuntimeError(payload["error"].get("message", str(payload["error"])))
    return payload.get("result")


def resolve_recipient(recipient):
    """Map an alias to its number; anything else is passed through."""
    if recipient in aliases:
        return pathlib.Path(aliases[recipient]).read_text().strip()
    return recipient


def style_markup(text):
    """Turn **bold** and *italic* markers into Signal text styles."""
    plain = []
    styles = []
    index = 0
    while index < len(text):
        if text.startswith("**", index):
            marker, style = "**", "BOLD"
        elif text.startswith("*", index):
            marker, style = "*", "ITALIC"
        else:
            plain.append(text[index])
            index += 1
            continue
        start = index + len(marker)
        end = text.find(marker, start)
        if end <= start:
            plain.append(text[index])
            index += 1
            continue
        body = text[start:end]
        offset = len("".join(plain).encode("utf-16-le")) // 2
        length = len(body.encode("utf-16-le")) // 2
        styles.append(f"{offset}:{length}:{style}")
        plain.append(body)
        index = end + len(marker)
    return "".join(plain), styles


def data_uri(path):
    """Inline a local file: the daemon runs on another host and cannot read it."""
    file = pathlib.Path(path).expanduser()
    if not file.is_file():
        raise ValueError(f"attachment not found: {path}")
    mime = mimetypes.guess_type(file.name)[0] or "application/octet-stream"
    data = base64.b64encode(file.read_bytes()).decode()
    return f"data:{mime};filename={file.name};base64,{data}"


@mcp.tool()
def send_message(
    message: str = "",
    recipient: str = "",
    group_id: str = "",
    attachments: list[str] | None = None,
    format: bool = True,
) -> str:
    """Send a Signal message from the bot account, optionally with files.

    Give either `recipient` (a name from list_recipients such as "me", a
    phone number in +E.164 form, or a UUID) or `group_id` (from list_groups).
    `attachments` are paths of files on this machine (images, PDFs, ...);
    `message` may be empty when sending files. With `format`, **bold** and
    *italic* markers become Signal text styles. Messages leave as the Hermes
    bot account.
    """
    if bool(recipient) == bool(group_id):
        raise ValueError("pass exactly one of recipient or group_id")
    if not message and not attachments:
        raise ValueError("pass a message, attachments, or both")
    params = {"message": message}
    if format and message:
        params["message"], styles = style_markup(message)
        if styles:
            params["textStyle"] = styles
    if attachments:
        params["attachments"] = [data_uri(a) for a in attachments]
    if group_id:
        params["groupId"] = group_id
    else:
        params["recipient"] = [resolve_recipient(recipient)]
    result = rpc("send", params) or {}
    # The raw reply carries the recipients' numbers and UUIDs; keep only the
    # delivery status.
    return json.dumps(
        {
            "timestamp": result.get("timestamp"),
            "results": [r.get("type") for r in result.get("results", [])],
        }
    )


@mcp.tool()
def list_recipients() -> list:
    """List the recipient names usable as `recipient` in send_message."""
    return sorted(aliases)


@mcp.tool()
def list_groups() -> list:
    """List the groups the bot account is a member of (id, name, member count)."""
    return [
        {
            "id": g["id"],
            "name": g.get("name"),
            "members": len(g.get("members", [])),
            "isMember": g.get("isMember"),
        }
        for g in rpc("listGroups") or []
    ]


@mcp.tool()
def list_contacts() -> list:
    """List the bot account's contacts (number, uuid, name)."""
    return [
        {
            "number": c.get("number"),
            "uuid": c.get("uuid"),
            "name": c.get("name") or c.get("profile", {}).get("givenName"),
        }
        for c in rpc("listContacts") or []
    ]


if __name__ == "__main__":
    mcp.run()
