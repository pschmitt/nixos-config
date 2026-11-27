"""Regression gate for the nixpp guest runtime.

Checks the commands the Android runtime has broken before: eza listings (alternate
signal stacks), zsh, Neovim, Nix configuration/registry (local only), Unix domain
sockets (short paths, tmux), a basic Go-built command (kubectl version --client; nothing
is compiled on the device) and the Rust CLIs that crashed with SIGSEGV (bat, rg incl. PCRE,
fd, rbw version, osc version). The Rust CLIs run against small generated fixture files in
the scratch directory with a scratch HOME/XDG: they never touch a vault, a config, a
daemon or the network. Nothing here reads personal data: outputs are only matched for
markers, never printed.

Two contexts, selected by --isolated:

* candidate (--isolated --generation DIR): run before activation against a Home
  Manager generation in the store. PATH is only DIR/home-path/bin, HOME, XDG_*
  and TMPDIR point into a scratch directory, and the environment is rebuilt from
  an allow-list. Nothing in the real home is read or written. Startup files are
  syntax-checked (zsh -n), never executed.
* active: run after activation in the real guest context (real HOME, login zsh,
  the user's Neovim configuration).

The isolation is environment scrubbing in the same Android runtime. It is not a
namespace, so it does not block the network and it cannot stop a tool that
ignores its environment.
"""
import argparse
import fnmatch
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from pathlib import Path

CHECKS = ('zsh', 'nvim', 'eza', 'nix', 'sockets', 'tmux', 'go', 'bat', 'rg', 'fd', 'rbw', 'osc', 'vivid', 'zoxide', 'rsync')
# Variables copied into the isolated environment. Runtime-specific launcher
# variables belong in NIXPP_PASS_ENV (space separated names or globs).
PASS_ENV = (
    'LANG',
    'NIX_STATE_DIR',
    'NIX_STORE_DIR',
    'NIX_LOG_DIR',
    'NIX_REMOTE',
    'NIX_DAEMON_SOCKET_PATH',
)
ZSH_FILES = ('.zshenv', '.zprofile', '.zshrc', '.zlogin')
MAX_DETAIL = 300
MAX_OUTPUT = 65536
# AF_UNIX paths are limited to about 108 bytes; stay well below.
MAX_SOCKET_PATH = 90

SOCKET_SCRIPT = '''
import os, socket, stat, sys
path = sys.argv[1]
server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
server.settimeout(5)
client.settimeout(5)
try:
    server.bind(path)
    assert stat.S_ISSOCK(os.stat(path).st_mode)
    server.listen(1)
    client.connect(path)
    conn, _ = server.accept()
    conn.settimeout(5)
    client.sendall(b"ping")
    assert conn.recv(4) == b"ping"
    conn.sendall(b"pong")
    assert client.recv(4) == b"pong"
    a, b = socket.socketpair()
    a.sendall(b"x")
    assert b.recv(1) == b"x"
finally:
    server.close()
    client.close()
    if os.path.exists(path):
        os.unlink(path)
print("NIXPP-SOCKET-OK")
'''

EZA_CASES = (
    ('-d', '{d}'),
    ('-al', '--icons=never', '{d}'),
    ('--color=always', '--icons=always', '--group-directories-first', '-al', '{d}'),
    ('--tree', '--level=3', '{d}'),
    ('--git', '-al', '{d}'),
    ('-al', '/etc'),
)


class CheckFailure(Exception):
    pass


class Result:
    def __init__(self, returncode, out, err):
        self.returncode = returncode
        self.out = out
        self.err = err

    @property
    def timed_out(self):
        return self.returncode is None


def describe_rc(rc):
    if rc is None:
        return 'timed out'
    if rc < 0:
        try:
            return 'killed by ' + signal.Signals(-rc).name
        except ValueError:
            return 'killed by signal %d' % -rc
    return 'exit %d' % rc


