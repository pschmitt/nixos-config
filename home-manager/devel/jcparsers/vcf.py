"""jc parser for vCard (VCF) files"""
from __future__ import annotations

from typing import Dict, List, Optional, Any, Tuple, Set
import re

import jc.utils


class info:
    version = '1.0'
    description = '`vCard` (`.vcf`) parser'
    author = 'Philipp Schmitt'
    compatible = ['linux', 'darwin', 'cygwin', 'win32', 'aix', 'freebsd']
    tags = ['file', 'structured']
    deprecated = False
    hidden = False


__version__ = info.version


_SEMICOLON_FIELDS = {
    'n',
    'adr',
    'org',
    'clientpidmap',
    'geo',
}

_COMMA_FIELDS = {
    'categories',
    'nickname',
    'member',
    'related',
}


_ESCAPE_RE = re.compile(r'\\(n|N|\\|;|,|:)', re.MULTILINE)
_PHONE_SANITIZE_RE = re.compile(r'[\s().-]')

_ADDRESS_PARTS = [
    'po_box',
    'extended',
    'street',
    'locality',
    'region',
    'postal_code',
    'country',
]

_NAME_PART_COUNT = 5


def _unfold_lines(data: str) -> List[str]:
    lines: List[str] = []
    current: Optional[str] = None

    for raw_line in data.splitlines():
        line = raw_line.rstrip('\r')
        if not line:
            if current is not None:
                lines.append(current)
                current = None
            continue

        if line.startswith((' ', '\t')):
            if current is None:
                current = line.lstrip()
            else:
                current += line[1:]
        else:
            if current is not None:
                lines.append(current)
            current = line

    if current is not None:
        lines.append(current)

    return lines


def _split_escaped(value: str, sep: str) -> List[str]:
    result: List[str] = []
    current: List[str] = []
    escape = False

    for ch in value:
        if escape:
            current.append(ch)
            escape = False
            continue

        if ch == '\\':
            escape = True
            continue

        if ch == sep:
            result.append(''.join(current))
            current = []
        else:
            current.append(ch)

    result.append(''.join(current))
    return result


def _unescape(value: str) -> str:
    def repl(match: re.Match[str]) -> str:
        group = match.group(1)
        if group in ('n', 'N'):
            return '\n'
        if group == '\\':
            return '\\'
        return group

    return _ESCAPE_RE.sub(repl, value)


def _parse_name_and_params(token: str) -> tuple[str, Optional[str], Dict[str, List[str]]]:
    parts = token.split(';')
    name_token = parts[0].strip()
    param_tokens = parts[1:]

    group: Optional[str] = None
    name = name_token
    if '.' in name_token:
        group, name = name_token.split('.', 1)

    name = name.strip()
    group = group.strip() if group else None

    norm_name = name.lower().replace('-', '_')
    norm_group = group.lower().replace('-', '_') if group else None

    params: Dict[str, List[str]] = {}
    for p in param_tokens:
        token = p.strip()
        if not token:
            continue
        if '=' in token:
            param_name, raw_value = token.split('=', 1)
            param_name = param_name.strip().lower().replace('-', '_')
            values = [
                _unescape(item.strip())
                for item in _split_escaped(raw_value, ',')
                if item.strip() != ''
            ]
        else:
            param_name = 'type'
            values = [
                _unescape(item.strip())
                for item in _split_escaped(token, ',')
                if item.strip() != ''
            ]

        if param_name == 'type':
            values = [value.lower() for value in values]
        elif param_name == 'value':
            values = [value.lower() for value in values]

        if not values:
            continue

        existing = params.setdefault(param_name, [])
        for val in values:
            if val not in existing:
                existing.append(val)

    return norm_name, norm_group, params


