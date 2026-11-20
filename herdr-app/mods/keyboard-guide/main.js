// Personal Ctrl-b command guide. The same rows drive the hints and the keys.
// Self-contained so Herdr can also load this file through a configuration link.
import { View, div } from "gpui-kit";
import { v_flex, h_flex, InputState, Input } from "gpui-base";
import { agents, spaces, panes, terminals, focused, props, closeOverlay,
  openOverlay, run, theme, hc, exec, checking, nextCommand, commands, layouts, themes, shared, window, settings } from "herdr";

const directions = { h: "left", j: "down", k: "up", l: "right",
  left: "left", down: "down", up: "up", right: "right" };
const shiftedDigits = "!@#$%^&*(";

// Prefer the typed character for punctuation, but retain Shift for letters.
export function keyName(e) {
  const m = e.modifiers ?? {};
  const key = e.key.toLowerCase();
  // Terminal encoders turn Ctrl-[ into Escape; native mod events do not.
  if (key === "[" && m.control && !m.alt && !m.platform && !m.shift) return "escape";
  if (m.control || m.alt || m.platform) {
    return `${m.platform ? "cmd-" : ""}${m.control ? "ctrl-" : ""}${m.alt ? "alt-" : ""}${m.shift ? "shift-" : ""}${key}`;
  }
  const typed = e.key_char;
  const i = shiftedDigits.indexOf(typed || key);
  if (i >= 0 && (typed || key).length === 1) return `shift-${i + 1}`;
  if (m.shift && /^[1-9]$/.test(key)) return `shift-${key}`;
  if (typed === "?" || key === "?" || (key === "/" && m.shift)) return "?";
  if (typed === '"' || key === '"' || (key === "'" && m.shift)) return '"';
  if (typed === ":" || key === ":" || (key === ";" && m.shift)) return ":";
  return m.shift ? `shift-${key}` : key;
}

const action = (keys, label, command, args = {}, needs = "", confirm = false) =>
  ({ keys: keys.split(" "), label, command, args, needs, confirm });
const mode = (key, label, mode) => ({ keys: [key], label, mode });
const ROOT = [
  ["MOVE", [mode("g", "Navigate →", "navigate"),
    action("h j k l", "Focus pane ← ↓ ↑ →", "direction", {}, "pane"),
    action("tab shift-tab", "Next / previous pane", "cycle", {}, "pane"),
    action("p n", "Previous / next tab", "tab-step", {}, "tab"),
    mode("w", "Find space or tab…", "places"),
    mode("a", "Choose agent →", "agents")]],
  ["PANES", [action("v", "Split side by side", "pane.split", { direction: "right" }, "pane"),
    action('- "', "Split above / below", "pane.split", { direction: "down" }, "pane"),
    action("z", "Zoom / restore pane", "pane.zoom", {}, "pane"),
    action("x", "Close pane…", "pane.close", {}, "pane", true),
    mode("[", "Scroll & copy →", "copy"),
    action("/", "Search terminal…", "terminal.search", {}, "terminal")]],
  ["TABS / SPACES", [action("c", "New tab", "tab.new"),
    action("shift-t", "Rename tab…", "tab.rename", {}, "tab"),
    action("shift-x", "Close tab…", "tab.close", {}, "tab", true),
    action("shift-n", "New space", "space.new"),
    action("shift-w", "Rename space…", "space.rename", {}, "space"),
    action("shift-d", "Close space…", "space.close", {}, "space", true)]],
  ["WORKSPACE", [action("b", "Toggle sidebar", "layout.toggle", { id: "sidebar" }),
    action("s", "Settings…", "app.settings"),
    mode(":", "Find any command…", "commands"),
    action("shift-g", "New worktree…", "worktree", {}, "space"),
    mode("?", "More keys & app limits →", "help"),
    action("q", "Minimize; keep terminals", "window.minimize")]],
];

function guideCommandId(command, args = {}) {
  return `${command}:${JSON.stringify(Object.fromEntries(Object.entries(args).sort(([a], [b]) => a.localeCompare(b))))}`;
}