class Gate:
    def __init__(self, args, scratch):
        self.args = args
        self.scratch = scratch
        self.deadline = time.monotonic() + args.total_timeout
        self.isolated = args.isolated
        self.generation = Path(args.generation) if args.generation else None
        self.env = self.build_env()
        self.config_dir = self.pick_config_dir()
        self.zdotdir = self.pick_zdotdir()
        self.rounds = args.eza_rounds or (10 if args.thorough else 3)

    # -- environment -------------------------------------------------------

    def pick_config_dir(self):
        if self.args.config_dir:
            return Path(self.args.config_dir)
        if self.isolated:
            return self.generation / 'home-files' / '.config' / 'nix'
        base = os.environ.get('XDG_CONFIG_HOME') or str(Path.home() / '.config')
        return Path(base) / 'nix'

    def pick_zdotdir(self):
        if self.args.zdotdir:
            return Path(self.args.zdotdir)
        if self.isolated:
            return self.generation / 'home-files' / '.config' / 'zsh'
        return None

    def build_env(self):
        bindir = None
        if self.generation is not None:
            bindir = str(self.generation / 'home-path' / 'bin')
        if not self.isolated:
            env = dict(os.environ)
            if bindir:
                env['PATH'] = bindir + os.pathsep + env.get('PATH', '')
            return env
        home = self.scratch / 'home'
        xdg = self.scratch / 'xdg'
        for sub in ('home', 'tmp', 'run', 'xdg', 'xdg/cache', 'xdg/data', 'xdg/state'):
            (self.scratch / sub).mkdir(mode=0o700, exist_ok=True)
        config = self.pick_config_dir()
        try:
            (xdg / 'nix').symlink_to(config)
        except OSError as exc:
            raise CheckFailure('cannot prepare isolated nix config: %s' % exc)
        env = {
            'PATH': bindir,
            'HOME': str(home),
            'XDG_CONFIG_HOME': str(xdg),
            'XDG_CACHE_HOME': str(xdg / 'cache'),
            'XDG_DATA_HOME': str(xdg / 'data'),
            'XDG_STATE_HOME': str(xdg / 'state'),
            'XDG_RUNTIME_DIR': str(self.scratch / 'run'),
            'TMPDIR': str(self.scratch / 'tmp'),
            'NIX_CONF_DIR': str(config),
            'LC_ALL': 'C.UTF-8',
            'TERM': 'xterm-256color',
            'USER': 'nixpp-check',
            'LOGNAME': 'nixpp-check',
            'GIT_CONFIG_NOSYSTEM': '1',
        }
        patterns = list(PASS_ENV)
        patterns += os.environ.get('NIXPP_PASS_ENV', '').split()
        for name, value in os.environ.items():
            if any(fnmatch.fnmatchcase(name, pat) for pat in patterns):
                env.setdefault(name, value)
        return env

    # -- helpers -----------------------------------------------------------

    def scrub(self, text):
        text = text.replace(str(self.scratch), '<scratch>')
        home = str(Path.home())
        if len(home) > 1:
            text = text.replace(home, '~')
        text = re.sub(r'[^\x20-\x7e\n]', '?', text).strip()
        text = ' | '.join(line.strip() for line in text.splitlines() if line.strip())
        if len(text) > MAX_DETAIL:
            text = text[:MAX_DETAIL] + '...'
        return text

    def tool(self, name):
        found = shutil.which(name, path=self.env.get('PATH', ''))
        if not found:
            raise CheckFailure('%s not found in the candidate PATH' % name)
        return found

    def run(self, argv, timeout=None, extra_env=None, cwd=None):
        remaining = self.deadline - time.monotonic()
        if remaining <= 0:
            raise CheckFailure('total time budget exhausted')
        limit = min(timeout or self.args.timeout, remaining)
        env = dict(self.env)
        if extra_env:
            for name, value in extra_env.items():
                if value is None:
                    env.pop(name, None)
                else:
                    env[name] = value
        with tempfile.TemporaryFile() as out, tempfile.TemporaryFile() as err:
            try:
                proc = subprocess.Popen(
                    argv,
                    stdin=subprocess.DEVNULL,
                    stdout=out,
                    stderr=err,
                    env=env,
                    cwd=cwd,
                    start_new_session=True,
                )
            except OSError as exc:
                raise CheckFailure('cannot start %s: %s' % (Path(argv[0]).name, exc))
            try:
                rc = proc.wait(timeout=limit)
            except subprocess.TimeoutExpired:
                rc = None
                try:
                    os.killpg(proc.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                proc.wait()
            out.seek(0)
            err.seek(0)
            return Result(
                rc,
                out.read(MAX_OUTPUT).decode('utf-8', 'replace'),
                err.read(MAX_OUTPUT).decode('utf-8', 'replace'),
            )

    def require(self, result, what, ok=(0,)):
        if result.returncode not in ok:
            detail = self.scrub(result.err)
            message = '%s: %s' % (what, describe_rc(result.returncode))
            if detail:
                message += ' (%s)' % detail
            raise CheckFailure(message)


# -- checks ---------------------------------------------------------------


def check_zsh(gate):
    zsh = gate.tool('zsh')
    res = gate.run([zsh, '-f', '-c', 'print -r -- NIXPP-ZSH-$ZSH_VERSION'])
    gate.require(res, 'zsh -f')
    match = re.search(r'^NIXPP-ZSH-(\d+\.\d+\S*)$', res.out, re.M)
    if not match:
        raise CheckFailure('zsh -f did not report a version')
    details = ['zsh ' + match.group(1)]
    if gate.zdotdir is not None:
        count = 0
        for name in ZSH_FILES:
            path = gate.zdotdir / name
            if path.is_file():
                gate.require(gate.run([zsh, '-n', str(path)]), 'zsh -n ' + name)
                count += 1
        if gate.isolated and count == 0:
            raise CheckFailure('no generated zsh startup files in the generation')
        details.append('%d startup files parse' % count)
    if not gate.isolated:
        res = gate.run(
            [zsh, '-l', '-i', '-c', 'print -r -- NIXPP-ZSH-LOGIN'],
            timeout=gate.args.login_timeout,
        )
        gate.require(res, 'zsh login shell')
        if 'NIXPP-ZSH-LOGIN' not in res.out:
            raise CheckFailure('zsh login shell did not run the command')
        details.append('login shell ok')
    return details


def check_nvim(gate):
    nvim = gate.tool('nvim')
    lua = ('lua assert(jit and not jit.status(), "Neovim JIT must be disabled"); '
           'io.stdout:write("NIXPP-NVIM-" .. vim.version().major .. "\\n")')
    rounds = 20 if gate.args.thorough else 1
    for _ in range(rounds):
        res = gate.run(
            [nvim, '--headless', '-u', 'NONE', '-i', 'NONE', '-c', lua, '-c', 'qa!']
        )
        gate.require(res, 'nvim -u NONE')
        if not re.search(r'^NIXPP-NVIM-\d+$', res.out, re.M):
            raise CheckFailure('nvim -u NONE did not run Lua')
    details = ['bare startup ok']
    if not gate.isolated:
        command = [nvim, '--headless', '-c', lua.replace('NVIM', 'NVIMCFG'), '-c', 'qa!']
        # Fresh plugin setup can exit successfully before running the probe.
        for _ in range(2):
            res = gate.run(command, timeout=gate.args.login_timeout)
            gate.require(res, 'nvim with user config')
            if 'NIXPP-NVIMCFG-' in res.out:
                break
        else:
            raise CheckFailure('nvim with user config did not run Lua after two starts')
        details.append('configured startup ok')
    return details


def check_eza(gate):
    eza = gate.tool('eza')
    git = gate.tool('git')
    root = gate.scratch / 'eza-fixture'
    (root / 'nested').mkdir(parents=True)
    (root / 'nested' / 'file.txt').write_text('test\n')
    (root / '.hidden').write_text('hidden\n')
    (root / 'link').symlink_to('nested/file.txt')
    gate.require(gate.run([git, 'init', '-q', str(root)]), 'git init')
    count = 0
    for _ in range(gate.rounds):
        for case in EZA_CASES:
            argv = [eza] + [arg.replace('{d}', str(root)) for arg in case]
            res = gate.run(argv, timeout=30)
            gate.require(res, 'eza %s' % ' '.join(case[:-1] or case))
            if not res.out.strip():
                raise CheckFailure('eza %s printed nothing' % ' '.join(case[:-1]))
            count += 1
    return ['%d listings' % count]


def parse_nix_conf(path):
    settings = {}
    for line in path.read_text().splitlines():
        line = line.split('#', 1)[0].strip()
        if '=' in line:
            key, value = line.split('=', 1)
            settings[key.strip()] = value.strip()
    return settings


def nix_config_problems(config_dir):
    problems = []
    conf = config_dir / 'nix.conf'
    try:
        settings = parse_nix_conf(conf)
    except OSError:
        return ['nix.conf is missing or unreadable']
    registry = settings.get('flake-registry')
    if registry is None:
        problems.append("flake-registry is unset (remote global registry; set it to '')")
    elif re.match(r'^[A-Za-z][A-Za-z0-9+.-]*://', registry) and not registry.startswith('file:///nix/store/'):
        problems.append('flake-registry is not an immutable local file URL')
    if settings.get('accept-flake-config', 'false').lower() in ('true', '1', 'yes'):
        problems.append('accept-flake-config is enabled')
    features = settings.get('experimental-features', '').split()
    for feature in ('nix-command', 'flakes'):
        if feature not in features:
            problems.append('experimental-features lacks ' + feature)
    try:
        data = json.loads((config_dir / 'registry.json').read_text())
    except (OSError, ValueError):
        problems.append('registry.json is missing or invalid')
        return problems
    for entry in data.get('flakes', []):
        target = entry.get('to', {})
        if target.get('type') != 'path':
            name = entry.get('from', {}).get('id', '?')
            problems.append(
                'registry entry %s is %s, not a local path' % (name, target.get('type'))
            )
    return problems


def check_nix(gate):
    nix = gate.tool('nix')
    res = gate.run([nix, '--version'])
    gate.require(res, 'nix --version')
    version = res.out.strip().splitlines()[0] if res.out.strip() else 'nix'
    problems = nix_config_problems(gate.config_dir)
    if problems:
        raise CheckFailure('; '.join(problems))
    res = gate.run([nix, '--offline', 'registry', 'list'])
    gate.require(res, 'nix registry list')
    entries = 0
    for line in res.out.splitlines():
        fields = line.split()
        if not fields:
            continue
        if fields[0] == 'global':
            registry = parse_nix_conf(gate.config_dir / 'nix.conf').get('flake-registry', '')
            if not registry.startswith('file:///nix/store/'):
                raise CheckFailure('global flake registry entries are active without an immutable local registry')
        if len(fields) < 3 or not fields[2].startswith('path:'):
            raise CheckFailure('registry entry %s is not a local path' % fields[1:2])
        entries += 1
    if entries == 0:
        raise CheckFailure('no registry entries resolved')
    details = [version, 'config and %d registry entries local only' % entries]
    if gate.args.thorough:
        res = gate.run(
            [nix, '--offline', 'eval', '--raw', 'nixpkgs#lib.version'],
            timeout=gate.args.heavy_timeout,
        )
        gate.require(res, 'offline nixpkgs eval')
        details.append('offline nixpkgs resolves')
    return details


def short_socket(gate, name):
    path = gate.scratch / 'run' / name
    (gate.scratch / 'run').mkdir(mode=0o700, exist_ok=True)
    if len(os.fsencode(path)) > MAX_SOCKET_PATH:
        raise CheckFailure(
            'scratch socket path too long; use --scratch-base with a short directory'
        )
    return path


def check_sockets(gate):
    python = gate.tool('python3')
    path = short_socket(gate, 's.sock')
    res = gate.run([python, '-I', '-c', SOCKET_SCRIPT, str(path)])
    gate.require(res, 'unix socket round trip')
    if 'NIXPP-SOCKET-OK' not in res.out:
        raise CheckFailure('unix socket script did not finish')
    return ['stream socket, socketpair ok']


def check_tmux(gate):
    tmux = gate.tool('tmux')
    path = short_socket(gate, 't.sock')
    base = [tmux, '-S', str(path), '-f', '/dev/null']
    try:
        gate.require(
            gate.run(base + ['new-session', '-d', '-s', 'fnx', 'sleep 120']),
            'tmux new-session',
        )
        res = gate.run(base + ['list-sessions', '-F', '#{session_name}'])
        gate.require(res, 'tmux list-sessions')
        if 'fnx' not in res.out.split():
            raise CheckFailure('tmux session not listed')
    finally:
        try:
            gate.run(base + ['kill-server'], timeout=15)
        except CheckFailure:
            pass
    return ['server socket ok']


def check_go(gate):
    """Basic Go-built command. kubectl is already installed, so nothing is compiled.

    Only the client version is read: no cluster is contacted and no kubeconfig is
    used. The check keeps the name "go" for compatibility with existing callers.
    """
    kubectl = gate.tool('kubectl')
    # The Android guest can corrupt memory during concurrent Go GC. This is
    # a short-lived version probe and does not configure the user's kubectl.
    env = {'KUBECONFIG': str(gate.scratch / 'no-kubeconfig'), 'GOGC': 'off'}
    res = gate.run([kubectl, 'version', '--client', '--output=json'], extra_env=env)
    gate.require(res, 'kubectl version --client')
    try:
        client = json.loads(res.out)['clientVersion']
        version = client['gitVersion']
        platform = client['platform']
    except (ValueError, KeyError, TypeError):
        raise CheckFailure('kubectl version output has no clientVersion.gitVersion/platform')
    if not isinstance(version, str) or not re.match(r'^v\d+\.\d+\.\d+', version):
        raise CheckFailure('unexpected kubectl gitVersion')
    expected = 'linux/' + gate.args.expect_arch if gate.args.expect_arch else ''
    if not isinstance(platform, str) or not platform.startswith('linux/'):
        raise CheckFailure('kubectl platform is %s, expected linux' % platform)
    if expected and platform != expected:
        raise CheckFailure('kubectl platform is %s, expected %s' % (platform, expected))
    return ['kubectl ' + version, platform]


# -- Rust CLI acceptance checks -------------------------------------------
# Every check runs on generated fixtures with a scratch HOME/XDG so that no real
# file, vault, config or daemon is involved, in candidate and active mode alike.

ANSI_RE = re.compile(r'\x1b\[[0-9;?]*[A-Za-z]')

BAT_FIXTURE = (
    'def nixpp_marker(value):\n'
    '    return "NIXPP-BAT-" + str(value)\n'
    'print(nixpp_marker(42))\n'
)

# relative path -> content. other.txt must never match "needle-".
RG_FILES = {
    'a.txt': 'alpha needle-123\nbeta\n',
    'b.txt': 'Gamma NEEDLE-456\n',
    'other.txt': 'nothing here\n',
    'sub/c.txt': 'plain\nneedle-789 tail\n',
}

FD_FILES = (
    'src/main.rs',
    'src/lib.rs',
    'docs/readme.md',
    'docs/notes.txt',
    'nested/deep/file.rs',
    '.hidden.txt',
)


def private_env(gate):
    """Scratch HOME/XDG so the tool cannot see the real home, in either context."""
    base = gate.scratch
    names = ('home', 'run', 'xdg', 'xdg/cache', 'xdg/data', 'xdg/state', 'xdg/config')
    for sub in names:
        (base / sub).mkdir(mode=0o700, parents=True, exist_ok=True)
    env = {name: None for name in gate.env if name not in ('PATH', 'LANG', 'LC_ALL', 'TERM')}
    env.update({
        'HOME': str(base / 'home'),
        'XDG_CONFIG_HOME': str(base / 'xdg'),
        'XDG_CACHE_HOME': str(base / 'xdg' / 'cache'),
        'XDG_DATA_HOME': str(base / 'xdg' / 'data'),
        'XDG_STATE_HOME': str(base / 'xdg' / 'state'),
        'XDG_RUNTIME_DIR': str(base / 'run'),
        'RIPGREP_CONFIG_PATH': str(base / 'no-ripgreprc'),
        'BAT_CONFIG_PATH': str(base / 'no-bat-config'),
        'BAT_CACHE_PATH': str(base / 'bat-cache'),
    })
    return env


def write_fixture(root, files):
    for rel, content in files.items():
        path = root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)