def _coerce_value(name: str, raw_value: str) -> Any:
    stripped = raw_value.strip()
    if name in _SEMICOLON_FIELDS:
        return [_unescape(item.strip()) for item in _split_escaped(stripped, ';')]
    if name in _COMMA_FIELDS:
        return [_unescape(item.strip()) for item in _split_escaped(stripped, ',')]
    return _unescape(stripped)


def _store_property(card: Dict[str, List[Dict[str, Any]]], name: str, entry: Dict[str, Any]) -> None:
    card.setdefault(name, []).append(entry)


def _simplify_entry(entry: Dict[str, Any]) -> Any:
    if set(entry.keys()) == {'value'}:
        return entry['value']
    return entry


def _simplify_card(card: Dict[str, List[Dict[str, Any]]]) -> Dict[str, Any]:
    simplified: Dict[str, Any] = {}
    for key, entries in card.items():
        processed = [_simplify_entry(entry) for entry in entries]
        if len(processed) == 1:
            simplified[key] = processed[0]
        else:
            simplified[key] = processed
    return simplified


def _split_types(entry: Dict[str, Any]) -> Tuple[Optional[str], bool]:
    params = entry.get('params', {})
    raw_types = params.get('type', []) or []
    preferred = False
    types: List[str] = []

    for item in raw_types:
        if item == 'pref':
            preferred = True
        else:
            types.append(item)

    if 'pref' in params:
        preferred = True

    label = types[0] if types else None
    return label, preferred


def _format_email(
    entry: Dict[str, Any], label_map: Dict[str, str]
) -> Optional[Dict[str, Any]]:
    value = entry.get('value')
    if not value:
        return None

    label, preferred = _split_types(entry)
    if (not label or label == '') and entry.get('group'):
        mapped = label_map.get(entry['group'])
        if mapped:
            label = mapped
    formatted: Dict[str, Any] = {
        'label': label,
        'value': value,
    }
    if preferred:
        formatted['preferred'] = True
    return formatted


def _format_phone(
    entry: Dict[str, Any], label_map: Dict[str, str]
) -> Optional[Dict[str, Any]]:
    raw_value = entry.get('value')
    if isinstance(raw_value, list):
        display = ' '.join(part for part in raw_value if part)
    else:
        display = str(raw_value) if raw_value is not None else ''

    display = display.strip()
    if not display:
        return None

    normalized = _PHONE_SANITIZE_RE.sub('', display)
    label, preferred = _split_types(entry)
    if (not label or label == '') and entry.get('group'):
        mapped = label_map.get(entry['group'])
        if mapped:
            label = mapped
    formatted: Dict[str, Any] = {
        'label': label,
        'display': display,
        'value': normalized or display,
    }
    if preferred:
        formatted['preferred'] = True
    return formatted


def _format_address(
    entry: Dict[str, Any], label_map: Dict[str, str]
) -> Optional[Dict[str, Any]]:
    raw_value = entry.get('value')
    components: Dict[str, str] = {}

    if isinstance(raw_value, list):
        parts = [item for item in raw_value if item]
        for index, part in enumerate(raw_value):
            if index < len(_ADDRESS_PARTS) and part:
                components[_ADDRESS_PARTS[index]] = part
    elif isinstance(raw_value, str):
        parts = [raw_value] if raw_value else []
    else:
        parts = []

    text = ', '.join(parts).strip()
    if not text:
        return None

    label, preferred = _split_types(entry)
    if (not label or label == '') and entry.get('group'):
        mapped = label_map.get(entry['group'])
        if mapped:
            label = mapped
    formatted: Dict[str, Any] = {
        'label': label,
        'value': text,
    }
    if components:
        formatted['components'] = components
    if preferred:
        formatted['preferred'] = True
    return formatted


def _format_url(
    entry: Dict[str, Any], label_map: Dict[str, str]
) -> Optional[Dict[str, Any]]:
    value = entry.get('value')
    if not value:
        return None

    label, preferred = _split_types(entry)
    if (not label or label == '') and entry.get('group'):
        mapped = label_map.get(entry['group'])
        if mapped:
            label = mapped
    formatted: Dict[str, Any] = {
        'label': label,
        'value': value,
    }
    if preferred:
        formatted['preferred'] = True
    return formatted


