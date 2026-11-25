"""List and resume locally recorded agent conversations."""
import argparse
from collections import deque
import datetime as dt
import itertools
import fcntl
import hashlib
import time
import threading
import unicodedata
import uuid
import json
import os
import re
from pathlib import Path
import sqlite3
import shlex
import subprocess
import sys
from urllib.parse import unquote, urlparse


USER_RECORD = re.compile(r'"(?:type|role)"\s*:\s*"user"')

AGENT_ICONS = {'codex': ('\uec81', '38;2;200;200;200'), 'claude': ('\uec82', '38;2;217;119;87'),
               'claude-work': ('\uec82', '38;2;217;119;87'), 'claude-auto': ('\uec82', '38;2;217;119;87'),
               'agy': ('󰊭', '38;5;111')}

CONCORD_KINDS = {'codex': 'codex', 'claude': 'claude-code', 'agy': 'antigravity'}


def session_ids(row, agents):
    agent, session_id = row[1:3]
    kind = CONCORD_KINDS.get(agents[agent]['kind'])
    digest = hashlib.sha256(session_id.encode()).hexdigest()[:8]
    return (session_id, f'{kind}:{digest}') if kind else (session_id,)


def selection_matches(row, selection, agents):
    return any(selection.casefold() in value.casefold() for value in session_ids(row, agents))


def concord_claims():
    """Return active task and claim names indexed by their Concord owner."""
    try:
        result = subprocess.run(['concord', 'status'], capture_output=True, text=True, check=True)
    except (FileNotFoundError, subprocess.CalledProcessError) as exc:
        raise RuntimeError(f'cannot look up Concord claims: {exc}') from exc
    active = False
    owners = {}
    for line in result.stdout.splitlines():
        if line == 'Active work':
            active = True
            continue
        if active and line and not line.startswith(' '):
            break
        if not active:
            continue
        match = re.match(r'^\s+(\S+)\s+active\s+v\d+\s+(\S+)\s+.*?touches: (.*)$', line)
        if match:
            task, owner, claims = match.groups()
            claims = re.sub(r'  \(child of .*\)$', '', claims).split(', ')
            owners.setdefault(owner, set()).update([task, *(claim for claim in claims if claim != '-')])
    return owners


def concord_claim_owners(selection):
    return {owner for owner, names in concord_claims().items()
            if any(selection.casefold() in name.casefold() for name in names)}


def load_agents():
    config = os.environ.get('RESUME_AGENTS_CONFIG')
    if not config:
        raise RuntimeError('RESUME_AGENTS_CONFIG is not set')
    with open(config, encoding='utf-8') as stream:
        agents = json.load(stream)
    if not isinstance(agents, dict) or not agents:
        raise RuntimeError('resume has no configured agents')
    return agents


