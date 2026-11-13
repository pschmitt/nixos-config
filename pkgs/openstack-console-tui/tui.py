"""Run a terminal VNC viewer against a noVNC URL supplied privately on stdin."""

import argparse
import asyncio
import contextlib
import os
import signal
import sys
import termios
from urllib.parse import parse_qs, urlencode, urljoin, urlsplit

from websockets.asyncio.client import connect


def websocket_target(url):
    url = url.strip()
    page = urlsplit(url)
    if page.scheme not in ("http", "https", "ws", "wss") or not page.hostname:
        raise ValueError("Unsupported console URL")
    if page.username or page.password or page.fragment:
        raise ValueError("Unsupported console URL")
    secure = page.scheme in ("https", "wss")
    origin = ("https://" if secure else "http://") + page.netloc
    if page.scheme in ("ws", "wss"):
        return url, origin
    query = parse_qs(page.query)
    path = query.get("path", [""])[0]
    if not path:
        # Nova also returns vnc_auto.html?token=... without a path parameter.
        if not query.get("token"):
            raise ValueError("Console URL has neither path nor token")
        path = "websockify?" + urlencode({"token": query["token"][0]})
    target = urljoin(("wss://" if secure else "ws://") + page.netloc + "/", path)
    parsed = urlsplit(target)
    if (
        parsed.netloc != page.netloc
        or parsed.scheme != ("wss" if secure else "ws")
        or parsed.fragment
    ):
        raise ValueError("Console WebSocket must use the console origin")
    return target, origin


def viewer_command(viewer, port, view_only):
    if viewer == "desktui":
        command = [
            viewer,
            f"127.0.0.1::{port}",
            "--scale",
            "fit",
            "--transfer",
            "direct",
            "--no-clipboard",
        ]
        # tmux swallows the outer terminal's reply to the graphics probe, so
        # detection always fails there even when passthrough works.
        if os.environ.get("TMUX"):
            command.append("--force")
    elif viewer == "farsee":
        command = [
            viewer,
            "--allow-none-auth",
            "--accept-new-host",
            "--presenter",
            "kitty-direct",
            "--clipboard",
            "off",
            f"127.0.0.1:{port}",
        ]
    else:
        raise ValueError("Unsupported viewer")
    if view_only:
        command.append("--view-only")
    return command


async def relay(reader, writer, websocket):
    async def upstream():
        while data := await reader.read(65536):
            await websocket.send(data)

    async def downstream():
        async for data in websocket:
            if not isinstance(data, bytes):
                raise ValueError("Console sent nonbinary VNC data")
            writer.write(data)
            await writer.drain()

    tasks = [asyncio.create_task(upstream()), asyncio.create_task(downstream())]
    try:
        done, _ = await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
        for task in done:
            task.result()
    finally:
        for task in tasks:
            task.cancel()
        await asyncio.gather(*tasks, return_exceptions=True)


async def stop_process(process):
    if process.returncode is None:
        with contextlib.suppress(ProcessLookupError):
            process.terminate()
        try:
            await asyncio.wait_for(process.wait(), 3)
        except TimeoutError:
            with contextlib.suppress(ProcessLookupError):
                process.kill()
            await process.wait()


async def run_viewer(target, origin, viewer, view_only):
    loop = asyncio.get_running_loop()
    ended = loop.create_future()
    handlers = set()
    accepted = False

    async def handle(reader, writer):
        nonlocal accepted
        if accepted:
            writer.close()
            with contextlib.suppress(ConnectionError):
                await writer.wait_closed()
            return
        accepted = True
        task = asyncio.current_task()
        handlers.add(task)
        try:
            async with connect(
                target,
                origin=origin,
                subprotocols=["binary"],
                compression=None,
                max_size=None,
                open_timeout=15,
                proxy=None,
            ) as websocket:
                await relay(reader, writer, websocket)
        except Exception:
            # WebSocket exceptions can include the credential-bearing request URL.
            if not ended.done():
                ended.set_result(1)
        finally:
            writer.close()
            with contextlib.suppress(ConnectionError):
                await writer.wait_closed()
            if not ended.done():
                ended.set_result(0)
            handlers.discard(task)

    server = await asyncio.start_server(handle, "127.0.0.1", 0)
    port = server.sockets[0].getsockname()[1]
    process = None
    waiter = None
    terminal_state = None
    loop.add_signal_handler(
        signal.SIGTERM, lambda: ended.done() or ended.set_result(143)
    )
    try:
        async with server:
            # stdin carries the URL; the viewer must read keyboard input from the tty.
            with open("/dev/tty", "rb", buffering=0) as terminal:
                if os.isatty(terminal.fileno()):
                    terminal_state = termios.tcgetattr(terminal.fileno())
                command = viewer_command(viewer, port, view_only)
                print(f"Opening {viewer}; clipboard disabled.", file=sys.stderr)
                if viewer == "desktui":
                    print("Disconnect with Ctrl+A, then q.", file=sys.stderr)
                process = await asyncio.create_subprocess_exec(*command, stdin=terminal)
            waiter = asyncio.create_task(process.wait())
            done, _ = await asyncio.wait(
                [waiter, ended], return_when=asyncio.FIRST_COMPLETED
            )
            if ended in done and ended.result():
                return ended.result()
            # On a clean socket close, let the viewer handle EOF and restore its tty.
            if waiter not in done:
                try:
                    await asyncio.wait_for(asyncio.shield(waiter), 3)
                except TimeoutError:
                    return 1
            return waiter.result() if waiter.result() >= 0 else 128 - waiter.result()
    finally:
        loop.remove_signal_handler(signal.SIGTERM)
        server.close()
        await server.wait_closed()
        forced = process is not None and process.returncode is None
        if process is not None:
            await stop_process(process)
        if terminal_state is not None:
            with open("/dev/tty", "wb", buffering=0) as terminal:
                termios.tcsetattr(terminal.fileno(), termios.TCSANOW, terminal_state)
                if forced or (process is not None and process.returncode):
                    # A killed viewer cannot restore raw input and terminal modes itself.
                    terminal.write(
                        b"\x1b[?1000l\x1b[?1002l\x1b[?1003l\x1b[?1006l\x1b[?1016l"
                        b"\x1b[?2004l\x1b[?2026l\x1b[?1049l\x1b[?25h\x1b[0m"
                    )
                    # Kitty images live in the outer terminal and outlast the viewer.
                    delete = b"\x1b_Ga=d,d=A,q=2\x1b\\"
                    if os.environ.get("TMUX"):
                        escaped = delete.replace(b"\x1b", b"\x1b\x1b")
                        delete = b"\x1bPtmux;" + escaped + b"\x1b\\"
                    terminal.write(delete)
        for task in list(handlers):
            task.cancel()
        await asyncio.gather(*handlers, return_exceptions=True)
        if waiter is not None:
            await waiter


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--viewer", choices=("desktui", "farsee"), required=True)
    parser.add_argument("--view-only", action="store_true")
    args = parser.parse_args()
    try:
        if args.viewer == "farsee" and os.environ.get("TMUX"):
            raise ValueError("farsee cannot run inside tmux")
        target, origin = websocket_target(sys.stdin.read(65536))
        result = asyncio.run(run_viewer(target, origin, args.viewer, args.view_only))
        if result:
            print(
                "Console connection or viewer failed (details suppressed).",
                file=sys.stderr,
            )
        return result
    except KeyboardInterrupt:
        return 130
    except Exception:
        print(
            "Console bridge failed (details suppressed to protect credentials).",
            file=sys.stderr,
        )
        return 1


if __name__ == "__main__":
    sys.exit(main())
