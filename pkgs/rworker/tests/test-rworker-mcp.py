"""Check that MCP exposes the worker profile selector."""

import importlib.util
from pathlib import Path
import sys
from types import ModuleType
import unittest
from unittest.mock import patch


class FakeServer:
    def __init__(self, _name):
        pass

    def tool(self):
        return lambda func: func


class ProfileTest(unittest.TestCase):
    def test_up_passes_profile_and_resource_overrides(self):
        modules = {name: ModuleType(name) for name in ("mcp", "mcp.server", "mcp.server.mcpserver")}
        modules["mcp.server.mcpserver"].MCPServer = FakeServer
        spec = importlib.util.spec_from_file_location("worker_mcp", Path(__file__).resolve().parents[1] / "mcp" / "rworker-mcp.py")
        module = importlib.util.module_from_spec(spec)
        with patch.dict(sys.modules, modules), patch.object(sys, "argv", ["rworker-mcp", "--rworker", "rworker"]):
            spec.loader.exec_module(module)
        with patch.object(module, "run", return_value='{"name":"test"}') as run:
            self.assertEqual(module.up(profile="large-builder", disk_gib=500)["name"], "test")
        args = run.call_args.args
        self.assertIn("--profile", args)
        self.assertEqual(args[args.index("--profile") + 1], "large-builder")
        self.assertEqual(args[args.index("--disk") + 1], "500")
        with patch.object(module, "run", return_value='[{"name":"standard"}]') as run:
            self.assertEqual(module.profiles(), [{"name": "standard"}])
            run.assert_called_once_with("profiles", "--json", timeout=120)

    def test_niks3_token_is_default_and_optional(self):
        modules = {name: ModuleType(name) for name in ("mcp", "mcp.server", "mcp.server.mcpserver")}
        modules["mcp.server.mcpserver"].MCPServer = FakeServer
        spec = importlib.util.spec_from_file_location("worker_mcp", Path(__file__).resolve().parents[1] / "mcp" / "rworker-mcp.py")
        module = importlib.util.module_from_spec(spec)
        with patch.dict(sys.modules, modules), patch.object(sys, "argv", ["rworker-mcp", "--rworker", "rworker"]):
            spec.loader.exec_module(module)
        with patch.object(module, "run", return_value="{}") as run:
            module.up()
            self.assertNotIn("--no-niks3-token", run.call_args.args)
            module.up(niks3_token=False)
            self.assertIn("--no-niks3-token", run.call_args.args)
            module.extend("w", "2h")
            self.assertNotIn("--no-niks3-token", run.call_args.args)
            module.extend("w", "2h", niks3_token=False)
            self.assertIn("--no-niks3-token", run.call_args.args)
            module.niks3_token("w")
            self.assertEqual(run.call_args.args[:2], ("niks3-token", "w"))
            module.topic("w", "rbw release build")
            self.assertEqual(
                run.call_args.args[:4], ("topic", "w", "rbw release build", "--json"))
            module.claim("w", "rbw release build", "claude-code:abc")
            self.assertEqual(
                run.call_args.args,
                ("claim", "w", "--topic", "rbw release build",
                 "--agent-id", "claude-code:abc", "--json"))
            module.up(agent_id="claude-code:abc")
            self.assertIn("--agent-id", run.call_args.args)
            module.ls(agent_id="claude-code:abc")
            self.assertEqual(
                run.call_args.args,
                ("ls", "--json", "--agent-id", "claude-code:abc"))

    def test_exec_uses_registered_job_and_returns_exit_status(self):
        modules = {name: ModuleType(name) for name in ("mcp", "mcp.server", "mcp.server.mcpserver")}
        modules["mcp.server.mcpserver"].MCPServer = FakeServer
        spec = importlib.util.spec_from_file_location("worker_mcp", Path(__file__).resolve().parents[1] / "mcp" / "rworker-mcp.py")
        module = importlib.util.module_from_spec(spec)
        with patch.dict(sys.modules, modules), patch.object(sys, "argv", ["rworker-mcp", "--rworker", "rworker"]):
            spec.loader.exec_module(module)
        with patch.object(module, "run", side_effect=["job-123\n", "job-123\texit 7\ttoday\n", "output\n"]) as run:
            result = module.exec("worker", "exit 7")
        self.assertEqual(result["job"], "job-123")
        self.assertEqual(result["exit_code"], 7)
        self.assertIn("output", result["stdout"])
        self.assertEqual(run.call_args_list[0].args, ("start", "worker", "--", "exit 7"))


if __name__ == "__main__":
    unittest.main()
