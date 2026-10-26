"""One MCP server in front of hypruse on several hosts.

Exposes hypruse's tools with an extra required `host` argument and forwards
each call over SSH (stdio) to that host's hypruse. Connections are opened
lazily and per host, so a powered-off laptop costs nothing until it is used,
and every agent gets its own SSH sessions.
"""

import argparse
import asyncio
import contextlib
import json
import os
import pathlib
import sys

import anyio
import mcp.types as types
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client
from mcp.server.lowlevel import Server
from mcp.server.stdio import stdio_server

CONNECT_TIMEOUT = 20
CALL_TIMEOUT = 120
CACHE_FILE = (
    pathlib.Path(os.environ.get("XDG_CACHE_HOME") or pathlib.Path.home() / ".cache")
    / "hypruse-hub"
    / "tools.json"
)


def log(msg):
    print(f"hypruse-hub: {msg}", file=sys.stderr, flush=True)


class Remote:
    """One SSH-backed hypruse session, owned by a single task."""

    def __init__(self, host, ssh, remote_cmd):
        self.host = host
        self.params = StdioServerParameters(
            command=ssh,
            args=[
                "-q",
                "-T",
                "-o",
                "BatchMode=yes",
                "-o",
                "ConnectTimeout=10",
                "-o",
                "ServerAliveInterval=30",
                host,
                remote_cmd,
            ],
        )
        self.queue = None
        self.ready = None
        self.task = None

    async def _run(self):
        try:
            async with stdio_client(self.params) as (read, write):
                async with ClientSession(read, write) as session:
                    await asyncio.wait_for(session.initialize(), CONNECT_TIMEOUT)
                    self.ready.set_result(session)
                    while True:
                        job = await self.queue.get()
                        if job is None:
                            return
                        fut, coro = job
                        try:
                            fut.set_result(await coro(session))
                        except Exception as exc:  # noqa: BLE001
                            fut.set_exception(exc)
                            if isinstance(exc, (anyio.ClosedResourceError, EOFError)):
                                return
        except BaseException as exc:  # noqa: BLE001
            if not self.ready.done():
                self.ready.set_exception(RuntimeError(f"{self.host}: {exc!r}"))
            log(f"{self.host}: session ended: {exc!r}")
        finally:
            self.task = None

    async def run(self, coro):
        if self.task is None:
            self.queue = asyncio.Queue()
            self.ready = asyncio.get_running_loop().create_future()
            self.task = asyncio.create_task(self._run())
        await asyncio.wait_for(asyncio.shield(self.ready), CONNECT_TIMEOUT + 5)
        fut = asyncio.get_running_loop().create_future()
        await self.queue.put((fut, coro))
        return await asyncio.wait_for(fut, CALL_TIMEOUT)

    async def close(self):
        if self.task is not None:
            await self.queue.put(None)
            with contextlib.suppress(Exception):
                await self.task


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ssh", required=True)
    ap.add_argument("--remote-cmd", required=True)
    ap.add_argument("hosts", nargs="+")
    args = ap.parse_args()

    remotes = {h: Remote(h, args.ssh, args.remote_cmd) for h in args.hosts}
    server = Server("hypruse")
    tools_cache = []

    async def fetch_tools():
        errors = []
        for host, remote in remotes.items():
            try:
                res = await remote.run(lambda s: s.list_tools())
                return res.tools
            except Exception as exc:  # noqa: BLE001
                errors.append(f"{host}: {exc!r}")
        raise RuntimeError("no host reachable: " + "; ".join(errors))

    def load_cache():
        try:
            return [
                types.Tool.model_validate(t) for t in json.loads(CACHE_FILE.read_text())
            ]
        except (OSError, ValueError):
            return []

    def save_cache(tools):
        try:
            CACHE_FILE.parent.mkdir(parents=True, exist_ok=True)
            CACHE_FILE.write_text(
                json.dumps(
                    [t.model_dump(mode="json", exclude_none=True) for t in tools]
                )
            )
        except OSError as exc:
            log(f"cannot write tool cache: {exc!r}")

    async def refresh_cache():
        try:
            tools = await fetch_tools()
        except Exception as exc:  # noqa: BLE001
            log(f"tool cache not refreshed: {exc}")
            return
        tools_cache[:] = tools
        save_cache(tools)

    background = set()

    @server.list_tools()
    async def list_tools():
        # Answer from the cache so the server works with every laptop off;
        # refresh it from a live host in the background.
        if not tools_cache:
            tools_cache.extend(load_cache())
            if tools_cache:
                task = asyncio.create_task(refresh_cache())
                background.add(task)
                task.add_done_callback(background.discard)
            else:
                await refresh_cache()
        if not tools_cache:
            raise RuntimeError("no hypruse tool list cached and no host reachable yet")
        out = []
        for tool in tools_cache:
            schema = dict(tool.inputSchema or {"type": "object"})
            props = dict(schema.get("properties") or {})
            props["host"] = {
                "type": "string",
                "enum": list(remotes),
                "description": "Which machine's Hyprland desktop to act on.",
            }
            schema["properties"] = props
            schema["required"] = ["host", *schema.get("required", [])]
            out.append(
                types.Tool(
                    name=tool.name,
                    description=tool.description,
                    inputSchema=schema,
                    annotations=tool.annotations,
                )
            )
        return out

    @server.call_tool(validate_input=False)
    async def call_tool(name, arguments):
        arguments = dict(arguments or {})
        host = arguments.pop("host", None)
        if host not in remotes:
            raise ValueError(f"host must be one of {list(remotes)}, got {host!r}")
        remote = remotes[host]
        try:
            res = await remote.run(lambda s: s.call_tool(name, arguments))
        except (asyncio.TimeoutError, anyio.ClosedResourceError, EOFError):
            # Stale connection: drop it and retry once on a fresh one.
            await remote.close()
            res = await remote.run(lambda s: s.call_tool(name, arguments))
        if res.isError:
            text = " ".join(c.text for c in res.content if hasattr(c, "text"))
            raise RuntimeError(text or "hypruse reported an error")
        return res.content

    async def serve():
        async with stdio_server() as (read, write):
            await server.run(read, write, server.create_initialization_options())
        for remote in remotes.values():
            await remote.close()

    asyncio.run(serve())


if __name__ == "__main__":
    main()