def records(agents, progress=None):
    progress = progress or (lambda _: None)
    scanned_roots = set()
    for agent, settings in agents.items():
        kind = settings['kind']
        root = Path(settings['configDir'])
        root_key = (kind, root)
        if root_key in scanned_roots:
            continue
        scanned_roots.add(root_key)
        progress(f'Scanning {agent} sessions')
        codex_titles = {}
        if kind == 'codex':
            index = root / 'session_index.jsonl'
            try:
                with index.open(encoding='utf-8') as stream:
                    for line in stream:
                        try:
                            entry = json.loads(line)
                            if entry.get('id') and entry.get('thread_name'):
                                codex_titles[entry['id']] = entry['thread_name']
                        except (ValueError, AttributeError):
                            continue
            except (OSError, UnicodeError):
                pass
            pattern = 'sessions/*/*/*/*.jsonl'
        elif kind == 'agy':
            pattern = None
        else:
            pattern = 'projects/*/*.jsonl'
        if kind == 'agy':
            db = root / 'conversation_summaries.db'
            if not db.exists():
                continue
            try:
                with sqlite3.connect(f'file:{db}?mode=ro', uri=True) as conn:
                    for sid, title, preview, modified, uris in conn.execute(
                        'SELECT conversation_id,title,preview,last_modified_time,workspace_uris FROM conversation_summaries'
                    ):
                        try:
                            values = json.loads(uris)
                            uri = values[0] if isinstance(values, list) and values else ''
                            cwd = unquote(urlparse(uri).path) if uri.startswith('file:') else ''
                            stamp = dt.datetime.fromisoformat(modified.replace('Z', '+00:00')).timestamp()
                            if cwd and stamp > 0:
                                dt.datetime.fromtimestamp(stamp)
                                yield (stamp, agent, sid, cwd, title or preview, str(db))
                        except (ValueError, TypeError, IndexError, OverflowError, OSError):
                            continue
            except sqlite3.Error as exc:
                print(f'resume: {exc}', file=sys.stderr)
            continue
        for path in root.glob(pattern):
            try:
                cwd, title, session_id = '', '', path.stem
                with path.open() as stream:
                    for line in itertools.islice(stream, 100):
                        if kind == 'codex':
                            if '"session_meta"' not in line and '"user_message"' not in line and not USER_RECORD.search(line):
                                continue
                        elif (cwd or '"cwd"' not in line) and not USER_RECORD.search(line):
                            continue
                        try:
                            obj = json.loads(line)
                        except (ValueError, UnicodeDecodeError):
                            continue
                        payload = obj.get('payload', {})
                        if kind == 'codex':
                            if obj.get('type') == 'session_meta':
                                cwd = payload.get('cwd', '')
                                session_id = payload.get('id', session_id)
                                title = codex_titles.get(session_id, title)
                            if payload.get('type') == 'user_message':
                                title = payload.get('message', '')
                            elif payload.get('type') == 'message' and payload.get('role') == 'user':
                                parts = payload.get('content', [])
                                candidate = ' '.join(part.get('text', '') for part in parts if isinstance(part, dict))
                                if not candidate.startswith(('# AGENTS.md', '<', '# Developer')):
                                    title = candidate
                        else:
                            cwd = obj.get('cwd') or cwd
                            session_id = obj.get('sessionId') or session_id
                            if obj.get('type') == 'user':
                                content = obj.get('message', {}).get('content', '')
                                if isinstance(content, str) and not content.startswith('<'):
                                    title = content
                        if cwd and title:
                            break
                if cwd:
                    if kind == 'codex':
                        title = codex_titles.get(session_id, title)
                    yield (path.stat().st_mtime, agent, session_id, cwd, title, str(path))
            except (OSError, UnicodeError):
                continue


class StartupSpinner:
    def __init__(self, enabled):
        self.enabled = enabled
        self.message = 'Starting session discovery'
        self.stop_event = threading.Event()
        self.worker = None

    def update(self, message):
        self.message = message

    def __enter__(self):
        if self.enabled:
            self.worker = threading.Thread(target=self.animate, daemon=True)
            self.worker.start()
        return self

    def animate(self):
        frames = itertools.cycle('⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏')
        while not self.stop_event.is_set():
            sys.stderr.write(f'\r\033[2K\033[38;5;110m{next(frames)}\033[0m {self.message}')
            sys.stderr.flush()
            self.stop_event.wait(0.08)

    def __exit__(self, *_):
        if self.worker is not None:
            self.stop_event.set()
            self.worker.join()
            sys.stderr.write('\r\033[2K')
            sys.stderr.flush()


def active_sessions(agents):
    active = {}
    scanned_roots = set()
    for agent, settings in agents.items():
        kind = settings['kind']
        if kind != 'claude':
            continue
        root = Path(settings['configDir'])
        root_key = (kind, root)
        if root_key in scanned_roots:
            continue
        scanned_roots.add(root_key)
        for path in (root / 'sessions').glob('*.json'):
            try:
                record = json.loads(path.read_text())
                pid = int(record['pid'])
                process_name = (Path('/proc') / str(pid) / 'comm').read_text().lower()
                if 'claude' in process_name and record.get('sessionId'):
                    active[(agent, record['sessionId'])] = pid
            except (OSError, ValueError, KeyError, TypeError):
                continue
    lock_owners = {}
    try:
        for line in Path('/proc/locks').read_text().splitlines():
            fields = line.split()
            if len(fields) >= 6 and fields[1] == 'FLOCK':
                try:
                    lock_owners[int(fields[5].split(':')[-1])] = int(fields[4])
                except ValueError:
                    continue
    except OSError:
        pass
    for agent, settings in agents.items():
        if settings['kind'] != 'codex':
            continue
        root = Path(settings['configDir'])
        root_key = ('codex', root)
        if root_key in scanned_roots:
            continue
        scanned_roots.add(root_key)
        for path in (root / 'thread-writer-locks').glob('*.lock'):
            try:
                with path.open('rb') as lock:
                    try:
                        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                        fcntl.flock(lock, fcntl.LOCK_UN)
                    except BlockingIOError:
                        active[(agent, path.stem)] = lock_owners.get(path.stat().st_ino)
            except OSError:
                continue
    return active