def output_lines(res, strip_dirs=False):
    lines = []
    for line in res.out.replace('\r', '').splitlines():
        if not line.strip():
            continue
        if line.startswith('./'):
            line = line[2:]
        if strip_dirs:
            line = line.rstrip('/')
        lines.append(line)
    return lines


def expect_output(gate, res, want, what, strip_dirs=False, ordered=False):
    got = output_lines(res, strip_dirs)
    want = list(want)
    if not ordered:
        got, want = sorted(got), sorted(want)
    if got != want:
        if not got:
            raise CheckFailure('%s printed nothing, expected %d lines' % (what, len(want)))
        raise CheckFailure(
            '%s printed unexpected output (%d lines, expected %d): %s'
            % (what, len(got), len(want), gate.scrub(res.out))
        )


def check_bat(gate):
    bat = gate.tool('bat')
    root = gate.scratch / 'bat-fixture'
    root.mkdir()
    sample = root / 'sample.py'
    sample.write_text(BAT_FIXTURE)
    env = private_env(gate)
    expected = BAT_FIXTURE.splitlines()
    base = [bat, '--paging=never', '--theme=ansi']

    res = gate.run(base + ['--plain', '--color=never', str(sample)], extra_env=env, cwd=root)
    gate.require(res, 'bat plain')
    expect_output(gate, res, expected, 'bat plain', ordered=True)

    res = gate.run(
        base
        + ['--decorations=always', '--style=numbers', '--color=never', '--language=py']
        + [str(sample)],
        extra_env=env,
        cwd=root,
    )
    gate.require(res, 'bat numbers')
    numbered = []
    for line in res.out.replace('\r', '').splitlines():
        match = re.match(r'^\s*(\d+)\s(.*)$', line)
        if not match:
            raise CheckFailure('bat numbers printed an unnumbered line')
        numbered.append((int(match.group(1)), match.group(2).strip()))
    if numbered != [(i + 1, line.strip()) for i, line in enumerate(expected)]:
        raise CheckFailure('bat numbers did not render the fixture lines')

    # Syntax highlighting is the path that crashed: it must emit colour escapes and
    # still contain exactly the fixture text.
    res = gate.run(
        base + ['--style=plain', '--color=always', '--language=py', str(sample)],
        extra_env=env,
        cwd=root,
    )
    gate.require(res, 'bat highlight')
    if not ANSI_RE.search(res.out):
        raise CheckFailure('bat highlight emitted no colour escapes')
    plain = ANSI_RE.sub('', res.out).replace('\r', '')
    if plain.rstrip('\n') != BAT_FIXTURE.rstrip('\n'):
        raise CheckFailure('bat highlight changed the fixture text')
    return ['plain, numbered and highlighted rendering ok']


