"""Send Signal messages through a signal-cli JSON-RPC daemon.

Send, reply, react, edit, delete and look-up only: the daemon belongs to the
Hermes gateway, which receives with it, so this server never consumes incoming
messages. Replies, reactions, edits and deletes therefore target messages by
the timestamp send_message returned (or one the user hands over).
"""

import argparse
import base64
import itertools
import json
import mimetypes
import pathlib
import re
import urllib.error
import urllib.request

from mcp.server.mcpserver import MCPServer

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

mcp = MCPServer("signal")
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


# (marker, signal style, literal): longest markers first
MARKERS = (
    ("```", "MONOSPACE", True),
    ("**", "BOLD", False),
    ("~~", "STRIKETHROUGH", False),
    ("||", "SPOILER", False),
    ("`", "MONOSPACE", True),
    ("*", "ITALIC", False),
)
ESCAPABLE = "*~|`"


def utf16_len(text):
    return len(text.encode("utf-16-le")) // 2


def style_markup(text):
    """Turn Markdown-ish markers into Signal text styles.

    **bold**, *italic*, ~~strikethrough~~, ||spoiler||, `monospace` and
    ```fenced monospace``` (Signal has no code block, only the monospace
    style). Styles nest; code is literal. A backslash escapes a marker
    character. Returns (plain text, ["start:length:STYLE", ...]) with offsets
    in UTF-16 code units, as signal-cli expects.
    """
    plain = []
    styles = []
    size = 0
    index = 0

    def emit(chunk):
        nonlocal size
        plain.append(chunk)
        size += utf16_len(chunk)

    while index < len(text):
        char = text[index]
        if char == "\\" and text[index + 1:index + 2] and text[index + 1] in ESCAPABLE:
            emit(text[index + 1])
            index += 2
            continue
        for marker, style, literal in MARKERS:
            if not text.startswith(marker, index):
                continue
            start = index + len(marker)
            end = text.find(marker, start)
            if end <= start:
                continue
            if not literal:
                # In a run like ***, the last two characters close **.
                while text.startswith(marker[0], end + len(marker)):
                    end += 1
            body = text[start:end]
            if not literal and (body[0].isspace() or body[-1].isspace()):
                continue
            if marker == "*" and index > 0 and text[index - 1].isalnum():
                continue
            if marker == "```":
                body = body.removeprefix("\n").removesuffix("\n")
                first, sep, rest = body.partition("\n")
                if sep and first.isidentifier():
                    body = rest
            begin = size
            if literal:
                emit(body)
                inner = []
            else:
                inner_plain, inner = style_markup(body)
                emit(inner_plain)
            styles.append(f"{begin}:{size - begin}:{style}")
            styles.extend(
                f"{begin + int(s.split(':')[0])}:{s.split(':', 1)[1]}" for s in inner
            )
            index = end + len(marker)
            break
        else:
            emit(char)
            index += 1
    return "".join(plain), styles


MENTION = re.compile(r"@\{([^}]+)\}")
PLACEHOLDER = "\ufffc"


def prepare_text(message, styled):
    """Split a message into (text, text styles, mentions).

    @{name} mentions someone (name: a list_recipients name, number or UUID);
    Signal wants a placeholder character at the mention's position.
    """
    names = MENTION.findall(message)
    text = MENTION.sub(PLACEHOLDER, message)
    styles = []
    if styled:
        text, styles = style_markup(text)
    mentions = []
    offset = 0
    for char in text:
        if char == PLACEHOLDER and len(mentions) < len(names):
            who = resolve_recipient(names[len(mentions)])
            mentions.append(f"{offset}:1:{who}")
        offset += utf16_len(char)
    return text, styles, mentions


def target(recipient, group_id):
    """The recipient or group part of a request, exactly one of them."""
    if bool(recipient) == bool(group_id):
        raise ValueError("pass exactly one of recipient or group_id")
    if group_id:
        return {"groupId": group_id}
    return {"recipient": [resolve_recipient(recipient)]}


def delivery(result):
    """Keep timestamp and status; the raw reply carries numbers and UUIDs."""
    result = result or {}
    return json.dumps(
        {
            "timestamp": result.get("timestamp"),
            "results": [r.get("type") for r in result.get("results", [])],
        }
    )


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
    quote_timestamp: int = 0,
    quote_author: str = "",
    quote_message: str = "",
    edit_timestamp: int = 0,
) -> str:
    """Send a Signal message from the bot account, optionally with files.

    Give either `recipient` (a name from list_recipients such as "me", a
    phone number in +E.164 form, or a UUID) or `group_id` (from list_groups).
    `attachments` are paths of files on this machine (images, PDFs, ...);
    `message` may be empty when sending files. With `format` (default),
    Markdown-ish markers become Signal text styles: **bold**, *italic*,
    ~~strikethrough~~, ||spoiler||, `monospace` and ```fenced monospace```
    (Signal has no real code block). Styles nest, code is literal, and a
    backslash escapes a marker. `@{name}` mentions someone (name as for
    `recipient`; shown as a highlighted @contact name, also in a 1:1 chat).
    Messages leave as the Hermes bot account.

    To reply to a message, pass `quote_timestamp` and `quote_author` (a name
    or number, `self` for the bot's own messages; `quote_message` is the
    quoted text, optional). To edit one of
    the bot's own messages, pass its timestamp as `edit_timestamp` together
    with the same recipient or group. The reply carries the new message's
    timestamp, which later replies, reactions, edits and deletes need.
    """
    if not message and not attachments:
        raise ValueError("pass a message, attachments, or both")
    params = target(recipient, group_id)
    text, styles, mentions = prepare_text(message, format)
    params["message"] = text
    if styles:
        params["textStyle"] = styles
    if mentions:
        params["mention"] = mentions
    if attachments:
        params["attachments"] = [data_uri(a) for a in attachments]
    if quote_timestamp:
        if not quote_author:
            raise ValueError("quote_timestamp needs quote_author")
        params["quoteTimestamp"] = quote_timestamp
        params["quoteAuthor"] = resolve_recipient(quote_author)
        if quote_message:
            params["quoteMessage"] = quote_message
    if edit_timestamp:
        params["editTimestamp"] = edit_timestamp
    return delivery(rpc("send", params))


@mcp.tool()
def react(
    emoji: str,
    target_author: str,
    target_timestamp: int,
    recipient: str = "",
    group_id: str = "",
    remove: bool = False,
) -> str:
    """React to a message with an emoji (or remove the reaction).

    `target_author` (a name or number, `self` for the bot's own messages) and
    `target_timestamp` identify the message; send to the same `recipient` or `group_id` the message is in.
    """
    params = target(recipient, group_id)
    params.update(
        emoji=emoji,
        targetAuthor=resolve_recipient(target_author),
        targetTimestamp=target_timestamp,
    )
    if remove:
        params["remove"] = True
    return delivery(rpc("sendReaction", params))


@mcp.tool()
def delete_message(
    target_timestamp: int, recipient: str = "", group_id: str = ""
) -> str:
    """Delete one of the bot's own messages for everyone.

    `target_timestamp` is the timestamp send_message returned; use the same
    `recipient` or `group_id` it was sent to.
    """
    params = target(recipient, group_id)
    params["targetTimestamp"] = target_timestamp
    return delivery(rpc("remoteDelete", params))


@mcp.tool()
def list_recipients() -> list:
    """List the names usable as recipient or author: me, self (the bot), ..."""
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