function guideCatalogue(rootGroups, snapshot) {
  const { commandInfo, layoutNames = [], themeNames = [], focus: f,
    spaces: allSpaces = [], agents: allAgents = [], panes: allPanes = [],
    terminals: allTerminals = [], layoutName = "main", platform = "macos" } = snapshot;
  const known = new Map(commandInfo.map(c => [c.name, c]));
  // v0.1.16 advertises these but run() dispatches them as no-ops. The native
  // key handler owns them; a custom keyboard entry must not promise them.
  const unavailable = new Set(["app.hide", "app.hide_others", "app.show_all"]);
  const list = [], ids = new Set(), covered = new Set();
  const add = e => {
    if (e.command && (!known.has(e.command) || unavailable.has(e.command))) return;
    e.id ??= e.mode ? `mode:${e.mode}` : guideCommandId(e.command, e.args);
    if (ids.has(e.id)) return;
    ids.add(e.id);
    if (e.command) covered.add(e.command);
    list.push({ keys: [], args: {}, words: "", needs: "", confirm: false, ...e });
  };
  const command = (name, args, group, label, words = "", extra = {}) =>
    add({ command: name, args, group, label, words, ...extra });
  const focusNeeds = name => name.startsWith("pane.") ? "pane"
    : name.startsWith("terminal.") && name !== "terminal.open" ? "terminal"
    : ["tab.rename", "tab.close", "tab.next", "tab.prev"].includes(name) ? "tab"
    : ["space.rename", "space.close", "space.next", "space.prev"].includes(name) ? "space" : "";

  // ROOT owns shortcut labels, commands, confirmation choices and execution.
  // Only combined rows need expansion, so selecting a named direction can never
  // silently execute the first key in "h j k l" or "p n".
  for (const [group, rows] of rootGroups) for (const row of rows) {
    const base = { ...row, group, label: row.label.replace(/\s*→$/, ""), root: row };
    if (row.command === "app.palette" || row.command === "app.help"
      || (row.command === "mod.open" && row.args?.name === "picker")) {
      const mode = row.command === "app.palette" ? "commands" : row.command === "app.help" ? "help" : "places";
      add({ ...base, command: undefined, mode, root: undefined,
        label: mode === "commands" ? "Find a command" : mode === "help" ? "Keyboard help" : "Find a space or tab" });
    } else if (row.command === "direction") {
      for (const [key, direction] of [["h", "left"], ["j", "down"], ["k", "up"], ["l", "right"]]) {
        add({ ...base, command: "pane.go", args: { direction }, keys: [key], key,
          label: `Focus pane ${direction}` });
      }
    } else if (row.command === "tab-step") {
      for (const [key, direction] of [["p", "prev"], ["n", "next"]]) {
        add({ ...base, command: `tab.${direction}`, args: {}, keys: [key], key,
          label: `${direction === "prev" ? "Previous" : "Next"} tab` });
      }
    } else if (row.command === "cycle") {
      for (const [key, label] of [["tab", "Next pane"], ["shift-tab", "Previous pane"]]) {
        add({ ...base, command: undefined, id: `root:cycle:${key}`, key, keys: [key], label });
      }
    } else if (row.command === "worktree") {
      add({ ...base, command: undefined, id: "root:worktree:new", key: row.keys[0] });
    } else {
      add({ ...base, key: row.keys?.[0] });
    }
  }

  // The shipped palette's additional public actions. Prefix actions above are
  // deliberately not redefined here. Missing installed commands never appear.
  const named = [
    ["space.next", {}, "Space", "Next space", "workspace"],
    ["space.prev", {}, "Space", "Previous space", "workspace"],
    ["layout.switch", {}, "Layout", "Next layout", "look switch"],
    ["layout.reset", {}, "Layout", "Reset layout…", "default restore"],
    ["terminal.open", {}, "Terminal", "New terminal", "shell"],
    ["terminal.copy", {}, "Terminal", "Copy selection", "clipboard"],
    ["terminal.paste", {}, "Terminal", "Paste", "clipboard"],
    ["terminal.paste_image", {}, "Terminal", "Paste image", "clipboard image remote"],
    ["terminal.select_all", {}, "Terminal", "Select all terminal text", "screen scrollback"],
    ["terminal.clear_selection", {}, "Terminal", "Clear selection"],
    ["agent.next", {}, "Agent", "Next agent"], ["agent.prev", {}, "Agent", "Previous agent"],
    ["app.welcome", {}, "App", "Welcome", "intro start onboarding"],
    ["app.whats_new", {}, "App", "What's new", "release news"],
    ["app.feedback", {}, "App", "Send feedback…", "report problem suggestion"],
    ["app.check_updates", {}, "App", "Check for updates", "version"],
    ["app.update", {}, "App", "Restart into the downloaded update…", "version upgrade"],
    ["app.update_core", {}, "App", "Update terminal service…", "core version upgrade"],
    ["app.reset", {}, "App", "Restore the default screen and keys…", "escape hatch broken reset"],
    ["app.zoom_in", {}, "App", "Zoom in", "bigger font"],
    ["app.zoom_out", {}, "App", "Zoom out", "smaller font"],
    ["app.zoom_reset", {}, "App", "Reset zoom", "normal font"],
    ["app.quit", {}, "App", "Quit Herdr…", "exit keep terminals"],
    ["window.minimize", {}, "Window", "Minimize window"],
    ["window.maximize", {}, "Window", "Maximize / restore window"],
    ["window.close", {}, "Window", "Close window…", "quit"],
  ];
  const confirmations = {
    "pane.close": "This ends this pane's terminal program.",
    "tab.close": "This ends every terminal program in this tab.",
    "space.close": "This ends every terminal program in this space.",
    "terminal.kill": "This ends this terminal and its sub-agents.",
    "layout.reset": "This restores the shipped layout and its clicks; Herdr keeps the old file aside.",
    "app.reset": "This sets your shown layout and keys aside and restores Herdr's defaults.",
    "app.update": "Herdr will restart into its downloaded update; terminals keep running.",
    "app.update_core": "Herdr will update its terminal service; terminals keep running.",
    "app.quit": "Herdr will quit; its terminal programs keep running.",
    "window.close": "This closes the window; on Linux it also quits Herdr. Terminals keep running.",
  };
  for (const [name, args, group, label, words] of named) {
    // The guide owns the removed Cmd-M shortcut, so unlike the native palette
    // it must expose real window controls on macOS too.
    if (platform !== "macos" && name === "app.quit") continue;
    command(name, args, group, label, words, { needs: focusNeeds(name),
      confirm: !!confirmations[name], confirmMessage: confirmations[name] });
  }
  for (const direction of ["left", "right", "up", "down"]) {
    command("pane.swap", { direction }, "Pane", `Swap pane ${direction}`, "move reorder", { needs: "pane" });
  }
  for (const name of layoutNames) {
    const label = { main: "Herdr", terminals: "Terminals", win98: "Herdr 98" }[name] ?? name;
    command("layout.switch", { name }, "Layout", `Layout: ${label}`, `look ${name}`);
  }
  command("layout.clone", { name: layoutName }, "Layout", "Duplicate current layout", "copy customize");
  // Native mod.clone flow: a name-only prompt, no raw arguments or JSON.
  command("mod.clone", {}, "Layout", "Duplicate mod…", "copy customize", {
    dialog: { mod: "prompt", kind: "dialog", width: 380, props: {
      title: "Duplicate mod", hint: "Mod to copy; creates <name>-copy",
      command: { name: "mod.clone", args: {} },
    } },
  });
  for (const item of themeNames) {
    const name = typeof item === "string" ? item : item.name;
    command("app.theme", { name }, "App", `Theme: ${name.replace(/-/g, " ")}`, "colors look");
  }
  // Reuse the app's agent chooser; it checks agents on the active machine.
  add({ id: "dialog:new-agent", group: "Agent", label: "Start an agent…", words: "new task codex claude pi",
    dialog: { mod: "new-menu", kind: "popup", width: 250, height: 512 } });
  command("mod.open", { name: "machine-add" }, "App", "Add machine…", "remote ssh connect");
  for (const [id, label] of [["files", "Show files panel"], ["changes", "Show changes panel"]]) {
    add({ id: `panel:${id}`, group: "Layout", label, words: "sidebar project git",
      sequence: [["layout.select", { stack: "panel-body", child: id }], ["layout.show", { id: "panel" }]] });
  }
  command("layout.hide", { id: "panel" }, "Layout", "Hide side panel", "files changes");

  const space = allSpaces.find(s => s.id === f?.space);
  const tab = space?.tabs.find(t => t.id === f?.tab);
  const terminal = allTerminals.find(t => t.address === f?.terminal && t.state === "live");
  const agent = allAgents.find(a => a.address === (f?.agent || f?.terminal));
  if (tab) {
    command("tab.move", { id: tab.id, by: -1 }, "Tab", "Move tab left", "reorder");
    command("tab.move", { id: tab.id, by: 1 }, "Tab", "Move tab right", "reorder");
    command(tab.settled ? "tab.unsettle" : "tab.settle", { id: tab.id }, "Tab",
      tab.settled ? "Bring tab back" : "Put tab away; keep it running", "settle hide restore");
  }
  if (space) {
    const index = allSpaces.findIndex(s => s.id === space.id);
    const sameMachine = other => other && (other.machine ?? null) === (space.machine ?? null);
    // spaces/main.js uses global one-based positions. Stay within this
    // machine's contiguous block instead of offering a cross-machine move.
    if (sameMachine(allSpaces[index - 1])) command("space.move", { id: space.id, index }, "Space", "Move space earlier", "reorder");
    if (sameMachine(allSpaces[index + 1])) command("space.move", { id: space.id, index: index + 2 }, "Space", "Move space later", "reorder");
    add({ id: `worktree:open:${space.id}`, group: "Space", label: "Open worktree…", words: "git branch checkout",
      dialog: { mod: "worktree", kind: "dialog", width: 560, height: 480,
        props: { space: space.id, folder: f?.cwd || space.folder, action: "open" } } });
    add({ id: `worktree:remove:${space.id}`, group: "Space", label: "Remove worktree…", words: "git branch checkout delete",
      worktreeRemove: { space: space.id, folder: f?.cwd || space.folder, machine: space.machine }, needs: "space" });
  }
  if (agent) command("terminal.pin", { terminal: agent.address, pinned: !agent.pinned }, "Agent",
    `${agent.pinned ? "Unpin" : "Pin"} current agent`, "top favorite");
  if (terminal) {
    command("terminal.kill", { terminal: terminal.address }, "Terminal", "Stop current terminal…", "kill end",
      { confirm: true, confirmMessage: confirmations["terminal.kill"] });
    const parent = allTerminals.find(t => t.address === terminal.parent);
    if (parent && allPanes.some(p => p.terminal === terminal.address)) {
      command("terminal.park", { terminal: terminal.address }, "Agent", `Send back to ${parent.name || parent.address}`, "park keep running");
    }
    const toProgram = terminal.labels?.["herdr.right-click"] === "program";
    command("terminal.right_click", { terminal: terminal.address, to: toProgram ? "menu" : "program" }, "Terminal",
      toProgram ? "Use Herdr right-click menu" : "Send right-clicks to terminal program", "mouse");
    for (const [args, label] of [[{ pages: -1 }, "Scroll up a page"], [{ pages: 1 }, "Scroll down a page"],
      [{ to: "top" }, "Scroll to oldest history"], [{ to: "bottom" }, "Return to live terminal"]]) {
      command("terminal.scroll", { ...args, terminal: terminal.address }, "Terminal", label, "scrollback history");
    }
  }
  for (const a of allAgents) command("agent.focus", { terminal: a.address }, "Agent",
    `Agent: ${a.space_name} / ${a.tab_name}`, `${a.program?.name ?? ""} ${a.status} ${a.address}`);
  // Background children are absent from agents(); give them named public actions.
  for (const t of allTerminals.filter(t => t.state === "live" && t.parent && !allPanes.some(p => p.terminal === t.address))) {
    const name = t.name || t.program?.name || t.address;
    command("terminal.peek", { terminal: t.address }, "Agent", `Peek at ${name}`, `${t.address} child sub-agent`);
    command("terminal.keep", { terminal: t.address, place: "tab" }, "Agent", `Keep ${name} as a tab`, `${t.address} child sub-agent`);
  }

  // Preserve native palette forward compatibility without presenting commands
  // requiring raw identifiers, arbitrary JSON, or a meaningless empty argument.
  const hidden = new Set([
    "space.move", "tab.move", "space.select", "tab.select", "pane.focus", "pane.swap", "pane.go", "pane.split",
    "terminal.keep", "terminal.park", "terminal.kill", "terminal.peek", "terminal.show", "terminal.pin",
    "terminal.right_click", "terminal.scroll", "terminal.select", "terminal.adjust_selection", "agent.focus",
    "layout.set", "layout.toggle", "layout.show", "layout.hide", "layout.resize", "layout.select", "mod.open", "overlay.close",
    "tab.settle", "tab.unsettle", "app.palette", "app.help", "app.hide", "app.hide_others", "app.show_all",
    "app.theme", "app.settings", "app.quit", "window.close", "window.minimize", "window.maximize",
  ]);
  for (const c of commandInfo) {
    if (covered.has(c.name) || hidden.has(c.name) || c.args.some(a => a.required && a.name !== "name")) continue;
    const [noun, verb] = c.name.split(".");
    const group = noun[0].toUpperCase() + noun.slice(1);
    const label = `${verb.replace(/_/g, " ")} ${noun}`.replace(/^./, c => c.toUpperCase());
    command(c.name, {}, group, label, c.about, { needs: focusNeeds(c.name) });
  }
  return list;
}