def check_rg(gate):
    rg = gate.tool('rg')
    root = gate.scratch / 'rg-fixture'
    write_fixture(root, RG_FILES)
    env = private_env(gate)
    common = [
        rg, '--no-config', '--no-ignore', '--no-messages', '--color=never',
        '--no-heading', '--sort', 'path',
    ]
    cases = (
        ('regex', ['-n', '--with-filename', 'needle-', '.'],
         ['a.txt:1:alpha needle-123', 'sub/c.txt:2:needle-789 tail'], (0,)),
        ('ignore case', ['-n', '--with-filename', '-i', 'needle-', '.'],
         ['a.txt:1:alpha needle-123', 'b.txt:1:Gamma NEEDLE-456',
          'sub/c.txt:2:needle-789 tail'], (0,)),
        ('fixed string', ['-n', '--with-filename', '-F', 'needle-1', '.'],
         ['a.txt:1:alpha needle-123'], (0,)),
        ('only matching', ['-N', '--no-filename', '-o', 'needle-[0-9]+', '.'],
         ['needle-123', 'needle-789'], (0,)),
        ('count', ['-c', '--with-filename', 'needle-', '.'],
         ['a.txt:1', 'sub/c.txt:1'], (0,)),
        ('files with matches', ['-l', '-i', 'needle-', '.'],
         ['a.txt', 'b.txt', 'sub/c.txt'], (0,)),
        ('pcre', ['-P', '-N', '--no-filename', '-o', r'(?<=needle-)\d+', '.'],
         ['123', '789'], (0,)),
        ('no match', ['needle-zzz', '.'], [], (1,)),
        ('file listing', ['--files', '.'],
         ['a.txt', 'b.txt', 'other.txt', 'sub/c.txt'], (0,)),
    )
    for name, args, want, rcs in cases:
        what = 'rg ' + name
        res = gate.run(common + args, extra_env=env, cwd=root)
        gate.require(res, what, ok=rcs)
        if want:
            expect_output(gate, res, want, what, ordered=True)
        elif res.out.strip():
            raise CheckFailure('%s printed output: %s' % (what, gate.scrub(res.out)))
    return ['%d searches incl. PCRE ok' % len(cases)]


