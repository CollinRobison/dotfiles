"""Run with Kitty's bundled Python so Kitty resolves defaults, includes and overrides."""
import json
import sys
from pathlib import Path

from kitty import fast_data_types as glfw
from kitty.config import load_config
from kitty.constants import config_dir

mods = {
    glfw.GLFW_MOD_CONTROL: "C", glfw.GLFW_MOD_ALT: "M", glfw.GLFW_MOD_SUPER: "D",
    glfw.GLFW_MOD_SHIFT: "S", glfw.GLFW_MOD_HYPER: "H", glfw.GLFW_MOD_META: "T",
}
names = {getattr(glfw, name): name.removeprefix("GLFW_FKEY_").lower()
         for name in dir(glfw) if name.startswith("GLFW_FKEY_")}

def key_name(key):
    if key.is_native:
        return None
    name = names.get(key.key) or chr(key.key)
    aliases = {" ": "Space", "<": "lt", "enter": "CR", "escape": "Esc",
               "backspace": "BS", "delete": "Del", "insert": "Insert",
               "page_up": "PageUp", "page_down": "PageDown", ">": ">"}
    name = aliases.get(name, name)
    parts = [label for bit, label in mods.items() if key.mods & bit]
    return "<" + "-".join([*parts, name]) + ">" if parts or len(name) != 1 else name

paths = sys.argv[1:] or [str(Path(config_dir) / "kitty.conf")]
opts = load_config(*paths)
rows = []
for mode, mappings in opts.keyboard_modes.items():
    for defs in mappings.keymap.values():
        for mapping in defs:
            keys = [key_name(key) for key in (mapping.trigger, *mapping.rest)]
            if not all(keys) or mapping.definition.split()[:1] in (["noop"], ["no_op"]):
                continue
            context = mode or "Terminal window"
            if mapping.options.when_focus_on:
                context += " · " + mapping.options.when_focus_on
            rows.append({"key": "".join(keys), "desc": mapping.definition, "context": context,
                         "scope": mode, "file": "Kitty configuration and defaults"})
print(json.dumps(rows))