// Call on selection, before changing modes: capture original IDs now so a
// confirmation cannot drift onto another pane, tab, or space after focus moves.
function guideCaptureEntry(entry, focus) {
  if (!entry.command || !focus) return entry;
  let args = { ...entry.args };
  if (["pane.close", "pane.zoom", "pane.split", "pane.swap"].includes(entry.command) && !args.pane) args.pane = focus.pane;
  if (["tab.close", "tab.rename"].includes(entry.command) && !args.id) args.id = focus.tab;
  if (["space.close", "space.rename"].includes(entry.command) && !args.id) args.id = focus.space;
  if (["tab.close", "space.close"].includes(entry.command) && entry.confirm) args.confirmed = true;
  return { ...entry, args };
}

export default class KeyboardGuide extends View {
  init(_props, cx) {
    this.mode = props()?.mode ?? "root";
    this.message = "";
    this.target = props()?.target ?? focused();
    this.selecting = this.mode === "copy" && !!terminals().find(t => t.address === this.target?.terminal)?.selection;
    this.copyQueue = [];
    this.copyBusy = false;
    this.copyClosed = false;
    this.copyToken = `copy-${String(props()?.overlay ?? "guide").replace(/[^a-zA-Z0-9_-]/g, "")}`;
    this.pending = null;
    this.query = "";
    this.at = 0;
    this.handle = cx.focus_handle();
    this.handle.focus();
    if (this.searching()) this.changeMode(this.mode, cx);
    if (!checking()) cx.spawn(async cx => {
      for (;;) {
        const command = await nextCommand();
        this.command(command, cx);
      }
    });
  }

