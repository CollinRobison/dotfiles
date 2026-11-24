"use strict";

const $ = (id) => document.getElementById(id);
const modeNames = {n: "Normal", x: "Visual", s: "Select", o: "Operator-pending",
  i: "Insert", l: "Language", c: "Command-line", t: "Terminal"};
const filters = [["All", "All sources"], ["Config", "My config"], ["Built-in", "Built-ins"],
  ["Runtime", "Runtime"], ["Kitty", "Kitty"], ["System", "System"]];
const glyphs = {C: "Ctrl", M: "Alt", D: /Mac/.test(navigator.platform) ? "⌘" : "Super",
  S: "Shift", leader: "Leader", localleader: "Local leader", CR: "Enter", Esc: "Esc",
  Space: "Space", BS: "Backspace", lt: "<", Bar: "|"};
let token = location.hash.slice(1);
if (token) {
  sessionStorage.setItem("keymaps-session", token);
  history.replaceState(null, "", location.pathname);
} else {
  token = sessionStorage.getItem("keymaps-session");
}
let inventory = null;
let origin = "All";
let selected = null;
let edit = null;
let reviewed = null;
let limit = 180;
let statusTimer = null;
let searchType = "keyword";
const smart = {result: null, pending: false, error: "", revision: 0};
const pi = {models: null, pending: false};

function node(tag, value, className) {
  const item = document.createElement(tag);
  if (value) item.textContent = value;
  if (className) item.className = className;
  return item;
}

async function api(path, body, wantPdf = false) {
  const headers = {"X-Keymaps-Session": token || ""};
  const init = {headers};
  if (body) {
    headers["Content-Type"] = "application/json";
    init.method = "POST";
    init.body = JSON.stringify(body);
  }
  let response;
  try {
    response = await fetch("/api/" + path, init);
  } catch {
    throw new Error("The local session is closed. Run nvim-keymaps again.");
  }
  if (response.status === 404 && path.startsWith("smart-")) {
    throw new Error("Reopen :Keymaps to start a session with the updated Smart search.");
  }
  if (!response.ok) throw new Error((await response.json()).error);
  if (wantPdf) return response.blob();
  if (response.status !== 204) return response.json();
}

function status(message, persistent = false) {
  $("status").textContent = message;
  $("status").hidden = false;
  clearTimeout(statusTimer);
  if (!persistent) statusTimer = setTimeout(() => { $("status").hidden = true; }, 6500);
}

function displayParts(raw) {
  return [...raw.matchAll(/<(?:[CMDSHT]-)+>>|<[^>]+>|[\s\S]/gu)].map(([key]) => {
    if (key.startsWith("<") && key.length > 1) {
      return key.slice(1, -1).split(/(?<!-)-(?!$)/).map((part) => glyphs[part] || part).join("+");
    }
    return key === " " ? "Space" : key;
  });
}

function keycaps(row, canonical = false) {
  const wrap = node("span", "", "keys");
  wrap.title = row.key;
  const values = row.display && !canonical ? [row.display] : displayParts(row.key);
  for (const part of values) wrap.append(node("kbd", part));
  return wrap;
}

function names(modes) {
  return modes.map((mode) => modeNames[mode] || mode).join(", ");
}

function sourceLabel(row) {
  if (!row.file) return "Session mapping";
  return row.line > 0 ? row.file + ":" + row.line : row.file;
}

function details() {
  const panel = $("details");
  panel.replaceChildren();
  panel.classList.toggle("selected", !!selected);
  if (selected) {
    panel.append(node("h2", selected.desc), keycaps(selected));
    const list = node("dl");
    for (const [label, value] of [
      ["Source", sourceLabel(selected)], ["Mode", names(selected.modes)], ["Context", selected.context],
      ["Mapping", selected.rhs && selected.rhs !== selected.desc ? selected.rhs : ""],
      ["Neovim help", selected.help ? ":help " + selected.help : ""],
    ]) {
      if (value) list.append(node("dt", label), node("dd", value));
    }
    panel.append(list);
    if (selected.editable) {
      const button = node("button", "Edit shortcut");
      button.type = "button";
      button.addEventListener("click", openEditor);
      panel.append(button);
    }
  } else {
    panel.append(node("h2", "Shortcut details"), node("p", "Select a keybinding to view its source or edit its keys."));
  }
  if (inventory) {
    const coverage = node("details");
    coverage.append(node("summary", "Discovery coverage"));
    for (const message of inventory.warnings) coverage.append(node("p", message, "warning"));
    coverage.append(
      node("p", inventory.live ? "Includes a snapshot of mappings in the launching Neovim session."
        : "Launch :Keymaps from a Neovim buffer to include its session-only mappings."),
      node("p", "Kitty and supported system settings are checked. Shortcuts registered privately by other apps may be missing."));
    panel.append(coverage);
  }
}

