from __future__ import annotations

import json
from pathlib import Path
import tempfile
import unittest
from urllib.error import URLError

from syncthing_nautilus.cache import StatusCache
from syncthing_nautilus.discovery import Endpoint, Folder, SyncthingConfiguration, discover, folder_for_path
from syncthing_nautilus.model import FolderSnapshot, Status, is_conflict_path
from syncthing_nautilus.syncthing import SyncthingClient, SyncthingUnavailable


class FolderMatchingTests(unittest.TestCase):
    def test_path_matching_uses_path_boundaries_and_prefers_nested_folder(self) -> None:
        folders = (
            Folder("root", Path("/home/alice/sync")),
            Folder("nested", Path("/home/alice/sync/work")),
        )
        self.assertEqual(folder_for_path(folders, "/home/alice/sync/work/note.md").id, "nested")
        self.assertIsNone(folder_for_path(folders, "/home/alice/sync-old/note.md"))

    def test_discovery_uses_state_config_and_env_endpoint_override(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            config_dir = Path(temporary)
            (config_dir / "config.xml").write_text(
                """<configuration><folder id=\"one\" path=\"/tmp/One Folder\" />
                <gui tls=\"false\"><address>127.0.0.1:8384</address><apikey>from-config</apikey></gui>
                </configuration>"""
            )
            configuration = discover(
                {
                    "SYNCTHING_CONFIG_DIR": str(config_dir),
                    "SYNCTHING_URL": "http://localhost:9999",
                    "SYNCTHING_API_KEY": "from-env",
                }
            )
        self.assertEqual(configuration.folders[0].id, "one")
        self.assertEqual(configuration.endpoint.url, "http://localhost:9999")
        self.assertEqual(configuration.endpoint.api_key, "from-env")

    def test_discovery_formats_ipv6_loopback_url(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            config_dir = Path(temporary)
            (config_dir / "config.xml").write_text(
                """<configuration><gui><address>[::1]:8384</address><apikey>key</apikey></gui></configuration>"""
            )
            configuration = discover({"SYNCTHING_CONFIG_DIR": str(config_dir)})
        self.assertEqual(configuration.endpoint.url, "http://[::1]:8384")


class StatusTests(unittest.TestCase):
    def setUp(self) -> None:
        self.snapshot = FolderSnapshot.from_api(
            {"needTotalItems": 2, "pullErrors": 1, "state": "syncing"},
            {"progress": [{"name": "downloading/file.txt"}], "queued": [{"name": "later.txt"}], "rest": []},
            {"errors": [{"path": "broken/file.txt", "error": "permission denied"}]},
            page_size=1024,
        )

    def test_status_mapping_for_files_and_directories(self) -> None:
        self.assertEqual(self.snapshot.status_for("downloading/file.txt", is_directory=False), Status.SYNCING)
        self.assertEqual(self.snapshot.status_for("downloading", is_directory=True), Status.SYNCING)
        self.assertEqual(self.snapshot.status_for("broken/file.txt", is_directory=False), Status.ERROR)
        self.assertEqual(self.snapshot.status_for("broken", is_directory=True), Status.ERROR)
        self.assertEqual(self.snapshot.status_for("unlisted.txt", is_directory=False), Status.UNKNOWN)

    def test_idle_folder_maps_to_synced_and_conflict_wins(self) -> None:
        snapshot = FolderSnapshot.from_api({"state": "idle"}, {}, {}, page_size=1024)
        self.assertEqual(snapshot.status_for("plain.txt", is_directory=False), Status.SYNCED)
        self.assertTrue(is_conflict_path("plain.sync-conflict-20260905-120000-DEVICE.txt"))
        self.assertEqual(
            snapshot.status_for("plain.sync-conflict-20260905-120000-DEVICE.txt", is_directory=False),
            Status.CONFLICT,
        )

    def test_folder_error_state_is_not_shown_as_syncing(self) -> None:
        snapshot = FolderSnapshot.from_api({"state": "error"}, {}, {}, page_size=1024)
        self.assertEqual(snapshot.status_for("", is_directory=True), Status.ERROR)


class CacheTests(unittest.TestCase):
    def test_invalidation_removes_snapshot_and_respects_retry_delay(self) -> None:
        folder = Folder("one", Path("/tmp/sync"))
        cache = StatusCache(ttl=30, retry_delay=5)
        cache.set_configuration(SyncthingConfiguration((folder,), None))
        cache.mark_refresh_attempt(folder, now=10)
        self.assertFalse(cache.refresh_due(folder, now=12))
        self.assertTrue(cache.refresh_due(folder, now=16))
        cache.store(folder, FolderSnapshot(state="idle"), now=16)
        self.assertFalse(cache.refresh_due(folder, now=20))
        cache.invalidate("one")
        self.assertTrue(cache.refresh_due(folder, now=22))


class ApiTests(unittest.TestCase):
    def test_client_parses_batched_api_responses(self) -> None:
        requests = []

        class Response:
            def __init__(self, payload: dict) -> None:
                self.payload = payload

            def __enter__(self):
                return self

            def __exit__(self, *_args):
                return False

            def read(self) -> bytes:
                return json.dumps(self.payload).encode()

        payloads = iter(
            [
                {"needTotalItems": 1, "state": "syncing"},
                {"progress": [{"name": "file with spaces.txt"}], "queued": [], "rest": []},
                {"errors": []},
            ]
        )

        def opener(request, **_kwargs):
            requests.append(request)
            return Response(next(payloads))

        client = SyncthingClient(Endpoint("http://127.0.0.1:8384", "test-key"), opener=opener)
        snapshot = client.folder_snapshot(Folder("one", Path("/tmp/sync")))
        self.assertIn("file with spaces.txt", snapshot.need_paths)
        self.assertEqual(len(requests), 3)
        self.assertEqual(requests[0].get_header("X-api-key"), "test-key")

    def test_unreachable_api_is_quietly_reported_to_caller(self) -> None:
        def opener(*_args, **_kwargs):
            raise URLError("connection refused")

        client = SyncthingClient(Endpoint("http://127.0.0.1:8384", "test-key"), opener=opener)
        with self.assertRaises(SyncthingUnavailable):
            client.folder_snapshot(Folder("one", Path("/tmp/sync")))
