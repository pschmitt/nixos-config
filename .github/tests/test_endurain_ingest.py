#!/usr/bin/env python3
"""Exercise the ingester against both supported Endurain API contracts."""

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[2] / "services" / "endurain-ingest.sh"
FAKE_CURL = r"""#!/usr/bin/env python3
import base64, hashlib, json, os, pathlib, sys
args = sys.argv[1:]
url = args[-1]
out = pathlib.Path(args[args.index('-o') + 1])
state = pathlib.Path(os.environ['FAKE_STATE'])
scenario = os.environ['FAKE_SCENARIO']
with (state / 'calls').open('a') as log:
    log.write(url + '\n')
status = 200
if url.endswith('/auth/login'):
    challenge = next(a.split('=', 1)[1] for a in args if a.startswith('code_challenge='))
    (state / 'challenge').write_text(challenge)
    for name in ('username', 'password'):
        assert any(a.startswith(name + '@') and pathlib.Path(a.split('@', 1)[1]).is_file() for a in args)
    if scenario == 'legacy':
        body = {'access_token': 'test-token'}
    elif scenario == 'mfa':
        body = {'next_step': 'mfa'}
    else:
        body = {'next_step': 'exchange', 'session_id': '11111111-1111-4111-8111-111111111111', 'device_id': 'test-device'}
elif '/auth/sessions/' in url:
    verifier = json.load(sys.stdin)['code_verifier']
    challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).decode().rstrip('=')
    assert challenge == (state / 'challenge').read_text()
    body = {'next_step': 'tokens', 'access_token': 'test-token', 'device_id': 'test-device'}
elif '/activities/upload' in url:
    status = 202
    body = {'id': '22222222-2222-4222-8222-222222222222'}
elif '/activities/ingestion-jobs/' in url:
    body = {'status': 'completed'}
elif '/jobs/' in url:
    if scenario == 'legacy':
        status, body = 404, {}
    elif scenario == 'invalid':
        body = {'status': 'failed', 'error_code': 'invalid_file'}
    elif scenario == 'failed':
        body = {'status': 'failed', 'error_code': 'processing_failed'}
    else:
        counter = state / 'polls'
        count = int(counter.read_text()) if counter.exists() else 0
        counter.write_text(str(count + 1))
        body = {'status': ['queued', 'running', 'succeeded'][min(count, 2)]}
elif '/activities?' in url:
    body = {'items': [{'start_time': '2026-01-01T12:00:00Z'}] if scenario == 'duplicate' else []}
else:
    raise AssertionError(url)
out.write_text(json.dumps(body))
print(status, end='')
"""


class IngestTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        curl = self.bin / "curl"
        curl.write_text(FAKE_CURL)
        curl.chmod(0o755)
        (self.root / "state").mkdir()
        self.env = dict(
            os.environ,
            PATH=f"{self.bin}:{os.environ['PATH']}",
            FAKE_STATE=str(self.root),
            ENDURAIN_STATE_DIR=str(self.root / "state"),
            ENDURAIN_USERNAME="example",
            ENDURAIN_PASSWORD="example-password",
        )

    def run_bash(self, scenario, command):
        env = dict(self.env, FAKE_SCENARIO=scenario)
        return subprocess.run(
            [
                "bash",
                "-euo",
                "pipefail",
                "-c",
                'source "$1"; sleep() { :; }; ' + command,
                "test",
                str(SCRIPT),
            ],
            env=env,
            text=True,
            capture_output=True,
        )

    def test_mobile_pkce_exchange(self):
        result = self.run_bash("v21", "login example.invalid")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "test-token")
        self.assertEqual((self.root / "state/device-id").read_text(), "test-device")
        self.assertEqual(len((self.root / "calls").read_text().splitlines()), 2)

    def test_legacy_login_and_job_route(self):
        result = self.run_bash(
            "legacy",
            'token="$(login example.invalid)"; poll_upload example.invalid "$token" job file "$ENDURAIN_STATE_DIR/marker"',
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.root / "state/marker").exists())
        self.assertIn(
            "/activities/ingestion-jobs/job", (self.root / "calls").read_text()
        )

    def test_new_job_states(self):
        result = self.run_bash(
            "v21",
            'poll_upload example.invalid token job file "$ENDURAIN_STATE_DIR/marker"; [[ "$upload_outcome" == uploaded ]]',
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.root / "state/marker").exists())
        self.assertEqual((self.root / "polls").read_text(), "3")

    def test_transient_failure_is_not_marked_handled(self):
        result = self.run_bash(
            "failed",
            'poll_upload example.invalid token job file "$ENDURAIN_STATE_DIR/marker"; [[ "$upload_outcome" == transient ]]',
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.root / "state/marker").exists())

    def test_full_upload_and_repeat_is_deduplicated(self):
        watch = self.root / "watch"
        watch.mkdir()
        (watch / "activity.fit").write_bytes(b"synthetic activity")
        self.env.update(ENDURAIN_HOST="example.invalid", ENDURAIN_WATCH_DIR=str(watch))
        first = self.run_bash("v21", "main")
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertIn("uploaded=1", first.stdout)
        calls = (self.root / "calls").read_text()
        self.assertIn("/activities/upload", calls)
        self.assertIn("/jobs/", calls)
        second = self.run_bash("v21", "main")
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertIn("nothing new", second.stdout)
        self.assertEqual((self.root / "calls").read_text(), calls)

    def test_existing_activity_is_not_uploaded(self):
        watch = self.root / "watch"
        watch.mkdir()
        (watch / "activity.gpx").write_text(
            "<gpx><trkpt><time>2026-01-01T12:01:00Z</time></trkpt></gpx>"
        )
        self.env.update(ENDURAIN_HOST="example.invalid", ENDURAIN_WATCH_DIR=str(watch))
        result = self.run_bash("duplicate", "main")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("duplicate=1", result.stdout)
        self.assertNotIn("/activities/upload", (self.root / "calls").read_text())

    def test_mfa_is_refused(self):
        result = self.run_bash("mfa", "login example.invalid")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("requires MFA", result.stderr)


if __name__ == "__main__":
    unittest.main()