function searchText(row) {
  const readable = displayParts(row.key);
  const leader = inventory.leader === " " ? "Space" : inventory.leader;
  const localLeader = inventory.localleader === " " ? "Space" : inventory.localleader;
  const resolved = readable.map((key) => key === "Leader" ? leader : key === "Local leader" ? localLeader : key);
  return [row.desc, row.key, row.display, row.file, row.rhs, row.help, row.context, row.group,
    row.origin, names(row.modes), readable.join(" "), readable.join(""), resolved.join(" "), resolved.join("")]
    .filter(Boolean).join(" ").toLowerCase();
}

function solutionCard(solution, primary) {
  const card = node("article", "", primary ? "solution solution-primary" : "solution");
  card.append(node(primary ? "h3" : "h4", solution.title));
  let context;
  if (solution.conflicts?.length) {
    context = node("div", "", "solution-context");
    const heading = solution.applicability === "text-buffer"
      ? "Switch to a text-editing buffer first" : "A mapping overrides this sequence";
    context.append(node("strong", heading));
    for (const row of solution.conflicts) {
      const note = node("p");
      note.append(node("kbd", row.key), document.createTextNode(" runs " + row.desc + " in " + row.context + "."));
      context.append(note);
    }
  }
  if (solution.steps.length) {
    const steps = node("ol", "", "solution-steps");
    for (const step of solution.steps) {
      const item = node("li", "", "solution-step");
      const sources = [...new Set(step.bindings.map(binding => binding.origin))].join(", ");
      const command = node("div", "", "solution-command");
      command.append(node("kbd", step.keys, "solution-sequence"),
        node("span", modeNames[step.mode] + " mode · " + sources, "solution-mode"));
      item.append(command);
      if (context && step === solution.steps[0]) item.append(context);
      if (step.note) item.append(node("p", step.note));
      if (step.bindings.length > 1) {
        const parts = node("ol", "", "sequence-parts");
        parts.setAttribute("aria-label", "Keys in order");
        for (const binding of step.bindings) {
          const part = node("li");
          part.append(node("kbd", binding.key), node("span", binding.label || binding.desc));
          parts.append(part);
        }
        item.append(parts);
      }
      steps.append(item);
    }
    if (solution.steps.length === 1) steps.classList.add("single-step");
    card.append(steps);
  }
  if (solution.answer) card.append(node("p", solution.answer, "solution-outcome"));
  return card;
}

function renderSolutions(isSmart) {
  const container = $("smart-answer");
  const expanded = container.querySelector("details")?.open ?? false;
  container.replaceChildren();
  const result = isSmart ? smart.result : null;
  if (!result) return;
  if (result.solutions.length) {
    const [primary, ...alternatives] = result.solutions;
    container.append(solutionCard(primary, true));
    if (alternatives.length) {
      const other = node("details", "", "other-solutions");
      other.open = expanded;
      other.append(node("summary", "Other solutions (" + alternatives.length + ")"));
      const cards = node("div", "", "solutions");
      for (const solution of alternatives) cards.append(solutionCard(solution, false));
      other.append(cards);
      container.append(other);
    }
  }
  for (const notice of result.notices) container.append(node("p", notice, "empty warning smart-notice"));
}

