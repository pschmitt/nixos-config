#!/usr/bin/env python3
"""Open a TermuxPP shell through ADB using run-as or authenticated mTLS."""

import argparse
import base64
import getpass
import hashlib
import hmac
import json
import os
import selectors
import select
import threading
import shlex
import socket
import ssl
import subprocess
import sys
import tempfile
import termios
import time
import tty
from pathlib import Path

if str(Path(__file__).resolve().parent) not in sys.path:
    sys.path.insert(0, str(Path(__file__).resolve().parent))
import termuxpp_adb_devices as devices


HOST = "127.0.0.1"
DEVICE_PORT = 5522
HOST_PORT = DEVICE_PORT
TLS_PREFACE = b"TERMUXPP/TLS/1\n"
DEFAULT_CREDENTIAL_DIR = devices.DEFAULT_CREDENTIAL_DIR


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--provision", action="store_true", help="create and install fresh mTLS credentials")
    mode.add_argument("--list-authorizations", action="store_true", help="list approved client certificates")
    mode.add_argument("--revoke", metavar="SHA256", help="revoke one approved client certificate")
    parser.add_argument("--name", default=socket.gethostname(), help="display name shown for fingerprint approval")
    parser.add_argument("--serial", help="ADB serial or configured device alias of the target (required for device operations)")
    parser.add_argument("--devices-config", type=Path,
                        help="private JSON device alias configuration (default: $XDG_CONFIG_HOME/termuxpp/adb-devices.json)")
    parser.add_argument("--list-aliases", action="store_true", help="print configured device aliases and exit")
    parser.add_argument("--completions", choices=("bash", "zsh", "fish"),
                        help="print shell completion integration and exit")
    parser.add_argument("--credential-dir", type=Path,
                        help="private directory for this device's mTLS credentials (default: per device)")
    parser.add_argument("--mode", choices=("auto", "mtls", "run-as"), default="auto",
                        help="shell transport (default: auto tries run-as, then mTLS for non-debuggable apps)")
    parser.add_argument("--outer", action="store_true", help="use the native TermuxPP shell instead of the Nix guest")
    parser.add_argument("--shell", help="override the native login shell with an executable name or absolute path")
    parser.add_argument("command", nargs=argparse.REMAINDER, metavar="COMMAND",
                        help="run command and arguments without a PTY (use -- before the command)")
    args = parser.parse_args()
    if args.command[:1] == ["--"]:
        args.command = args.command[1:]
    if args.command and (args.provision or args.list_authorizations or args.revoke is not None or args.completions
                         or args.list_aliases):
        parser.error("commands cannot be combined with provisioning, authorization management or completions")
    if args.command and (len(args.command) > 4096 or any("\0" in arg for arg in args.command)
                         or not args.command[0] or args.command[0].startswith("-")):
        parser.error("command requires an executable (not an option), no NULs and at most 4096 arguments")
    if len(json.dumps({"shell": args.shell, "argv": args.command}, ensure_ascii=False).encode("utf-8")) > 65536:
        parser.error("command request exceeds 64 KiB")
    if args.shell is not None and (not args.shell or len(args.shell) > 4000 or not args.shell.isascii()
                                   or any(c.isspace() or ord(c) < 32 or ord(c) == 127 for c in args.shell)):
        parser.error("--shell must be an ASCII executable name or path without whitespace")
    if (args.shell or args.outer) and (args.provision or args.list_authorizations or args.revoke is not None):
        parser.error("--shell and --outer are only valid for shell sessions")
    if not args.completions and not args.list_aliases and not args.serial:
        parser.error("--serial is required for device operations")
    if args.mode == "run-as" and (args.provision or args.list_authorizations or args.revoke is not None):
        parser.error("provisioning and authorization management require mTLS, not --mode run-as")
    return args


def read_line(connection):
    data = bytearray()
    while len(data) <= 16:
        byte = connection.recv(1)
        if not byte:
            break
        if byte == b"\n":
            break
        data.extend(byte)
    return bytes(data)


def run_terminal(connection):
    selector = selectors.DefaultSelector()
    selector.register(connection, selectors.EVENT_READ, "socket")
    selector.register(sys.stdin, selectors.EVENT_READ, "stdin")
    try:
        while True:
            for key, _ in selector.select():
                if key.data == "socket":
                    data = connection.recv(8192)
                    if not data:
                        return
                    sys.stdout.buffer.write(data)
                    sys.stdout.buffer.flush()
                else:
                    data = os.read(sys.stdin.fileno(), 8192)
                    if not data:
                        connection.shutdown(socket.SHUT_WR)
                        selector.unregister(sys.stdin)
                        continue
                    connection.sendall(data)
    finally:
        selector.close()