  command(command, cx) {
    // run() queues requests. A command sent back through that same queue is an
    // acknowledgement: preceding selection changes are now in the live snapshot.
    if (command === `${this.copyToken}-moved` || command === `${this.copyToken}-ready`) {
      if (this.mode !== "copy" || this.copyClosed || !this.copyBusy) return;
      if (command.endsWith("-moved")) {
        const selection = terminals().find(t => t.address === this.target?.terminal)?.selection;
        if (!selection) {
          this.copyQueue = [];
          this.copyBusy = false;
          return this.hint("Selection is no longer available. Escape returns.", cx);
        }
        if (!this.selecting) run("terminal.select", { terminal: this.target.terminal, at: selection.end });
        run(`keyboard-guide.${this.copyToken}-ready`);
      } else {
        this.copyBusy = false;
        this.pumpCopy(cx);
        cx.notify();
      }
      return;
    }
    if (command === "focus") this.searching() ? this.input?.focus() : this.handle.focus();
    else if (command === "close") this.dismiss();
    else if (["root", "navigate", "agents", "copy", "help", "commands", "places"].includes(command)) this.changeMode(command, cx);
  }

  searching() { return this.mode === "commands" || this.mode === "places"; }

  dismiss() {
    this.copyClosed = true;
    this.copyQueue = [];
    closeOverlay(props().overlay);
  }

