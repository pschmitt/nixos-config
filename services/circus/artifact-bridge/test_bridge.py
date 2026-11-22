"""Verify exact-revision artifact selection and fail-closed publication."""

import importlib.util
import io
import json
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("bridge", Path(__file__).with_name("bridge.py"))
bridge = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(bridge)
REVISION = "a" * 40
PATH_X86 = "/nix/store/" + "1" * 32 + "-x86-output"
PATH_ARM = "/nix/store/" + "2" * 32 + "-arm-output"
TRUSTED_PR = {"number": 17, "state": "open", "draft": False, "user": {"login": "pschmitt", "id": 123},
              "base": {"ref": "main"}, "head": {"sha": REVISION, "ref": "feature", "repo": {"full_name": "pschmitt/stricknani"}}}
READY_STATUS = {"statuses": [{"context": "circus/pr-artifacts", "state": "success"}]}
READY_RUN = {"workflow_runs": [{"event": "workflow_dispatch", "head_branch": "main",
                                "display_title": f"Circus PR artifacts {REVISION}",
                                "status": "completed", "conclusion": "success"}]}
READY_E2E = {"workflow_runs": [READY_RUN["workflow_runs"][0] | {"display_title": f"Circus PR E2E {REVISION}"}]}


class FakeApi:
    def __init__(self, project="stricknani"):
        self.project = project
        self.arm_status = "succeeded"
        self.arm_outputs = {"out": PATH_ARM}
        self.arm_error = None

    def __call__(self, path, **params):
        if path == "projects":
            return {"items": [{"id": "project", "name": self.project}], "total": 1}
        if path == "projects/project/jobsets":
            return [{"id": "x", "name": "main"}, {"id": "a", "name": "main-arm"}]
        if path == "evaluations":
            name = params["jobset_id"]
            return {"items": [
                {"id": "wrong-pr", "commit_hash": REVISION, "pr_number": 42, "status": "completed"},
                {"id": name, "commit_hash": REVISION, "pr_number": None, "status": "completed",
                 "error_message": self.arm_error if name == "a" else None},
            ], "total": 2}
        if path == "builds":
            is_arm = params["evaluation_id"] == "a"
            return {"items": [
                {"job_name": "drv:input", "status": "pending"},
                {"job_name": "packages.default", "status": self.arm_status if is_arm else "succeeded",
                 "outputs": self.arm_outputs if is_arm else {"out": PATH_X86}},
                {"job_name": "checks.format", "status": "succeeded", "outputs": {"out": PATH_X86}},
            ], "total": 3}
        raise AssertionError(path)


