// Exercise the actual badge renderers and prefix handler against the same model.
// This is a behavior fixture for Herdr's native JavaScript mods, not a UI driver.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const mods = process.argv[2];
let scene;

// Keep children, IDs, and callbacks; presentation-only builder methods are inert.
// In particular, .when() must behave like GPUI or hidden badges could pass tests.
function element(kind) {
  const node = { kind, nodeId: null, nodes: [], events: {}, attributes: {} };
  let builder;
  builder = new Proxy(node, { get(target, key) {
    if (key in target) return target[key];
    if (key === 'id') return value => { node.nodeId = value; return builder; };
    if (key === 'child') return child => {
      assert.notEqual(child, null, 'GPUI .child() does not accept null');
      assert.notEqual(child, undefined, 'GPUI .child() does not accept undefined');
      node.nodes.push(child);
      return builder;
    };
    if (key === 'children') return children => { node.nodes.push(...children.filter(child => child != null)); return builder; };
    if (key === 'when') return (condition, fn) => condition ? fn(builder) : builder;
    if (key.startsWith('on_')) return (...args) => { node.events[key] = args.at(-1); return builder; };
    return (...args) => { node.attributes[key] = args; return builder; };
  } });
  return builder;
}

const cx = {
  notify() {}, stop_propagation() {}, timer: { every() {} },
  focus_handle: () => ({ focus() {} }),
  spawn: () => { throw new Error('Numbering checks must not start background tasks'); },
};
const api = {
  View: class {},
  ...Object.fromEntries(['div', 'v_flex', 'h_flex', 'svg', 'image'].map(kind => [kind, () => element(kind)])),
  ScrollHandle: { new: () => ({ scroll_to_item() {} }) },
  agents: () => scene.agents, terminals: () => scene.terminals, panes: () => scene.panes,
  spaces: () => scene.spaces, focused: () => scene.focus, props: () => scene.props,
  theme: () => ({ background: '#0e0e0e', foreground: '#ffffff', accent: '#8abeb7' }),
  window: () => ({ platform: 'macos' }), settings: () => ({ zoom: 1 }),
  layout: () => ({ children: [{ id: 'sidebar', size: { px: scene.sidebarWidth } }] }),
  shared: key => scene.shared[key], setShared: (key, value) => { scene.shared[key] = value; },
  setAgentOrder: order => { scene.displayOrder = Array.from(order); },
  run: (command, args = {}) => scene.calls.push([command, JSON.parse(JSON.stringify(args))]),
  openOverlay() {}, closeOverlay: () => scene.closed++, checking: () => true,
  localStorage: {
    getItem: key => scene.storage.get(key) ?? null,
    setItem: (key, value) => scene.storage.set(key, value),
    removeItem: key => scene.storage.delete(key),
  },
};

function load(name, className) {
  const filename = path.join(mods, name, 'main.js');
  const source = fs.readFileSync(filename, 'utf8')
    .replace(/^import[\s\S]*?from "[^"]+";\n/gm, '')
    .replace(/^export function /gm, 'function ')
    .replace(`export default class ${className}`, `class ${className}`);
  const context = vm.createContext({ ...api });
  vm.runInContext(`${source}\nglobalThis.Mod = ${className};`, context, { filename });
  return context.Mod;
}
const Tabs = load('keyboard-tabs', 'Tabs');
const Agents = load('keyboard-agents', 'Agents');
const KeyboardGuide = load('keyboard-guide', 'KeyboardGuide');

