#!/usr/bin/env python3
"""Supply a fresh GitHub OIDC token directly to the niks3 client."""

import base64
import datetime
import json
import os
import sys
import urllib.parse
import urllib.request


def main():
    url = os.environ["ACTIONS_ID_TOKEN_REQUEST_URL"]
    separator = "&" if "?" in url else "?"
    url += separator + urllib.parse.urlencode(
        {"audience": os.environ["NIKS3_SERVER_URL"]}
    )
    request = urllib.request.Request(
        url,
        headers={
            "Authorization": "Bearer " + os.environ["ACTIONS_ID_TOKEN_REQUEST_TOKEN"]
        },
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        token = json.load(response)["value"]
    # stdout is consumed by niks3's token helper, never by a workflow log step.
    payload = token.split(".")[1]
    claims = json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)))
    expires = datetime.datetime.fromtimestamp(
        claims["exp"], datetime.timezone.utc
    ).isoformat()
    json.dump({"token": token, "expires_at": expires}, sys.stdout)


if __name__ == "__main__":
    main()