def tmux_pane_for_pid(pid):
    if not pid or not os.environ.get('TMUX'):
        return None
    try:
        result = subprocess.run(['tmux', 'list-panes', '-a', '-F', '#{pane_id}\t#{pane_tty}'],
                                text=True, capture_output=True, check=True)
        panes = {}
        for line in result.stdout.splitlines():
            pane, tty = line.split('\t', 1)
            panes.setdefault(tty, set()).add(pane)
        visited = set()
        while pid > 1 and pid not in visited:
            visited.add(pid)
            proc = Path('/proc') / str(pid)
            try:
                tty = os.readlink(proc / 'fd/0')
            except OSError:
                tty = ''
            matches = panes.get(tty, set())
            if len(matches) == 1:
                return next(iter(matches))
            stat = (proc / 'stat').read_text()
            pid = int(stat[stat.rfind(')') + 2:].split()[1])
    except (OSError, ValueError, IndexError, subprocess.SubprocessError):
        pass
    return None


def switch_to_live_session(agent, session_id, agents):
    active = active_sessions(agents)
    if (agent, session_id) not in active:
        return False
    pid = active[(agent, session_id)]
    pane = tmux_pane_for_pid(pid)
    if not pane or pane == os.environ.get('TMUX_PANE'):
        print('resume: session is active, but its tmux pane could not be found; starting native resume.', file=sys.stderr)
        return False
    try:
        subprocess.run(['tmux', 'switch-client', '-t', pane], check=True)
        subprocess.run(['tmux', 'select-window', '-t', pane], check=True)
        subprocess.run(['tmux', 'select-pane', '-t', pane], check=True)
        return True
    except (OSError, subprocess.SubprocessError):
        print('resume: could not switch to the active tmux pane; starting native resume.', file=sys.stderr)
        return False


def relative_time(stamp):
    seconds = max(0, int(time.time() - stamp))
    for size, suffix in ((31536000, 'y'), (2592000, 'mo'), (86400, 'd'), (3600, 'h'), (60, 'm')):
        if seconds >= size:
            return f'{seconds // size}{suffix} ago'
    return 'now'


def cell_width(text):
    return sum(0 if unicodedata.combining(c) else 2 if unicodedata.east_asian_width(c) in ('W', 'F') else 1
               for c in text)


def agent_icon(agent, agents):
    kind = agents[agent]['kind']
    return AGENT_ICONS.get(agent, AGENT_ICONS[kind])


def message_card(role, agent, content, agents):
    try:
        width = max(20, int(os.environ.get('FZF_PREVIEW_COLUMNS', '80')) - 2)
    except ValueError:
        width = 78
    inner = width - 4
    icon, color = ('󰀄', '38;5;111') if role == 'user' else agent_icon(agent, agents)
    label = 'You' if role == 'user' else agent
    border = f'\033[{color}m'
    reset = '\033[0m'
    print(f'{border}▎ {icon}{reset} {label}')

    def print_line(text):
        padding = ' ' * max(0, inner - cell_width(text))
        print(f'{border}▏{reset} \033[48;2;49;50;68m{text}{padding}{reset}')

    for paragraph in content.expandtabs(4).split('\n'):
        line = ''
        for word in paragraph.split(' '):
            while cell_width(word) > inner:
                if line:
                    print_line(line)
                    line = ''
                part = ''
                while word and cell_width(part + word[0]) <= inner:
                    part += word[0]
                    word = word[1:]
                print_line(part)
            candidate = f'{line} {word}' if line else word
            if cell_width(candidate) > inner:
                print_line(line)
                line = word
            else:
                line = candidate
        print_line(line)
    print()