def _collect(
    entries: List[Dict[str, Any]],
    formatter,
    label_map: Dict[str, str],
) -> List[Dict[str, Any]]:
    results: List[Dict[str, Any]] = []
    seen: Set[Tuple[Any, Any]] = set()

    for entry in entries:
        formatted = formatter(entry, label_map)
        if not formatted:
            continue
        key = (formatted.get('value'), formatted.get('label'))
        if key in seen:
            continue
        seen.add(key)
        results.append(formatted)

    return results


def _format_card(card: Dict[str, List[Dict[str, Any]]]) -> Dict[str, Any]:
    simplified = _simplify_card(card)
    label_map: Dict[str, str] = {}

    for entry in card.get('x_ablabel', []):
        group = entry.get('group') if isinstance(entry, dict) else None
        value = entry.get('value') if isinstance(entry, dict) else None
        if not group or not value:
            continue
        if group not in label_map:
            label_map[group] = str(value)

    formatted: Dict[str, Any] = {
        key: value
        for key, value in simplified.items()
        if key not in {'adr', 'email', 'tel', 'url', 'nickname'}
    }

    formatted['emails'] = _collect(card.get('email', []), _format_email, label_map)
    formatted['phones'] = _collect(card.get('tel', []), _format_phone, label_map)
    formatted['addresses'] = _collect(card.get('adr', []), _format_address, label_map)
    formatted['urls'] = _collect(card.get('url', []), _format_url, label_map)

    nick = simplified.get('nickname')
    if isinstance(nick, list):
        nick_list = [item for item in nick if item]
    elif isinstance(nick, str):
        nick_list = [nick] if nick else []
    else:
        nick_list = []

    if nick_list:
        formatted['nicknames'] = nick_list

    if 'n' in simplified and isinstance(simplified['n'], list):
        components = simplified['n'][:_NAME_PART_COUNT]
        if len(components) < _NAME_PART_COUNT:
            components = components + [''] * (_NAME_PART_COUNT - len(components))
        name_parts = {
            'family': components[0] if len(components) > 0 else '',
            'given': components[1] if len(components) > 1 else '',
            'additional': components[2] if len(components) > 2 else '',
            'prefix': components[3] if len(components) > 3 else '',
            'suffix': components[4] if len(components) > 4 else '',
        }
        formatted['name_components'] = name_parts

    return formatted


def parse(data: str, raw: bool = False, quiet: bool = False) -> List[Dict[str, Any]]:
    jc.utils.compatibility(__name__, info.compatible, quiet)
    jc.utils.input_type_check(data)

    raw_cards: List[Dict[str, List[Dict[str, Any]]]] = []
    current: Optional[Dict[str, List[Dict[str, Any]]]] = None

    if not jc.utils.has_data(data):
        return raw_cards if raw else []

    for line in _unfold_lines(data):
        if not line:
            continue

        upper_line = line.upper()
        if upper_line == 'BEGIN:VCARD':
            if current is not None:
                raw_cards.append(current)
            current = {}
            continue
        if upper_line == 'END:VCARD':
            if current is not None:
                raw_cards.append(current)
                current = None
            continue

        if current is None:
            continue

        if ':' not in line:
            continue

        name_token, raw_value = line.split(':', 1)
        prop_name, group, params = _parse_name_and_params(name_token)
        value = _coerce_value(prop_name, raw_value)

        entry: Dict[str, Any] = {'value': value}
        if params:
            entry['params'] = params
        if group:
            entry['group'] = group

        _store_property(current, prop_name, entry)

    if current is not None:
        raw_cards.append(current)

    if raw:
        return raw_cards

    return [_format_card(card) for card in raw_cards]
