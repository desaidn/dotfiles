// Keep the keyboard and clickable command entry points on the same interface.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const app = process.argv[2];
const keys = JSON.parse(fs.readFileSync(path.join(app, 'keys.json'), 'utf8'));

let count = 0;
function test(name, fn) {
  fn();
  console.log(`ok ${++count} - ${name}`);
}

test('Ctrl-b is the only Herdr global command shortcut', () => {
  assert.deepEqual(Object.keys(keys).sort(), ['global', 'terminal']);
  assert.deepEqual(keys.global, { 'ctrl-b': 'mod.open:keyboard-guide' });
});

test('Terminal clipboard and native editing bindings stay intact', () => {
  assert.deepEqual(keys.terminal, {
    'cmd-a': 'terminal.select_all',
    'cmd-c': 'terminal.copy',
    'cmd-v': 'terminal.paste',
    'ctrl-v': 'terminal.paste_image',
    'alt-left': 'send:\u001bb',
    'alt-right': 'send:\u001bf',
    'alt-backspace': 'send:\u0017',
    'cmd-left': 'send:\u0001',
    'cmd-right': 'send:\u0005',
    'cmd-backspace': 'send:\u0015',
  });
});

// Retain the rendered text and events while leaving presentation methods inert.
function element() {
  const node = { nodeId: null, children: [], events: {} };
  let builder;
  builder = new Proxy(node, { get(target, key) {
    if (key === 'id') return id => { node.nodeId = id; return builder; };
    if (key === 'child') return child => { node.children.push(child); return builder; };
    if (key === 'when') return (condition, fn) => condition ? fn(builder) : builder;
    if (key.startsWith('on_')) return handler => { node.events[key] = handler; return builder; };
    if (key in target) return target[key];
    return () => builder;
  } });
  return builder;
}
function walk(node) {
  return typeof node === 'object' && node ? [node, ...node.children.flatMap(walk)] : [];
}
function text(node) {
  return typeof node === 'object' && node ? node.children.map(text).join('') : String(node);
}

test('Footer advertises Ctrl-b and opens the same command guide when clicked', () => {
  const file = path.join(app, 'mods/keyboard-status/main.js');
  const source = fs.readFileSync(file, 'utf8')
    .replace(/^import[\s\S]*?from "[^"]+";\n/gm, '')
    .replace('export default class WorkspaceStatus', 'class WorkspaceStatus');
  const calls = [];
  const api = {
    View: class {}, div: element, h_flex: element, svg: element,
    spaces: () => [{ active: true, machine: null, branch: 'main' }],
    agents: () => [{ status: 'blocked' }, { status: 'working' }],
    theme: () => ({}),
    run: (command, args) => calls.push([command, JSON.parse(JSON.stringify(args))]),
  };
  vm.createContext(api);
  vm.runInContext(`${source}\nglobalThis.Footer = WorkspaceStatus;`, api, { filename: file });
  const tree = new api.Footer().render();
  const controls = walk(tree).filter(node => node.events.on_click);
  assert.equal(controls.length, 1, 'Footer should have one command entry point');
  assert.equal(text(controls[0]), 'Ctrl-b  commands');
  controls[0].events.on_click();
  assert.deepEqual(calls, [['mod.open', { name: 'keyboard-guide' }]]);
  assert.equal(keys.global['ctrl-b'], `${calls[0][0]}:${calls[0][1].name}`);
  assert.match(text(tree), /This computer/);
  assert.match(text(tree), /main/);
  assert.match(text(tree), /2 agents/);
  assert.match(text(tree), /1 needs you/);
});

console.log(`${count} command entry-point checks passed`);