def agy_transcript_paths(summary_path, session_id):
    try:
        session_id = str(uuid.UUID(session_id))
    except (ValueError, TypeError, AttributeError):
        return []
    logs = Path(summary_path).parent / 'brain' / session_id / '.system_generated' / 'logs'
    return [logs / 'transcript_full.jsonl', logs / 'transcript.jsonl']


def file_state(paths):
    state = []
    for path in paths:
        try:
            stat = path.stat()
            state.append((stat.st_mtime_ns, stat.st_size, stat.st_ino))
        except OSError:
            state.append(None)
    return tuple(state)


def extract_message(kind, obj):
    if kind == 'agy':
        message_kind = obj.get('type')
        if message_kind == 'USER_INPUT' and obj.get('source') != 'SYSTEM_SDK':
            role = 'user'
        elif message_kind == 'PLANNER_RESPONSE':
            role = 'assistant'
        else:
            return None
        content = obj.get('content', '')
    elif kind == 'codex':
        item = obj.get('payload', {})
        if obj.get('type') != 'response_item' or item.get('type') != 'message':
            return None
        role, content = item.get('role'), item.get('content', [])
    else:
        if obj.get('type') not in ('user', 'assistant'):
            return None
        item = obj.get('message') or {}
        role, content = obj['type'], item.get('content', '')
    if role not in ('user', 'assistant'):
        return None
    if isinstance(content, list):
        content = '\n'.join(part.get('text', '') for part in content
                            if isinstance(part, dict) and part.get('type') in ('text', 'input_text', 'output_text'))
    if not isinstance(content, str):
        return None
    content = content.strip()
    if kind == 'agy' and role == 'user' and content.startswith('<USER_REQUEST'):
        match = re.search(r'<USER_REQUEST(?:\s[^>]*)?>(.*?)</USER_REQUEST>', content, re.DOTALL)
        if not match:
            return None
        content = match.group(1).strip()
    if not content or (kind != 'agy' and content.startswith(('<', '# AGENTS.md', '# Developer', '# system'))):
        return None
    return role, ''.join(c for c in content if c in '\n\t' or 32 <= ord(c) < 127 or ord(c) >= 160)


def search_transcripts(rows, query, progress, agents):
    pattern = re.compile(re.escape(query), re.IGNORECASE)
    # Match both literal UTF-8 and JSON-escaped text before parsing records.
    needles = {query.lower().encode('utf-8'), json.dumps(query, ensure_ascii=True)[1:-1].lower().encode('ascii')}
    for index, row in enumerate(rows):
        _, agent, sid, cwd, title, source = row
        progress(f'Searching conversations {index + 1}/{len(rows)}')
        kind = agents[agent]['kind']
        paths = agy_transcript_paths(source, sid) if kind == 'agy' else [Path(source)]
        path = next((p for p in paths if p.is_file()), None)
        if path is None:
            continue
        hit = None
        try:
            with path.open('rb') as stream:
                for raw in stream:
                    lowered = raw.lower()
                    if query.isascii() and not any(needle in lowered for needle in needles):
                        continue
                    try:
                        message = extract_message(kind, json.loads(raw))
                        if not message:
                            continue
                        role, content = message
                        text = ' '.join(content.split())
                        match = pattern.search(text)
                        if match:
                            start = max(0, match.start() - 50)
                            end = min(len(text), match.end() + 90)
                            hit = (role, ('…' if start else '') + text[start:end] + ('…' if end < len(text) else ''))
                    except (ValueError, TypeError, AttributeError):
                        continue
        except OSError:
            continue
        if hit:
            yield row, hit


