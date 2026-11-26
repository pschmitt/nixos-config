#!/usr/bin/env python3
"""Compare two zsh-state.zsh dumps section by section.

Usage: zsh-state-diff.py OLD NEW

Prints functions that exist only on one side or changed, and per section the
lines that went away (-) or appeared (+). New autoload stubs are only counted.
"""
import collections
import sys


def parse(path):
    sections = collections.OrderedDict()
    current = function = None
    with open(path, errors='replace') as handle:
        for line in handle:
            line = line.rstrip('\n')
            if line.startswith('## ') and not line.startswith('### '):
                current = line[3:]
                sections[current] = {} if current == 'functions' else []
                function = None
            elif current == 'functions':
                if line.startswith('### '):
                    function = line[4:]
                    sections[current][function] = []
                elif function:
                    sections[current][function].append(line)
            elif current:
                sections[current].append(line)
    return sections


def main(argv):
    if len(argv) == 2 and argv[1] in ('-h', '--help'):
        print(__doc__)
        return 0
    if len(argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    old, new = parse(argv[1]), parse(argv[2])
    stub = ['builtin autoload -XU']
    fo, fn = old.get('functions', {}), new.get('functions', {})
    print('functions only old:', sorted(k for k in fo if k not in fn))
    print('functions only new:', sorted(k for k in fn if k not in fo and fn[k] != stub))
    print('autoload stubs only new:', sum(1 for k in fn if k not in fo and fn[k] == stub))
    print('functions changed:', sorted(k for k in fo if k in fn and fo[k] != fn[k]))
    for section, lines in old.items():
        if section == 'functions':
            continue
        before, after = set(lines), set(new.get(section, []))
        if before != after:
            print(f'== {section}: -{len(before - after)} +{len(after - before)}')
            for line in sorted(before - after):
                print('  -', line[:200])
            for line in sorted(after - before):
                print('  +', line[:200])
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