function renderRows() {
  if (!inventory) return;
  const terms = $("query").value.trim().toLowerCase().split(/\s+/).filter(Boolean);
  const mode = $("modes").value;
  const isSmart = searchType === "smart";
  const rows = isSmart ? smart.result?.rows || [] : inventory.rows.filter((row) => (origin === "All" || row.origin === origin)
    && (!mode || row.modes.includes(mode))
    && terms.every((term) => row.search.includes(term)));
  $("result-count").textContent = isSmart && smart.pending ? "Asking Pi…"
    : isSmart && !smart.result ? ""
    : new Intl.NumberFormat().format(rows.length) + (rows.length === 1 ? " shortcut" : " shortcuts");
  $("more").hidden = rows.length <= limit;
  const visible = $("rows");
  visible.replaceChildren();
  renderSolutions(isSmart);
  if (!rows.length) {
    if (isSmart && smart.result?.solutions.length) return;
    let message = "No shortcuts match your search.";
    if (isSmart) {
      if (smart.error) message = smart.error;
      else if (smart.pending) message = "Looking for matching shortcuts…";
      else if (!smart.result) message = "Describe what you want to do in Neovim, then select Search with Pi.";
    }
    visible.append(node("p", message, smart.error && isSmart ? "empty warning" : "empty"));
    return;
  }
  const groups = new Map();
  for (const row of rows.slice(0, limit)) {
    const title = isSmart ? "Relevant keybindings" : origin === "All" ? row.origin + " · " + row.group : row.group;
    if (!groups.has(title)) {
      const group = node("section", "", "list-group");
      const inner = node("div", "", "group-rows");
      group.append(node("h3", title), inner);
      groups.set(title, inner);
      visible.append(group);
    }
    const button = node("button", "", "row");
    button.type = "button";
    button.dataset.id = row.id;
    button.setAttribute("aria-pressed", String(selected?.id === row.id));
    const info = node("span");
    info.append(node("span", isSmart ? row.label || row.desc : row.desc, "action"), node("span",
      [isSmart ? row.origin : "", names(row.modes), row.context].filter(Boolean).join(" · "), "row-meta"));
    button.append(info, keycaps(row, isSmart));
    button.addEventListener("click", () => {
      visible.querySelector('.row[aria-pressed="true"]')?.setAttribute("aria-pressed", "false");
      selected = row;
      button.setAttribute("aria-pressed", "true");
      details();
      if (matchMedia("(max-width: 760px)").matches) $("details").scrollIntoView({block: "nearest"});
    });
    groups.get(title).append(button);
  }
}

function load(data, saved) {
  inventory = data;
  resetSmart();
  syncPiControls();
  inventory.rows.forEach((row) => { row.search = searchText(row); });
  const origins = ["Config", "Runtime", "Built-in", "Kitty", "System"];
  inventory.rows.sort((a, b) => origins.indexOf(a.origin) - origins.indexOf(b.origin)
    || a.group.localeCompare(b.group) || a.desc.localeCompare(b.desc));
  selected = saved
    ? inventory.rows.find((row) => row.file === saved.file && row.id.startsWith(saved.file + ":" + saved.start + ":"))
    : inventory.rows.find((row) => row.id === selected?.id);
  $("profile").textContent = inventory.config;
  $("profile").title = inventory.config;
  $("leader").hidden = false;
  $("leader").querySelector("kbd").textContent = displayParts(inventory.leader).join(" ");
  details();
  renderRows();
}

function openEditor() {
  edit = selected;
  reviewed = null;
  $("edit-action").textContent = edit.desc + " · " + sourceLabel(edit);
  $("new-key").value = edit.key;
  $("review-result").replaceChildren();
  $("save").hidden = true;
  $("edit").showModal();
  $("new-key").select();
}

function showReview(result, key) {
  const output = $("review-result");
  output.replaceChildren();
  if (result.conflicts.length) {
    output.append(node("strong", "Check these conflicts before applying the change.", "warning"));
    const list = node("ul");
    for (const conflict of result.conflicts) {
      const item = node("li");
      item.append(node("span", conflict.desc), node("small", [conflict.message, conflict.origin, conflict.key, conflict.context]
        .filter(Boolean).join(" · ")));
      list.append(item);
    }
    output.append(list);
  } else {
    output.append(node("p", "No conflicts found in the available sources."));
  }
  for (const warning of result.warnings) output.append(node("p", warning, "warning"));
  const change = node("p");
  change.append(node("code", edit.key), document.createTextNode(" → "), node("code", key));
  output.append(change);
  $("save").textContent = result.conflicts.length ? "Apply despite conflicts" : "Apply to Lua";
  $("save").hidden = false;
}

