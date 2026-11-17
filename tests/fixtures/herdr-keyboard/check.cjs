// A native-JavaScript fixture for the Herdr mod; no desktop or terminal input.
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');

// Herdr owns these module imports. Replace only the imports/export wrappers;
// the production class and its handlers run unchanged against API doubles.
const source = fs.readFileSync(process.argv[2], 'utf8')
  .replace(/^import[\s\S]*?from "[^"]+";\n/gm, '')
  .replace('export function keyName', 'function keyName')
  .replace('export default class KeyboardGuide', 'class KeyboardGuide');
const element = new Proxy({}, { get: () => () => element });
let scene;
const tasks = [];
const cx = {
  notify() {}, stop_propagation() {},
  focus_handle: () => ({ focus() {} }),
  spawn: fn => tasks.push(fn(cx)),
};

function run(command, args = {}) {
  scene.calls.push([command, args]);
  const terminal = scene.terminals.find(t => t.address === args.terminal);
  if (command === 'terminal.select' && terminal) {
    const at = args.at === 'cursor' || !args.at ? { row: 10, col: 5 } : args.at;
    terminal.selection = { start: { ...at }, end: { ...at } };
  }
  if (command === 'terminal.adjust_selection' && terminal?.selection) {
    const end = terminal.selection.end;
    const delta = { left: [0, -1], right: [0, 1], up: [-1, 0], down: [1, 0] }[args.direction];
    if (delta) terminal.selection.end = { row: end.row + delta[0], col: end.col + delta[1] };
  }
  if (command === 'terminal.clear_selection' && terminal) terminal.selection = null;
}

const sandbox = {
  View: class {}, div: () => element, v_flex: () => element, h_flex: () => element,
  agents: () => scene.agents, spaces: () => scene.spaces, panes: () => scene.panes,
  terminals: () => scene.terminals, focused: () => scene.focus,
  props: () => ({ overlay: 'guide' }), closeOverlay: () => scene.closed++,
  openOverlay: spec => scene.overlays.push(spec), run, theme: () => ({}), checking: () => scene.checking,
  hc: async args => { scene.calls.push(['hc', args]); return { code: 0 }; },
  window: { viewport_size: () => ({ width: 1200, height: 800 }) },
  settings: () => ({ zoom: 1 }),
};
vm.createContext(sandbox);
vm.runInContext(source + '\nglobalThis.api = { KeyboardGuide, keyName };', sandbox);
const { KeyboardGuide, keyName } = sandbox.api;
const event = (key, modifiers = {}, key_char) => ({ key, modifiers, key_char, keystroke: key });
const press = (guide, key, modifiers, typed) => guide.key(event(key, modifiers, typed), cx);

function fresh() {
  scene = {
    calls: [], closed: 0, overlays: [], checking: true,
    focus: { space: 's1', tab: 't1', pane: 'p1', terminal: 'term1', cwd: '/tmp' },
    agents: Array.from({ length: 9 }, (_, i) => ({
      address: `a${i + 1}`, pinned: false, space_name: 'one', tab_name: '1', status: 'idle',
    })),
    terminals: [{ address: 'term1', state: 'live', selection: null }],
    spaces: [{ id: 's1', name: 'one', active: true, tabs: [
      { id: 't1', name: '1', active: true }, { id: 't2', name: '2' },
    ] }],
    panes: [{ pane: 'p1', tab: 't1' }, { pane: 'p2', tab: 't1' }],
  };
  const guide = new KeyboardGuide();
  guide.init({}, cx);
  return guide;
}

let count = 0;
function test(name, fn) {
  fn();
  console.log(`ok ${++count} - ${name}`);
}

