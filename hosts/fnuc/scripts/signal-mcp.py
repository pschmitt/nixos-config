"""Send Signal messages through a signal-cli JSON-RPC daemon.

Send and look-up only: the daemon belongs to the Hermes gateway, which
receives with it, so this server never consumes incoming messages.
"""

import argparse
import itertools
import json
import urllib.error
import urllib.request

from mcp.server.fastmcp import FastMCP

ap = argparse.ArgumentParser()
ap.add_argument("--url", required=True, help="signal-cli daemon base URL")
args = ap.parse_args()

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


@mcp.tool()
def send_message(message: str, recipient: str = "", group_id: str = "") -> str:
    """Send a Signal message from the bot account.

    Give either `recipient` (phone number in +E.164 form, or a UUID) or
    `group_id` (from list_groups). Messages leave as the Hermes bot account.
    """
    if bool(recipient) == bool(group_id):
        raise ValueError("pass exactly one of recipient or group_id")
    params = {"message": message}
    if group_id:
        params["groupId"] = group_id
    else:
        params["recipient"] = [recipient]
    result = rpc("send", params)
    return json.dumps(result)


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