function resetSmart() {
  smart.result = null;
  smart.error = "";
  smart.revision++;
}

function syncPiControls() {
  $("pi-model").disabled = pi.pending || !pi.models?.length;
  $("pi-thinking").disabled = pi.pending || !$("pi-model").value;
  $("ask-pi").disabled = !inventory || smart.pending || pi.pending || !$("pi-model").value;
}

function setThinkingLevels() {
  const model = pi.models?.find(item => item.id === $("pi-model").value);
  const levels = model?.levels || [];
  const saved = sessionStorage.getItem("keymaps-pi-thinking");
  const labels = {off: "Off", minimal: "Minimal", low: "Low", medium: "Medium", high: "High",
    xhigh: "Extra high", max: "Maximum"};
  $("pi-thinking").replaceChildren(...levels.map(level => new Option(labels[level] || level, level)));
  if (levels.includes(saved)) $("pi-thinking").value = saved;
  syncPiControls();
}

async function loadPiOptions() {
  if (pi.pending) return;
  pi.pending = true;
  $("model-status").hidden = true;
  $("reload-models").hidden = true;
  syncPiControls();
  try {
    const options = await api("smart-options");
    pi.models = options.models.sort((a, b) => a.provider.localeCompare(b.provider) || a.name.localeCompare(b.name));
    const select = $("pi-model");
    select.replaceChildren(new Option("Choose a model", ""));
    select.options[0].disabled = true;
    const groups = new Map();
    for (const item of pi.models) {
      if (!groups.has(item.provider)) {
        const group = document.createElement("optgroup");
        group.label = item.provider;
        groups.set(item.provider, group);
        select.append(group);
      }
      const modelId = item.id.slice(item.provider.length + 1);
      const text = item.name === modelId ? modelId : item.name + " · " + modelId;
      groups.get(item.provider).append(new Option(text, item.id));
    }
    const saved = sessionStorage.getItem("keymaps-pi-model");
    if (pi.models.some(item => item.id === saved)) select.value = saved;
    else if (pi.models.some(item => item.id === options.defaultModel)) select.value = options.defaultModel;
    if (!pi.models.length) throw new Error("Pi has no available chat models. Check your Pi login, then reload models.");
    if (options.defaultModel && !select.value) {
      $("model-status").textContent = "The default Pi model is unavailable. Choose an available model.";
      $("model-status").hidden = false;
    }
  } catch (error) {
    pi.models = null;
    $("pi-model").replaceChildren(new Option("Unavailable", ""));
    $("model-status").textContent = error.message;
    $("model-status").hidden = false;
    $("reload-models").hidden = false;
  } finally {
    pi.pending = false;
    setThinkingLevels();
  }
}

function selectSearch(type) {
  if (searchType === type) return;
  searchType = type;
  const isSmart = type === "smart";
  $("keyword-search").setAttribute("aria-pressed", String(!isSmart));
  $("smart-search").setAttribute("aria-pressed", String(isSmart));
  $("keyword-field").hidden = isSmart;
  $("smart-form").hidden = !isSmart;
  $("smart-note").hidden = !isSmart;
  $("smart-settings").hidden = !isSmart;
  if (isSmart && !pi.models) loadPiOptions();
  $(isSmart ? "smart-query" : "query").focus();
  renderRows();
}

$("keyword-search").addEventListener("click", () => selectSearch("keyword"));
$("smart-search").addEventListener("click", () => selectSearch("smart"));
$("smart-query").addEventListener("input", () => { resetSmart(); renderRows(); });
$("reload-models").addEventListener("click", loadPiOptions);
$("pi-model").addEventListener("change", () => {
  sessionStorage.setItem("keymaps-pi-model", $("pi-model").value);
  $("model-status").hidden = true;
  setThinkingLevels();
  resetSmart();
  renderRows();
});
$("pi-thinking").addEventListener("change", () => {
  sessionStorage.setItem("keymaps-pi-thinking", $("pi-thinking").value);
  resetSmart();
  renderRows();
});
$("smart-form").addEventListener("submit", async (event) => {
  event.preventDefault();
  const query = $("smart-query").value.trim();
  const model = $("pi-model").value;
  const thinking = $("pi-thinking").value;
  if (!inventory || !query || !model || smart.pending || pi.pending) return;
  resetSmart();
  const revision = smart.revision;
  smart.pending = true;
  syncPiControls();
  renderRows();
  try {
    const result = await api("smart-search", {query, origin, mode: $("modes").value, model, thinking});
    if (revision === smart.revision) smart.result = result;
  } catch (error) {
    if (revision === smart.revision) smart.error = error.message;
  } finally {
    smart.pending = false;
    syncPiControls();
    renderRows();
  }
});

