#!/usr/bin/env python3
"""List and resume locally recorded agent conversations."""
import argparse
from collections import deque
import datetime as dt
import itertools
import fcntl
import time
import unicodedata
import json
import os
from pathlib import Path
import sqlite3
import shlex
import subprocess
import sys
from urllib.parse import unquote, urlparse


AGENT_ICONS = {'codex': ('\uec81', '38;2;200;200;200'), 'claude': ('\uec82', '38;2;217;119;87'),
               'claude-work': ('\uec82', '38;2;217;119;87'), 'claude-auto': ('\uec82', '38;2;217;119;87'),
               'agy': ('󰊭', '38;5;111')}


def records():
    home = Path.home()
    codex_titles = {}
    index = home / '.config/codex/session_index.jsonl'
    try:
        with index.open() as stream:
            for line in stream:
                try:
                    entry = json.loads(line)
                    if entry.get('id') and entry.get('thread_name'):
                        codex_titles[entry['id']] = entry['thread_name']
                except (ValueError, AttributeError):
                    continue
    except (OSError, UnicodeError):
        pass
    for agent in ('claude', 'claude-work', 'claude-auto', 'codex'):
        root = home / '.config' / agent
        pattern = 'sessions/*/*/*/*.jsonl' if agent == 'codex' else 'projects/*/*.jsonl'
        for path in root.glob(pattern):
            try:
                cwd, title, session_id = '', '', path.stem
                with path.open() as stream:
                    for line in itertools.islice(stream, 100):
                        try:
                            obj = json.loads(line)
                        except (ValueError, UnicodeDecodeError):
                            continue
                        payload = obj.get('payload', {})
                        if agent == 'codex':
                            if obj.get('type') == 'session_meta':
                                cwd = payload.get('cwd', '')
                                session_id = payload.get('id', session_id)
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
                    if agent == 'codex':
                        title = codex_titles.get(session_id, title)
                    yield (path.stat().st_mtime, agent, session_id, cwd, title, str(path))
            except (OSError, UnicodeError):
                continue
    db = home / '.gemini/antigravity-cli/conversation_summaries.db'
    if db.exists():
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
                        # Some databases contain year-one sentinel timestamps.
                        # They cannot be converted to local time on every system.
                        if cwd and stamp > 0:
                            dt.datetime.fromtimestamp(stamp)
                            yield (stamp, 'agy', sid, cwd, title or preview, str(db))
                    except (ValueError, TypeError, IndexError, OverflowError, OSError):
                        continue
        except sqlite3.Error as exc:
            print(f'resume: {exc}', file=sys.stderr)


def active_sessions():
    home = Path.home() / '.config'
    active = set()
    for agent in ('claude', 'claude-work', 'claude-auto'):
        for path in (home / agent / 'sessions').glob('*.json'):
            try:
                record = json.loads(path.read_text())
                pid = int(record['pid'])
                cmd = (Path('/proc') / str(pid) / 'cmdline').read_bytes().lower()
                if b'claude' in cmd and record.get('sessionId'):
                    active.add((agent, record['sessionId']))
            except (OSError, ValueError, KeyError, TypeError):
                continue
    for path in (home / 'codex/thread-writer-locks').glob('*.lock'):
        try:
            with path.open('rb') as lock:
                try:
                    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    fcntl.flock(lock, fcntl.LOCK_UN)
                except BlockingIOError:
                    active.add(('codex', path.stem))
        except OSError:
            continue
    return active


def relative_time(stamp):
    seconds = max(0, int(time.time() - stamp))
    for size, suffix in ((31536000, 'y'), (2592000, 'mo'), (86400, 'd'), (3600, 'h'), (60, 'm')):
        if seconds >= size:
            return f'{seconds // size}{suffix} ago'
    return 'now'


def cell_width(text):
    return sum(0 if unicodedata.combining(c) else 2 if unicodedata.east_asian_width(c) in ('W', 'F') else 1
               for c in text)


def message_card(role, agent, content):
    try:
        width = max(20, int(os.environ.get('FZF_PREVIEW_COLUMNS', '80')) - 2)
    except ValueError:
        width = 78
    inner = width - 4
    icon, color = ('󰀄', '38;5;111') if role == 'user' else AGENT_ICONS[agent]
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


