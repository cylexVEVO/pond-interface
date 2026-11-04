#!/usr/bin/env python3
"""Remappable Niri keyboard shortcuts.

Defaults come from the shipped shell + cfg keybind files. User changes are
stored in ~/.config/pond-interface/keybinds.json and applied through
~/.config/niri/cfg/keybinds-pond.kdl (included last so it wins per key).

Niri has no true unbind; clearing a shortcut overrides its chord with a no-op
spawn so the key no longer runs the previous action.
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from kdl import atomic_write, nodes, tokens

NIRI = Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config')) / 'niri'
POND = Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config')) / 'pond-interface'
STATE = POND / 'keybinds.json'
MANAGED = NIRI / 'cfg' / 'keybinds-pond.kdl'
SHELL_BINDS = NIRI / 'shell' / 'config.kdl'
USER_BINDS = NIRI / 'cfg' / 'keybinds.kdl'

# Packaged templates (repo/install layout) used for the default catalog.
_HERE = Path(__file__).resolve()
_PACKAGED = [
    _HERE.parents[3] / 'config' / 'niri' / 'shell' / 'config.kdl',
    _HERE.parents[3] / 'config' / 'niri' / 'cfg' / 'keybinds.kdl',
    Path('/usr/share/pond-interface/config/niri/shell/config.kdl'),
    Path('/usr/share/pond-interface/config/niri/cfg/keybinds.kdl'),
]

OPTIONAL = [
    {
        'id': 'toggle-sidebar',
        'title': 'Toggle Sidebar',
        'category': 'Shell',
        'defaultChord': None,
        'action': 'spawn "qs" "-c" "pond-shell" "ipc" "call" "sidebar" "toggle";',
        'props': {'repeat': False, 'hotkey-overlay-title': 'Toggle Sidebar'},
        'capturable': True,
    },
    {
        'id': 'toggle-settings',
        'title': 'Toggle Settings',
        'category': 'Shell',
        'defaultChord': None,
        'action': 'spawn "qs" "-c" "pond-shell" "ipc" "call" "settings" "toggle";',
        'props': {'repeat': False, 'hotkey-overlay-title': 'Toggle Settings'},
        'capturable': True,
    },
    {
        'id': 'open-display-settings',
        'title': 'Open Display Settings',
        'category': 'Shell',
        'defaultChord': None,
        'action': 'spawn "qs" "-c" "pond-shell" "ipc" "call" "settings" "open" "display";',
        'props': {'repeat': False, 'hotkey-overlay-title': 'Open Display Settings'},
        'capturable': True,
    },
]

CATEGORIES = [
    ('Applications', ('vicinae', 'kitty', 'nautilus', 'Open Launcher', 'Clipboard', 'Terminal', 'File Manager')),
    ('Shell', ('sidebar', 'settings', 'Switch Keyboard', 'Lock Screen', 'switch-layout', 'lockscreen',
               'Toggle Sidebar', 'Toggle Settings', 'Display Settings')),
    ('Media', ('volume', 'media', 'Audio', 'brightness', 'Volume Up', 'Volume Down', 'Mute', 'Track',
               'Play / Pause', 'Brightness')),
    ('Windows', ('close-window', 'focus-column', 'focus-window', 'move-column', 'move-window',
                 'focus-monitor', 'move-column-to-monitor', 'expand-column', 'center-column',
                 'center-visible', 'set-column-width', 'set-window-height', 'toggle-window-floating',
                 'fullscreen', 'toggle-column-tabbed', 'Close Window', 'Focus Column', 'Focus Window',
                 'Move Column', 'Move Window', 'Focus Monitor', 'Floating', 'Fullscreen', 'Tabbed',
                 'Column Width', 'Window Height', 'Center')),
    ('Workspaces', ('focus-workspace', 'move-column-to-workspace', 'workspace-previous', 'toggle-overview',
                    'Focus Workspace', 'Toggle Overview')),
    ('Screenshots', ('screenshot', 'Screenshot')),
    ('System', ('hotkey-overlay', 'keyboard-shortcuts-inhibit', 'quit', 'power-off', 'Hotkey Overlay',
                'Shortcuts Inhibit', 'Quit', 'Power Off')),
]

def run(*args, timeout=15):
    p = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
    if p.returncode:
        raise RuntimeError(p.stderr.strip() or 'Could not reload Niri config')
    return p.stdout


def decode(token: str):
    if token in ('true', 'false', 'null'):
        return {'true': True, 'false': False, 'null': None}[token]
    try:
        return json.loads(token)
    except Exception:
        return token


def normalize_chord(chord: str) -> str:
    parts = [p for p in chord.split('+') if p]
    if not parts:
        return ''
    aliases = {
        'control': 'Ctrl', 'ctrl': 'Ctrl', 'super': 'Mod', 'win': 'Mod', 'meta': 'Mod',
        'mod': 'Mod', 'alt': 'Alt', 'shift': 'Shift',
    }
    trigger = parts[-1]
    mods = [aliases.get(part.casefold(), part) for part in parts[:-1]]
    order = ['Mod', 'Ctrl', 'Alt', 'Shift']
    seen = []
    for name in order:
        if name in mods and name not in seen:
            seen.append(name)
    for name in mods:
        if name not in seen:
            seen.append(name)
    trigger_norm = {
        'escape': 'Escape', 'return': 'Return', 'space': 'Space', 'tab': 'TAB',
        'delete': 'Delete', 'home': 'Home', 'end': 'End', 'left': 'Left', 'right': 'Right',
        'up': 'Up', 'down': 'Down', 'minus': 'Minus', 'plus': 'Plus', 'equal': 'equal',
        'comma': 'Comma',
    }.get(trigger.casefold(), trigger)
    return '+'.join(seen + [trigger_norm]) if seen else trigger_norm


def normalize_action(action: str) -> str:
    return re.sub(r'\s+', ' ', action.strip().rstrip(';')) + ';'


def parse_props(ts, start, end):
    props = {}
    i = start
    while i < end:
        token = ts[i][0]
        if token in ('{', '\n', ';'):
            break
        if '=' in token:
            key, _, value = token.partition('=')
            if value == '' and i + 1 < end:
                props[key] = decode(ts[i + 1][0])
                i += 2
                continue
            props[key] = decode(value)
            i += 1
        else:
            i += 1
    return props


def parse_binds(text: str) -> list[dict]:
    if not text.strip():
        return []
    ts = tokens(text)
    result = []
    for first, last, opening, closing in nodes(ts):
        if ts[first][0] != 'binds' or opening is None:
            continue
        for bf, bl, bo, bc in nodes(ts, opening + 1, closing):
            if bo is None or bc is None:
                continue
            chord = ts[bf][0]
            props = parse_props(ts, bf + 1, bo)
            action = text[ts[bo][2]:ts[bc][1]].strip()
            result.append({
                'chord': chord,
                'norm': normalize_chord(chord),
                'props': props,
                'action': action,
                'fingerprint': normalize_action(action),
            })
    return result


def spawn_args(action: str) -> list[str]:
    body = normalize_action(action).rstrip(';')
    if body.startswith('spawn-sh '):
        body = body[len('spawn-sh '):]
    elif body.startswith('spawn '):
        body = body[len('spawn '):]
    else:
        return []
    return [decode(tok) if isinstance(decode(tok), str) else str(decode(tok))
            for tok in re.findall(r'"((?:\\.|[^"\\])*)"|(\S+)', body)
            for tok in (tok[0] if tok[0] else tok[1],) if tok]


def human_title(action: str, props: dict, chord: str | None = None) -> str:
    title = props.get('hotkey-overlay-title')
    if isinstance(title, str) and title.strip():
        return title.strip()
    action = normalize_action(action).rstrip(';')
    chord_l = (chord or '').casefold()
    # spawn / spawn-sh summaries
    if action.startswith('spawn-sh '):
        body = action[len('spawn-sh '):]
        if 'lockscreen' in body:
            return 'Lock Screen'
        return 'Run shell command'
    if action.startswith('spawn '):
        args = spawn_args(action)
        joined = ' '.join(str(a) for a in args)
        if 'vicinae' in joined and 'clipboard' in joined:
            return 'Open Clipboard History'
        if 'vicinae' in joined:
            return 'Open Launcher'
        if 'lockscreen' in joined:
            return 'Lock Screen'
        if 'volume' in joined and 'increase' in joined:
            return 'Volume Up'
        if 'volume' in joined and 'decrease' in joined:
            return 'Volume Down'
        if 'muteOutput' in joined:
            return 'Mute Volume'
        if 'muteInput' in joined:
            return 'Mute Microphone'
        if 'media' in joined and 'next' in joined:
            return 'Next Track'
        if 'media' in joined and 'previous' in joined:
            return 'Previous Track'
        if 'playPause' in joined:
            if 'pause' in chord_l and 'play' not in chord_l.replace('playpause', ''):
                return 'Pause'
            if 'play' in chord_l:
                return 'Play'
            return 'Play / Pause'
        if 'brightness' in joined and 'increase' in joined:
            return 'Brightness Up'
        if 'brightness' in joined and 'decrease' in joined:
            return 'Brightness Down'
        if args:
            return f'Open {Path(args[0]).name}'
    name, _, rest = action.partition(' ')
    label = name.replace('-', ' ')
    if rest:
        return f'{label} {rest}'.strip().title()
    return label.title()


def category_for(title: str, action: str) -> str:
    blob = f'{title} {action}'.casefold()
    for name, needles in CATEGORIES:
        if any(n.casefold() in blob for n in needles):
            return name
    return 'Other'


def capturable_chord(chord: str | None) -> bool:
    if not chord:
        return True
    lower = chord.casefold()
    return not any(token in lower for token in (
        'wheelscroll', 'touchpadscroll', 'mouseleft', 'mouseright', 'mousemiddle',
        'mouseforward', 'mouseback', 'tabletstylus',
    ))


def slug(parts: list[str]) -> str:
    base = '-'.join(re.sub(r'[^a-z0-9]+', '-', p.casefold()).strip('-') for p in parts if p)
    return base or 'bind'


def packaged_paths() -> tuple[Path | None, Path | None]:
    shell = next((p for p in _PACKAGED if p.name == 'config.kdl' and p.is_file()), None)
    cfg = next((p for p in _PACKAGED if p.name == 'keybinds.kdl' and p.is_file()), None)
    if shell is None and SHELL_BINDS.is_file():
        shell = SHELL_BINDS
    if cfg is None and USER_BINDS.is_file():
        cfg = USER_BINDS
    return shell, cfg


def build_catalog() -> list[dict]:
    shell_path, cfg_path = packaged_paths()
    entries = []
    used_ids: set[str] = set()

    def add(chord, props, action, optional=False):
        fingerprint = normalize_action(action)
        title = human_title(action, props, chord)
        base_id = slug([title, chord] if chord and not optional else [title])
        if optional:
            base_id = slug(['optional', title])
        ident = base_id
        n = 2
        while ident in used_ids:
            ident = f'{base_id}-{n}'
            n += 1
        used_ids.add(ident)
        default = None if optional else normalize_chord(chord)
        action_text = action.strip() if action.strip().endswith(';') else action.strip() + ';'
        # Prefer a stable short title; keep chord only in the id.
        display = human_title(action, props, chord)
        entries.append({
            'id': ident,
            'title': display,
            'category': category_for(title, action),
            'defaultChord': default,
            'action': action_text,
            'props': {k: v for k, v in props.items() if v is not None},
            'capturable': capturable_chord(default),
            'fingerprint': fingerprint,
        })

    if shell_path:
        for bind in parse_binds(shell_path.read_text()):
            add(bind['chord'], bind['props'], bind['action'])
    if cfg_path:
        for bind in parse_binds(cfg_path.read_text()):
            add(bind['chord'], bind['props'], bind['action'])

    for item in OPTIONAL:
        if item['id'] not in used_ids:
            used_ids.add(item['id'])
            entries.append(dict(item, fingerprint=normalize_action(item['action'])))

    return entries


_CATALOG = None


def catalog() -> list[dict]:
    global _CATALOG
    if _CATALOG is None:
        _CATALOG = build_catalog()
    return _CATALOG


def catalog_by_id() -> dict[str, dict]:
    return {item['id']: item for item in catalog()}


def read_json() -> dict:
    if not STATE.is_file():
        return {'bindings': {}}
    try:
        data = json.loads(STATE.read_text())
    except Exception:
        return {'bindings': {}}
    bindings = data.get('bindings')
    return {'bindings': bindings if isinstance(bindings, dict) else {}}


def write_json(data: dict):
    POND.mkdir(parents=True, exist_ok=True)
    atomic_write(STATE, json.dumps(data, indent=2, sort_keys=True) + '\n')


def format_props(props: dict) -> str:
    parts = []
    for key, value in props.items():
        if value is True:
            parts.append(f'{key}=true')
        elif value is False:
            parts.append(f'{key}=false')
        elif value is None:
            parts.append(f'{key}=null')
        elif isinstance(value, (int, float)):
            parts.append(f'{key}={value}')
        else:
            parts.append(f'{key}={json.dumps(value)}')
    return (' ' + ' '.join(parts)) if parts else ''


def noop_line(chord: str) -> str:
    return f'    {chord} hotkey-overlay-title=null {{ spawn ""; }}\n'


def bind_line(chord: str, entry: dict) -> str:
    props = dict(entry.get('props') or {})
    return f'    {chord}{format_props(props)} {{ {entry["action"].strip()} }}\n'


def base_binds() -> list[dict]:
    result = []
    for path in (SHELL_BINDS, USER_BINDS):
        if path.is_file():
            result.extend(parse_binds(path.read_text()))
    return result


def effective_key_map(include_managed=True) -> dict[str, dict]:
    """Later files win per normalized chord."""
    mapping = {}
    paths = [SHELL_BINDS, USER_BINDS]
    if include_managed:
        paths.append(MANAGED)
    for path in paths:
        if not path.is_file():
            continue
        for bind in parse_binds(path.read_text()):
            mapping[bind['norm']] = bind
    return mapping


def match_entries(key_map: dict[str, dict]) -> dict[str, str | None]:
    """Map catalog id -> current chord (or None if unbound)."""
    by_fp: dict[str, list[str]] = {}
    for chord, bind in key_map.items():
        if bind['fingerprint'] == normalize_action('spawn "";'):
            continue
        by_fp.setdefault(bind['fingerprint'], []).append(chord)

    assigned: dict[str, str | None] = {}
    used_chords: set[str] = set()
    for entry in catalog():
        fp = entry['fingerprint']
        candidates = [c for c in by_fp.get(fp, []) if c not in used_chords]
        if not candidates:
            assigned[entry['id']] = None
            continue
        preferred = entry['defaultChord']
        chord = preferred if preferred in candidates else candidates[0]
        used_chords.add(chord)
        assigned[entry['id']] = chord
    return assigned


def display_chord(chord: str | None) -> str:
    if not chord:
        return 'None'
    return chord.replace('Mod+', 'Super+').replace('CTRL+', 'Ctrl+').replace('Ctrl+', 'Ctrl+')


def status_rows(bindings: dict) -> list[dict]:
    key_map = effective_key_map(include_managed=True)
    matched = match_entries(key_map)
    rows = []
    for entry in catalog():
        if entry['id'] in bindings:
            value = bindings[entry['id']]
            chord = None if value is None else normalize_chord(str(value))
        elif matched.get(entry['id']) is not None:
            chord = matched[entry['id']]
        else:
            chord = entry['defaultChord'] if not key_map else None
        customized = entry['id'] in bindings and chord != entry['defaultChord']
        rows.append({
            'id': entry['id'],
            'title': entry['title'],
            'category': entry['category'],
            'chord': chord,
            'label': display_chord(chord),
            'defaultChord': entry['defaultChord'],
            'defaultLabel': display_chord(entry['defaultChord']),
            'customized': customized,
            'capturable': bool(entry['capturable']),
            'unbound': chord is None,
        })
    order = {name: i for i, (name, _) in enumerate(CATEGORIES)}
    rows.sort(key=lambda r: (order.get(r['category'], 99), r['title'].casefold()))
    return rows


def render_managed(bindings: dict) -> str:
    if not bindings:
        return '// Generated by Pond settings. Do not edit.\nbinds {\n}\n'

    entries = catalog_by_id()
    base = base_binds()
    # Effective keys before managed file.
    before = {}
    for bind in base:
        before[bind['norm']] = bind

    # Resolve desired chord per catalog id.
    desired: dict[str, str | None] = {}
    for entry in catalog():
        if entry['id'] in bindings:
            value = bindings[entry['id']]
            desired[entry['id']] = None if value is None else normalize_chord(str(value))
        else:
            # leave untouched
            pass

    noop_keys: set[str] = set()
    emit: list[tuple[str, dict]] = []

    for ident, chord in desired.items():
        entry = entries[ident]
        fp = entry['fingerprint']
        # Keys currently running this action in base configs.
        current_keys = [b['norm'] for b in before.values() if b['fingerprint'] == fp]
        if entry['defaultChord']:
            current_keys.append(entry['defaultChord'])
        current_keys = list(dict.fromkeys(current_keys))

        for key in current_keys:
            if chord is None or key != chord:
                noop_keys.add(key)

        if chord is not None:
            # Stealing a key from another action: noop not needed; we overwrite.
            emit.append((chord, entry))
            noop_keys.discard(chord)

    # If two overrides emit the same chord, last wins — prevent that.
    by_chord = {}
    for chord, entry in emit:
        by_chord[chord] = entry

    lines = ['// Generated by Pond settings. Do not edit.\n', 'binds {\n']
    for key in sorted(noop_keys):
        if key in by_chord:
            continue
        lines.append(noop_line(key))
    for chord, entry in sorted(by_chord.items(), key=lambda item: item[0].casefold()):
        lines.append(bind_line(chord, entry))
    lines.append('}\n')
    return ''.join(lines)


def apply(bindings: dict):
    write_json({'bindings': bindings})
    MANAGED.parent.mkdir(parents=True, exist_ok=True)
    atomic_write(MANAGED, render_managed(bindings))
    try:
        run('niri', 'msg', 'action', 'load-config-file')
    except Exception as error:
        # Still persist; compositor may be absent in tests or mid-session.
        result = load()
        result['warning'] = str(error)
        return result
    return load()


def load():
    data = read_json()
    rows = status_rows(data['bindings'])
    language = next(
        (row['label'] for row in rows
         if 'switch-layout' in catalog_by_id().get(row['id'], {}).get('action', '')),
        'Super+K',
    )
    return {
        'bindings': data['bindings'],
        'shortcuts': rows,
        'languageChord': language,
    }

def set_bind(ident: str, chord: str):
    entries = catalog_by_id()
    if ident not in entries:
        raise ValueError('Unknown shortcut')
    chord = normalize_chord(chord)
    if not chord:
        raise ValueError('Invalid shortcut')
    if not capturable_chord(chord):
        raise ValueError('That key cannot be captured; pick a keyboard shortcut')
    data = read_json()
    bindings = dict(data['bindings'])
    bindings[ident] = chord
    # Free the chord from whoever currently owns it (live map, override, or default).
    current = match_entries(effective_key_map(include_managed=True))
    for other, other_chord in current.items():
        if other != ident and other_chord == chord:
            bindings[other] = None
    for entry in catalog():
        if entry['id'] == ident:
            continue
        if entry['id'] in bindings:
            value = bindings[entry['id']]
            if value is not None and normalize_chord(str(value)) == chord:
                bindings[entry['id']] = None
        elif entry['defaultChord'] == chord:
            bindings[entry['id']] = None
    return apply(bindings)


def unbind(ident: str):
    if ident not in catalog_by_id():
        raise ValueError('Unknown shortcut')
    data = read_json()
    bindings = dict(data['bindings'])
    bindings[ident] = None
    return apply(bindings)


def reset(ident: str):
    entries = catalog_by_id()
    if ident not in entries:
        raise ValueError('Unknown shortcut')
    data = read_json()
    bindings = dict(data['bindings'])
    entry = entries[ident]
    # Force packaged default through the override layer. status_rows treats a
    # binding that equals the default as not customized.
    bindings[ident] = entry['defaultChord']
    return apply(bindings)


def reset_all():
    return apply({})


if __name__ == '__main__':
    try:
        action, *args = sys.argv[1:]
        actions = {
            'load': load,
            'set': set_bind,
            'unbind': unbind,
            'reset': reset,
            'reset-all': reset_all,
        }
        print(json.dumps(actions[action](*args)))
    except Exception as error:
        print(json.dumps({'error': str(error)}))
        sys.exit(1)
