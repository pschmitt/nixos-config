"""Safety and behavior tests for the rbw unlock request helper."""

from __future__ import annotations

import importlib.util
import io
import json
import os
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest import mock
from urllib.error import URLError

SCRIPT = Path(__file__).parents[1] / "scripts" / "rbw-request-unlock.py"
SPEC = importlib.util.spec_from_file_location("rbw_request_unlock", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
helper = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(helper)


class RbwRequestUnlockTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tempdir = tempfile.TemporaryDirectory()
        self.addCleanup(self.tempdir.cleanup)
        self.endpoint_path = Path(self.tempdir.name) / "endpoint"
        self.endpoint_path.write_text("http://127.0.0.1:8765/hook\n", encoding="utf-8")
        self.endpoint_path.chmod(0o600)
        self.env = mock.patch.dict(
            os.environ,
            {"RBW_UNLOCK_WEBHOOK_URL_FILE": str(self.endpoint_path)},
        )
        self.env.start()
        self.addCleanup(self.env.stop)

    @staticmethod
    def unlocked_result(code: int) -> mock.Mock:
        return mock.Mock(returncode=code, stdout="", stderr="")

    def test_already_unlocked_skips_endpoint_and_notification(self) -> None:
        with (
            mock.patch.object(helper.subprocess, "run", return_value=self.unlocked_result(0)),
            mock.patch.object(helper, "_read_endpoint", side_effect=AssertionError),
            mock.patch.object(helper, "urlopen", side_effect=AssertionError),
            redirect_stdout(io.StringIO()) as output,
        ):
            self.assertEqual(helper.main([]), 0)
        self.assertIn("already unlocked", output.getvalue())

    def test_request_failure_does_not_echo_sensitive_exception_text(self) -> None:
        self.endpoint_path.write_text("http://127.0.0.1:8765/secret", encoding="utf-8")
        sensitive = "http://user:password@example.invalid/hook?token=sentinel"
        calls = [self.unlocked_result(1)]
        stdout = io.StringIO()
        stderr = io.StringIO()
        with (
            mock.patch.object(helper.subprocess, "run", side_effect=calls),
            mock.patch.object(helper, "urlopen", side_effect=URLError(sensitive)),
            redirect_stdout(stdout),
            redirect_stderr(stderr),
        ):
            self.assertEqual(helper.main([]), 1)
        self.assertNotIn(sensitive, stdout.getvalue() + stderr.getvalue())
        self.assertNotIn("sentinel", stdout.getvalue() + stderr.getvalue())

    def test_successful_delayed_unlock_posts_expected_json(self) -> None:
        results = [self.unlocked_result(1), self.unlocked_result(0)]
        request = mock.MagicMock()
        request.__enter__.return_value = None
        stdout = io.StringIO()
        with (
            mock.patch.object(helper.subprocess, "run", side_effect=results) as run,
            mock.patch.object(helper, "urlopen", return_value=request) as open_url,
            mock.patch.object(helper.time, "sleep"),
            mock.patch.object(helper.socket, "gethostname", return_value="testhost.example"),
            redirect_stdout(stdout),
        ):
            self.assertEqual(helper.main(["--agent", "unit test", "--timeout", "5"]), 0)
        self.assertEqual(run.call_count, 2)
        args, kwargs = open_url.call_args
        self.assertEqual(args[0].full_url, "http://127.0.0.1:8765/hook")
        self.assertEqual(json.loads(args[0].data), {"host": "testhost", "agent": "unit test"})
        self.assertEqual(kwargs, {"timeout": 10.0})
        self.assertNotIn("secret", " ".join(run.call_args_list[-1].args[0]))

    def test_timeout_reports_failure(self) -> None:
        stdout = io.StringIO()
        stderr = io.StringIO()
        with (
            mock.patch.object(helper.subprocess, "run", return_value=self.unlocked_result(1)),
            mock.patch.object(helper, "urlopen", return_value=mock.MagicMock()),
            mock.patch.object(helper.time, "monotonic", side_effect=[0.0, 2.0]),
            mock.patch.object(helper.time, "sleep"),
            redirect_stdout(stdout),
            redirect_stderr(stderr),
        ):
            self.assertEqual(helper.main(["--timeout", "1"]), 1)
        self.assertIn("Timed out", stderr.getvalue())

    def test_endpoint_file_and_url_validation_are_safe(self) -> None:
        cases = ["", "file:///tmp/hook", "https://user:password@example.test/hook", "https://example.test:bad/hook"]
        for endpoint in cases:
            with self.subTest(endpoint=endpoint):
                self.endpoint_path.write_text(endpoint, encoding="utf-8")
                with self.assertRaises(helper.UnlockError) as error:
                    helper._read_endpoint()
                if endpoint:
                    self.assertNotIn(endpoint, str(error.exception))

    def test_missing_or_unreadable_endpoint_file_fails_safely(self) -> None:
        self.endpoint_path.unlink()
        with self.assertRaises(helper.UnlockError) as error:
            helper._read_endpoint()
        self.assertNotIn(str(self.endpoint_path), str(error.exception))

    def test_endpoint_file_rejects_group_or_world_permissions(self) -> None:
        self.endpoint_path.chmod(0o644)
        with self.assertRaises(helper.UnlockError) as error:
            helper._read_endpoint()
        self.assertEqual(str(error.exception), "webhook endpoint file permissions are too broad")

    def test_request_construction_error_does_not_expose_endpoint(self) -> None:
        sensitive = "http://user:password@example.invalid/hook?token=sentinel"
        stdout = io.StringIO()
        stderr = io.StringIO()
        with (
            mock.patch.object(helper, "Request", side_effect=ValueError(sensitive)),
            redirect_stdout(stdout),
            redirect_stderr(stderr),
        ):
            with self.assertRaises(helper.UnlockError) as error:
                helper._request_unlock(sensitive, "unit test")
        combined = str(error.exception) + stdout.getvalue() + stderr.getvalue()
        self.assertNotIn(sensitive, combined)
        self.assertNotIn("sentinel", combined)

    def test_url_is_never_passed_as_a_process_argument(self) -> None:
        calls = [self.unlocked_result(1), self.unlocked_result(1)]
        with (
            mock.patch.object(helper.subprocess, "run", side_effect=calls) as run,
            mock.patch.object(helper, "urlopen", return_value=mock.MagicMock()),
            mock.patch.object(helper.time, "monotonic", side_effect=[0.0, 2.0]),
            mock.patch.object(helper.time, "sleep"),
            redirect_stdout(io.StringIO()),
            redirect_stderr(io.StringIO()),
        ):
            helper.main(["--timeout", "1"])
        self.assertTrue(all(call.args[0] == ["rbw", "unlocked"] for call in run.call_args_list))


if __name__ == "__main__":
    unittest.main()