def check_fd(gate):
    fd = gate.tool('fd')
    root = gate.scratch / 'fd-fixture'
    write_fixture(root, {rel: 'x\n' for rel in FD_FILES})
    env = private_env(gate)
    common = [fd, '--no-ignore', '--color=never']
    cases = (
        ('extension', ['-t', 'f', '-e', 'rs'],
         ['nested/deep/file.rs', 'src/lib.rs', 'src/main.rs']),
        ('regex', ['-t', 'f', r'^(main|lib)\.rs$'], ['src/lib.rs', 'src/main.rs']),
        ('substring', ['-t', 'f', 'readme'], ['docs/readme.md']),
        ('glob', ['-t', 'f', '-g', '*.md'], ['docs/readme.md']),
        ('hidden included', ['-t', 'f', '-H', r'^\.hidden'], ['.hidden.txt']),
        ('hidden skipped', ['-t', 'f', 'hidden'], []),
        ('directories', ['-t', 'd'], ['docs', 'nested', 'nested/deep', 'src']),
    )
    for name, args, want in cases:
        what = 'fd ' + name
        res = gate.run(common + args, extra_env=env, cwd=root)
        gate.require(res, what)
        if want:
            expect_output(gate, res, want, what, strip_dirs=True)
        elif res.out.strip():
            raise CheckFailure('%s printed output: %s' % (what, gate.scrub(res.out)))
    return ['%d searches ok' % len(cases)]


