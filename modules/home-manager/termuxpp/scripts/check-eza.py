import json
from pathlib import Path
import subprocess
import tempfile


cache = Path.home() / '.cache'
cache.mkdir(exist_ok=True)
with tempfile.TemporaryDirectory(prefix='nixpp-eza-', dir=cache) as directory:
    root = Path(directory)
    (root / 'nested').mkdir()
    (root / 'nested' / 'file.txt').write_text('test\n')
    (root / '.hidden').write_text('hidden\n')
    (root / 'link').symlink_to('nested/file.txt')
    subprocess.run(['git', 'init', '-q', directory], check=True, timeout=15)
    cases = [
        ['-d', directory],
        ['-al', '--icons=never', directory],
        ['--color=always', '--icons=always', '--group-directories-first', '-al', directory],
        ['--tree', '--level=3', directory],
        ['--git', '-al', directory],
        ['-al', '/etc'],
    ]
    count = 0
    for _ in range(10):
        for args in cases:
            result = subprocess.run(['eza', *args], stdout=subprocess.PIPE,
                                    stderr=subprocess.PIPE, timeout=30)
            assert result.returncode == 0, (args, result.returncode)
            assert result.stdout, args
            count += 1
    print(json.dumps({'eza_listings': count, 'success': True}))