  close() {
    this.copyClosed = true;
    this.copyQueue = [];
    if (this.mode === "copy" && terminals().some(t => t.address === this.target?.terminal && t.state === "live")) {
      run("terminal.clear_selection", { terminal: this.target.terminal });
    }
  }

  context() { return this.mode === "copy" ? this.target : focused(); }

  available(row) { return !row.needs || !!this.context()?.[row.needs]; }

  agentList() {
    const list = agents();
    const order = shared("keyboard.agents.order");
    if (order && order.layout === shared("layout") && Array.isArray(order.addresses)) {
      const byAddress = new Map(list.map(a => [a.address, a]));
      return order.addresses.map(address => byAddress.get(address)).filter(Boolean);
    }
    // The guide also works in layouts without the numbered sidebar.
    return [...list.filter(a => a.pinned), ...list.filter(a => !a.pinned)];
  }

  changeMode(mode, cx) {
    this.message = "";
    if (mode === "copy") {
      const target = focused();
      if (!target?.terminal) return this.hint("Focus a terminal before entering copy mode.", cx);
      // A popup keeps copy keys and native Escape together. A floating window
      // can lose keyboard focus while remaining stuck over the terminal.
      const viewport = globalThis.window.viewport_size();
      const zoom = Number(settings().zoom) || 1;
      this.dismiss();
      openOverlay({ mod: "keyboard-guide", props: { mode: "copy", target }, kind: "popup",
        width: 760, height: 146, at: "top", offset: Math.max(8, (viewport.height / zoom - 146) / 2) });
      return;
    }
    this.mode = mode;
    if (this.searching()) {
      this.query = "";
      this.at = 0;
      this.input = InputState.new({ placeholder: mode === "places" ? "Find a space or tab…" : "Find a command…" });
      this.input.on("change", (_e, cx) => { this.query = this.input.value(); this.at = 0; cx.notify(); });
      this.input.on("submit", (_e, cx) => this.chooseSearch(cx));
      this.input.focus();
    } else this.handle.focus();
    cx.notify();
  }

  searchRows() {
    let entries;
    if (this.mode === "places") {
      entries = spaces().flatMap(space => [
        { id: `space-${space.id}`, label: space.name, group: "Space", words: space.machine ?? "local",
          command: "space.select", args: { id: space.id }, keys: [] },
        ...space.tabs.map(tab => ({ id: `tab-${tab.id}`, label: `${space.name} / ${tab.name}`,
          group: "Tab", words: space.machine ?? "local", command: "tab.select", args: { id: tab.id }, keys: [] })),
      ]);
    } else {
      entries = guideCatalogue(ROOT, { commandInfo: commands(), layoutNames: layouts(), themeNames: themes(),
        focus: this.context(), spaces: spaces(), agents: agents(), panes: panes(), terminals: terminals(),
        layoutName: shared("layout") ?? "keyboard", platform: window()?.platform });
    }
    const words = this.query.toLowerCase().trim().split(/\s+/).filter(Boolean);
    return entries.filter(e => words.every(word => `${e.label} ${e.group} ${e.words ?? ""}`.toLowerCase().includes(word)));
  }

  chooseSearch(cx, entry = this.searchRows()[this.at]) {
    if (!entry) return;
    if (entry.root) return this.runAction(entry.root, entry.key, cx);
    this.runAction(entry, entry.key, cx);
  }

  searchKey(e, cx) {
    const key = keyName(e);
    if (key === "escape" || key === "ctrl-c") {
      cx.stop_propagation();
      return this.dismiss();
    }
    if (key === "ctrl-b" || (key === "backspace" && !this.query)) {
      cx.stop_propagation();
      return this.changeMode("root", cx);
    }
    const step = { up: -1, down: 1, pageup: -8, pagedown: 8, "ctrl-p": -1, "ctrl-n": 1 }[key];
    if (step) {
      cx.stop_propagation();
      this.at = Math.max(0, Math.min(this.searchRows().length - 1, this.at + step));
      return cx.notify();
    }
    // Native Input owns typing, selection, clipboard, composition and Enter.
  }

  hint(message, cx) { this.message = message; cx.notify(); }