function fresh() {
  scene = {
    agents: [], terminals: [], panes: [], calls: [], closed: 0, storage: new Map(),
    sidebarWidth: 268, shared: { 'agents.sort': 'priority' }, props: { overlay: 'test' },
    focus: { space: 's1', tab: 't1', pane: 'p1', terminal: 'term1' },
    spaces: [{ id: 's1', name: 'One', active: true, tabs: [] }, { id: 's2', name: 'Two', tabs: [] }],
  };
}
function view(Class) { const instance = new Class(); instance.init({}, cx); return instance; }
function walk(tree) {
  if (typeof tree !== 'object' || !tree) return [];
  return [tree, ...tree.nodes.flatMap(walk)];
}
function containingRow(tree, badge, kind, parent = null) {
  if (typeof tree !== 'object' || !tree) return null;
  const rowPrefix = kind === 'tab' ? /^tab-(?!key-|scroll$)/ : /^(ag-|sub-)/;
  const row = rowPrefix.test(tree.nodeId ?? '') ? tree : parent;
  if (tree === badge) return row;
  for (const child of tree.nodes) {
    const found = containingRow(child, badge, kind, row);
    if (found) return found;
  }
  return null;
}
function find(tree, id) {
  const node = walk(tree).find(node => node.nodeId === id);
  assert.ok(node, `Expected rendered ${id}`);
  return node;
}
function text(tree) {
  return typeof tree === 'object' && tree ? tree.nodes.map(text).join('') : String(tree);
}
function press(guide, key, shift = false) {
  guide.key({ key, keystroke: key, modifiers: { shift } }, cx);
}
function dispatch(number, agent, chooser = false) {
  const guide = view(KeyboardGuide);
  scene.calls = [];
  if (chooser) press(guide, 'a');
  press(guide, String(number), agent && !chooser);
  assert.equal(scene.calls.length, 1, `Badge ${number} should dispatch exactly once`);
  return scene.calls[0];
}
function badges(tree, prefix) {
  return walk(tree).filter(node => node.nodeId?.startsWith(prefix));
}
function checkBadges(tree, kind, expected) {
  const agent = kind === 'agent', prefix = `${kind}-key-`;
  const rendered = badges(tree, prefix);
  const actual = {};
  for (const badge of rendered) {
    const target = badge.nodeId.slice(prefix.length);
    const row = containingRow(tree, badge, kind);
    assert.equal(row?.nodeId.replace(kind === 'tab' ? /^tab-/ : /^(ag-|sub-)/, ''), target,
      'Badge must be inside the row for the terminal or tab it advertises');
    const number = text(badge);
    actual[target] = number;
    assert.match(number, agent ? /^⇧[1-9]$/ : /^[1-9]$/, 'Badge must name a supported key');
    const digit = Number(number.replace('⇧', ''));
    assert.deepEqual(dispatch(digit, agent), agent
      ? ['agent.focus', { terminal: target }] : ['tab.select', { id: target }],
    `Visible ${number} must focus the row carrying that badge`);
    if (agent) assert.deepEqual(dispatch(digit, true, true), ['agent.focus', { terminal: target }],
      `Agent chooser ${digit} must agree with the sidebar`);
  }
  assert.deepEqual(actual, expected, 'Visible badge coverage and values');
}
function addAgent(address, status, space = 's1', extras = {}) {
  const tab = `tab-${address}`;
  const agent = { address, status, space, space_name: space === 's1' ? 'One' : 'Two',
    tab, tab_name: address, pane: `pane-${address}`, seq: scene.agents.length,
    program: { agent: true, name: 'Codex', key: 'codex' }, ...extras };
  scene.agents.push(agent);
  scene.spaces.find(s => s.id === space).tabs.push({ id: tab, name: address, named: true });
  scene.panes.push({ ...agent, terminal: address });
  scene.terminals.push({ ...agent, state: 'live' });
  return agent;
}
function switchSort(sidebar, sort) {
  scene.props = { sortMenu: true, overlay: 'sort' };
  find(sidebar.render(cx), `sort-${sort}`).events.on_click({}, cx);
  scene.props = { overlay: 'test' };
  return sidebar.render(cx);
}

let count = 0;
function test(name, fn) { fresh(); fn(); console.log(`ok ${++count} - ${name}`); }

test('Tab badges and digit dispatch follow live tabs through reorder and settlement', () => {
  scene.spaces[0].tabs = [
    { id: 'old', name: 'Old', settled: true }, { id: 't1', name: 'Editor', active: true },
    { id: 't2', name: 'Build' }, { id: 'archived', name: 'Archived', settled: true },
    { id: 't3', name: 'Logs' },
  ];
  const tabs = view(Tabs);
  let tree = tabs.render(cx);
  find(tree, 'tab-old'); // Still visible, but intentionally has no shortcut.
  checkBadges(tree, 'tab', { t1: '1', t2: '2', t3: '3' });
  scene.spaces[0].tabs = [scene.spaces[0].tabs[4], scene.spaces[0].tabs[1], scene.spaces[0].tabs[2]];
  scene.spaces[0].tabs[1].settled = true;
  tree = tabs.render(cx);
  checkBadges(tree, 'tab', { t3: '1', t2: '2' });
});

test('Tab badges change with the active space and stop at nine', () => {
  scene.spaces[0].tabs = [{ id: 't1', name: 'One' }];
  scene.spaces[1].tabs = Array.from({ length: 11 }, (_, i) => ({ id: `other${i + 1}`, name: `Other ${i + 1}` }));
  const tabs = view(Tabs);
  checkBadges(tabs.render(cx), 'tab', { t1: '1' });
  scene.spaces[0].active = false;
  scene.spaces[1].active = true;
  scene.focus = { ...scene.focus, space: 's2', tab: 'other1' };
  const tree = tabs.render(cx);
  find(tree, 'tab-other10');
  find(tree, 'tab-other11');
  checkBadges(tree, 'tab', { other1: '1', other2: '2', other3: '3', other4: '4', other5: '5',
    other6: '6', other7: '7', other8: '8', other9: '9' });
});

