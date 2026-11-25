"""Answer editor questions with the current shortcut inventory and the Pi SDK."""
import json
import os
import re
import shutil
import subprocess
import tempfile

from catalog import HERE, MODE_NAMES, public_row

ORIGINS = {"All", "Config", "Built-in", "Runtime", "Kitty", "System"}
THINKING_LEVELS = {"off", "minimal", "low", "medium", "high", "xhigh", "max"}
MAX_RESULTS = 12
MAX_QUERY = 400


class SearchUnavailable(RuntimeError):
    pass


def run_pi(payload, timeout):
    node = shutil.which("node")
    if not node:
        raise SearchUnavailable("Smart search needs Node.js 22.19 or newer and the Pi SDK.")
    env = {**os.environ, "NVIM_KEYMAPS_PI_COMMAND": shutil.which("pi") or ""}
    try:
        with tempfile.TemporaryDirectory(prefix="nvim-keymaps-pi-") as cwd:
            result = subprocess.run([node, str(HERE / "pi_search.mjs")], input=json.dumps(payload),
                                    encoding="utf-8", errors="replace", capture_output=True,
                                    cwd=cwd, env=env, timeout=timeout)
    except subprocess.TimeoutExpired as error:
        raise SearchUnavailable("Pi took too long to answer. Try again or choose a lower reasoning level.") from error
    except OSError as error:
        raise SearchUnavailable("Could not start the Pi SDK. Check your Node.js and Pi installation.") from error

    try:
        reply = json.loads(result.stdout)
    except ValueError as error:
        raise SearchUnavailable("Could not start the Pi SDK. Check your Node.js and Pi installation.") from error
    if not isinstance(reply, dict):
        raise SearchUnavailable("Pi returned an unreadable response. Try asking a more specific question.")
    if result.returncode or "error" in reply:
        errors = {
            "sdk": "Pi SDK unavailable. Install @earendil-works/pi-coding-agent with Node.js 22.19 or newer.",
            "model": "That model is unavailable. Choose another Pi model or check your Pi login.",
            "thinking": "That reasoning level is unavailable for the selected model.",
            "request": "Pi could not complete the search. Check that your model is available in Pi, or try again.",
            "format": "Pi returned an unreadable response. Try asking a more specific question.",
        }
        raise SearchUnavailable(errors.get(reply.get("error"), errors["request"]))
    return reply


def smart_options():
    return run_pi({"action": "options"}, 20)


def action_label(row):
    desc = row["desc"]
    if row["origin"] == "Kitty":
        # Kitty actions can contain shell commands and paths after the action name.
        return desc.split(maxsplit=1)[0].replace("_", " ") if desc else ""
    if desc and desc == row.get("rhs"):
        command = re.match(r"^(?:<cmd>|:)(\w+)", desc, re.IGNORECASE)
        return "Run " + command[1] if command else "Mapped keys"
    return desc[:180]


def builtin_operator(row):
    return bool(row.get("help") and "{motion}" in row.get("display", "") and "n" in row["modes"])


def relevant_scope(row, context):
    scope = row["scope"]
    return (not scope or context.get("filetype") in scope.split("|") or
            (scope == "lsp" and context.get("buffer_lsp")))


def output_text(value, limit):
    return value.strip()[:limit] if isinstance(value, str) else ""


OPERATORS = {"d": "Delete", "c": "Change", "y": "Yank"}
DELIMITERS = {
    "[": "square brackets", "]": "square brackets", "(": "parentheses", ")": "parentheses",
    "{": "braces", "}": "braces", "<": "angle brackets", ">": "angle brackets",
    '"': "double quotes", "'": "single quotes", "`": "backticks",
}


def step_part(row):
    key = row["key"]
    label = row["desc"].strip()
    if builtin_operator(row):
        label = {"d": "Delete", "c": "Change and enter Insert mode", "y": "Copy to a register"}.get(key, label)
    elif row.get("help") and row["group"] == "Text objects" and len(key) == 2 and key[1] in DELIMITERS:
        prefix = "Inside " if key[0] == "i" else "Around "
        label = prefix + DELIMITERS[key[1]]
    return dict(public_row(row), label=label)