  runAction(row, key, cx) {
    if (row.mode) return this.changeMode(row.mode, cx);
    if (!this.available(row)) return this.hint(`Focus a ${row.needs} first.`, cx);
    if (row.worktreeRemove) return this.removeWorktree(row.worktreeRemove, cx);
    if (row.sequence) {
      this.dismiss();
      for (const [command, args] of row.sequence) run(command, args);
      return;
    }
    if (row.confirm) {
      this.pending = { ...guideCaptureEntry(row, this.context()), confirm: false };
      this.mode = "confirm";
      this.handle.focus();
      return cx.notify();
    }
    if (row.dialog) {
      this.dismiss();
      openOverlay(row.dialog);
      return;
    }
    if (row.command === "direction") return this.execute("pane.go", { direction: directions[key] });
    if (row.command === "tab-step") return this.execute(key === "p" ? "tab.prev" : "tab.next");
    if (row.command === "cycle") return this.cycle(key === "shift-tab" ? -1 : 1, false, cx);
    if (row.command === "worktree") {
      const f = focused();
      this.dismiss();
      openOverlay({ mod: "worktree", props: { space: f.space, folder: f.cwd, action: "new" }, kind: "dialog", width: 560, height: 430 });
      return;
    }
    this.execute(row.command, row.args);
  }

  removeWorktree(target, cx) {
    if (this.worktreeChecking) return;
    this.worktreeChecking = true;
    this.hint("Checking the current checkout…", cx);
    cx.spawn(async cx => {
      try {
        const options = { cwd: target.folder, on: target.machine ?? null };
        const [gitDir, common] = await Promise.all([
          exec("git", ["rev-parse", "--absolute-git-dir"], options),
          exec("git", ["rev-parse", "--path-format=absolute", "--git-common-dir"], options),
        ]);
        if (this.copyClosed) return;
        if (gitDir.code || common.code) return this.hint("This space is not in an available Git checkout.", cx);
        const normalize = path => path.trim().replace(/\\/g, "/").replace(/\/$/, "");
        if (normalize(common.stdout) === normalize(gitDir.stdout)) {
          return this.hint("This is the main checkout. Only a linked worktree can be removed.", cx);
        }
        this.dismiss();
        openOverlay({ mod: "worktree", kind: "dialog", width: 560, height: 300,
          props: { space: target.space, folder: target.folder, action: "remove" } });
      } catch (error) {
        if (!this.copyClosed) this.hint(`Could not check this worktree: ${error}`, cx);
      } finally { this.worktreeChecking = false; }
    });
  }

  execute(command, args = {}) {
    this.dismiss();
    run(command, args);
  }

  cycle(by, stay, cx) {
    const f = focused();
    const list = panes().filter(p => p.tab === f?.tab);
    const at = list.findIndex(p => p.pane === f?.pane);
    if (!list.length || at < 0) return this.hint("Focus a pane to cycle through this tab.", cx);
    if (!stay) this.dismiss();
    run("pane.focus", { pane: list[(at + by + list.length) % list.length].pane });
    if (stay) { this.handle.focus(); cx.notify(); }
  }

  copyKey(key, cx) {
    const terminal = this.target?.terminal;
    if (key === "escape" || key === "q" || key === "ctrl-c" || key === "backspace") {
      if (terminal) run("terminal.clear_selection", { terminal });
      this.dismiss();
      if (key === "backspace") run("mod.open", { name: "keyboard-guide" });
      return;
    }
    if (!terminal || !terminals().some(t => t.address === terminal && t.state === "live")) {
      return this.hint("That terminal is no longer available. Escape returns.", cx);
    }
    if (this.copyClosed) return;
    this.copyQueue.push(key);
    this.pumpCopy(cx);
  }

  pumpCopy(cx) {
    if (this.copyClosed || this.copyBusy || !this.copyQueue.length) return;
    const key = this.copyQueue.shift();
    const terminal = this.target?.terminal;
    if (!terminals().some(t => t.address === terminal && t.state === "live")) {
      this.copyQueue = [];
      return this.hint("That terminal is no longer available. Escape returns.", cx);
    }
    const selection = terminals().find(t => t.address === terminal)?.selection;
    if (key === "y" || key === "enter") {
      if (!selection) {
        this.hint("Press v to select, then move with h j k l.", cx);
        return this.pumpCopy(cx);
      }
      run("pane.focus", { terminal });
      run("terminal.copy");
      run("terminal.clear_selection", { terminal });
      return this.dismiss();
    }
    if (key === "v" || key === "space" || key === "shift-v") {
      this.copyBusy = true;
      run("terminal.select", { terminal, at: selection?.end ?? "cursor", mode: key === "shift-v" ? "line" : "cell" });
      this.selecting = true;
      run(`keyboard-guide.${this.copyToken}-ready`);
      return this.hint("Selecting · h j k l extend · y copies · Escape cancels", cx);
    }
    const move = directions[key] ?? ({ "ctrl-u": "page_up", "ctrl-d": "page_down",
      pageup: "page_up", pagedown: "page_down", g: "home", "shift-g": "end", "0": "line_start", "shift-4": "line_end" })[key];
    if (move) {
      this.copyBusy = true;
      if (!selection) run("terminal.select", { terminal });
      run("terminal.adjust_selection", { terminal, direction: move });
      run(`keyboard-guide.${this.copyToken}-moved`);
      return cx.notify();
    }
    this.hint("h j k l move · v selects · y copies · Ctrl-u/d page · g/G top/bottom", cx);
    this.pumpCopy(cx);
  }

