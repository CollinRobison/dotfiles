"""Discover external shortcuts and compare them using Neovim key notation."""
import ast
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
MODS = ("C", "M", "D", "S", "H", "T", "Fn")
ANGLE_KEY = re.compile(r"<((?:(?:[CMDSHT]|Fn)-)+>)>|<([^<>]+)>", re.I)
ALIASES = {
    " ": "Space", "space": "Space", "return": "CR", "enter": "CR", "cr": "CR",
    "esc": "Esc", "escape": "Esc", "tab": "Tab", "backspace": "BS", "bs": "BS",
    "delete": "Del", "del": "Del", "insert": "Insert", "ins": "Insert",
    "lt": "<", "bar": "|", "bslash": "\\", "up": "Up", "down": "Down",
    "left": "Left", "right": "Right", "home": "Home", "end": "End",
    "pageup": "PageUp", "pagedown": "PageDown", "page_up": "PageUp",
    "page_down": "PageDown", "nl": "NL", "nul": "Nul", "help": "Help",
}
SHIFTED = dict(zip('`1234567890-=[]\\;\',./', '~!@#$%^&*()_+{}|:"<>?'))

def tokens(value, leader="\\", localleader="\\"):
    """Return a sequence of physical chords for matching across layers."""
    result = []
    pos = 0
    while pos < len(value):
        match = ANGLE_KEY.match(value, pos) if value[pos] == "<" else None
        if not match:
            char = value[pos]
            result.append(((), ALIASES.get(char, char)))
            pos += 1
            continue
        word = match[1] or match[2]
        pos = match.end()
        if word.lower() in ("leader", "localleader"):
            expansion = leader if word.lower() == "leader" else localleader
            if re.search(r"<(?:local)?leader>", expansion, re.I):
                expansion = "\\"
            result.extend(tokens(expansion))
            continue
        mods = set()
        while (prefix := re.match(r"([CMDSHT]|Fn)-", word, re.I)) is not None:
            mod = prefix[1]
            mods.add("Fn" if mod.lower() == "fn" else mod.upper())
            word = word[len(prefix[0]):]
        key = ALIASES.get(word.lower(), word if len(word) == 1 else word.lower())
        if len(key) == 1 and key.isascii() and key.isalpha():
            if key.isupper() and not mods:
                mods.add("S")
            key = key.lower()
        if "S" in mods:
            key = SHIFTED.get(key, key) if key in SHIFTED else key
            if key in SHIFTED.values():
                mods.discard("S")
        result.append((tuple(mod for mod in MODS if mod in mods), key))
    return tuple((("S",), key.lower()) if not modifiers and len(key) == 1 and key.isascii() and key.isupper()
                 else (modifiers, key) for modifiers, key in result)


def legacy(chords):
    aliases = {"i": "Tab", "m": "CR", "j": "NL", "[": "Esc", "h": "BS", "@": "Nul", "Space": "Nul"}
    return tuple(((), aliases[key]) if mods == ("C",) and key in aliases else (mods, key)
                 for mods, key in chords)


def chord(key, modifiers=()):
    if key == "<":
        key = "lt"
    return "<" + "-".join([*modifiers, key]) + ">" if modifiers or len(key) != 1 else key


def command(*args):
    return subprocess.run(args, capture_output=True, timeout=5, check=True).stdout


def kitty_shortcuts():
    executable = shutil.which("kitty")
    if not executable:
        return [], "Kitty executable unavailable"
    runner = 'import runpy, sys; runpy.run_path(sys.argv.pop(1), run_name="__main__")'
    paths = []
    if os.environ.get("KITTY_CONFIG_DIRECTORY"):
        paths = [str(Path(os.environ["KITTY_CONFIG_DIRECTORY"]) / "kitty.conf")]
    try:
        return json.loads(command(executable, "+runpy", runner, str(HERE / "kitty_keys.py"), *paths)), None
    except (subprocess.SubprocessError, OSError, ValueError):
        return [], "Kitty could not resolve its keymap"