class ProjectOutputsTest(unittest.TestCase):
    def test_author_list_rejects_empty_or_non_integer_values(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "authors"
            path.write_text("[123, 456]")
            self.assertEqual(bridge.author_ids(path), {123, 456})
            for value in ("[]", "[true]", '["123"]', "[0]"):
                path.write_text(value)
                with self.subTest(value=value), self.assertRaises(ValueError):
                    bridge.author_ids(path)

    def test_selects_exact_main_revision_and_both_architectures(self):
        self.assertEqual(bridge.project_outputs(FakeApi(), REVISION), {
            "main-packages.default-out": PATH_X86,
            "main-arm-packages.default-out": PATH_ARM,
        })

    def test_pending_arm_never_publishes_x86_alone(self):
        api = FakeApi()
        api.arm_status = "pending"
        self.assertIsNone(bridge.project_outputs(api, REVISION))

    def test_failed_evaluation_and_missing_output_fail_closed(self):
        api = FakeApi()
        api.arm_error = "attribute evaluation failed"
        with self.assertRaises(bridge.BuildFailed):
            bridge.project_outputs(api, REVISION)
        api.arm_error = None
        api.arm_outputs = {}
        with self.assertRaisesRegex(ValueError, "no output"):
            bridge.project_outputs(api, REVISION)

    def test_old_or_pull_request_revision_is_not_published(self):
        self.assertIsNone(bridge.project_outputs(FakeApi(), "b" * 40))

    def test_selects_monarch_outputs_from_monarch_jobsets(self):
        outputs = bridge.project_outputs(FakeApi("monarch"), REVISION, "monarch")
        self.assertEqual(outputs["main-arm-packages.default-out"], PATH_ARM)

    def test_pr_never_uses_a_main_or_different_pr_evaluation(self):
        self.assertIsNone(bridge.project_outputs(FakeApi(), REVISION, "stricknani", 17))
        outputs = bridge.project_outputs(FakeApi(), REVISION, "stricknani", 42)
        self.assertEqual(set(outputs), {"main-packages.default-out", "main-arm-packages.default-out"})


class ReconcileTest(unittest.TestCase):
    def setUp(self):
        patcher = patch.object(bridge, "author_ids", return_value={123})
        patcher.start()
        self.addCleanup(patcher.stop)

    def test_enumeration_only_queues_trusted_prs(self):
        with tempfile.TemporaryDirectory() as directory:
            token = Path(directory) / "token"
            token.write_text("not-a-real-token")
            args = SimpleNamespace(repository="pschmitt/stricknani", pr_author_ids_file="unused", github_token_file=token,
                                   api_token_file=token, api="http://localhost")
            foreign = TRUSTED_PR | {"number": 18, "user": {"login": "someone-else", "id": 456}}
            with patch.object(bridge, "branch_head", return_value="b" * 40), \
                 patch.object(bridge, "request", return_value=[TRUSTED_PR, foreign]), \
                 patch.object(bridge, "reconcile_source") as source:
                bridge.reconcile(args)
            self.assertEqual(source.call_count, 2)
            self.assertEqual(source.call_args_list[0].args[2:], ("b" * 40,))
            self.assertEqual(source.call_args_list[1].args[2:], (REVISION, 17))

    def test_pending_status_is_not_reposted_each_poll(self):
        with tempfile.TemporaryDirectory() as directory:
            args = SimpleNamespace(
                repository="pschmitt/stricknani", pr_author_ids_file="unused", state_dir=Path(directory),
                github_token_file="unused", api_token_file=Path(directory) / "api",
                api="http://localhost", secrets_file="unused", runtime_dir=directory,
            )
            args.api_token_file.write_text("not-a-real-token")
            with patch.object(bridge, "branch_head", return_value=REVISION), \
                 patch.object(bridge, "github_status") as status, \
                 patch.object(bridge, "project_outputs", return_value=None):
                bridge.reconcile_source(args, None, REVISION)
                bridge.reconcile_source(args, None, REVISION)
            self.assertEqual(status.call_count, 1)
            self.assertEqual(status.call_args.args[3], "pending")

    def test_success_status_follows_copy_and_current_head_check(self):
        with tempfile.TemporaryDirectory() as directory:
            args = SimpleNamespace(
                repository="pschmitt/stricknani", pr_author_ids_file="unused", state_dir=Path(directory),
                github_token_file="unused", api_token_file=Path(directory) / "api",
                api="http://localhost", secrets_file="unused", runtime_dir=directory,
            )
            args.api_token_file.write_text("not-a-real-token")
            events = []
            with patch.object(bridge, "branch_head", return_value=REVISION), \
                 patch.object(bridge, "github_status", side_effect=lambda *a, **kw: events.append(a[3])), \
                 patch.object(bridge, "project_outputs", return_value={"main-default": PATH_X86}), \
                 patch.object(bridge, "copy_outputs", side_effect=lambda *a: events.append("copy")):
                bridge.reconcile_source(args, None, REVISION)
            self.assertEqual(events, ["pending", "copy", "success"])
            self.assertTrue((args.state_dir / f"{REVISION}.json").exists())

    def test_failed_circus_build_marks_status_without_upload(self):
        with tempfile.TemporaryDirectory() as directory:
            args = SimpleNamespace(
                repository="pschmitt/stricknani", pr_author_ids_file="unused", state_dir=Path(directory),
                github_token_file="unused", api_token_file=Path(directory) / "api",
                api="http://localhost", secrets_file="unused", runtime_dir=directory,
            )
            args.api_token_file.write_text("not-a-real-token")
            events = []
            with patch.object(bridge, "branch_head", return_value=REVISION), \
                 patch.object(bridge, "github_status", side_effect=lambda *a, **kw: events.append(a[3])), \
                 patch.object(bridge, "project_outputs", side_effect=bridge.BuildFailed("failed")), \
                 patch.object(bridge, "copy_outputs") as copy:
                bridge.reconcile_source(args, None, REVISION)
            self.assertEqual(events, ["pending", "failure"])
            copy.assert_not_called()

    def test_pr_publication_uses_its_own_status_and_exact_pr_identity(self):
        with tempfile.TemporaryDirectory() as directory:
            args = SimpleNamespace(repository="pschmitt/stricknani", pr_author_ids_file="unused", state_dir=Path(directory),
                                   github_token_file="unused", secrets_file="unused", runtime_dir=directory)
            with patch.object(bridge, "github_status") as status, \
                 patch.object(bridge, "project_outputs", return_value={"main-default": PATH_X86}) as outputs, \
                 patch.object(bridge, "copy_outputs") as copy, \
                 patch.object(bridge, "source_is_current", return_value=True), \
                 patch.object(bridge, "dispatch_pr_consumers") as dispatch:
                bridge.reconcile_source(args, None, REVISION, 17)
            outputs.assert_called_once_with(None, REVISION, "stricknani", 17)
            self.assertEqual(copy.call_args.args[5], 17)
            self.assertEqual([call.kwargs["context"] for call in status.call_args_list],
                             ["circus/pr-artifacts", "circus/pr-artifacts"])
            self.assertTrue((args.state_dir / f"pr-17-{REVISION}.json").exists())
            dispatch.assert_called_once_with(args, REVISION, 17)

    def test_pr_that_changes_during_upload_does_not_report_success(self):
        with tempfile.TemporaryDirectory() as directory:
            args = SimpleNamespace(repository="pschmitt/stricknani", pr_author_ids_file="unused", state_dir=Path(directory),
                                   github_token_file="unused", secrets_file="unused", runtime_dir=directory)
            with patch.object(bridge, "github_status") as status, \
                 patch.object(bridge, "project_outputs", return_value={"main-default": PATH_X86}), \
                 patch.object(bridge, "copy_outputs"), \
                 patch.object(bridge, "source_is_current", return_value=False):
                bridge.reconcile_source(args, None, REVISION, 17)
            self.assertEqual([call.args[3] for call in status.call_args_list], ["pending"])
            self.assertFalse((args.state_dir / f"pr-17-{REVISION}.json").exists())


class PublishTest(unittest.TestCase):
    def setUp(self):
        patcher = patch.object(bridge, "author_ids", return_value={123})
        patcher.start()
        self.addCleanup(patcher.stop)

    def test_empty_dispatch_response_is_accepted(self):
        class EmptyResponse:
            status = 204

            def __enter__(self):
                return self

            def __exit__(self, *_args):
                return None

        with patch.object(bridge.urllib.request, "urlopen", return_value=EmptyResponse()):
            self.assertIsNone(bridge.request("https://example.invalid/dispatch", "not-a-real-token", {"ref": "feature"}))

    def test_pr_dispatches_both_consumers_once_for_exact_head(self):
        with tempfile.TemporaryDirectory() as directory:
            token = Path(directory) / "token"
            token.write_text("not-a-real-token")
            args = SimpleNamespace(repository="pschmitt/stricknani", pr_author_ids_file="unused", github_token_file=token, state_dir=Path(directory))
            with patch.object(bridge, "pull_request", return_value=TRUSTED_PR), \
                 patch.object(bridge, "github_status") as status, \
                 patch.object(bridge, "request", side_effect=[READY_STATUS, None, READY_STATUS, READY_RUN, None,
                                                              READY_STATUS, READY_RUN, READY_E2E]) as request:
                bridge.dispatch_pr_consumers(args, REVISION, 17)
                bridge.dispatch_pr_consumers(args, REVISION, 17)
                bridge.dispatch_pr_consumers(args, REVISION, 17)
                bridge.dispatch_pr_consumers(args, REVISION, 17)
            self.assertEqual(request.call_count, 8)
            self.assertTrue(request.call_args_list[1].args[0].endswith("/build.yaml/dispatches"))
            self.assertTrue(request.call_args_list[4].args[0].endswith("/e2e.yaml/dispatches"))
            for call in [request.call_args_list[1], request.call_args_list[4]]:
                payload = call.args[2]
                self.assertEqual(payload["ref"], "main")
                self.assertEqual(payload["inputs"]["circus_pr_number"], "17")
                self.assertEqual(payload["inputs"]["circus_pr_sha"], REVISION)
            self.assertEqual(request.call_args_list[4].args[2]["inputs"]["lane"], "smoke")
            self.assertEqual([call.args[3] for call in status.call_args_list], ["pending", "success"])

    def test_pr_dispatch_stops_if_head_changed(self):
        with tempfile.TemporaryDirectory() as directory:
            token = Path(directory) / "token"
            token.write_text("not-a-real-token")
            args = SimpleNamespace(repository="pschmitt/stricknani", pr_author_ids_file="unused", github_token_file=token, state_dir=Path(directory))
            changed = TRUSTED_PR | {"head": TRUSTED_PR["head"] | {"sha": "b" * 40}}
            with patch.object(bridge, "pull_request", return_value=changed), \
                 patch.object(bridge, "request", return_value=READY_STATUS) as request:
                bridge.dispatch_pr_consumers(args, REVISION, 17)
            self.assertEqual(request.call_count, 1)

    def test_pr_dispatch_waits_for_status_visibility(self):
        with tempfile.TemporaryDirectory() as directory:
            token = Path(directory) / "token"
            token.write_text("not-a-real-token")
            args = SimpleNamespace(repository="pschmitt/stricknani", pr_author_ids_file="unused", github_token_file=token, state_dir=Path(directory))
            with patch.object(bridge, "pull_request") as pr, \
                 patch.object(bridge, "request", return_value={"statuses": []}):
                bridge.dispatch_pr_consumers(args, REVISION, 17)
            pr.assert_not_called()

    def test_e2e_waits_for_matching_successful_build_without_runner(self):
        with tempfile.TemporaryDirectory() as directory:
            token = Path(directory) / "token"
            token.write_text("not-a-real-token")
            args = SimpleNamespace(repository="pschmitt/stricknani", pr_author_ids_file="unused", github_token_file=token, state_dir=Path(directory))
            running = {"workflow_runs": [READY_RUN["workflow_runs"][0] | {"status": "in_progress", "conclusion": None}]}
            with patch.object(bridge, "pull_request", return_value=TRUSTED_PR), \
                 patch.object(bridge, "github_status"), \
                 patch.object(bridge, "request", side_effect=[READY_STATUS, None, READY_STATUS, running,
                                                              READY_STATUS, READY_RUN, None]) as request:
                bridge.dispatch_pr_consumers(args, REVISION, 17)
                self.assertEqual(request.call_count, 2)
                bridge.dispatch_pr_consumers(args, REVISION, 17)
                self.assertEqual(request.call_count, 4)
                bridge.dispatch_pr_consumers(args, REVISION, 17)
            self.assertEqual(request.call_count, 7)
            self.assertTrue(request.call_args_list[6].args[0].endswith("/e2e.yaml/dispatches"))

    def test_partial_dispatch_retries_only_missing_consumer(self):
        with tempfile.TemporaryDirectory() as directory:
            token = Path(directory) / "token"
            token.write_text("not-a-real-token")
            args = SimpleNamespace(repository="pschmitt/stricknani", pr_author_ids_file="unused", github_token_file=token, state_dir=Path(directory))
            with patch.object(bridge, "pull_request", return_value=TRUSTED_PR), \
                 patch.object(bridge, "github_status"), \
                 patch.object(bridge, "request", side_effect=[READY_STATUS, None, READY_STATUS, READY_RUN,
                                                              OSError("temporary failure"), READY_STATUS, READY_RUN, None]) as request:
                bridge.dispatch_pr_consumers(args, REVISION, 17)
                with self.assertRaises(OSError):
                    bridge.dispatch_pr_consumers(args, REVISION, 17)
                bridge.dispatch_pr_consumers(args, REVISION, 17)
            self.assertEqual(request.call_count, 8)
            self.assertTrue(request.call_args_list[7].args[0].endswith("/e2e.yaml/dispatches"))

    def test_failed_build_reports_failure_and_does_not_dispatch_e2e(self):
        with tempfile.TemporaryDirectory() as directory:
            token = Path(directory) / "token"
            token.write_text("not-a-real-token")
            args = SimpleNamespace(repository="pschmitt/stricknani", pr_author_ids_file="unused", github_token_file=token, state_dir=Path(directory))
            failed = {"workflow_runs": [READY_RUN["workflow_runs"][0] | {"conclusion": "failure"}]}
            with patch.object(bridge, "pull_request", return_value=TRUSTED_PR), \
                 patch.object(bridge, "github_status") as status, \
                 patch.object(bridge, "request", side_effect=[READY_STATUS, None, READY_STATUS, failed]) as request:
                bridge.dispatch_pr_consumers(args, REVISION, 17)
                bridge.dispatch_pr_consumers(args, REVISION, 17)
            self.assertEqual([call.args[3] for call in status.call_args_list], ["pending", "failure"])
            self.assertEqual(request.call_count, 4)
            self.assertFalse((Path(directory) / f"pr-17-{REVISION}-e2e.yaml.dispatched").exists())

    def test_only_allowlisted_same_repository_prs_are_trusted(self):
        self.assertTrue(bridge.trusted_pull_request(TRUSTED_PR, "pschmitt/stricknani", {123}))
        bot = TRUSTED_PR | {"user": {"login": "renovate[bot]", "id": 123}}
        self.assertTrue(bridge.trusted_pull_request(bot, "pschmitt/stricknani", {123}))
        for changed in [
            {"user": {"login": "someone-else", "id": 456}},
            {"head": {"sha": REVISION, "repo": {"full_name": "someone-else/stricknani"}}},
            {"base": {"ref": "other"}}, {"state": "closed"}, {"draft": True},
            {"head": {"sha": "bad", "repo": {"full_name": "pschmitt/stricknani"}}},
        ]:
            with self.subTest(changed=changed):
                self.assertFalse(bridge.trusted_pull_request(TRUSTED_PR | changed, "pschmitt/stricknani", {123}))

    def test_pr_head_must_still_match_before_moving_pins(self):
        with patch.object(bridge, "pull_request", return_value=TRUSTED_PR):
            self.assertTrue(bridge.source_is_current("pschmitt/stricknani", REVISION, 17, "unused"))
            self.assertFalse(bridge.source_is_current("pschmitt/stricknani", "b" * 40, 17, "unused"))
            self.assertFalse(bridge.source_is_current("pschmitt/stricknani", REVISION, 18, "unused"))

    def test_advanced_main_never_moves_pins(self):
        process = SimpleNamespace(stdout=io.BytesIO(b"/nix/store/path\n"), wait=lambda: 0)
        with patch.object(bridge.subprocess, "Popen", return_value=process), \
             patch.object(bridge.subprocess, "run", return_value=SimpleNamespace(returncode=0)) as run, \
             patch.object(bridge, "branch_head", return_value="b" * 40):
            with self.assertRaisesRegex(RuntimeError, "advanced"):
                bridge.publish_outputs({"main-default": PATH_X86}, "pschmitt/stricknani", REVISION)
        self.assertEqual(run.call_count, 1)
        self.assertEqual(run.call_args.args[0], ["niks3", "push", "--stdin"])

    def test_secret_scope_and_substitute_only_options(self):
        with tempfile.TemporaryDirectory() as directory:
            secret = Path(directory) / "secrets.json"
            secret.write_text(json.dumps({"niks3-stricknani-publisher": {
                "condition": {"and": ["isDefaultBranch", {"isOwner": "pschmitt"}, {"isRepo": "stricknani"}]},
                "data": {"token": "not-a-real-token", "server_url": "https://example.invalid"},
            }}))

            def run(command, *, check, env):
                self.assertTrue(check)
                self.assertIn("max-jobs", command)
                self.assertEqual(command[command.index("max-jobs") + 1], "0")
                self.assertEqual(command[command.index("fallback") + 1], "false")
                self.assertEqual(Path(env["NIKS3_AUTH_TOKEN_FILE"]).read_text(), "not-a-real-token")

            with patch.object(bridge.subprocess, "run", side_effect=run):
                bridge.copy_outputs({"main-default": PATH_X86}, "pschmitt/stricknani", REVISION, secret, directory)

    def test_rejects_a_credential_scoped_to_another_project(self):
        with tempfile.TemporaryDirectory() as directory:
            secret = Path(directory) / "secrets.json"
            secret.write_text(json.dumps({"niks3-monarch-publisher": {
                "condition": {"and": ["isDefaultBranch", {"isOwner": "pschmitt"}, {"isRepo": "stricknani"}]},
                "data": {"token": "not-a-real-token", "server_url": "https://example.invalid"},
            }}))
            with self.assertRaisesRegex(ValueError, "not scoped"):
                bridge.copy_outputs({"main-default": PATH_X86}, "pschmitt/monarch", REVISION, secret, directory)

    def test_pr_credential_cannot_be_mounted_by_effects(self):
        with tempfile.TemporaryDirectory() as directory:
            secret = Path(directory) / "secrets.json"
            entry = {"condition": False, "data": {"token": "not-a-real-token", "server_url": "https://example.invalid"}}
            secret.write_text(json.dumps({"niks3-stricknani-pr-publisher": entry}))
            with patch.object(bridge.subprocess, "run") as run:
                bridge.copy_outputs({"main-default": PATH_X86}, "pschmitt/stricknani", REVISION,
                                    secret, directory, 17, "token-file")
            self.assertEqual(run.call_args.args[0][-3:], ["17", "token-file", ""])
            entry["condition"] = True
            secret.write_text(json.dumps({"niks3-stricknani-pr-publisher": entry}))
            with self.assertRaisesRegex(ValueError, "not scoped"):
                bridge.copy_outputs({"main-default": PATH_X86}, "pschmitt/stricknani", REVISION,
                                    secret, directory, 17, "token-file")


if __name__ == "__main__":
    unittest.main()