  key(e, cx) {
    if (this.searching()) return this.searchKey(e, cx);
    cx.stop_propagation();
    const key = keyName(e);
    if (this.mode === "copy") return this.copyKey(key, cx);
    if (key === "escape" || key === "ctrl-c") return this.dismiss();
    if (key === "ctrl-b") {
      const terminal = focused()?.terminal;
      if (!terminal || checking()) return this.dismiss();
      // Forward only the explicitly requested literal prefix to this terminal.
      cx.spawn(async cx => {
        try {
          const result = await hc(["keys", terminal, "ctrl+b"]);
          if (result.code !== 0) throw new Error(result.stderr || "Could not send Ctrl-b");
          this.dismiss();
        } catch (error) { this.hint(String(error), cx); }
      });
      return;
    }
    if (key === "backspace") return this.changeMode("root", cx);
    if (this.mode === "confirm") {
      if (key === "enter" || key === "y") return this.runAction(this.pending, key, cx);
      if (key === "n") return this.changeMode("root", cx);
      return this.hint("Enter confirms · n goes back · Escape cancels", cx);
    }
    if (this.mode === "help") {
      if (key === ":") return this.changeMode("commands", cx);
      return this.changeMode("root", cx);
    }
    if (this.mode === "navigate") {
      if (key === "enter" || key === "g") return this.dismiss();
      if (key === "tab" || key === "shift-tab") return this.cycle(key === "tab" ? 1 : -1, true, cx);
      const command = key === "up" ? ["space.prev"] : key === "down" ? ["space.next"]
        : directions[key] ? ["pane.go", { direction: directions[key] }]
        : key === "p" ? ["tab.prev"] : key === "n" ? ["tab.next"]
        : key === "[" ? ["agent.prev"] : key === "]" ? ["agent.next"] : null;
      if (command) { run(command[0], command[1] ?? {}); this.handle.focus(); return cx.notify(); }
    }
    const digit = key.match(/^(shift-)?([1-9])$/);
    if (digit) {
      const index = Number(digit[2]);
      if (digit[1] || this.mode === "agents") {
        const agent = this.agentList()[index - 1];
        if (agent) return this.execute("agent.focus", { terminal: agent.address });
        return this.hint(`No agent ${index}. The available agents are listed here.`, cx);
      }
      const tab = spaces().find(s => s.active)?.tabs.filter(t => !t.settled)[index - 1];
      if (tab) return this.execute("tab.select", { id: tab.id });
      return this.hint(`No tab ${index} in this space. Press c to create one.`, cx);
    }
    if (this.mode === "agents") return this.hint("Choose an agent number · Backspace returns · Escape cancels", cx);
    const row = ROOT.flatMap(([, rows]) => rows).find(row => row.keys.includes(key));
    if (row) return this.runAction(row, key, cx);
    const limits = { r: "Herdr app has no keyboard pane-resize command yet. Drag a divider; z toggles zoom.",
      "shift-p": "Pane renaming is not exposed by Herdr app. Shift-T renames this tab.",
      e: "Editing scrollback is not exposed by Herdr app. [ opens keyboard copy; / searches.",
      "shift-r": "Herdr app reloads personal files automatically when saved.",
      o: "Use a to choose an agent, including those waiting for you." };
    this.hint(limits[key] ?? `No command for ${e.keystroke || e.key}. Choose a key shown below.`, cx);
  }

  keyLabel(key) {
    return key.replace(/^shift-/, "⇧").replace(/^ctrl-/, "Ctrl-")
      .replace("tab", "Tab").replace("escape", "Esc");
  }

  row(row, t, cx, id) {
    const enabled = this.available(row);
    return h_flex().id(id).h(20).gap(9).items_center().cursor_pointer()
      .hover(s => s.bg(t.hover)).on_click((_e, cx) => this.runAction(row, row.keys[0], cx))
      .child(div().w(62).flex_none().text_color(enabled ? t.accent : t.dim)
        .child(row.keys.map(k => this.keyLabel(k)).join(" ")))
      .child(div().text_color(enabled ? t.foreground : t.dim).truncate().child(row.label));
  }