test('Agent badges remain attached to targets when status changes reorder priority rows', () => {
  const idle = addAgent('idle', 'idle');
  const busy = addAgent('busy', 'working');
  const blocked = addAgent('remote/blocked', 'blocked', 's2');
  const done = addAgent('done', 'done', 's2');
  const sidebar = view(Agents);
  const expected = { idle: '⇧1', busy: '⇧2', 'remote/blocked': '⇧3', done: '⇧4' };
  checkBadges(sidebar.render(cx), 'agent', expected);
  assert.deepEqual(scene.displayOrder, ['remote/blocked', 'done', 'busy', 'idle']);
  idle.status = 'blocked'; busy.status = 'done'; blocked.status = 'idle'; done.status = 'working';
  checkBadges(sidebar.render(cx), 'agent', expected);
  assert.deepEqual(scene.displayOrder, ['idle', 'busy', 'done', 'remote/blocked']);
});

test('Pin changes renumber both sidebar and guide, independently of priority order', () => {
  const first = addAgent('first', 'blocked');
  const pin = addAgent('pin', 'idle', 's2', { pinned: true });
  addAgent('last', 'done', 's2');
  const sidebar = view(Agents);
  checkBadges(sidebar.render(cx), 'agent', { pin: '⇧1', first: '⇧2', last: '⇧3' });
  pin.pinned = false; first.pinned = true;
  checkBadges(sidebar.render(cx), 'agent', { first: '⇧1', pin: '⇧2', last: '⇧3' });
});

test('Grouped, folded, and collapsed sidebar presentations keep the same key targets', () => {
  addAgent('one', 'idle'); addAgent('two', 'blocked'); addAgent('three', 'working', 's2');
  const sidebar = view(Agents);
  const expected = { one: '⇧1', two: '⇧2', three: '⇧3' };
  checkBadges(sidebar.render(cx), 'agent', expected);
  let tree = switchSort(sidebar, 'grouped');
  assert.deepEqual(scene.displayOrder, ['one', 'two', 'three']);
  checkBadges(tree, 'agent', expected);
  find(tree, 'sp-s1').events.on_click({}, cx);
  tree = sidebar.render(cx);
  checkBadges(tree, 'agent', { three: '⇧3' });
  find(tree, 'sp-s1').events.on_click({}, cx);
  checkBadges(sidebar.render(cx), 'agent', expected);
  scene.sidebarWidth = 76;
  checkBadges(sidebar.render(cx), 'agent', expected);
  checkBadges(switchSort(sidebar, 'priority'), 'agent', expected);
});

test('Kept child badges target the child; unlisted background children have no digit', () => {
  addAgent('parent', 'idle');
  const child = addAgent('child', 'working', 's1', { parent: 'parent' });
  addAgent('peer', 'done', 's2');
  scene.terminals.push({ address: 'background', parent: 'parent', state: 'live', status: 'blocked', name: 'Worker' });
  const sidebar = view(Agents);
  let tree = sidebar.render(cx);
  const expected = { parent: '⇧1', child: '⇧2', peer: '⇧3' };
  find(find(tree, 'sub-child'), 'agent-key-child');
  assert.equal(badges(find(tree, 'sub-background'), 'agent-key-').length, 0);
  checkBadges(tree, 'agent', expected);
  find(tree, 'fold-parent').events.on_click({}, cx);
  checkBadges(sidebar.render(cx), 'agent', { parent: '⇧1', peer: '⇧3' });
  scene.sidebarWidth = 76;
  tree = sidebar.render(cx);
  find(find(tree, 'ag-child'), 'agent-key-child');
  checkBadges(tree, 'agent', expected);
  scene.sidebarWidth = 268;
  child.pinned = true;
  checkBadges(sidebar.render(cx), 'agent', { child: '⇧1', parent: '⇧2', peer: '⇧3' });
});

test('More than nine agents remain visible without advertising unsupported digits', () => {
  for (let i = 1; i <= 12; i++) addAgent(`a${i}`, i % 2 ? 'idle' : 'blocked', i <= 6 ? 's1' : 's2');
  const sidebar = view(Agents);
  const expected = { a1: '⇧1', a2: '⇧2', a3: '⇧3', a4: '⇧4', a5: '⇧5', a6: '⇧6', a7: '⇧7', a8: '⇧8', a9: '⇧9' };
  for (const width of [268, 76]) {
    scene.sidebarWidth = width;
    const tree = sidebar.render(cx);
    for (const address of ['a10', 'a11', 'a12']) {
      assert.equal(badges(find(tree, `ag-${address}`), 'agent-key-').length, 0);
    }
    checkBadges(tree, 'agent', expected);
  }
});

test('Empty tab and agent models render without phantom shortcut badges', () => {
  scene.spaces = [];
  scene.focus = null;
  checkBadges(view(Tabs).render(cx), 'tab', {});
  checkBadges(view(Agents).render(cx), 'agent', {});
});

console.log(`${count} rendered numbering checks passed`);