def check_rbw(gate):
    """Only `rbw version`: no config, vault, list or agent command is ever run."""
    rbw = gate.tool('rbw')
    res = gate.run([rbw, 'version'], extra_env=private_env(gate))
    gate.require(res, 'rbw version')
    match = re.search(r'^rbw (\d+\.\d+\.\d+\S*)$', res.out, re.M)
    if not match:
        raise CheckFailure('rbw version did not report a version: %s' % gate.scrub(res.out))
    return ['rbw ' + match.group(1)]


def check_osc(gate):
    osc = gate.tool('osc')
    res = gate.run([osc, '--version'], extra_env=private_env(gate))
    gate.require(res, 'osc version')
    match = re.search(r'\d+\.\d+\.\d+\S*', res.out)
    if not match:
        raise CheckFailure('osc version did not report a version: %s' % gate.scrub(res.out))
    return ['osc ' + match.group(0)]


def check_vivid(gate):
    res = gate.run([gate.tool('vivid'), 'generate', 'molokai'], extra_env=private_env(gate))
    gate.require(res, 'vivid generate')
    entries = res.out.strip().split(':')
    if len(entries) < 10 or not all(re.fullmatch(r'[^=\s]+=[0-9;]+', item) for item in entries):
        raise CheckFailure('vivid generate did not emit LS_COLORS assignments')
    return ['molokai LS_COLORS generation ok']


