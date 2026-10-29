import json
import os
import subprocess
import tempfile
import unittest
from datetime import UTC, datetime, timedelta, timezone
from pathlib import Path

SCRIPT = (
    Path(__file__).resolve().parents[2]
    / "profiles/specializations/server/scripts/restic-last-backup.sh"
)


class ResticLastBackupTest(unittest.TestCase):
    def run_check(self, snapshots, *, status=0, threshold="86400"):
        with tempfile.TemporaryDirectory() as directory:
            stub = Path(directory) / "restic-main"
            stub.write_text(
                '#!/usr/bin/env bash\nprintf "%s" "$SNAPSHOTS"\nexit "$STATUS"\n'
            )
            stub.chmod(0o755)
            env = os.environ | {
                "PATH": f"{directory}:{os.environ['PATH']}",
                "SNAPSHOTS": snapshots,
                "STATUS": str(status),
            }
            return subprocess.run(
                ["bash", str(SCRIPT), threshold],
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )

    def test_recent_and_old(self):
        now = datetime.now(UTC)
        recent = (now - timedelta(minutes=1)).isoformat()
        old = (now - timedelta(days=2)).isoformat()
        self.assertEqual(self.run_check(json.dumps([{"time": recent}])).returncode, 0)
        self.assertEqual(self.run_check(json.dumps([{"time": old}])).returncode, 1)
        self.assertEqual(
            self.run_check(json.dumps([{"time": recent}, {"time": old}])).returncode, 0
        )
        different_offset = (
            (now - timedelta(hours=1))
            .astimezone(timezone(timedelta(hours=12)))
            .isoformat()
        )
        self.assertEqual(
            self.run_check(
                json.dumps([{"time": recent}, {"time": different_offset}]),
                threshold="600",
            ).returncode,
            0,
        )

    def test_query_failure_and_invalid_data(self):
        for data, status in [
            ("[]", 1),
            ("[]", 0),
            ("invalid", 0),
            ('[{"time":"bad"}]', 0),
        ]:
            with self.subTest(data=data, status=status):
                self.assertNotEqual(self.run_check(data, status=status).returncode, 0)

    def test_invalid_threshold(self):
        self.assertEqual(self.run_check("[]", threshold="bad").returncode, 2)


if __name__ == "__main__":
    unittest.main()
