"""Tests for circus_effects' pure parts: signature, gate, ordering, state."""

import hashlib
import hmac
import json
import os
import tempfile
import threading
import time
import unittest
from pathlib import Path

import circus_effects as ce


def settings(tmp: Path, **kw: object) -> ce.Settings:
    base = {
        "state_dir": tmp,
        "secret_key": b"k",
        "project": "nixos-config",
        "jobset": "main",
        "branch": "main",
        "repository": "o/r",
    }
    base.update(kw)
    return ce.Settings(**base)  # type: ignore[arg-type]


def good_event(**kw: object) -> dict:
    event = {
        "event": "evaluation_finished",
        "evaluation_id": "e1",
        "status": "success",
        "project_name": "nixos-config",
        "jobset_name": "main",
        "branch": "main",
        "commit_hash": "a" * 40,
        "pr_number": None,
        "superseded_by": None,
    }
    event.update(kw)
    return event


class SignatureTest(unittest.TestCase):
    def test_valid_and_invalid(self) -> None:
        body = b'{"x":1}'
        sig = "sha256=" + hmac.new(b"key", body, hashlib.sha256).hexdigest()
        self.assertTrue(ce.valid_signature(b"key", body, sig))
        self.assertFalse(ce.valid_signature(b"other", body, sig))
        self.assertFalse(ce.valid_signature(b"key", body + b" ", sig))
        self.assertFalse(ce.valid_signature(b"key", body, None))
        self.assertFalse(ce.valid_signature(b"key", body, sig.removeprefix("sha256=")))


class GateTest(unittest.TestCase):
    def setUp(self) -> None:
        self.s = settings(Path(tempfile.mkdtemp()))
        self.head = "a" * 40

    def test_green_head_of_branch_passes(self) -> None:
        self.assertIsNone(ce.gate(good_event(), self.s, self.head))

    def test_rejections(self) -> None:
        cases = {
            "event": good_event(event="build_finished"),
            "status": good_event(status="failure"),
            "pull request": good_event(pr_number=7),
            "superseded": good_event(superseded_by="e2"),
            "project": good_event(project_name="other"),
            "jobset": good_event(jobset_name="pr"),
            "branch": good_event(branch="feature"),
            "no longer the head": good_event(commit_hash="b" * 40),
        }
        for why, event in cases.items():
            with self.subTest(why):
                reason = ce.gate(event, self.s, self.head)
                self.assertIsNotNone(reason)
                self.assertIn(why, reason)

    def test_unknown_head_fails_closed(self) -> None:
        self.assertIn("cannot resolve", ce.gate(good_event(), self.s, None))


class OrderTest(unittest.TestCase):
    def test_dependencies_first(self) -> None:
        effects = {
            "b": ce.Effect("b", after=("a",)),
            "a": ce.Effect("a"),
            "c": ce.Effect("c", after=("b", "a")),
        }
        result = ce.order(effects)
        self.assertLess(result.index("a"), result.index("b"))
        self.assertLess(result.index("b"), result.index("c"))

    def test_cycle_and_unknown(self) -> None:
        with self.assertRaises(ValueError):
            ce.order({"a": ce.Effect("a", after=("b",)), "b": ce.Effect("b", after=("a",))})
        with self.assertRaises(ValueError):
            ce.order({"a": ce.Effect("a", after=("missing",))})


class ChangedTest(unittest.TestCase):
    def test_when_changed_roundtrip(self) -> None:
        d = Path(tempfile.mkdtemp())
        effect = ce.Effect("iso", changed={"image": "/nix/store/x"})
        self.assertFalse(ce.unchanged(effect, d))
        ce.record_success(effect, d)
        self.assertTrue(ce.unchanged(effect, d))
        newer = ce.Effect("iso", changed={"image": "/nix/store/y"})
        self.assertFalse(ce.unchanged(newer, d))
        always = ce.Effect("glance")
        ce.record_success(always, d)
        self.assertFalse(ce.unchanged(always, d))


class EnqueueTest(unittest.TestCase):
    def test_dedup_and_bad_ids(self) -> None:
        s = settings(Path(tempfile.mkdtemp()))
        self.assertTrue(ce.enqueue(s, good_event()))
        self.assertFalse(ce.enqueue(s, good_event()))
        (s.queue_dir / "e1.json").unlink()
        s.done_dir.mkdir(parents=True)
        (s.done_dir / "e1").write_text("1")
        self.assertFalse(ce.enqueue(s, good_event()))
        for bad in ("", "../x", ".hidden"):
            with self.subTest(bad), self.assertRaises(ValueError):
                ce.enqueue(s, good_event(evaluation_id=bad))


class LockTest(unittest.TestCase):
    def test_same_lock_serializes(self) -> None:
        d = Path(tempfile.mkdtemp())
        order: list[str] = []

        def hold(tag: str, pause: float) -> None:
            with ce.EffectLock(d, "iso-publish"):
                order.append(f"{tag}+")
                time.sleep(pause)
                order.append(f"{tag}-")

        first = threading.Thread(target=hold, args=("a", 0.3))
        first.start()
        time.sleep(0.05)
        hold("b", 0)
        first.join()
        self.assertEqual(order, ["a+", "a-", "b+", "b-"])

    def test_no_lock_name_is_a_no_op(self) -> None:
        with ce.EffectLock(Path(tempfile.mkdtemp()), None) as lock:
            self.assertIsNone(lock.fd)


class DryRunTest(unittest.TestCase):
    def test_dry_run_lists_without_running(self) -> None:
        d = Path(tempfile.mkdtemp())
        nbo = d / "nbo"
        listed = {
            "publish.a": {"after": [], "lock": "x", "changed": {"i": "/nix/store/1"}},
            "publish.b": {"after": ["publish.a"], "lock": None, "changed": None},
        }
        nbo.write_text(
            "#!/bin/sh\n"
            'case "$2" in\n'
            f"list) cat <<'EOF'\n{json.dumps(listed)}\nEOF\n;;\n"
            "*) exit 99 ;;\n"
            "esac\n"
        )
        nbo.chmod(0o755)
        status_dir = d / "status"
        s = settings(d, nbo=str(nbo), dry_run=True, status_dir=status_dir)
        orig = ce.branch_head
        ce.branch_head = lambda _repo, _branch: "a" * 40  # type: ignore[assignment]
        try:
            out = ce.process(good_event(), s)
        finally:
            ce.branch_head = orig  # type: ignore[assignment]
        self.assertEqual(out.ran, ["publish.a", "publish.b"])
        self.assertEqual(out.failed, [])
        self.assertFalse(any(s.changed_dir.glob("*")) if s.changed_dir.exists() else False)
        snapshot = json.loads((status_dir / f"{'a' * 40}.json").read_text())
        self.assertEqual(
            snapshot["effects"],
            [
                {"name": name, "state": "dry_run", "message": "The effect was selected in a dry run."}
                for name in ("publish.a", "publish.b")
            ],
        )


if __name__ == "__main__":
    os.environ.setdefault("PYTHONDONTWRITEBYTECODE", "1")
    unittest.main()
