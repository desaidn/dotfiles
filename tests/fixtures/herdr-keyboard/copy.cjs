// Replay the production copy handler across Herdr's native asynchronous boundary.
// Herdr v0.1.16: src/mods.rs run() queues Request::Run (lines 1106-1121),
// request() uses async_channel::try_send (551-554), and terminals() reads the
// published snapshot (556-559, 1146). src/window.rs receives those requests
// asynchronously (650) and dispatches them in order (3910).
// https://github.com/herdrdev/herdr-app/tree/v0.1.16
// This fixture models that boundary, not terminal rendering: fixed-width ASCII
// rows make the expected inclusive ranges unambiguous. No desktop/clipboard IO.
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');

const source = fs.readFileSync(process.argv[2], 'utf8')
  .replace(/^import[\s\S]*?from "[^"]+";\n/gm, '')
  .replace('export function keyName', 'function keyName')
  .replace('export default class KeyboardGuide', 'class KeyboardGuide');
const clone = value => structuredClone(value);
const point = (row, col) => ({ row, col });
const range = (r1, c1, r2 = r1, c2 = c1) => ({ start: point(r1, c1), end: point(r2, c2) });
const columns = 20;
const rows = Array.from({ length: 30 }, (_, i) => `${String(i).padStart(2, '0')} ABCDEFGHIJKLMNOPQ`);
let scene, queued, guide, overlayProps;
const cx = {
  notify() {}, stop_propagation() {},
  focus_handle: () => ({ focus() {} }),
};
const sandbox = {
  View: class {}, checking: () => true,
  props: () => clone(overlayProps),
  focused: () => clone(scene.focus), terminals: () => clone(scene.terminals),
  run: (name, args = {}) => queued.push({ name, args: clone(args) }),
  closeOverlay: id => queued.push({ name: 'close-overlay', args: { id } }),
  openOverlay: spec => queued.push({ name: 'open-overlay', args: clone(spec) }),
};
vm.createContext(sandbox);
vm.runInContext(source + '\nglobalThis.Guide = KeyboardGuide;', sandbox);

function fresh({ selection = null, cursor = point(10, 5), target = null } = {}) {
  const focus = { terminal: 'term1', pane: 'pane1', tab: 'tab1', space: 'space1' };
  scene = {
    focus, cursor, terminals: [
      { address: 'term1', state: 'live', selection: clone(selection) },
      { address: 'term2', state: 'live', selection: range(2, 1, 2, 3) },
    ], clipboard: null, closed: false, calls: [], replies: [],
  };
  queued = [];
  overlayProps = { overlay: 'copy-guide', mode: 'copy', target: target ?? clone(focus) };
  guide = new sandbox.Guide();
  guide.init({}, cx);
}

function selectionText(selection) {
  if (!selection) return null;
  const cells = [selection.start, selection.end].sort((a, b) => a.row - b.row || a.col - b.col);
  const [start, end] = cells;
  return rows.slice(start.row, end.row + 1).map((text, index, selected) =>
    text.slice(index === 0 ? start.col : 0, index === selected.length - 1 ? end.col + 1 : columns)).join('\n');
}

function move(end, direction) {
  const next = clone(end);
  const delta = { left: [0, -1], right: [0, 1], up: [-1, 0], down: [1, 0], page_up: [-4, 0], page_down: [4, 0] }[direction];
  if (delta) { next.row += delta[0]; next.col += delta[1]; }
  else if (direction === 'home') Object.assign(next, point(0, 0));
  else if (direction === 'end') Object.assign(next, point(rows.length - 1, columns - 1));
  else if (direction === 'line_start') next.col = 0;
  else if (direction === 'line_end') next.col = columns - 1;
  else assert.fail(`Unmodelled selection direction: ${direction}`);
  if (next.col < 0 && next.row > 0) { next.row--; next.col = columns - 1; }
  if (next.col >= columns && next.row < rows.length - 1) { next.row++; next.col = 0; }
  next.row = Math.max(0, Math.min(rows.length - 1, next.row));
  next.col = Math.max(0, Math.min(columns - 1, next.col));
  return next;
}