MAC_CODES = {
    0:"a", 1:"s", 2:"d", 3:"f", 4:"h", 5:"g", 6:"z", 7:"x", 8:"c", 9:"v", 11:"b",
    12:"q", 13:"w", 14:"e", 15:"r", 16:"y", 17:"t", 18:"1", 19:"2", 20:"3", 21:"4",
    22:"6", 23:"5", 24:"=", 25:"9", 26:"7", 27:"-", 28:"8", 29:"0", 30:"]", 31:"o",
    32:"u", 33:"[", 34:"i", 35:"p", 36:"CR", 37:"l", 38:"j", 39:"'", 40:"k", 41:";",
    42:"\\", 43:",", 44:"/", 45:"n", 46:"m", 47:".", 48:"Tab", 49:"Space", 50:"`",
    51:"BS", 53:"Esc", 64:"F17", 79:"F18", 80:"F19", 90:"F20", 96:"F5", 97:"F6", 98:"F7",
    99:"F3", 100:"F8", 101:"F9", 103:"F11", 105:"F13", 106:"F16", 107:"F14", 109:"F10",
    111:"F12", 113:"F15", 114:"Help", 115:"Home", 116:"PageUp", 117:"Del", 118:"F4",
    119:"End", 120:"F2", 121:"PageDown", 122:"F1", 123:"Left", 124:"Right", 125:"Down", 126:"Up",
}
MAC_MODS = {17: "S", 18: "C", 19: "M", 20: "D", 23: "Fn"}
MAC_LABELS = {"27": "Move focus to next window", "32": "Mission Control", "33": "Application windows",
              "36": "Screenshot", "37": "Copy screenshot", "38": "Screenshot selection",
              "39": "Copy screenshot selection", "60": "Select previous input source",
              "61": "Select next input source", "64": "Spotlight", "65": "Finder search window",
              "79": "Move left a Space", "81": "Move right a Space", "184": "Screenshot options"}

def external_row(key, desc, context, file, origin="System"):
    return {"key": key, "desc": desc, "context": context, "file": file, "origin": origin}

def mac_preferences(domain):
    return plistlib.loads(command("defaults", "export", domain, "-"))

