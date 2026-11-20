# jc parser for: adb shell cmd wifi status
# usage:
#   adb shell cmd wifi status | jc --cmd-wifi-status -p
from typing import List, Dict
import jc.utils
import re

class info():
  version = '1.0'
  description = '`adb shell cmd wifi status` parser'
  author = 'Philipp Schmitt'
  compatible = ['linux', 'darwin', 'cygwin', 'win32', 'aix', 'freebsd']
  tags = ['command']
  deprecated = False
  hidden = False

__version__ = info.version

_num_re = re.compile(r'-?(?:\d+\.\d*|\d*\.\d+|\d+)(?:[eE]-?\d+)?$')

def _to_bool(s: str):
  sl = s.lower()
  if sl in ('true', 'yes', 'on'):
    return True
  if sl in ('false', 'no', 'off'):
    return False
  return None

def _coerce(_, v: str):
  s = v.strip().strip('"')
  if s == '<none>':
    return None
  b = _to_bool(s)
  if b is not None:
    return b
  if _num_re.match(s):
    try:
      return int(s)
    except ValueError:
      try:
        return float(s)
      except ValueError:
        pass
  m = re.fullmatch(r'(\d+)\s*Mb(?:ps)?', s, re.I)
  if m:
    return int(m.group(1))
  m = re.fullmatch(r'(\d+)\s*MHz', s, re.I)
  if m:
    return int(m.group(1))
  if s.startswith('/') and _num_re.match(s[1:]) is None:
    # normalize weird leading slash in IP like "/10.5.0.188"
    return s[1:]
  return s

def _kv_line(line: str, out: Dict):
  if ':' not in line:
    return
  k, v = line.split(':', 1)
  k = k.strip().lower().replace(' ', '_')
  out[k] = _coerce(k, v)

def _parse_wifiinfo(remainder: str, out: Dict):
  parts = re.split(r',\s+(?=[A-Za-z])', remainder.strip())
  for p in parts:
    if ':' not in p:
      continue
    k, v = p.split(':', 1)
    k = k.strip().lower().replace(' ', '_')
    out[k] = _coerce(k, v)

def _process(proc_data: List[Dict]) -> List[Dict]:
  # derive channel/band if frequency present
  if proc_data and isinstance(proc_data[0].get('frequency'), int):
    f = proc_data[0]['frequency']
    ch = None
    band = None
    if 2400 <= f <= 2500:
      band = '2.4GHz'
      ch = round((f - 2407) / 5)
    elif 5150 <= f <= 5950:
      band = '5GHz'
      # common 5 GHz mapping (approx)
      ch = round((f - 5000) / 5)
    elif 5925 <= f <= 7125:
      band = '6GHz'
      ch = round((f - 5950) / 5)
    if ch:
      proc_data[0]['channel'] = ch
    if band:
      proc_data[0]['band'] = band
  return proc_data

def parse(data: str, raw: bool = False, quiet: bool = False) -> List[Dict]:
  jc.utils.compatibility(__name__, info.compatible, quiet)
  jc.utils.input_type_check(data)

  out: Dict[str, object] = {}
  if not jc.utils.has_data(data):
    return [] if raw else _process([])

  for line in filter(None, data.splitlines()):
    line = line.rstrip()

    if line == 'Wifi is enabled':
      out['wifi_enabled'] = True
      continue
    if line == 'Wifi scanning is always available':
      out['wifi_scanning_always_available'] = True
      continue
    if line.startswith('==== '):
      continue

    m = re.match(r'Wifi is connected to\s+"(.+)"', line)
    if m:
      out['connected_ssid'] = m.group(1)
      continue

    if line.startswith('WifiInfo:'):
      _, rest = line.split(':', 1)
      _parse_wifiinfo(rest, out)
      continue

    _kv_line(line, out)

  return [out] if raw else _process([out])