function drain() {
  let budget = 200;
  while (queued.length) {
    assert.ok(budget-- > 0, 'Copy command queue did not settle');
    const { name, args } = queued.shift();
    scene.calls.push([name, args]);
    const terminal = scene.terminals.find(t => t.address === args.terminal);
    if (name === 'terminal.select') {
      assert.ok(terminal, 'Selection targets a live terminal');
      const at = !args.at || args.at === 'cursor' ? scene.cursor : args.at;
      terminal.selection = args.mode === 'line'
        ? range(at.row, 0, at.row, columns - 1) : range(at.row, at.col);
    } else if (name === 'terminal.adjust_selection') {
      assert.ok(terminal?.selection, 'Native adjustment requires a selection');
      terminal.selection.end = move(terminal.selection.end, args.direction);
    } else if (name === 'terminal.clear_selection') {
      if (terminal) terminal.selection = null;
    } else if (name === 'pane.focus') scene.focus.terminal = args.terminal;
    else if (name === 'terminal.copy') {
      const selected = scene.terminals.find(t => t.address === scene.focus.terminal)?.selection;
      scene.clipboard = { terminal: scene.focus.terminal, selection: clone(selected), text: selectionText(selected) };
    } else if (name.startsWith('keyboard-guide.')) {
      const command = name.slice('keyboard-guide.'.length);
      scene.replies.push(command);
      // Herdr delivers mod commands only to copies that are still shown.
      if (!scene.closed) guide.command(command, cx);
    } else if (name === 'close-overlay') {
      scene.closed = true;
      guide.close();
    }
  }
}

function press(key, flush = true) {
  const event = { key: key.toLowerCase(),
    modifiers: { shift: key === 'V' || key === 'G' }, keystroke: key, is_held: false };
  // Native named keys have no key_char; it is the printable character only.
  if (key.length === 1) event.key_char = key;
  guide.key(event, cx);
  if (flush) drain();
}
const selected = () => scene.terminals[0].selection;
let count = 0, failures = 0;
function test(name, fn) {
  try { fn(); console.log(`ok ${++count} - ${name}`); }
  catch (error) { failures++; console.error(`not ok ${++count} - ${name}\n${error.stack}`); }
}