for (const [value, label] of filters) {
  const button = node("button", label);
  button.type = "button";
  button.setAttribute("aria-pressed", String(value === origin));
  button.addEventListener("click", () => {
    $("filters").querySelector('[aria-pressed="true"]').setAttribute("aria-pressed", "false");
    button.setAttribute("aria-pressed", "true");
    if (origin !== value) resetSmart();
    origin = value;
    limit = 180;
    renderRows();
  });
  $("filters").append(button);
}
for (const [code, label] of Object.entries(modeNames)) $("modes").append(new Option(label, code));
$("query").addEventListener("input", () => { limit = 180; renderRows(); });
$("modes").addEventListener("change", () => { resetSmart(); limit = 180; renderRows(); });
$("more").addEventListener("click", () => { limit += 180; renderRows(); });
document.addEventListener("keydown", (event) => {
  if (event.key === "/" && !["INPUT", "SELECT", "TEXTAREA"].includes(document.activeElement.tagName)
      && !$("edit").open) {
    event.preventDefault();
    $(searchType === "smart" ? "smart-query" : "query").focus();
  }
});
for (const id of ["close-edit", "cancel-edit"]) $(id).addEventListener("click", () => $("edit").close());
$("new-key").addEventListener("input", () => {
  reviewed = null;
  $("review-result").replaceChildren();
  $("save").hidden = true;
});
$("edit-form").addEventListener("submit", async (event) => {
  event.preventDefault();
  const row = edit;
  const key = $("new-key").value;
  $("check").disabled = true;
  try {
    const result = await api("review", {id: row.id, key});
    if (row !== edit || $("new-key").value !== key || !$("edit").open) return;
    reviewed = {id: row.id, key, review: result.review};
    showReview(result, key);
  } catch (error) {
    $("review-result").replaceChildren(node("p", error.message, "warning"));
  } finally {
    $("check").disabled = false;
  }
});
$("save").addEventListener("click", async () => {
  if (!reviewed) return;
  $("save").disabled = true;
  $("new-key").disabled = true;
  try {
    const result = await api("save", reviewed);
    $("edit").close();
    if (result.inventory) load(result.inventory, result);
    status("Saved " + result.file + ":" + result.line + ". Restart Neovim to use the new keys."
      + (result.inventory ? "" : " Use Refresh to update this list."));
  } catch (error) {
    reviewed = null;
    $("save").hidden = true;
    $("review-result").replaceChildren(node("p", error.message, "warning"));
  } finally {
    $("save").disabled = false;
    $("new-key").disabled = false;
  }
});
$("refresh").addEventListener("click", async () => {
  $("refresh").disabled = true;
  try {
    load(await api("refresh", {}));
    status("Keybindings refreshed.");
  } catch (error) {
    status(error.message, true);
  } finally {
    $("refresh").disabled = false;
  }
});
$("atlas").addEventListener("click", async () => {
  $("atlas").disabled = true;
  $("atlas").textContent = "Regenerating PDF…";
  try {
    const pdf = await api("atlas", {}, true);
    const url = URL.createObjectURL(pdf);
    const link = node("a");
    link.href = url;
    link.download = "Nvim-Dark-Complete-Atlas.pdf";
    link.click();
    setTimeout(() => URL.revokeObjectURL(url), 60_000);
    status("Atlas regenerated. The PDF download has started.");
  } catch (error) {
    status(error.message, true);
  } finally {
    $("atlas").disabled = false;
    $("atlas").textContent = "↓ Regenerate Atlas PDF";
  }
});

api("catalog").then(load).catch((error) => {
  $("profile").textContent = error.message;
  status(error.message, true);
});
setInterval(() => {
  if (!document.hidden) api("ping").catch(() => {});
}, 60_000);
