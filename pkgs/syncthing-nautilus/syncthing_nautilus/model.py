"""Small, Nautilus-independent data model and status resolution."""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import StrEnum
import posixpath
from typing import Any, Iterable


class Status(StrEnum):
    SYNCED = "synced"
    SYNCING = "syncing"
    ERROR = "error"
    CONFLICT = "conflict"
    UNKNOWN = "unknown"


def normalise_relative_path(path: str) -> str:
    """Return a Syncthing-style relative path, with the folder root as ``""``."""
    normalised = posixpath.normpath(path.replace("\\", "/"))
    return "" if normalised in (".", "/") else normalised.lstrip("/")


def is_conflict_path(path: str) -> bool:
    """Recognise Syncthing's documented ``.sync-conflict-`` filename marker."""
    return ".sync-conflict-" in posixpath.basename(path)


def _contains_or_is_descendant(paths: Iterable[str], relative_path: str) -> bool:
    prefix = f"{relative_path}/" if relative_path else ""
    return any(path == relative_path or path.startswith(prefix) for path in paths)


@dataclass(frozen=True)
class FolderSnapshot:
    """A bounded, batched view of one folder's currently outstanding work."""

    need_paths: frozenset[str] = field(default_factory=frozenset)
    error_paths: frozenset[str] = field(default_factory=frozenset)
    need_total: int = 0
    receive_only_changed_total: int = 0
    pull_errors: int = 0
    state: str = "unknown"
    need_paths_truncated: bool = False
    error_paths_truncated: bool = False

    @classmethod
    def from_api(
        cls,
        status: dict[str, Any],
        need: dict[str, Any],
        errors: dict[str, Any],
        *,
        page_size: int,
    ) -> "FolderSnapshot":
        def paths_from(items: Iterable[Any], key: str) -> list[str]:
            return [
                normalise_relative_path(item[key])
                for item in items
                if isinstance(item, dict) and isinstance(item.get(key), str)
            ]

        need_items = [
            item
            for section in ("progress", "queued", "rest")
            for item in need.get(section, [])
            if isinstance(need.get(section, []), list)
        ]
        error_items = errors.get("errors", []) if isinstance(errors.get("errors", []), list) else []
        need_paths = paths_from(need_items, "name")
        error_paths = paths_from(error_items, "path")
        return cls(
            need_paths=frozenset(need_paths),
            error_paths=frozenset(error_paths),
            need_total=int(status.get("needTotalItems", status.get("needFiles", 0)) or 0),
            receive_only_changed_total=int(
                status.get("receiveOnlyChangedTotalItems", status.get("receiveOnlyChangedFiles", 0)) or 0
            ),
            pull_errors=int(status.get("pullErrors", 0) or 0),
            state=str(status.get("state", "unknown")),
            # Syncthing does not provide a total count for these endpoints. Treat
            # a full page conservatively: unlisted descendants are not "synced".
            need_paths_truncated=len(need_items) >= page_size,
            error_paths_truncated=len(error_items) >= page_size,
        )

    @property
    def folder_has_pending_work(self) -> bool:
        return (
            self.need_total > 0
            or self.receive_only_changed_total > 0
            or self.state.lower() not in {"", "idle", "unknown"}
        )

    @property
    def folder_is_synced(self) -> bool:
        return not self.folder_has_pending_work and self.pull_errors == 0 and not self.error_paths

    def status_for(self, relative_path: str, *, is_directory: bool) -> Status:
        relative_path = normalise_relative_path(relative_path)
        if is_conflict_path(relative_path):
            return Status.CONFLICT

        if is_directory and not relative_path and self.state.lower() == "error":
            return Status.ERROR
        if _contains_or_is_descendant(self.error_paths, relative_path):
            return Status.ERROR
        if is_directory and not relative_path and self.pull_errors:
            return Status.ERROR

        if _contains_or_is_descendant(self.need_paths, relative_path):
            return Status.SYNCING
        if is_directory and not relative_path and self.folder_has_pending_work:
            return Status.SYNCING

        if self.folder_is_synced:
            return Status.SYNCED

        # Do not label unlisted files "synced" when the folder has outstanding
        # entries that did not fit into the bounded batch response.
        return Status.UNKNOWN
