import { View, div } from "gpui-kit";
import { prefixAction } from "./prefix.js";

function expect(actual, expected, message) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(`${message}: ${JSON.stringify(actual)}`);
  }
}

function key(name, shift = false, keyChar = name, extra = {}) {
  return { key: name, key_char: keyChar, modifiers: { shift, ...extra } };
}

export default class PrefixBehavior extends View {
  init() {
    const agents = [
      { address: "t1" },
      { address: "remote/t2" },
      { address: "t3" },
      { address: "t4" },
      { address: "t5" },
      { address: "t6" },
      { address: "t7" },
      { address: "t8" },
      { address: "remote/t9", pinned: true },
    ];
    const order = ["remote/t9", "t1", "remote/t2", "t3", "t4", "t5", "t6", "t7", "t8"];
    const shifted = "!@#$%^&*(";
    for (let index = 1; index <= 9; index++) {
      expect(prefixAction(key(String(index)), agents), ["tab.select", { index }], "plain digit selects tab");
      const expected = ["agent.focus", { terminal: order[index - 1] }];
      expect(prefixAction(key(String(index), true), agents), expected, "shifted digit follows pinned/space order");
      expect(prefixAction(key(String(index), true, shifted[index - 1]), agents), expected, "typed punctuation focuses agent");
      expect(prefixAction(key(shifted[index - 1], true), agents), expected, "punctuation key focuses agent");
    }
    expect(prefixAction(key("1", true), []), null, "missing agent does nothing");
    for (const name of ["tab", "up", "left", "f2"]) {
      expect(prefixAction(key(name, false, ""), agents), null, "non-text key must not focus the first agent");
    }
    for (const modifier of ["control", "alt", "platform"]) {
      expect(prefixAction(key("1", true, "!", { [modifier]: true }), agents), null, "modified input is ignored");
    }
    expect(prefixAction(key("0"), agents), null, "zero has no tab binding");
    expect(prefixAction(key("/", true, "?"), agents), ["app.help"], "question mark opens help");
    expect(prefixAction(key("q"), agents), ["app.hide"], "q hides the macOS app");
  }

  render() {
    return div().child("Prefix behavior checks passed");
  }
}