def check_zoxide(gate):
    zoxide = gate.tool('zoxide')
    root = gate.scratch / 'zoxide-fixture'
    root.mkdir()
    env = private_env(gate)
    res = gate.run([zoxide, 'add', str(root)], extra_env=env)
    gate.require(res, 'zoxide add')
    res = gate.run([zoxide, 'query', 'zoxide-fixture'], extra_env=env)
    gate.require(res, 'zoxide query')
    expect_output(gate, res, [str(root)], 'zoxide query', ordered=True)
    return ['scratch database add/query ok']


def check_rsync(gate):
    rsync = gate.tool('rsync')
    root = gate.scratch / 'rsync-fixture'
    source = root / 'source'
    write_fixture(source, {'a.txt': 'alpha\n', 'nested/b.txt': 'beta\n'})
    (source / 'link').symlink_to('a.txt')
    (source / 'a.txt').chmod(0o640)
    env = private_env(gate)
    for name, absolute in (('relative', False), ('absolute', True), ('existing', False)):
        dest = root / name
        if name == 'existing':
            dest.mkdir()
        target = str(dest) if absolute else name
        res = gate.run([rsync, '-a', 'source/', target + '/'], extra_env=env, cwd=root)
        gate.require(res, 'rsync ' + name)
        if ((dest / 'a.txt').read_text() != 'alpha\n'
                or (dest / 'nested/b.txt').read_text() != 'beta\n'
                or not (dest / 'link').is_symlink()
                or os.readlink(dest / 'link') != 'a.txt'
                or (dest / 'a.txt').stat().st_mode & 0o777 != 0o640):
            raise CheckFailure('rsync ' + name + ' did not preserve fixture content/mode/symlink')
    (source / 'a.txt').write_text('updated alpha\n')
    res = gate.run([rsync, '-a', 'source/', 'relative/'], extra_env=env, cwd=root)
    gate.require(res, 'rsync update')
    if (root / 'relative/a.txt').read_text() != 'updated alpha\n':
        raise CheckFailure('rsync update did not copy changed content')
    return ['relative, absolute, existing directory and update copies verified']


