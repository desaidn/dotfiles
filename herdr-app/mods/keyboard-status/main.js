// Derived from Herdr app v0.1.16, defaults/mods/workspace-status/main.js (Apache-2.0).
// Modified by Dhairya Desai: Ctrl-b commands footer opens the keyboard guide.
// Source: https://github.com/herdrdev/herdr-app/tree/v0.1.16
// License and attribution: upstream/LICENSE-herdr-app-0.1.16, upstream/README.md.
import { View, div, svg } from "gpui-kit";
import { h_flex } from "gpui-base";
import { spaces, agents, theme, run } from "herdr";

export default class WorkspaceStatus extends View {
  render() {
    const t = theme();
    const space = spaces().find(s => s.active);
    const list = agents();
    const needs = list.filter(a => a.status === "blocked").length;
    const label = (icon, text) => h_flex().gap(6).items_center().child(svg(`mods/workspace-chrome/${icon}.svg`).size(13)).child(text);
    return h_flex().size_full().px(14).gap(16).items_center().bg(t.chrome).border_t(1).border_color(t.border).text_size(11.8).text_color(t.muted)
      .child(label(space?.machine ? "server" : "monitor", space?.machine ?? "This computer"))
      .when(Boolean(space?.branch), el => el.child(label("branch", space.branch)))
      .child(h_flex().gap(6).items_center().child(div().size(6).rounded(3).bg(t.dim)).child(`${list.length} agents`)
        .when(needs > 0, el => el.child(div().text_color(t.blocked).child(`· ${needs} needs you`))))
      .child(div().flex_1())
      .child(div().id("keyboard-commands").text_color(t.dim).cursor_pointer()
        .hover(style => style.text_color(t.accent))
        .on_click(() => run("mod.open", { name: "keyboard-guide" }))
        .child("Ctrl-b  commands"));
  }
}