def delimiter_recipes(question, entries):
    """Use the help index for direct requests to operate inside delimiters."""
    match = re.fullmatch(
        r"""(?:(?:how (?:do|can|would|to)(?: i)?|what (?:key|keys) (?:do i use to|to))\s+)?"""
        r"""(delete|change|yank|copy) (?:the (?:text|contents) )?(?:inside|within) (?:the )?"""
        r"""(brackets|square brackets|round brackets|parentheses|curly brackets|(?:curly )?braces|"""
        r"""angle brackets|double quotes|single quotes|backticks|\[\]|\(\)|\{\}|<>|""|'')\s*[?.]?""",
        question.casefold(),
    )
    if not match:
        return []
    action, target = match.groups()
    operator = {"delete": "d", "change": "c", "yank": "y", "copy": "y"}[action]
    objects = {
        "brackets": "[({", "square brackets": "[", "[]": "[", "round brackets": "(",
        "parentheses": "(", "()": "(", "curly brackets": "{", "curly braces": "{",
        "braces": "{", "{}": "{", "angle brackets": "<", "<>": "<", "double quotes": '"',
        '""': '"', "single quotes": "'", "''": "'", "backticks": "`",
    }
    operator_id = next((ident for ident, row in entries.items()
                        if row["key"] == operator and builtin_operator(row)), None)
    recipes = []
    for delimiter in objects[target]:
        object_id = next((ident for ident, row in entries.items()
                          if row["key"] == "i" + delimiter and row["group"] == "Text objects"
                          and "o" in row["modes"]), None)
        if operator_id is not None and object_id is not None:
            recipes.append({
                "title": f"{OPERATORS[operator]} inside {DELIMITERS[delimiter]}",
                "answer": {
                    "d": "Deletes the contents and leaves the delimiters in place.",
                    "c": "Deletes the contents and enters Insert mode so you can type a replacement.",
                    "y": "Copies the contents to a Vim register and leaves the text in place.",
                }[operator],
                "steps": [{"mode": "n", "bindings": [operator_id, object_id],
                           "note": "Place the cursor inside the matching pair."}],
            })
    return recipes


def build_step(raw, entries, overrides, shadowed):
    if not isinstance(raw, dict):
        return None
    mode = raw.get("mode")
    ids = raw.get("bindings")
    if not isinstance(mode, str) or mode not in MODE_NAMES or not isinstance(ids, list) or not 1 <= len(ids) <= 6:
        return None
    if any(type(ident) is not int or ident not in entries for ident in ids):
        return None
    parts = [entries[ident] for ident in ids]
    phase = mode
    for index, row in enumerate(parts):
        if phase not in row["modes"]:
            return None
        if row.get("help"):
            remaining = tuple(chord for part in parts[index:] for chord in part["chords"])
            for other in overrides:
                if phase in other["modes"] and other["chords"] and remaining[:len(other["chords"])] == other["chords"]:
                    shadowed[other["id"]] = other
        if builtin_operator(row):
            phase = "o"
        elif row.get("help") and phase == "n" and row["key"] in ("v", "V", "<C-v>", "<C-V>"):
            phase = "x"
        elif phase == "o" and row.get("help") not in ("o_v", "o_V", "o_CTRL-V"):
            phase = "n"
    if mode == "n" and phase == "o":
        return None
    return {"keys": "".join(row["key"] for row in parts), "mode": mode,
            "note": output_text(raw.get("note"), 350), "bindings": [step_part(row) for row in parts]}