test('Vim directions retain their meanings', () => {
  for (const [key, direction] of Object.entries({ h: 'left', j: 'down', k: 'up', l: 'right' })) {
    const guide = fresh();
    press(guide, key);
    assert.equal(scene.calls[0][0], 'pane.go');
    assert.equal(scene.calls[0][1].direction, direction);
    assert.equal(scene.closed, 1);
  }
});
test('Shift-5 and percent choose agent 5, never a split', () => {
  for (const key of [event('5', { shift: true }, '%'), event('%', {}, '%')]) {
    const guide = fresh();
    guide.key(key, cx);
    assert.equal(scene.calls[0][0], 'agent.focus');
    assert.equal(scene.calls[0][1].terminal, 'a5');
  }
});
test('Numbers choose tabs; a missing number explains without dismissing', () => {
  let guide = fresh();
  press(guide, '2');
  assert.equal(scene.calls[0][1].id, 't2');
  guide = fresh();
  press(guide, '9');
  assert.equal(scene.calls.length, 0);
  assert.equal(scene.closed, 0);
  assert.match(guide.message, /No tab 9/);
});
test('Navigation stays open through several moves and Enter returns', () => {
  const guide = fresh();
  press(guide, 'g');
  assert.equal(guide.mode, 'navigate');
  press(guide, 'up');
  press(guide, 'k');
  assert.equal(scene.calls[0][0], 'space.prev');
  assert.equal(scene.calls[1][1].direction, 'up');
  assert.equal(scene.closed, 0);
  press(guide, 'enter');
  assert.equal(scene.closed, 1);
});
test('Tab cycles panes within the current tab', () => {
  for (const shift of [false, true]) {
    const guide = fresh();
    scene.panes.push({ pane: 'unrelated', tab: 'another-tab' });
    press(guide, 'tab', { shift });
    assert.equal(scene.calls[0][0], 'pane.focus');
    assert.equal(scene.calls[0][1].pane, 'p2');
  }
});
test('Close confirmation stays attached to its original target', () => {
  const guide = fresh();
  press(guide, 'x');
  assert.equal(scene.calls.length, 0);
  assert.equal(guide.mode, 'confirm');
  scene.focus.pane = 'p2';
  press(guide, 'enter');
  assert.equal(scene.calls[0][1].pane, 'p1');
});
test('Cancel never closes terminal work', () => {
  const guide = fresh();
  press(guide, 'x');
  press(guide, 'escape');
  assert.equal(scene.calls.length, 0);
  assert.equal(scene.closed, 1);
});
test('Split aliases and shifted punctuation normalize correctly', () => {
  for (const key of [event('v'), event('-'), event("'", { shift: true }, '"')]) {
    const guide = fresh();
    guide.key(key, cx);
    assert.equal(scene.calls[0][0], 'pane.split');
  }
  assert.equal(keyName(event(';', { shift: true }, ':')), ':');
});
test('Missing app capabilities explain their limits without acting', () => {
  const guide = fresh();
  press(guide, 'r');
  assert.match(guide.message, /no keyboard pane-resize/);
  assert.equal(scene.calls.length, 0);
  assert.equal(scene.closed, 0);
});
test('Copy mode opens a compact strip without terminal input', () => {
  const guide = fresh();
  press(guide, '[');
  assert.equal(scene.overlays[0].props.mode, 'copy');
  assert.ok(scene.overlays[0].height < 180);
  assert.equal(scene.calls.length, 0);
});
// Selection movement and yank cross run()'s asynchronous native boundary.
// copy.cjs owns those regressions with queued commands and published snapshots.
test('Copy mode can still be escaped after its terminal exits', () => {
  const guide = fresh();
  guide.mode = 'copy';
  scene.terminals = [];
  press(guide, 'escape');
  assert.equal(scene.closed, 1);
});
test('Copy Backspace returns to the full guide', () => {
  const guide = fresh();
  guide.mode = 'copy';
  press(guide, 'backspace');
  assert.equal(scene.closed, 1);
  assert.equal(scene.calls.at(-1)[0], 'mod.open');
  assert.equal(scene.calls.at(-1)[1].name, 'keyboard-guide');
});
test('Closing a copy window clears only its captured selection', () => {
  const guide = fresh();
  guide.mode = 'copy';
  press(guide, 'v');
  guide.close();
  assert.equal(scene.terminals[0].selection, null);
  assert.equal(scene.calls.at(-1)[1].terminal, 'term1');
});
test('Unmapped and modified keys never invoke a prefix action', () => {
  for (const key of [event('f'), event('c', { control: true }), event('v', { alt: true })]) {
    const guide = fresh();
    guide.key(key, cx);
    assert.equal(scene.calls.length, 0);
  }
});
test('Every mode renders, including an empty workspace', () => {
  for (const mode of ['root', 'navigate', 'agents', 'copy', 'confirm', 'help']) {
    const guide = fresh();
    guide.mode = mode;
    guide.render(cx);
    scene.focus = null;
    scene.spaces = [];
    scene.agents = [];
    guide.render(cx);
  }
});
async function checkLiteralPrefix() {
  const guide = fresh();
  scene.checking = false;
  press(guide, 'b', { control: true });
  await Promise.all(tasks);
  assert.deepEqual(Array.from(scene.calls[0][1]), ['keys', 'term1', 'ctrl+b']);
  assert.equal(scene.closed, 1);
  console.log(`ok ${++count} - Literal prefix targets only the captured terminal`);
  console.log(`${count} behavior checks passed`);
}
checkLiteralPrefix().catch(error => { console.error(error); process.exitCode = 1; });