def mac_shortcuts():
    rows, notes = [], []
    try:
        saved = mac_preferences("com.apple.symbolichotkeys").get("AppleSymbolicHotKeys", {})
    except (subprocess.SubprocessError, OSError, ValueError, plistlib.InvalidFileException):
        saved = {}
        notes.append("macOS shortcut preferences unavailable")
    # These common defaults apply when there is no explicit preference. Some
    # system-wide shortcuts, such as app switching, have no symbolic ID.
    defaults = {
        "32": [65535, 126, 1 << 18], "33": [65535, 125, 1 << 18],
        "36": [51, 20, (1 << 20) | (1 << 17)],
        "38": [52, 21, (1 << 20) | (1 << 17)],
        "64": [32, 49, 1 << 20], "184": [53, 23, (1 << 20) | (1 << 17)],
    }
    for ident, params in defaults.items():
        saved.setdefault(ident, {"enabled": True, "value": {"parameters": params}})
    for ident, item in saved.items():
        params = item.get("value", {}).get("parameters", [])
        if not item.get("enabled") or len(params) != 3:
            continue
        codepoint, keycode, flags = params
        key = MAC_CODES.get(keycode)
        if keycode < 64 and 32 < codepoint < 127:
            key = chr(codepoint).lower()
        if key:
            mods = [mod for bit, mod in MAC_MODS.items() if flags & (1 << bit)]
            rows.append(external_row(chord(key, mods), MAC_LABELS.get(ident, "Symbolic shortcut " + ident),
                                     "macOS global", "Keyboard Shortcuts"))
    for key, title in (("<D-Tab>", "Switch apps"), ("<D-S-Tab>", "Switch apps in reverse"),
                       ("<D-M-Esc>", "Force Quit"), ("<D-C-q>", "Lock screen")):
        rows.append(external_row(key, title, "macOS global", "Built-in macOS shortcut"))
    for domain, label in (("NSGlobalDomain", "All apps"), ("net.kovidgoyal.kitty", "Kitty")):
        try:
            menu = mac_preferences(domain).get("NSUserKeyEquivalents", {})
        except (subprocess.SubprocessError, OSError, ValueError, plistlib.InvalidFileException):
            continue
        for title, binding in menu.items():
            modifier_map = {"@": "D", "^": "C", "~": "M", "$": "S"}
            prefix, key = binding[:-1], binding[-1:]
            if not key or any(char not in modifier_map for char in prefix):
                continue
            key = {" ": "Space", "\r": "CR", "\t": "Tab", "\x1b": "Esc",
                   "\uf700": "Up", "\uf701": "Down", "\uf702": "Left", "\uf703": "Right"}.get(key, key)
            rows.append(external_row(chord(key, [modifier_map[char] for char in prefix]),
                                     title.rsplit("->", 1)[-1], label + " menu", "App Shortcuts"))
    try:
        if "/Loop.app/" in command("ps", "-ax", "-o", "comm=").decode(errors="replace"):
            loop = mac_preferences("com.MrKai77.Loop")
            loop_flags = {54: "D", 55: "D", 56: "S", 57: "CapsLock", 58: "M",
                          59: "C", 60: "S", 61: "M", 62: "C", 63: "Fn"}
            trigger = loop.get("trigger", [])
            if trigger and all(code in loop_flags for code in trigger):
                mods = [loop_flags[code] for code in trigger]
                for entry in loop.get("keybinds", []):
                    action = json.loads(entry)
                    keys = action.get("keybind", [])
                    if len(keys) == 1 and keys[0] in MAC_CODES:
                        rows.append(external_row(chord(MAC_CODES[keys[0]], mods),
                                                action.get("name") or action["direction"],
                                                "Loop window manager", "Active Loop preferences"))
    except (subprocess.SubprocessError, OSError, ValueError, plistlib.InvalidFileException):
        notes.append("Loop shortcut preferences unavailable")
    return rows, notes


def gnome_key(binding):
    match = re.fullmatch(r"((?:<\w+>)*)((?:\w|[,.+\-/=])+)\Z", binding)
    if not match:
        return None
    mapping = {"ctrl": "C", "control": "C", "primary": "C", "alt": "M",
               "shift": "S", "super": "D", "meta": "T", "hyper": "H"}
    names = re.findall(r"<(\w+)>", match[1].lower())
    if all(name in mapping for name in names):
        return chord(match[2], [mapping[name] for name in names])


def gnome_shortcuts():
    if not shutil.which("gsettings") or "GNOME" not in os.getenv("XDG_CURRENT_DESKTOP", "").upper():
        return [], ["System shortcuts are unavailable for this desktop"]
    schemas = ("org.gnome.desktop.wm.keybindings", "org.gnome.shell.keybindings",
               "org.gnome.settings-daemon.plugins.media-keys")
    rows, notes = [], []
    for schema in schemas:
        try:
            data = command("gsettings", "list-recursively", schema).decode()
        except (subprocess.SubprocessError, OSError):
            notes.append(f"Could not read {schema}")
            continue
        for line in data.splitlines():
            parts = line.split(maxsplit=2)
            if len(parts) != 3 or not parts[2].startswith("["):
                continue
            try:
                values = ast.literal_eval(parts[2])
            except (ValueError, SyntaxError):
                continue
            if parts[1] == "custom-keybindings":
                for path in values:
                    custom = f"{schema}.custom-keybinding:{path}"
                    try:
                        label = ast.literal_eval(command("gsettings", "get", custom, "name").decode().strip())
                        value = ast.literal_eval(command("gsettings", "get", custom, "binding").decode().strip())
                    except (subprocess.SubprocessError, OSError, ValueError, SyntaxError):
                        notes.append("A GNOME custom shortcut could not be read")
                        continue
                    if key := gnome_key(value):
                        rows.append(external_row(key, label, "GNOME custom shortcut", schema))
                continue
            for value in values:
                if key := gnome_key(value):
                    rows.append(external_row(key, parts[1].replace("-", " ").capitalize(), "GNOME", schema))
    return rows, notes