def preview(agent, path, cwd, title, session_id, timestamp):
    reset = '\033[0m'

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

    if agent == 'agy':
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
            print('\033[3;38;5;245mFull conversation messages are stored in a binary format.\033[0m')
        except (sqlite3.Error, OSError) as exc:
            print(f'\033[3mCould not read Antigravity summary: {exc}\033[0m', file=sys.stderr)
        return
    messages = deque(maxlen=5)
    latest_user = ''
    try:
        with open(path, 'rb') as stream:
            size = stream.seek(0, os.SEEK_END)
            stream.seek(max(0, size - 4 * 1024 * 1024))
            if size > 4 * 1024 * 1024:
                stream.readline()  # Discard the partial first JSON line.
            for raw_line in stream:
                line = raw_line.decode('utf-8', errors='replace')
                try:
                    obj = json.loads(line)
                    if agent == 'codex':
                        item = obj.get('payload', {})
                        if obj.get('type') != 'response_item' or item.get('type') != 'message':
                            continue
                        role, content = item.get('role'), item.get('content', [])
                    else:
                        if obj.get('type') not in ('user', 'assistant'):
                            continue
                        item = obj.get('message') or {}
                        role, content = obj['type'], item.get('content', '')
                    if role not in ('user', 'assistant'):
                        continue
                    if isinstance(content, list):
                        content = '\n'.join(part.get('text', '') for part in content
                                            if isinstance(part, dict) and part.get('type') in ('text', 'input_text', 'output_text'))
                    if not isinstance(content, str):
                        continue
                    content = content.strip()
                    if not content or content.startswith(('<', '# AGENTS.md', '# Developer', '# system')):
                        continue
                    # Escape terminal control sequences in transcript content.
                    content = ''.join(c for c in content if c in '\n\t' or ord(c) >= 32 and ord(c) != 127)
                    if role == 'user':
                        latest_user = content
                    messages.append((role, content[-3000:]))
                except (ValueError, AttributeError, TypeError):
                    continue
        pinned(latest_user)
        metadata()
        for role, content in messages:
            message_card(role, agent, content)
        if not messages:
            print('\033[3;38;5;245mNo readable messages found.\033[0m')
    except OSError as exc:
        pinned('')
        metadata()
        print(f'\033[3mCould not read conversation: {exc}\033[0m', file=sys.stderr)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--preview-session', nargs=6, metavar=('AGENT', 'PATH', 'CWD', 'TITLE', 'ID', 'TIME'), help=argparse.SUPPRESS)
    parser.add_argument('selection', nargs='?', help='session number or ID to resume')
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--pick', action='store_true', help='select interactively with fzf (default)')
    mode.add_argument('--list', action='store_true', help='print sessions without opening the picker')
    parser.add_argument('--agent', choices=('codex', 'claude', 'claude-work', 'claude-auto', 'agy'), help='filter by agent')
    parser.add_argument('--cwd', help='filter by working directory or directory name')
    parser.add_argument('--limit', type=int, default=0, help='maximum displayed results (default: all)')
    args = parser.parse_args()
    if args.preview_session:
        preview(*args.preview_session)
        return
    sessions = sorted(records(), key=lambda row: row[0], reverse=True)
    active = active_sessions()
    agent_filter = args.agent
    cwd_filter = args.cwd
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
        icon, color = AGENT_ICONS[agent]
        reset = '\033[0m'
        provider = f'\033[{color}m{icon}{reset} {agent:11}'
        status = '\033[1;38;5;114m●\033[0m' if live else ' '
        width = 18 if narrow else 24
        folder = short_cwd if len(short_cwd) <= width else '…' + short_cwd[-(width - 1):]
        topic = clean if clean else '\033[3;38;5;245muntitled\033[0m'
        return (f'\033[38;5;245m{when:8}{reset} {status} {provider} '
                f'\033[38;5;109m{folder:{width}}{reset} {topic}')

    def filtered():
        return [row for row in sessions
                if (not agent_filter or row[1] == agent_filter) and (not cwd_filter or (row[3] == cwd_filter if cwd_filter.startswith('/') else cwd_filter.casefold() in row[3].casefold()))]

    if args.pick or (not args.list and not args.selection):
        env = os.environ.copy()
        env.pop('FZF_DEFAULT_OPTS', None)
        env.pop('FZF_DEFAULT_OPTS_FILE', None)
        theme = '--color=fg:#cdd6f4,bg:#1e1e2e,fg+:#ffffff,bg+:#313244,hl:#f9e2af,hl+:#f9e2af,pointer:#cba6f7,prompt:#89b4fa,header:#94e2d5,border:#6c7086'
        try:
            while True:
                rows = filtered()
                lines = '\n'.join('\t'.join([display(i, row, styled=True), row[1], row[5], row[3],
                                             ' '.join(str(row[4]).split()), row[2],
                                             dt.datetime.fromtimestamp(row[0]).strftime('%Y-%m-%d %H:%M:%S %Z')])
                                  for i, row in enumerate(rows, 1))
                width = 18 if narrow else 24
                columns = f'\033[38;5;245m{"LAST":8}   {"AGENT":13} {"CWD":{width}} TOPIC\033[0m'
                folder_label = Path(cwd_filter).name if cwd_filter else 'all'
                key = '\033[1;38;5;110m'
                hint = '\033[38;5;60m'
                shortcuts = f'{key}^G {hint}agent  {key}^D {hint}cwd  {key}^R {hint}reset  {key}Pg↑/↓ {hint}scroll'
                filters = f'agent: {agent_filter or "all"}  cwd: {folder_label}'
                list_width = terminal_width // 2 - 5 if terminal_width >= 120 else terminal_width - 4
                spacing = max(2, list_width - cell_width('^G agent  ^D cwd  ^R reset  Pg↑/↓ scroll') - cell_width(filters))
                footer = f'{shortcuts}{" " * spacing}{hint}{filters}\033[0m'
                result = subprocess.run(
                    ['fzf', '--ansi', '--info=hidden', '--no-separator', '--delimiter=\t', '--with-nth=1', '--no-sort', '--layout=reverse',
                     '--prompt=󰍉  Session  ❯ ', '--pointer=❯', '--marker=󰄬', theme,
                     '--bind=alt-up:preview-up,alt-down:preview-down,alt-k:preview-up,alt-j:preview-down,pgup:preview-page-up,pgdn:preview-page-down',
                     '--expect=ctrl-g,ctrl-d,ctrl-r', '--header=' + columns, '--footer=' + footer, '--footer-border=none',
                     '--preview=' + ' '.join(map(shlex.quote, [sys.executable, __file__, '--preview-session'])) + ' {2} {3} {4} {5} {6} {7}',
                     '--preview-window=right:50%:wrap-word:follow:noinfo:~1:<60(down:40%:wrap-word:follow:noinfo:~1)', '--preview-wrap-sign='],
                    input=lines, text=True, stdout=subprocess.PIPE, env=env,
                )
                if result.returncode:
                    return
                key, _, selected = result.stdout.partition('\n')
                if key == 'ctrl-r':
                    agent_filter = cwd_filter = None
                    continue
                if key in ('ctrl-g', 'ctrl-d'):
                    options = sorted({row[1] if key == 'ctrl-g' else row[3] for row in sessions})
                    prompt = 'Filter ' + ('agent' if key == 'ctrl-g' else 'directory') + ' ❯ '
                    if key == 'ctrl-g':
                        entries = ['󰒊 All\tAll'] + [
                            f'\033[{AGENT_ICONS[agent][1]}m{AGENT_ICONS[agent][0]}\033[0m {agent}\t{agent}'
                            for agent in options
                        ]
                        picker_options = ['--ansi', '--delimiter=\t', '--with-nth=1']
                    else:
                        entries = ['All'] + options
                        picker_options = []
                    choice = subprocess.run(['fzf', '--layout=reverse', '--prompt=' + prompt, theme] + picker_options,
                                            input='\n'.join(entries), text=True,
                                            stdout=subprocess.PIPE, env=env)
                    if choice.returncode == 0:
                        value = choice.stdout.strip()
                        if key == 'ctrl-g':
                            value = value.rsplit('\t', 1)[-1]
                        value = None if value == 'All' else value
                        if key == 'ctrl-g':
                            agent_filter = value
                        else:
                            cwd_filter = value
                    continue
                if not selected:
                    return
                args.selection = selected.split('\t')[5]
                break
        except FileNotFoundError:
            parser.error('the picker requires fzf')
    if not args.selection:
        for i, row in enumerate(filtered(), 1):
            if args.limit and i > args.limit:
                break
            print(display(i, row))
        return
    matches = ([sessions[int(args.selection) - 1]] if args.selection.isdigit() and 1 <= int(args.selection) <= len(sessions)
               else [row for row in sessions if row[2] == args.selection])
    if len(matches) != 1:
        parser.error('session not found or ambiguous; use its displayed number')
    _, agent, sid, cwd, _, _ = matches[0]
    if not os.path.isdir(cwd):
        parser.error(f'original working directory no longer exists: {cwd}')
    os.chdir(cwd)
    command = [agent, 'resume', sid] if agent == 'codex' else [agent, '--conversation' if agent == 'agy' else '--resume', sid]
    os.execvp(command[0], command)


if __name__ == '__main__':
    main()
