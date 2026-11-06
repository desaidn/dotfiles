// Personal compatibility for Ctrl+B prefix keys, including Shift+1–9 agents.
import { View, div } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { agents, props, closeOverlay, run, theme, shared, setShared } from "herdr";

// Keep the mod self-contained: Herdr rejects relative imports through symlinks.
const actions = {
  "?": ["app.help"],
  s: ["app.settings"],
  q: ["app.hide"],
  w: ["mod.open", { name: "picker" }],
  "shift-n": ["space.new"],
  "shift-w": ["space.rename"],
  "shift-d": ["space.close"],
  c: ["tab.new"],
  "shift-t": ["tab.rename"],
  p: ["tab.prev"],
  n: ["tab.next"],
  "shift-x": ["tab.close"],
  h: ["pane.go", { direction: "left" }],
  j: ["pane.go", { direction: "down" }],
  k: ["pane.go", { direction: "right" }],
  l: ["pane.go", { direction: "up" }],
  v: ["pane.split", { direction: "right" }],
  "-": ["pane.split", { direction: "down" }],
  x: ["pane.close"],
  z: ["pane.zoom"],
  b: ["layout.toggle", { id: "sidebar" }],
};

const shiftedDigits = "!@#$%^&*(";

export function prefixAction(event, agentList) {
  const modifiers = event.modifiers ?? {};
  if (modifiers.control || modifiers.alt || modifiers.platform) return null;

  const key = event.key.toLowerCase();
  const typed = event.key_char ?? key;
  const shiftedIndex = typed.length === 1 ? shiftedDigits.indexOf(typed) : -1;
  const index = /^[1-9]$/.test(key)
    ? Number(key)
    : shiftedIndex >= 0
      ? shiftedIndex + 1
      : null;

  if (index !== null) {
    if (!modifiers.shift && shiftedIndex < 0) {
      return ["tab.select", { index }];
    }
    // Match the bundled grouped Agents panel: pinned rows, then space order.
    const ordered = [
      ...agentList.filter((agent) => agent.pinned),
      ...agentList.filter((agent) => !agent.pinned),
    ];
    const agent = ordered[index - 1];
    return agent ? ["agent.focus", { terminal: agent.address }] : null;
  }

  if (typed === "?" || (key === "/" && modifiers.shift)) return actions["?"];
  if (key === "-" && !modifiers.shift) return actions["-"];
  return actions[modifiers.shift ? `shift-${key}` : key] ?? null;
}

export default class LegacyPrefix extends View {
  init(_props, cx) {
    this.handle = cx.focus_handle();
    this.handle.focus();
    // Migrate the old preference once; later changes in the sort menu win.
    if (shared("agents.sort") == null) setShared("agents.sort", "grouped");
    this.message = "";
  }

  key(event, cx) {
    cx.stop_propagation();
    if (event.key === "escape") return closeOverlay(props().overlay);

    if (event.key === "b" && event.modifiers.control
      && !event.modifiers.shift && !event.modifiers.alt && !event.modifiers.platform) {
      closeOverlay(props().overlay);
      return;
    }

    const action = prefixAction(event, agents());
    if (action) {
      closeOverlay(props().overlay);
      run(action[0], action[1] ?? {});
      return;
    }

    const unavailable = {
      g: "Use the space picker (w) or the app command palette.",
      "shift-g": "Use New worktree in the space menu.",
      o: "The app has no jump-to-notification command.",
      "shift-p": "The app has no pane-rename command.",
      e: "The app has no edit-scrollback command.",
      r: "Resize panes by dragging their divider.",
      tab: "Use h, j, k or l to move between panes.",
      "shift-tab": "Use h, j, k or l to move between panes.",
      "shift-r": "Configuration files reload automatically.",
    };
    const key = event.modifiers.shift ? `shift-${event.key}` : event.key;
    this.message = unavailable[key] ?? "No matching agent or prefix command. Esc cancels.";
    cx.notify();
  }

  render() {
    const t = theme();
    return v_flex()
      .id("legacy-prefix")
      .track_focus(this.handle)
      .on_key_down((event, cx) => this.key(event, cx))
      .size_full()
      .p(18)
      .gap(12)
      .bg(t.popover)
      .text_color(t.foreground)
      .text_size(12.5)
      .child(h_flex()
        .items_center()
        .justify_between()
        .child(div().font_semibold().text_size(15).child("Ctrl+B"))
        .child(div().text_color(t.dim).child("Esc to cancel")))
      .child(div().text_color(t.accent).child("Shift+1–9  focus agent     ·     1–9  select tab"))
      .child(div().child("h j k l  focus pane     ·     v / −  split     ·     x / z  close / zoom"))
      .child(div().child("c  new tab     ·     p / n  previous / next     ·     Shift+T / X  rename / close"))
      .child(div().child("Shift+N  new space     ·     w  picker     ·     Shift+W / D  rename / close"))
      .child(div().child("b  sidebar     ·     s  settings     ·     ?  app keys     ·     q  hide app"))
      .child(div().text_color(t.muted).child(this.message || "Press a prefix command. Ctrl+B or Escape cancels."));
  }
}