def external_shortcuts():
    kitty, warning = kitty_shortcuts()
    if sys.platform == "darwin":
        system, notes = mac_shortcuts()
    elif sys.platform.startswith("linux"):
        desktop = os.getenv("XDG_CURRENT_DESKTOP", "").upper()
        system, notes = kde_shortcuts() if "KDE" in desktop else gnome_shortcuts()
    elif os.name == "nt":
        system, notes = windows_shortcuts()
    else:
        system, notes = [], ["System shortcut discovery is unavailable on this platform"]
    return [dict(row, origin="Kitty") for row in kitty] + system, ([warning] if warning else []) + notes


def kde_shortcuts():
    path = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config") / "kglobalshortcutsrc"
    if not path.is_file():
        return [], ["KDE global shortcut preferences unavailable"]
    rows = []
    qt_mods = {"ctrl": "C", "alt": "M", "meta": "D", "shift": "S"}
    for line in path.read_text(encoding="utf-8").splitlines():
        action, sep, value = line.partition("=")
        if not sep or action.startswith("_"):
            continue
        columns = re.split(r"(?<!\\),", value, maxsplit=2)
        if len(columns) != 3:
            continue
        shortcuts, _, title = columns
        for sequence in shortcuts.replace(r"\t", "\t").split("\t"):
            if sequence in ("", "none"):
                continue
            keys = []
            for stroke in sequence.split(r"\, "):
                parts = stroke.split("+")
                if parts[-2:] == ["", ""]:
                    parts[-2:] = ["+"]
                if len(parts) > 1 and not all(mod.lower() in qt_mods for mod in parts[:-1]):
                    keys = []
                    break
                key = parts[-1].replace(r"\,", ",")
                keys.append(chord(key, [qt_mods[mod.lower()] for mod in parts[:-1]]))
            if any(keys):
                rows.append(external_row("".join(keys), title or action, "KDE Plasma", path.name))
    return rows, []


def windows_shortcuts():
    # Windows has no public API for enumerating other apps' RegisterHotKey registrations.
    pairs = (
        ("<M-Tab>", "Switch apps"), ("<M-S-Tab>", "Switch apps in reverse"),
        ("<C-S-Esc>", "Task Manager"), ("<C-M-Del>", "Security options"),
        ("<D-l>", "Lock the PC"), ("<D-e>", "File Explorer"), ("<D-r>", "Run dialog"),
        ("<D-d>", "Show desktop"), ("<D-i>", "Settings"), ("<D-v>", "Clipboard history"),
        ("<D-Tab>", "Task View"), ("<D-Left>", "Snap window left"), ("<D-Right>", "Snap window right"),
        ("<D-Up>", "Maximize window"), ("<D-Down>", "Restore or minimize window"),
        ("<D-S-s>", "Screen snipping"), ("<D-Space>", "Switch input language"),
        ("<D-.>", "Emoji picker"), ("<D-C-d>", "Create virtual desktop"),
        ("<D-C-Left>", "Switch to previous virtual desktop"), ("<D-C-Right>", "Switch to next virtual desktop"),
    )
    rows = [external_row(key, title, "Windows global", "Windows shortcut reference") for key, title in pairs]
    return rows, ["Windows coverage includes standard OS shortcuts. Third-party registrations are unavailable."]