def smart_search(data, rows, leader, localleader, context):
    query = data.get("query")
    origin, mode = data.get("origin", "All"), data.get("mode", "")
    model, thinking = data.get("model", ""), data.get("thinking", "")
    if not isinstance(query, str) or not query.strip() or len(query) > MAX_QUERY:
        raise ValueError(f"Enter a question of up to {MAX_QUERY} characters.")
    if not isinstance(origin, str) or origin not in ORIGINS:
        raise ValueError("Choose a valid shortcut source.")
    if not isinstance(mode, str) or (mode and mode not in MODE_NAMES):
        raise ValueError("Choose a valid Neovim mode.")
    if not isinstance(model, str) or (model and not re.fullmatch(r"[^/\s]{1,80}/\S{1,200}", model)):
        raise ValueError("Choose a Pi model.")
    if not isinstance(thinking, str) or (thinking and thinking not in THINKING_LEVELS):
        raise ValueError("Choose a reasoning level.")

    entries = dict(enumerate(rows, start=1))
    bindings = [
        [ident, row["key"], action_label(row), "".join(row["modes"]),
         row["context"] if row["scope"] or row.get("kind") == "command" or row["origin"] in ("Kitty", "System") else "",
         row["origin"], row["group"] if row["origin"] in ("Config", "Built-in") else "",
         builtin_operator(row), row.get("kind", "binding")]
        for ident, row in entries.items()
    ]
    prompt = {"bindings": bindings, "leader": leader, "localLeader": localleader, "buffer": context,
              "filters": {"source": origin, "mode": mode}, "question": query.strip()}
    reply = run_pi({"action": "search", "model": model, "thinking": thinking, "prompt": prompt}, 90)
    if not isinstance(reply.get("matches"), list) or not isinstance(reply.get("solutions"), list):
        raise SearchUnavailable("Pi returned an unreadable response. Try asking a more specific question.")
    overrides = [row for row in rows if row["origin"] in ("Config", "Runtime", "Built-in")
                 and row["chords"] and not row.get("help") and relevant_scope(row, context)]
    recipes = delimiter_recipes(query.strip(), entries)
    targets = {DELIMITERS[entries[recipe["steps"][0]["bindings"][1]]["key"][1]] for recipe in recipes}

    def matching_object(row):
        key = row["key"]
        if not targets or not row.get("help") or row["group"] not in ("Text objects", "Visual mode"):
            return True
        if len(key) != 2 or key[0] not in "ia":
            return True
        aliases = {"b": "parentheses", "B": "braces"}
        return DELIMITERS.get(key[1], aliases.get(key[1])) in targets

    solutions, notices, shadowed = [], [], {}
    sequences = set()
    for raw in recipes + reply["solutions"][:3]:
        if not isinstance(raw, dict) or not isinstance(raw.get("steps"), list):
            continue
        conflicts = {}
        steps = [build_step(step, entries, overrides, conflicts) for step in raw["steps"][:8]]
        if any(step is None for step in steps):
            notices = ["Some suggested keys did not form a verifiable sequence."]
            continue
        if recipes and (not steps or any(not matching_object(row) for step in steps for row in step["bindings"])):
            continue
        answer = output_text(raw.get("answer"), 700)
        sequence = tuple((step["mode"], step["keys"]) for step in steps)
        if sequence and sequence in sequences:
            continue
        if answer or steps:
            sequences.add(sequence)
            shadowed.update(conflicts)
            applicability = "current"
            if conflicts:
                portable = all(row["scope"] == "" for step in steps for row in step["bindings"])
                applicability = "text-buffer" if portable and all(row["scope"] for row in conflicts.values()) else "overridden"
            solutions.append({"title": output_text(raw.get("title"), 95) or "How to do it",
                              "answer": answer, "steps": steps, "applicability": applicability,
                              "conflicts": [public_row(row) for row in conflicts.values()]})
    solutions.sort(key=lambda solution: solution["applicability"] == "overridden")
    solutions = solutions[:5]
    matches = {}
    for ident in reply["matches"]:
        if type(ident) is int and ident in entries:
            row = entries[ident]
            if matching_object(row):
                matches[row["id"]] = row
    for solution in solutions:
        for step in solution["steps"]:
            for row in step["bindings"]:
                matches.setdefault(row["id"], row)
    for ident, row in shadowed.items():
        matches.setdefault(ident, row)
    matches = [step_part(row) for row in matches.values() if (origin == "All" or origin == row["origin"])
               and (not mode or mode in row["modes"])]
    return {"rows": matches[:MAX_RESULTS], "solutions": solutions, "notices": notices if not solutions else []}