RUNNERS = {
    'zsh': check_zsh,
    'nvim': check_nvim,
    'eza': check_eza,
    'nix': check_nix,
    'sockets': check_sockets,
    'tmux': check_tmux,
    'go': check_go,
    'bat': check_bat,
    'rg': check_rg,
    'fd': check_fd,
    'rbw': check_rbw,
    'osc': check_osc,
    'vivid': check_vivid,
    'zoxide': check_zoxide,
    'rsync': check_rsync,
}


def parse_args(argv):
    parser = argparse.ArgumentParser(
        prog='check-runtime',
        description='Regression gate for the nixpp guest runtime.',
    )
    parser.add_argument('--generation', help='Home Manager generation directory')
    parser.add_argument(
        '--isolated',
        action='store_true',
        help='scrubbed environment, scratch HOME, candidate PATH only (needs --generation)',
    )
    parser.add_argument('--config-dir', help='Nix config dir (default: from the context)')
    parser.add_argument('--zdotdir', help='zsh startup file dir to syntax-check')
    parser.add_argument('--skip', action='append', default=[], choices=CHECKS)
    parser.add_argument('--only', action='append', default=[], choices=CHECKS)
    parser.add_argument('--list', action='store_true', help='list checks and exit')
    parser.add_argument('--thorough', action='store_true', help='slower checks')
    parser.add_argument('--eza-rounds', type=int, default=0)
    parser.add_argument(
        '--expect-arch', default='arm64', help='kubectl platform arch; empty disables'
    )
    parser.add_argument('--timeout', type=float, default=60, help='per command, seconds')
    parser.add_argument('--login-timeout', type=float, default=90)
    parser.add_argument('--heavy-timeout', type=float, default=300)
    parser.add_argument('--total-timeout', type=float, default=900)
    parser.add_argument('--scratch-base', default=os.environ.get('NIXPP_CHECK_TMP'))
    args = parser.parse_args(argv)
    if args.isolated and not args.generation:
        parser.error('--isolated needs --generation')
    return args


def main(argv):
    args = parse_args(argv)
    if args.list:
        print('\n'.join(CHECKS))
        return 0
    selected = [c for c in CHECKS if (not args.only or c in args.only)]
    scratch = Path(tempfile.mkdtemp(prefix='fnx-', dir=args.scratch_base))
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(143))
    results = {}
    try:
        try:
            gate = Gate(args, scratch)
        except CheckFailure as exc:
            print('FAIL setup: %s' % exc, file=sys.stderr)
            return 1
        for name in selected:
            if name in args.skip:
                results[name] = {'status': 'skipped'}
                print('SKIP %s' % name, file=sys.stderr)
                continue
            started = time.monotonic()
            try:
                details = RUNNERS[name](gate)
                entry = {'status': 'pass', 'detail': ', '.join(details)}
            except CheckFailure as exc:
                entry = {'status': 'fail', 'detail': gate.scrub(str(exc))}
            except Exception as exc:  # a broken check must fail the gate, not crash it
                entry = {'status': 'fail', 'detail': gate.scrub('%s: %s' % (type(exc).__name__, exc))}
            entry['seconds'] = round(time.monotonic() - started, 1)
            results[name] = entry
            print(
                '%s %s (%.1fs): %s'
                % (entry['status'].upper(), name, entry['seconds'], entry['detail']),
                file=sys.stderr,
            )
    finally:
        shutil.rmtree(scratch, ignore_errors=True)
    failed = [n for n, e in results.items() if e['status'] == 'fail']
    print(
        json.dumps(
            {
                'context': 'candidate' if args.isolated else 'active',
                'success': not failed,
                'failed': failed,
                'checks': results,
            },
            sort_keys=True,
        )
    )
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
