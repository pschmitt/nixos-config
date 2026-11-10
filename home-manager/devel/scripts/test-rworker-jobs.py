"""Exercise the job manager locally, using a fake SSH transport."""

import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest

CLIENT = Path(__file__).resolve().parents[1] / "skills/rworker/scripts/rworker.sh"


class JobsTest(unittest.TestCase):
    def test_ps_shows_running_job_processes(self):
        with tempfile.TemporaryDirectory() as directory:
            env = {**os.environ, "HOME": directory}
            script = 'source "$1"; shift; cmd_ssh() { shift; bash -c "$1"; }; cmd_jobs_remote "$@"'

            def call(*args):
                return subprocess.run(["bash", "-c", script, "test", str(CLIENT), *args],
                                      env=env, text=True, capture_output=True, check=True).stdout

            job = call("start", "worker", "--name", "process-test", "--", "sleep 2").strip()
            deadline = time.monotonic() + 1
            while True:
                rows = call("ps", "worker")
                if any(line.startswith(job + "\t") and line.endswith("\tsleep") for line in rows.splitlines()):
                    break
                self.assertLess(time.monotonic(), deadline)
                time.sleep(0.05)
            self.assertTrue(any(line.startswith(job + "\t") and line.endswith("\tsleep 2")
                                for line in call("ps", "worker", "--long").splitlines()))
            time.sleep(2)
            self.assertNotIn(job, call("ps", "worker"))

    def test_jobs_capture_output_and_status_and_register_files(self):
        with tempfile.TemporaryDirectory() as directory:
            env = {**os.environ, "HOME": directory}

            def call(*args):
                script = 'source "$1"; shift; cmd_ssh() { shift; bash -c "$1"; }; cmd_jobs_remote "$@"'
                return subprocess.run(["bash", "-c", script, "test", str(CLIENT), *args],
                                      env=env, text=True, capture_output=True, check=True).stdout

            job = call("start", "worker", "--", "printf 'hello\\n'; printf 'error\\n' >&2; exit 7").strip()
            deadline = time.monotonic() + 5
            while "exit 7" not in call("jobs", "worker"):
                self.assertLess(time.monotonic(), deadline)
                time.sleep(0.05)
            output = call("logs", "worker", job)
            self.assertIn("hello", output)
            self.assertIn("error", output)
            self.assertFalse((Path(directory) / ".local/state/rworker/jobs" / job / "command").exists())
            external = Path(directory) / "external.log"
            external.write_text("external output\n")
            call("register", "worker", "external", "--log", str(external))
            self.assertIn("external output", call("logs", "worker"))
            second = call("start", "worker", "--", "true").strip()
            self.assertNotEqual(job, second)


if __name__ == "__main__":
    unittest.main()