def setup_forwarding(serial):
    try:
        result = subprocess.run(["adb", "-s", serial, "forward", "tcp:0", f"tcp:{DEVICE_PORT}"],
                                check=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
        port = int(result.stdout.strip())
        if not 1 <= port <= 65535:
            raise ValueError("invalid forwarding port")
        return port
    except (OSError, subprocess.CalledProcessError, ValueError) as error:
        raise RuntimeError("adb port forwarding failed.") from error


def remove_forwarding(serial, port):
    subprocess.run(["adb", "-s", serial, "forward", "--remove", f"tcp:{port}"], check=False,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def request_token():
    try:
        return getpass.getpass("TermuxPP ADB shell token: ").encode("ascii")
    except UnicodeEncodeError:
        raise RuntimeError("The access token must be ASCII.") from None


def receive_exact(connection, count):
    data = bytearray()
    while len(data) < count:
        chunk = connection.recv(count - len(data))
        if not chunk:
            raise RuntimeError("The device closed the mTLS connection before completing the operation.")
        data.extend(chunk)
    return bytes(data)


def receive_frame(connection):
    length = int.from_bytes(receive_exact(connection, 4), "big")
    if not 1 <= length <= 16 * 1024:
        raise RuntimeError("The device sent an invalid mTLS provisioning frame.")
    return receive_exact(connection, length)


def send_frame(connection, data):
    if not 1 <= len(data) <= 16 * 1024:
        raise RuntimeError("Invalid mTLS provisioning data size.")
    connection.sendall(len(data).to_bytes(4, "big") + data)


def bootstrap(token, operation, material_factory=None):
    with socket.create_connection((HOST, HOST_PORT), timeout=10) as connection:
        connection.settimeout(10)
        client_nonce = os.urandom(32)
        operation_bytes = operation.encode("ascii")
        connection.sendall(b"TERMUXPP/BOOT/3 " + operation_bytes + b" " + base64.b64encode(client_nonce) + b"\n")
        device_public_key = receive_frame(connection)
        server_nonce = receive_frame(connection)
        existing_certificate = receive_frame(connection)
        server_proof = receive_frame(connection)
        if len(server_nonce) != 32:
            raise RuntimeError("Invalid bootstrap challenge.")
        transcript = (b"TERMUXPP/BOOT/3\0" + operation_bytes + b"\0" + client_nonce + server_nonce
                      + hashlib.sha256(device_public_key).digest()
                      + hashlib.sha256(existing_certificate).digest())

        def proof(role, data):
            return hmac.digest(token, role + b"\0" + data, "sha256")

        if not hmac.compare_digest(server_proof, proof(b"server", transcript)):
            raise RuntimeError("Bootstrap server authentication failed.")
        send_frame(connection, proof(b"client", transcript))
        if operation == "PROVISION":
            if material_factory is None:
                raise RuntimeError("mTLS provisioning materials are unavailable.")
            materials = material_factory(device_public_key, existing_certificate)
            digest = hashlib.sha256()
            for data in materials:
                digest.update(len(data).to_bytes(4, "big"))
                digest.update(data)
                send_frame(connection, data)
            send_frame(connection, proof(b"material", transcript + digest.digest()))
        connection.settimeout(130)
        response = read_line(connection)
        if response == b"ERR_APPROVAL":
            raise RuntimeError("Fingerprint approval was denied, unavailable, or expired.")
        if response == b"ERR_KEY":
            raise RuntimeError("The device could not decrypt the server key.")
        if response == b"ERR_CERT":
            raise RuntimeError("The device rejected the mTLS certificates or could not store them.")
        if response != b"OK":
            raise RuntimeError("The device rejected the mTLS operation.")


def run_openssl(*args, input_text=None):
    try:
        result = subprocess.run(["openssl", *args], input=input_text, text=True,
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    except FileNotFoundError:
        raise RuntimeError("openssl is required to provision mTLS credentials.") from None
    if result.returncode != 0:
        raise RuntimeError("openssl failed while creating mTLS credentials.")


def create_credentials(credential_dir, name=None):
    name = name or socket.gethostname()
    if not name.strip() or len(name) > 128 or any(ord(c) < 32 or ord(c) == 127 for c in name):
        raise RuntimeError("Invalid client display name.")
    if (credential_dir / "client.key").exists():
        raise RuntimeError("Client credentials already exist; use a new credential directory to enroll another identity.")
    if credential_dir.is_symlink():
        raise RuntimeError("Credential directory must not be a symbolic link.")
    credential_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(credential_dir, 0o700)
    with tempfile.TemporaryDirectory(prefix="termuxpp-adb-mtls-") as temporary:
        work = Path(temporary)
        extensions = work / "client.ext"
        extensions.write_text(
            "basicConstraints=critical,CA:FALSE\n"
            "keyUsage=critical,digitalSignature\n"
            "extendedKeyUsage=clientAuth\n"
            "subjectKeyIdentifier=hash\n"
            "authorityKeyIdentifier=keyid,issuer\n",
            encoding="ascii",
        )
        server_extensions = work / "server.ext"
        server_extensions.write_text(
            "basicConstraints=critical,CA:FALSE\n"
            "keyUsage=critical,digitalSignature,keyEncipherment\n"
            "extendedKeyUsage=serverAuth\n"
            "subjectAltName=IP:127.0.0.1\n",
            encoding="ascii",
        )
        server_config = write_openssl_config(work, server_extensions)
        run_openssl("genpkey", "-algorithm", "EC", "-pkeyopt", "ec_paramgen_curve:P-256",
                    "-out", str(work / "server.key"))
        run_openssl("req", "-new", "-x509", "-key", str(work / "server.key"), "-sha256", "-days", "365",
                    "-subj", "/CN=TermuxPP ADB Shell Server", "-out", str(work / "server.crt"),
                    "-extensions", "v3_req", "-config", str(server_config))
        run_openssl("pkcs8", "-topk8", "-nocrypt", "-in", str(work / "server.key"), "-outform", "DER",
                    "-out", str(work / "server.pk8"))
        run_openssl("req", "-x509", "-newkey", "rsa:3072", "-nodes", "-sha256", "-days", "3650",
                    "-subj", "/CN=TermuxPP ADB Shell Client CA", "-keyout", str(work / "client-ca.key"),
                    "-out", str(work / "client-ca.crt"), "-addext", "basicConstraints=critical,CA:TRUE",
                    "-addext", "keyUsage=critical,keyCertSign,cRLSign")
        run_openssl("req", "-new", "-newkey", "rsa:3072", "-nodes", "-sha256", "-subj",
                    "/CN=TermuxPP ADB Shell Client", "-keyout", str(work / "client.key"),
                    "-out", str(work / "client.csr"))
        run_openssl("x509", "-req", "-in", str(work / "client.csr"), "-CA", str(work / "client-ca.crt"),
                    "-CAkey", str(work / "client-ca.key"), "-CAcreateserial", "-out", str(work / "client.crt"),
                    "-days", "90", "-sha256", "-extfile", str(extensions))
        for filename in ("server.key", "server.pk8", "server.crt", "client.key", "client.crt", "client-ca.key", "client-ca.crt"):
            os.chmod(work / filename, 0o600)
        token = request_token()

        der = ssl.PEM_cert_to_DER_cert((work / "client.crt").read_text(encoding="ascii"))
        print(f"Client certificate SHA-256: {hashlib.sha256(der).hexdigest()}", file=sys.stderr)
        print("Open the TermuxPP approval notification, compare the fingerprint, and touch the fingerprint sensor.",
              file=sys.stderr)

        def encrypt_server_key(device_public_key, existing_certificate):
            if existing_certificate != b"\0":
                (work / "server.crt").write_bytes(existing_certificate)
            public_key_file = work / "device-provisioning.pub"
            public_key_file.write_bytes(device_public_key)
            encrypted_key = work / "server.pk8.enc"
            run_openssl("pkeyutl", "-encrypt", "-pubin", "-inkey", str(public_key_file),
                        "-in", str(work / "server.pk8"), "-out", str(encrypted_key),
                        "-pkeyopt", "rsa_padding_mode:oaep", "-pkeyopt", "rsa_oaep_md:sha256",
                        "-pkeyopt", "rsa_mgf1_md:sha256")
            return (encrypted_key.read_bytes(), (work / "server.crt").read_bytes(),
                    (work / "client-ca.crt").read_bytes(), (work / "client.crt").read_bytes(), name.encode("utf-8"))

        bootstrap(token, "PROVISION", encrypt_server_key)
        for name in ("server.crt", "client.key", "client.crt", "client-ca.crt"):
            destination = credential_dir / name
            descriptor, temporary_path = tempfile.mkstemp(prefix=".credential-", dir=credential_dir)
            temporary_copy = Path(temporary_path)
            try:
                with os.fdopen(descriptor, "wb") as output:
                    output.write((work / name).read_bytes())
                    output.flush()
                    os.fsync(output.fileno())
                os.chmod(temporary_copy, 0o600)
                os.replace(temporary_copy, destination)
            finally:
                try:
                    temporary_copy.unlink()
                except FileNotFoundError:
                    pass


def write_openssl_config(work, extensions):
    config = work / "openssl.cnf"
    config.write_text(
        "[req]\n"
        "distinguished_name=dn\n"
        "x509_extensions=v3_req\n"
        "prompt=no\n"
        "[dn]\n"
        "CN=TermuxPP ADB Shell Server\n"
        "[v3_req]\n"
        f"{extensions.read_text(encoding='ascii')}",
        encoding="ascii",
    )
    return config


def manage_authorizations(credential_dir, revoke=None):
    if revoke is not None and (len(revoke) != 64 or any(c not in "0123456789abcdef" for c in revoke)):
        raise RuntimeError("Revocation requires the full lowercase SHA-256 certificate fingerprint.")
    with authenticated_connection(credential_dir) as connection:
        if revoke is None:
            connection.sendall(b"LIST\n")
            entries = json.loads(receive_frame(connection))
            print(json.dumps(entries, ensure_ascii=True, indent=2))
        else:
            connection.sendall(b"REVOKE " + revoke.encode("ascii") + b"\n")
            if read_line(connection) != b"OK":
                raise RuntimeError("The device could not persist revocation.")
            print("Client authorization revoked.", file=sys.stderr)


def load_tls_credentials(credential_dir):
    server_cert = credential_dir / "server.crt"
    client_cert = credential_dir / "client.crt"
    client_key = credential_dir / "client.key"
    if not all(path.is_file() for path in (server_cert, client_cert, client_key)):
        raise RuntimeError("mTLS credentials are missing; run with --provision first.")
    context = ssl.create_default_context(ssl.Purpose.SERVER_AUTH, cafile=str(server_cert))
    context.check_hostname = True
    context.verify_mode = ssl.CERT_REQUIRED
    context.load_cert_chain(certfile=str(client_cert), keyfile=str(client_key))
    return context


def connect_tls(context):
    for attempt in range(4):
        try:
            raw_connection = socket.create_connection((HOST, HOST_PORT), timeout=10)
            try:
                raw_connection.sendall(TLS_PREFACE)
                return context.wrap_socket(raw_connection, server_hostname=HOST)
            except BaseException:
                raw_connection.close()
                raise
        except (ConnectionRefusedError, ConnectionResetError, ssl.SSLEOFError):
            if attempt == 3:
                raise RuntimeError(
                    "TermuxPP's mTLS listener is unavailable or closed the TLS handshake. "
                    "Open the updated TermuxPP app to restore enabled access, and check "
                    "Settings > Debugging > ADB shell access. Do not toggle enabled access off "
                    "just to restart it: that revokes approvals. If the listener is running, check "
                    "that this client's certificate is still approved."
                ) from None
            time.sleep(1)


def authenticated_connection(credential_dir):
    context = load_tls_credentials(credential_dir)
    connection = connect_tls(context)
    try:
        connection.sendall(b"TERMUXPP/2\n")
        if read_line(connection) != b"OK":
            raise RuntimeError("Certificate authentication failed; update the TermuxPP app for token-free sessions.")
        return connection
    except BaseException:
        connection.close()
        raise


def run_shell(credential_dir, shell=None):
    if not sys.stdin.isatty() or not sys.stdout.isatty():
        raise RuntimeError("This command requires an interactive terminal.")
    connection = None
    terminal_state = termios.tcgetattr(sys.stdin.fileno())
    try:
        connection = authenticated_connection(credential_dir)
        connection.sendall(("SHELL" + (" " + shell if shell else "") + "\n").encode("ascii"))
        if read_line(connection) != b"OK":
            raise RuntimeError("The device rejected shell access; check that the Nix guest is ready or use --outer.")
        connection.settimeout(None)
        tty.setraw(sys.stdin.fileno())
        run_terminal(connection)
    finally:
        termios.tcsetattr(sys.stdin.fileno(), termios.TCSADRAIN, terminal_state)
        if connection is not None:
            connection.close()


def run_command(credential_dir, shell, argv):
    request = json.dumps({"shell": shell, "argv": argv}, ensure_ascii=False).encode("utf-8")
    if not 1 <= len(request) <= 65536:
        raise RuntimeError("Command request exceeds 64 KiB.")
    stopped = threading.Event()
    input_errors = []
    with authenticated_connection(credential_dir) as connection:
        connection.sendall(b"EXEC\n" + len(request).to_bytes(4, "big") + request)
        if read_line(connection) != b"OK":
            raise RuntimeError("The device rejected command execution; check that the Nix guest is ready or use --outer.")
        connection.settimeout(None)

        def send_input():
            try:
                while not stopped.is_set():
                    if not select.select([sys.stdin.fileno()], [], [], 0.1)[0]:
                        continue
                    data = os.read(sys.stdin.fileno(), 8192)
                    if stopped.is_set():
                        return
                    connection.sendall((b"I" if data else b"E") + len(data).to_bytes(4, "big") + data)
                    if not data:
                        return
            except (OSError, ValueError) as error:
                if not stopped.is_set():
                    input_errors.append(error)
                    try:
                        connection.shutdown(socket.SHUT_RDWR)
                    except OSError:
                        pass

        writer = threading.Thread(target=send_input, daemon=True)
        writer.start()
        try:
            while True:
                kind = receive_exact(connection, 1)
                length = int.from_bytes(receive_exact(connection, 4), "big")
                if kind not in (b"O", b"R", b"X") or length > 65536 or (kind == b"X" and length != 4):
                    raise RuntimeError("The device sent an invalid command response.")
                data = receive_exact(connection, length)
                if kind == b"X":
                    returncode = int.from_bytes(data, "big", signed=True)
                    if not 0 <= returncode <= 255:
                        raise RuntimeError("The device sent an invalid command exit status.")
                    return returncode
                stream = sys.stdout.buffer if kind == b"O" else sys.stderr.buffer
                stream.write(data)
                stream.flush()
        except RuntimeError:
            if input_errors:
                raise RuntimeError("Could not stream command input.") from None
            raise
        finally:
            stopped.set()
            try:
                connection.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            writer.join(timeout=1)


PACKAGE = "dev.pschmitt.termux"
GUEST_LOGIN = f"/data/data/{PACKAGE}/files/home/.local/share/termuxpp-nix/login.sh"


def supports_run_as(serial):
    result = subprocess.run(
        ["adb", "-s", serial, "shell", "run-as", PACKAGE, "id", "-u"],
        stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=15,
    )
    if result.returncode == 0 and result.stdout.strip().isdigit():
        return True
    if "package not debuggable" in result.stderr or "package not debuggable" in result.stdout:
        return False
    raise RuntimeError("Could not probe run-as; check the ADB connection and installed TermuxPP package.")


def run_as_shell(serial, shell=None, command=None):
    if not command and (not sys.stdin.isatty() or not sys.stdout.isatty()):
        raise RuntimeError("This command requires an interactive terminal.")
    result = subprocess.run(["adb", "-s", serial, "shell", "pm", "path", PACKAGE],
                            stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=15)
    paths = [line.removeprefix("package:") for line in result.stdout.splitlines()
             if line.startswith("package:") and line.endswith("/base.apk")]
    if result.returncode != 0 or len(paths) != 1:
        raise RuntimeError("Could not locate the installed TermuxPP APK.")
    apk_dir = str(Path(paths[0]).parent)
    script = f"""export HOME=/data/data/{PACKAGE}/files/home
export PREFIX=/data/data/{PACKAGE}/files/usr
export TERMUX_APP__DATA_DIR=/data/data/{PACKAGE}
export PATH="$PREFIX/bin:/system/bin:/system/xbin"
export LD_LIBRARY_PATH="$PREFIX/lib"
export TERM="${{TERM:-xterm-256color}}"
for redirect in {shlex.quote(apk_dir)}/lib/*/libtermux-pkg-redirect.so
do
  if [ -f "$redirect" ]
  then
    export LD_PRELOAD="$redirect"
    break
  fi
done
if [ -z "${{LD_PRELOAD:-}}" ]
then
  printf '%s\\n' 'TermuxPP prefix redirect library is missing.' >&2
  exit 1
fi
if [ -f "$PREFIX/lib/libtermux-exec.so" ]
then
  export LD_PRELOAD="$LD_PRELOAD:$PREFIX/lib/libtermux-exec.so"
fi
cd "$HOME" || exit 1
SHELL={shlex.quote(shell or '')}
if [ -z "$SHELL" ]
then
  for config in "$HOME/.config/termuxpp/shell" "$HOME/.config/termux/shell" "$HOME/.termux/shell"
  do
    if [ -e "$config" ] || [ -L "$config" ]
    then
      SHELL="$config"
      break
    fi
  done
fi
if [ -z "$SHELL" ]
then
  SHELL="$PREFIX/bin/bash"
  [ -x "$SHELL" ] || SHELL="$PREFIX/bin/sh"
fi
case "$SHELL" in
  /*) ;;
  *) SHELL="$PREFIX/bin/$SHELL" ;;
esac
SHELL=$(/system/bin/readlink -f "$SHELL") || exit 1
if [ ! -f "$SHELL" ] || [ ! -x "$SHELL" ]
then
  printf '%s\\n' 'Selected shell is not executable.' >&2
  exit 1
fi
export SHELL
exec "$SHELL" -l
"""
    if command:
        arguments = shlex.join(command)
        script = script.replace('exec "$SHELL" -l\n', f'''case "${{SHELL##*/}}" in
  fish) exec "$SHELL" -l -c 'exec $argv' {arguments} ;;
  *) exec "$SHELL" -l -c 'exec "$@"' termuxpp-command {arguments} ;;
esac
''')
    remote = shlex.join(["run-as", PACKAGE, "/system/bin/sh", "-c", script])
    print("Using run-as (debuggable TermuxPP).", file=sys.stderr)
    return subprocess.run(["adb", "-s", serial, "shell", "-T" if command else "-tt", remote]).returncode


def main():
    global HOST_PORT
    os.umask(0o077)
    args = parse_args()
    if args.completions:
        completion = Path(__file__).resolve().parent / "completions" / f"termuxpp-adb-shell.{args.completions}"
        try:
            print(completion.read_text(encoding="utf-8"), end="")
        except OSError as error:
            print(f"Could not load completions: {error}", file=sys.stderr)
            return 1
        return 0
    if args.list_aliases:
        try:
            print("\n".join(sorted(devices.load_aliases(args.devices_config))))
        except (OSError, RuntimeError) as error:
            print(f"ADB shell failed: {error}", file=sys.stderr)
            return 1
        return 0
    try:
        device = devices.resolve_device(args.serial, args.devices_config, credential_root=DEFAULT_CREDENTIAL_DIR)
    except (OSError, RuntimeError) as error:
        print(f"ADB shell failed: {error}", file=sys.stderr)
        return 1
    args.serial = device.serial
    if device.credential_error and args.credential_dir is None:
        print(f"ADB shell failed: {device.credential_error}", file=sys.stderr)
        return 1
    if args.credential_dir is None:
        args.credential_dir = device.credential_dir
    management = args.provision or args.list_authorizations or args.revoke is not None
    shell = args.shell if args.shell or args.outer else GUEST_LOGIN
    try:
        if not management and args.mode != "mtls":
            if supports_run_as(args.serial):
                if args.command:
                    return run_as_shell(args.serial, shell, args.command)
                return run_as_shell(args.serial, shell)
            if args.mode == "run-as":
                raise RuntimeError("run-as requires a debuggable TermuxPP APK; use --mode mtls instead.")
            print("TermuxPP is not debuggable; using mTLS.", file=sys.stderr)
    except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(f"ADB shell failed: {error}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        return 130
    if args.credential_dir.is_symlink():
        print("Credential directory must not be a symbolic link.", file=sys.stderr)
        return 2
    if args.credential_dir.exists() and not args.credential_dir.is_dir():
        print("Credential path is not a directory.", file=sys.stderr)
        return 2
    forward = None
    try:
        forward = setup_forwarding(args.serial)
        HOST_PORT = forward
        if args.provision:
            create_credentials(args.credential_dir, args.name)
            print(f"mTLS credentials installed in {args.credential_dir}", file=sys.stderr)
        elif args.revoke or args.list_authorizations:
            manage_authorizations(args.credential_dir, args.revoke)
        else:
            if args.command:
                return run_command(args.credential_dir, shell, args.command)
            run_shell(args.credential_dir, shell)
        return 0
    except (OSError, RuntimeError, ssl.SSLError, termios.error) as error:
        print(f"ADB shell failed: {error}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        return 130
    finally:
        if forward is not None:
            remove_forwarding(args.serial, forward)


if __name__ == "__main__":
    sys.exit(main())