test('First motion moves a collapsed cursor, not a selected range', () => {
  fresh(); press('h');
  assert.deepEqual(selected(), range(10, 4));
});
test('Repeated motion progresses using the published moving endpoint', () => {
  fresh(); press('h'); press('h');
  assert.deepEqual(selected(), range(10, 3));
});
test('Moving then selecting and yanking copies the intended cells', () => {
  fresh(); ['h', 'h', 'v', 'l', 'y'].forEach(key => press(key));
  assert.deepEqual(scene.clipboard.selection, range(10, 3, 10, 4));
  assert.equal(scene.clipboard.text, 'AB');
  assert.equal(selected(), null);
  assert.equal(scene.closed, true);
});
test('A rapid key burst has the same result as individually drained keys', () => {
  fresh(); ['h', 'h', 'v', 'l', 'y'].forEach(key => press(key, false)); drain();
  assert.deepEqual(scene.clipboard.selection, range(10, 3, 10, 4));
  assert.equal(scene.clipboard.text, 'AB');
  assert.equal(selected(), null);
  assert.equal(scene.closed, true);
});
test('Direct visual selection still copies and clears', () => {
  fresh(); ['v', 'l', 'y'].forEach(key => press(key));
  assert.deepEqual(scene.clipboard.selection, range(10, 5, 10, 6));
  assert.equal(scene.clipboard.text, 'CD');
  assert.equal(selected(), null);
});
test('An unchanged endpoint at a boundary cannot wedge following commands', () => {
  fresh({ cursor: point(0, 0) });
  ['h', 'l', 'v', 'l', 'y'].forEach(key => press(key, false)); drain();
  assert.deepEqual(scene.clipboard.selection, range(0, 1, 0, 2));
  assert.equal(scene.closed, true);
});
test('Existing native selection is preserved and extended on entry', () => {
  fresh({ selection: range(8, 2, 8, 4) }); press('l');
  assert.deepEqual(selected(), range(8, 2, 8, 5));
});
test('Live selection wins over a stale target snapshot', () => {
  fresh({ selection: range(8, 2, 8, 4), target: {
    terminal: 'term1', pane: 'pane1', tab: 'tab1', space: 'space1', selection: null,
  } }); press('l');
  assert.deepEqual(selected(), range(8, 2, 8, 5));
});
test('v resets the anchor at the current native moving endpoint', () => {
  fresh({ selection: range(8, 2, 8, 4) }); press('v'); press('l');
  assert.deepEqual(selected(), range(8, 4, 8, 5));
});
test('V retains native line selection while subsequent movement extends it', () => {
  fresh(); press('V'); press('j'); press('y');
  assert.deepEqual(scene.clipboard.selection, range(10, 0, 11, columns - 1));
  assert.equal(scene.clipboard.text, `${rows[10]}\n${rows[11]}`);
  assert.equal(scene.calls.filter(([name, args]) => name === 'terminal.select' && args.mode === 'line').length, 1);
});
test('Escape cancels a pending move and ignores its outstanding replies', () => {
  fresh(); press('h', false); press('escape', false); drain();
  assert.equal(scene.closed, true);
  assert.equal(selected(), null);
  assert.equal(scene.clipboard, null);
  const calls = scene.calls.length;
  if (guide.command) for (const reply of scene.replies) guide.command(reply, cx);
  drain();
  assert.equal(scene.calls.length, calls, 'Stale replies must not restart selection after closing');
});
// Native macOS Escape is key="escape" (gpui-pre-macos/src/events.rs:434).
// The mod bridge preserves key/modifiers and omits a character when absent
// (gpui-kit/crates/shell/src/engine/quickjs/mod.rs:4481-4487). Ctrl-[ becomes
// an Escape byte only in the terminal encoder (src/terminal.rs:4656); a mod
// must explicitly support that Vim alias. These tests exercise the callback
// payload and queued teardown, not native focus or event routing.
const cancellations = [
  ['Escape', { key: 'escape', keystroke: 'escape', modifiers: {} }],
  ['Ctrl-[', { key: '[', keystroke: 'ctrl-[', modifiers: { control: true } }],
  ['Ctrl-c', { key: 'c', keystroke: 'ctrl-c', modifiers: { control: true } }],
];
for (const [name, event] of cancellations) {
  for (const state of ['before selection', 'after selection', 'during a queued move']) {
    test(`${name} cancels ${state} using its native event payload`, () => {
      fresh();
      if (state === 'after selection') { press('v'); press('l'); }
      if (state === 'during a queued move') press('h', false);
      assert.equal(event.key_char, undefined);
      guide.key({ ...event, is_held: false }, cx);
      drain();
      assert.equal(scene.closed, true, `${name} must close the copy window`);
      assert.equal(selected(), null, `${name} must clear the captured selection`);
      assert.equal(scene.clipboard, null, 'Cancel must not copy');
      assert.deepEqual(scene.terminals[1].selection, range(2, 1, 2, 3));
    });
  }
}
test('Yank and cleanup use the captured terminal after focus changes', () => {
  fresh(); press('v'); press('l');
  scene.focus = { terminal: 'term2', pane: 'pane2', tab: 'tab2', space: 'space2' };
  press('y');
  assert.equal(scene.clipboard.terminal, 'term1');
  assert.deepEqual(scene.clipboard.selection, range(10, 5, 10, 6));
  assert.deepEqual(scene.terminals[1].selection, range(2, 1, 2, 3));
});
test('Target props survive focus changing during overlay creation', () => {
  fresh({ target: { terminal: 'term2', pane: 'pane2', tab: 'tab2', space: 'space2' } });
  press('l'); press('y');
  assert.equal(scene.clipboard.terminal, 'term2');
  assert.deepEqual(scene.clipboard.selection, range(2, 1, 2, 4));
  assert.equal(selected(), null);
});

console.log(`${count - failures}/${count} queued copy checks passed`);
process.exitCode = failures ? 1 : 0;