  render(cx) {
    const t = theme();
    const f = this.context();
    const space = spaces().find(s => s.id === f?.space);
    const tab = space?.tabs.find(tab => tab.id === f?.tab);
    const root = v_flex().id("keyboard-guide").track_focus(this.handle)
      .on_key_down((e, cx) => this.key(e, cx)).size_full().p(16).gap(8)
      .bg(t.background).text_color(t.foreground).text_size(12);
    root.child(h_flex().items_center().justify_between()
      .child(h_flex().gap(10).child(div().font_semibold().text_color(t.accent).child("Ctrl-b"))
        .child(div().child(this.mode === "root" ? " /  next command" : ` /  ${this.mode}`)))
      .child(div().text_color(t.muted).truncate().child(`${space?.name ?? "Herdr"}  /  ${tab?.name ?? "—"}`)));
    root.child(div().h(1).bg(t.border));
    if (this.searching()) {
      const rows = this.searchRows();
      this.at = Math.min(this.at, Math.max(0, rows.length - 1));
      const start = Math.max(0, this.at - 7);
      root.child(Input.new(this.input).h(34).px(10).border(1).border_color(t.accent)
        .bg(t.background).text_color(t.foreground));
      root.child(v_flex().h(277).flex_none().overflow_hidden().gap(2).children(rows.slice(start, start + 9).map((entry, i) =>
        h_flex().id(`command-${entry.id}`).h(29).flex_none().px(8).gap(12).items_center()
          .bg(start + i === this.at ? t.selected : t.background).hover(s => s.bg(t.hover))
          .cursor_pointer().on_click((_e, cx) => this.chooseSearch(cx, entry))
          .child(div().flex_1().min_w(0).truncate().text_color(this.available(entry) ? t.foreground : t.dim).child(entry.label))
          .child(div().text_color(t.muted).text_size(10).child(entry.group))
          .child(div().text_color(t.accent).text_size(11).child(entry.keys?.length ? `Ctrl-b ${entry.keys.map(k => this.keyLabel(k)).join(" / ")}` : "")) )));
      if (!rows.length) root.child(div().text_color(t.muted).child("No matching commands or places."));
      root.child(div().text_color(t.muted).child(`↑ / ↓ choose · Enter runs · Ctrl-b returns · Esc closes · ${rows.length} matches`));
    } else if (this.mode === "copy") {
      root.child(div().child("h j k l  move     v / V  select / line     y  copy     Esc  leave"));
      root.child(div().text_color(t.muted).child("Ctrl-u / Ctrl-d  page     g / G  top / bottom     0 / $  line edges"));
    } else if (this.mode === "confirm") {
      root.child(div().text_size(17).child(this.pending?.label.replace("…", "?") ?? "Confirm"));
      root.child(div().text_color(t.muted).child(this.pending?.confirmMessage ?? "This closes the selected work and its running terminal programs."));
      root.child(div().text_color(t.accent).child("Enter / y  confirm     n / Backspace  go back     Esc  cancel"));
    } else if (this.mode === "help") {
      root.child(div().child("TUI keys: v / − split · Shift-1…9 choose agents · q minimizes the window."));
      root.child(div().child("tmux copy flow: [ enters copy mode · v starts selection · y copies."));
      root.child(div().child("Ctrl-b Ctrl-b sends a literal Ctrl-b to your terminal."));
      root.child(div().text_color(t.muted).child("Pane resize, pane rename and edit-scrollback have no app command yet."));
      root.child(div().text_color(t.muted).child("% stays Shift-5 (agent 5). b stays the TUI sidebar toggle."));
      root.child(div().child("Clipboard and text editing keep their standard keys. Herdr commands start with Ctrl-b."));
      root.child(div().text_color(t.accent).child(":  find any command     Backspace  prefix commands     Esc  close"));
    } else if (this.mode === "agents") {
      root.child(div().text_color(t.muted).child("Numbers follow the agent list from top to bottom and update when rows move."));
      root.child(v_flex().flex_1().min_h(0).overflow_y_scrollbar().children(
        this.agentList().slice(0, 9).map((a, i) => this.row(action(String(i + 1), `${a.space_name} / ${a.tab_name} · ${a.program?.name ?? a.app ?? a.address} · ${a.status}`, "agent.focus", { terminal: a.address }), t, cx, `agent-${a.address}`))));
      if (this.agentList().length > 9) root.child(div().text_color(t.muted).child("First nine agents shown. Use g then [ / ] to reach the others."));
    } else if (this.mode === "navigate") {
      root.child(div().text_size(16).child("Move freely. Enter returns to the terminal."));
      root.child(div().child("h j k l / ← →  focus pane      ↑ ↓  previous / next space"));
      root.child(div().child("Tab / Shift-Tab  cycle panes    p / n  previous / next tab"));
      root.child(div().child("[ / ]  previous / next agent    1…9  choose tab & return"));
      root.child(div().text_color(t.accent).child("Enter  finish     Backspace  all commands     Esc  leave"));
    } else {
      root.child(h_flex().gap(26).children([ROOT.slice(0, 2), ROOT.slice(2)].map((groups, col) =>
        v_flex().flex_1().min_w(0).gap(6).children(groups.map(([title, rows], group) =>
          v_flex().gap(2)
            .child(div().text_size(10).text_color(t.muted).child(title))
            .children(rows.map((row, i) => this.row(row, t, cx, `action-${col}-${group}-${i}`))))))));
      const tabs = space?.tabs.filter(t => !t.settled).slice(0, 9) ?? [];
      root.child(div().h(1).bg(t.border));
      root.child(div().text_color(t.accent).child("1…9  tabs     Shift-1…9  agents     Ctrl-b  send prefix     Esc  cancel"));
      root.child(div().text_color(t.muted).truncate().child(tabs.map((tab, i) => `${i + 1} ${tab.name}${tab.active ? " •" : ""}`).join("    ") || "No open tabs"));
    }
    root.child(div().flex_1());
    root.child(div().text_color(this.message ? t.accent : t.muted).child(this.message ||
      (this.mode === "root" ? "Press a key above. Your next choices appear here." : "Backspace returns to commands · Escape closes")));
    return root;
  }
}
