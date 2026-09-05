"""Minimal, stdlib-only Syncthing REST and Events API client."""

from __future__ import annotations

import json
import ssl
from typing import Any, Callable
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

from .discovery import Endpoint, Folder
from .model import FolderSnapshot


class SyncthingUnavailable(RuntimeError):
    """The local API is unavailable, unauthorised, or returned invalid JSON."""


class SyncthingClient:
    PAGE_SIZE = 1024

    def __init__(
        self,
        endpoint: Endpoint,
        *,
        opener: Callable[..., Any] = urlopen,
    ) -> None:
        self.endpoint = endpoint
        self._opener = opener
        self._ssl_context = (
            ssl.create_default_context(cafile=str(endpoint.certificate)) if endpoint.certificate else None
        )

    def _json(self, endpoint: str, params: dict[str, Any] | None = None, *, timeout: float = 3.0) -> Any:
        url = f"{self.endpoint.url}{endpoint}"
        if params:
            url = f"{url}?{urlencode(params)}"
        request = Request(url, headers={"Accept": "application/json", "X-API-Key": self.endpoint.api_key})
        try:
            with self._opener(request, timeout=timeout, context=self._ssl_context) as response:
                payload = response.read().decode("utf-8")
            return json.loads(payload)
        except (HTTPError, URLError, TimeoutError, OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
            raise SyncthingUnavailable(type(error).__name__) from error

    def folder_snapshot(self, folder: Folder) -> FolderSnapshot:
        status = self._json("/rest/db/status", {"folder": folder.id})
        need = self._json("/rest/db/need", {"folder": folder.id, "page": 1, "perpage": self.PAGE_SIZE})
        errors = self._json("/rest/folder/errors", {"folder": folder.id, "page": 1, "perpage": self.PAGE_SIZE})
        if not all(isinstance(value, dict) for value in (status, need, errors)):
            raise SyncthingUnavailable("unexpected API response")
        return FolderSnapshot.from_api(status, need, errors, page_size=self.PAGE_SIZE)

    def events(self, since: int) -> list[dict[str, Any]]:
        events = self._json("/rest/events", {"since": since, "timeout": 45}, timeout=50.0)
        if not isinstance(events, list) or not all(isinstance(event, dict) for event in events):
            raise SyncthingUnavailable("unexpected event response")
        return events