def preview(agent, path, cwd, title, session_id, timestamp, agents):
    reset = '\033[0m'
    kind = agents[agent]['kind']

    def pinned(message):
        try:
            width = max(1, int(os.environ.get('FZF_PREVIEW_COLUMNS', '80')) - 10)
        except ValueError:
            width = 70
        text = ' '.join(message.split()) if message else 'no user message available'
        clipped = ''
        for char in text:
            if cell_width(clipped + char) > width:
                clipped = clipped[:-1] + '…' if clipped else '…'
                break
            clipped += char
        padding = ' ' * max(0, width - cell_width(clipped))
        message_style = '\033[3;38;5;245m' if not message else '\033[39m'
        print(f'\033[48;2;49;50;68m\033[1;38;5;111m󰐃 YOU  \033[22m{message_style}{clipped}{padding}{reset}')

    def metadata():
        print(f'\033[1;38;5;111m󰭹  {title or "Conversation"}{reset}')
        print(f'\033[38;5;109m󰉋  {cwd}{reset}')
        print(f'\033[38;5;245m󰥔  {timestamp}{reset}\n')

    def agy_summary():
        pinned('')
        metadata()
        try:
            with sqlite3.connect(Path(path).as_uri() + '?mode=ro', uri=True) as conn:
                row = conn.execute('SELECT preview FROM conversation_summaries WHERE conversation_id = ?',
                                   (session_id,)).fetchone()
            summary = row[0].strip() if row and isinstance(row[0], str) else ''
            summary = ''.join(c for c in summary if c in '\n\t' or ord(c) >= 32 and ord(c) != 127)
            if summary:
                print(f'\033[1;38;5;111m󰊭  Antigravity summary{reset}\n{summary}\n')
            else:
                print('\033[3;38;5;245mNo indexed summary is available.\033[0m')
            print('\033[3;38;5;245mNo readable Antigravity transcript is available.\033[0m')
        except (sqlite3.Error, OSError) as exc:
            print(f'\033[3mCould not read Antigravity summary: {exc}\033[0m', file=sys.stderr)

    transcript_path = Path(path)
    if kind == 'agy':
        transcript_path = next((p for p in agy_transcript_paths(path, session_id) if p.is_file()), None)
        if transcript_path is None:
            agy_summary()
            return
    messages = deque(maxlen=5)
    latest_user = ''
    try:
        with open(transcript_path, 'rb') as stream:
            size = stream.seek(0, os.SEEK_END)
            stream.seek(max(0, size - 4 * 1024 * 1024))
            if size > 4 * 1024 * 1024:
                stream.readline()  # Discard the partial first JSON line.
            for raw_line in stream:
                line = raw_line.decode('utf-8', errors='replace')
                try:
                    obj = json.loads(line)
                    message = extract_message(kind, obj)
                    if not message:
                        continue
                    role, content = message
                    if role == 'user':
                        latest_user = content
                    messages.append((role, content[-3000:]))
                except (ValueError, AttributeError, TypeError):
                    continue
        if kind == 'agy' and not messages:
            agy_summary()
            return
        pinned(latest_user)
        metadata()
        for role, content in messages:
            message_card(role, agent, content, agents)
        if not messages:
            print('\033[3;38;5;245mNo readable messages found.\033[0m')
    except OSError as exc:
        if kind == 'agy':
            agy_summary()
            return
        pinned('')
        metadata()
        print(f'\033[3mCould not read conversation: {exc}\033[0m', file=sys.stderr)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    try:
        agents = load_agents()
    except (OSError, ValueError, RuntimeError) as exc:
        parser.error(str(exc))
    parser.add_argument('--preview-session', nargs=7, metavar=('AGENT', 'PATH', 'CWD', 'TITLE', 'ID', 'TIME', 'LIVE'), help=argparse.SUPPRESS)
    parser.add_argument('selection', nargs='?', help='session number, ID, Concord agent ID or claim to resume')
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--pick', action='store_true', help='select interactively with fzf (default)')
    mode.add_argument('--list', action='store_true', help='print sessions without opening the picker')
    parser.add_argument('--agent', choices=tuple(agents), help='filter by agent')
    parser.add_argument('--cwd', help='filter by working directory or directory name')
    parser.add_argument('--limit', type=int, default=0, help='maximum displayed results (default: all)')
    args = parser.parse_args()
    if args.preview_session:
        *details, live = args.preview_session
        preview(*details, agents)
        if live != '1':
            return
        sys.stdout.flush()
        path = Path(details[1])
        paths = [path]
        if agents[details[0]]['kind'] == 'agy':
            paths = agy_transcript_paths(path, details[4]) + [path, Path(str(path) + '-wal')]
        try:
            previous = file_state(paths)
            while True:
                time.sleep(1)
                current = file_state(paths)
                if current != previous:
                    previous = current
                    print('\033[2J', end='')
                    preview(*details, agents)
                    sys.stdout.flush()
        except (OSError, BrokenPipeError):
            return

    interactive = sys.stderr.isatty() and not args.list and (args.pick or not args.selection)
    with StartupSpinner(interactive) as spinner:
        sessions = sorted(records(agents, spinner.update), key=lambda row: row[0], reverse=True)
        spinner.update('Checking active sessions')
        active = active_sessions(agents)
    agent_filter = args.agent
    cwd_filter = args.cwd
    selection_filter = None
    selection_candidates = None
    selected_row = None
    if args.selection and not args.pick and not args.list:
        if args.selection.isdigit() and 1 <= int(args.selection) <= len(sessions):
            selected_row = sessions[int(args.selection) - 1]
        else:
            candidates = [row for row in sessions if selection_matches(row, args.selection, agents)]
            if not candidates:
                try:
                    owners = concord_claim_owners(args.selection)
                except RuntimeError as exc:
                    parser.error(str(exc))
                candidates = [row for row in sessions if any(owner in session_ids(row, agents) for owner in owners)]
                if owners and not candidates:
                    parser.error('claim owner has no locally recorded session')
            exact = [row for row in candidates if args.selection.casefold() in
                     (value.casefold() for value in session_ids(row, agents))]
            candidates = exact or candidates
            if len(candidates) == 1:
                selected_row = candidates[0]
            elif not candidates:
                parser.error('session not found')
            else:
                selection_filter = args.selection
                selection_candidates = candidates
    try:
        terminal_width = os.get_terminal_size(0).columns
        narrow = terminal_width < 100
    except OSError:
        terminal_width = 80
        narrow = True

    def display(i, row, styled=False):
        stamp, agent, sid, cwd, title, path = row
        when = relative_time(stamp)
        live = (agent, sid) in active
        clean = ' '.join(str(title).split())[:500]
        short_cwd = Path(cwd).name or '/'
        if not styled:
            return f'{when:8}  {"●" if live else " "} {agent:11}  {short_cwd:30}  {clean or "untitled"}  —  {cwd}  [{sid}]'
        icon, color = agent_icon(agent, agents)
        reset = '\033[0m'
        provider = f'\033[{color}m{icon}{reset} {agent:11}'
        status = '\033[1;38;5;114m●\033[0m' if live else ' '
        width = 18 if narrow else 24
        folder = short_cwd if len(short_cwd) <= width else '…' + short_cwd[-(width - 1):]
        topic = clean if clean else '\033[3;38;5;245muntitled\033[0m'
        ids = ' '.join(session_ids(row, agents))
        return (f'\033[38;5;245m{when:8}{reset} {status} {provider} '
                f'\033[38;5;109m{folder:{width}}{reset} {topic} \033[38;5;245m{ids}{reset}')

    def filtered():
        return [row for row in sessions
                if (selection_candidates is None or row in selection_candidates)
                and (not agent_filter or row[1] == agent_filter) and (not cwd_filter or (row[3] == cwd_filter if cwd_filter.startswith('/') else cwd_filter.casefold() in row[3].casefold()))]

    if args.pick or selection_filter or (not args.list and not args.selection):
        try:
            claims_by_owner = concord_claims()
        except RuntimeError:
            claims_by_owner = {}

        def picker_display(row):
            names = sorted({name for ident in session_ids(row, agents) for name in claims_by_owner.get(ident, ())})
            suffix = f' \033[38;5;109m{" ".join(names)}\033[0m' if names else ''
            return display(0, row, styled=True) + suffix

        env = os.environ.copy()
        env.pop('FZF_DEFAULT_OPTS', None)
        env.pop('FZF_DEFAULT_OPTS_FILE', None)
        theme = '--color=fg:#cdd6f4,bg:#1e1e2e,fg+:#ffffff,bg+:#313244,hl:#f9e2af,hl+:#f9e2af,pointer:#cba6f7,prompt:#89b4fa,header:#94e2d5,border:#6c7086,preview-scrollbar:#45475a'
        try:
            while True:
                rows = filtered()
                lines = '\n'.join('\t'.join([picker_display(row), row[1], row[5], row[3],
                                             ' '.join(str(row[4]).split()), row[2],
                                             dt.datetime.fromtimestamp(row[0]).strftime('%Y-%m-%d %H:%M:%S %Z'),
                                             '1' if agents[row[1]]['kind'] == 'agy' or (row[1], row[2]) in active else '0'])
                                  for i, row in enumerate(rows, 1))
                width = 18 if narrow else 24
                columns = f'\033[38;5;245m{"LAST":8}   {"AGENT":13} {"CWD":{width}} TOPIC\033[0m'
                folder_label = Path(cwd_filter).name if cwd_filter else 'all'
                key = '\033[1;38;5;110m'
                hint = '\033[38;5;60m'
                shortcuts = f'{key}^T {hint}search  {key}^G {hint}agent  {key}^D {hint}cwd  {key}^R {hint}reset  {key}Pg↑/↓ {hint}scroll'
                filters = f'agent: {agent_filter or "all"}  cwd: {folder_label}'
                if selection_filter:
                    filters += f'  id: {selection_filter}'
                list_width = terminal_width // 2 - 5 if terminal_width >= 120 else terminal_width - 4
                spacing = max(2, list_width - cell_width('^T search  ^G agent  ^D cwd  ^R reset  Pg↑/↓ scroll  M-Q quit') - cell_width(filters))
                footer = f'{shortcuts}{" " * spacing}{hint}{filters}\033[0m'
                result = subprocess.run(
                    ['fzf', '--ansi', '--info=hidden', '--no-separator', '--no-hscroll', '--delimiter=\t', '--with-nth=1', '--tiebreak=index', '--layout=reverse',
                     '--prompt=󰍉  Session  ❯ ', '--pointer=❯', '--marker=󰄬', theme,
                     '--bind=alt-Q:abort,alt-up:preview-up,alt-down:preview-down,alt-k:preview-up,alt-j:preview-down,pgup:preview-page-up,pgdn:preview-page-down',
                     '--expect=ctrl-g,ctrl-d,ctrl-r,ctrl-t', '--header=' + columns, '--footer=' + footer, '--footer-border=none',
                     '--preview=' + ' '.join(map(shlex.quote, [sys.executable, __file__, '--preview-session'])) + ' {2} {3} {4} {5} {6} {7} {8}',
                     '--preview-window=right:50%:wrap-word:follow:noinfo:~1:<60(down:40%:wrap-word:follow:noinfo:~1)', '--preview-wrap-sign='],
                    input=lines, text=True, stdout=subprocess.PIPE, env=env,
                )
                if result.returncode:
                    return
                key, _, selected = result.stdout.partition('\n')
                if key == 'ctrl-r':
                    agent_filter = cwd_filter = None
                    selection_filter = None
                    selection_candidates = None
                    continue
                if key == 'ctrl-t':
                    try:
                        query = input('Search conversation messages: ').strip()
                    except EOFError:
                        return
                    if not query:
                        continue
                    with StartupSpinner(sys.stderr.isatty()) as spinner:
                        hits = list(search_transcripts(filtered(), query, spinner.update, agents))
                    if not hits:
                        try:
                            input('No matching messages. Press Enter to return. ')
                        except EOFError:
                            return
                        continue
                    search_lines = []
                    matcher = re.compile(re.escape(query), re.IGNORECASE)
                    for row, (role, excerpt) in hits:
                        _, provider, sid, directory, title, source = row
                        icon, color = agent_icon(provider, agents)
                        highlighted = matcher.sub(lambda match: '\033[1;38;5;221m' + match.group() + '\033[0m', excerpt)
                        line = f'\033[{color}m{icon}\033[0m {provider}  \033[38;5;109m{Path(directory).name}\033[0m  {role}: {highlighted}'
                        fields = [line, provider, source, directory, ' '.join(str(title).split()), sid,
                                  dt.datetime.fromtimestamp(row[0]).strftime('%Y-%m-%d %H:%M:%S %Z'),
                                  '1' if agents[provider]['kind'] == 'agy' or (provider, sid) in active else '0']
                        search_lines.append('\t'.join(fields))
                    found = subprocess.run(
                        ['fzf', '--ansi', '--no-sort', '--no-hscroll', '--layout=reverse', '--delimiter=\t',
                         '--with-nth=1', '--prompt=󰍉  Matches ❯ ', theme,
                         '--header=Matching messages · Enter: resume · Esc: back · Alt-Shift-Q: quit', '--expect=alt-Q',
                         '--bind=alt-up:preview-up,alt-down:preview-down,pgup:preview-page-up,pgdn:preview-page-down',
                         '--preview=' + ' '.join(map(shlex.quote, [sys.executable, __file__, '--preview-session'])) + ' {2} {3} {4} {5} {6} {7} {8}',
                         '--preview-window=right:50%:wrap-word:follow:noinfo:~1:<60(down:40%:wrap-word:follow:noinfo:~1)'],
                        input='\n'.join(search_lines), text=True, stdout=subprocess.PIPE, env=env)
                    if found.returncode == 0 and found.stdout:
                        pressed, _, selected_hit = found.stdout.partition('\n')
                        if pressed == 'alt-Q':
                            return
                        if selected_hit:
                            fields = selected_hit.split('\t')
                            selected_row = next(row for row in sessions if row[1] == fields[1] and row[5] == fields[2] and row[2] == fields[5])
                            args.selection = fields[5]
                            break
                    continue
                if key in ('ctrl-g', 'ctrl-d'):
                    options = sorted({row[1] if key == 'ctrl-g' else row[3] for row in sessions})
                    prompt = 'Filter ' + ('agent' if key == 'ctrl-g' else 'directory') + ' ❯ '
                    if key == 'ctrl-g':
                        entries = ['󰒊 All\tAll'] + [
                            f'\033[{agent_icon(agent, agents)[1]}m{agent_icon(agent, agents)[0]}\033[0m {agent}\t{agent}'
                            for agent in options
                        ]
                        picker_options = ['--ansi', '--delimiter=\t', '--with-nth=1']
                    else:
                        entries = ['󰒊 All\tAll'] + [f'\033[38;5;109m󰉋\033[0m {directory}\t{directory}' for directory in options]
                        picker_options = ['--ansi', '--delimiter=\t', '--with-nth=1']
                    choice = subprocess.run(['fzf', '--layout=reverse', '--prompt=' + prompt, '--expect=alt-Q', theme] + picker_options,
                                            input='\n'.join(entries), text=True,
                                            stdout=subprocess.PIPE, env=env)
                    if choice.returncode == 0:
                        pressed, _, value = choice.stdout.partition('\n')
                        if pressed == 'alt-Q':
                            return
                        value = value.strip().rsplit('\t', 1)[-1]
                        value = None if value == 'All' else value
                        if key == 'ctrl-g':
                            agent_filter = value
                        else:
                            cwd_filter = value
                    continue
                if not selected:
                    return
                fields = selected.split('\t')
                selected_row = next(row for row in sessions if row[1] == fields[1] and row[5] == fields[2] and row[2] == fields[5])
                args.selection = fields[5]
                break
        except FileNotFoundError:
            parser.error('the picker requires fzf')
    if not args.selection:
        for i, row in enumerate(filtered(), 1):
            if args.limit and i > args.limit:
                break
            print(display(i, row))
        return
    if selected_row is None:
        matches = [row for row in sessions if row[2] == args.selection]
        if len(matches) != 1:
            parser.error('session not found or ambiguous; use its displayed number')
        selected_row = matches[0]
    _, agent, sid, cwd, _, _ = selected_row
    if switch_to_live_session(agent, sid, agents):
        return
    if not os.path.isdir(cwd):
        parser.error(f'original working directory no longer exists: {cwd}')
    os.chdir(cwd)
    settings = agents[agent]
    command = [settings['program'], *settings['resumeArgs'], sid]
    os.execv(command[0], command)


if __name__ == '__main__':
    main()
