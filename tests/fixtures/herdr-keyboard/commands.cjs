// Drive the production guide through native-input change/submit callbacks.
// No application, subprocess, clipboard, or terminal IO is used by this fixture.
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const source = fs.readFileSync(process.argv[2], 'utf8')
  .replace(/^import[\s\S]*?from "[^"]+";\n/gm, '')
  .replace('export function keyName', 'function keyName')
  .replace('export default class KeyboardGuide', 'class KeyboardGuide');
const clone = value => JSON.parse(JSON.stringify(value));
let scene, guide;

function element() {
  const node = { nodeId: null, nodes: [], events: {} };
  let builder;
  builder = new Proxy(node, { get(target, key) {
    if (key in target) return target[key];
    if (key === 'id') return id => { node.nodeId = id; return builder; };
    if (key === 'child') return child => {
      assert.ok(child != null, 'GPUI children cannot be null or undefined');
      node.nodes.push(child); return builder;
    };
    if (key === 'children') return children => { node.nodes.push(...children); return builder; };
    if (key === 'when') return (condition, fn) => condition ? fn(builder) : builder;
    if (key.startsWith('on_')) return handler => { node.events[key] = handler; return builder; };
    return () => builder;
  } });
  return builder;
}
function walk(node) { return typeof node === 'object' && node ? [node, ...node.nodes.flatMap(walk)] : []; }
function text(node) { return typeof node === 'object' && node ? node.nodes.map(text).join(' ') : String(node); }

class NativeInput {
  constructor(options) { this.options = options; this.text = ''; this.events = {}; }
  on(name, callback) { this.events[name] = callback; }
  value() { return this.text; }
  focus() { scene.inputFocus++; }
  type(value) { this.text = value; this.events.change({}, cx); }
  submit() { this.events.submit({}, cx); }
}
const cx = {
  notify() {}, stop_propagation: () => scene.stopped++,
  focus_handle: () => ({ focus: () => scene.guideFocus++ }),
  spawn: fn => scene.tasks.push(fn(cx)),
};
const nativeNames = `space.new space.close space.rename space.move space.select space.next space.prev
tab.new tab.close tab.rename tab.move tab.select tab.settle tab.unsettle tab.next tab.prev
pane.split pane.close pane.zoom pane.focus pane.go pane.swap terminal.open terminal.keep terminal.park
terminal.right_click terminal.pin terminal.kill terminal.peek terminal.show terminal.select_all terminal.select
terminal.adjust_selection terminal.clear_selection terminal.copy terminal.scroll terminal.paste terminal.paste_image
terminal.search agent.focus agent.next agent.prev layout.switch layout.clone mod.clone layout.set layout.toggle
layout.show layout.hide layout.resize layout.select layout.reset mod.open overlay.close app.help app.welcome
app.whats_new app.feedback app.palette app.settings app.check_updates app.update_core app.reset app.theme
app.zoom_in app.zoom_out app.zoom_reset app.update app.quit app.hide app.hide_others app.show_all
window.close window.minimize window.maximize`.split(/\s+/);
const api = {
  View: class {}, div: element, v_flex: element, h_flex: element,
  InputState: { new: options => new NativeInput(options) }, Input: { new: () => element() },
  agents: () => scene.agents, spaces: () => scene.spaces, panes: () => scene.panes,
  terminals: () => scene.terminals, focused: () => clone(scene.focus),
  props: () => scene.props, closeOverlay: () => scene.closed++,
  openOverlay: spec => scene.overlays.push(clone(spec)),
  run: (command, args = {}) => scene.calls.push([command, clone(args)]),
  theme: () => ({}), checking: () => true,
  commands: () => scene.commands, layouts: () => scene.layouts, themes: () => scene.themes,
  shared: key => key === 'layout' ? scene.layout : null,
  window: Object.assign(() => ({ platform: 'macos' }), { viewport_size: () => ({ width: 1200, height: 800 }) }),
  settings: () => ({ zoom: 1 }),
  exec: (program, args, options) => new Promise((resolve, reject) => {
    scene.probes.push({ program, args: clone(args), options: clone(options), resolve, reject });
  }),
};
vm.createContext(api);
vm.runInContext(`${source}\nglobalThis.Guide = KeyboardGuide;`, api);

function fresh(props = {}) {
  scene = {
    calls: [], closed: 0, overlays: [], stopped: 0, inputFocus: 0, guideFocus: 0,
    tasks: [], probes: [],
    props: { overlay: 'guide', ...props },
    commands: nativeNames.map(name => ({ name, args: [], about: '' })),
    layouts: ['main', 'keyboard'], themes: [{ name: 'terminal' }, { name: 'ink' }], layout: 'keyboard',
    focus: { space: 's1', tab: 't1', pane: 'p1', terminal: 'term1', agent: 'term1', cwd: '/tmp' },
    agents: [{ address: 'term1', pinned: false, space_name: 'One', tab_name: 'Editor', status: 'idle' }],
    terminals: [{ address: 'term1', state: 'live', selection: null }],
    spaces: [{ id: 's1', name: 'One', active: true, machine: null, tabs: [
      { id: 't1', name: 'Editor', active: true }, { id: 't2', name: 'Build' },
    ] }, { id: 'remote/s2', name: 'Server', machine: 'remote', tabs: [
      { id: 'remote/t3', name: 'Logs', settled: true },
    ] }],
    panes: [{ pane: 'p1', tab: 't1', terminal: 'term1' }, { pane: 'p2', tab: 't1' }, { pane: 'p3', tab: 't1' }],
  };
  guide = new api.Guide();
  guide.init({}, cx);
  return guide;
}
function press(key, modifiers = {}, key_char) {
  guide.key({ key, modifiers, key_char, keystroke: key }, cx);
}
function search(query = '') {
  if (guide.mode !== 'commands') press(':');
  guide.input.type(query);
  return guide.searchRows();
}
function choose(label, query = label) {
  const rows = search(query);
  const index = rows.findIndex(row => row.label === label);
  assert.ok(index >= 0, `Search should expose ${label}`);
  for (let i = 0; i < index; i++) press('down');
  guide.input.submit();
}
function forbidExternalPalette() {
  assert.ok(scene.calls.every(([name, args]) => !['app.palette', 'app.help'].includes(name)
    && !(name === 'mod.open' && args.name === 'picker')));
}
let count = 0;
function test(name, fn) { fresh(); fn(); console.log(`ok ${++count} - ${name}`); }

test('Colon opens command search directly', () => {
  for (const event of [[':'], [';', { shift: true }, ':']]) {
    fresh();
    press(...event);
    assert.equal(guide.mode, 'commands');
    assert.equal(guide.query, '');
    assert.ok(scene.inputFocus > 0);
    assert.ok(guide.searchRows().length > 0);
    guide.input.type('focus pane right');
    guide.input.submit();
    assert.deepEqual(scene.calls, [['pane.go', { direction: 'right' }]]);
    forbidExternalPalette();
  }
});

test('Question mark no longer opens command search or help', () => {
  for (const event of [['?'], ['/', { shift: true }, '?']]) {
    fresh();
    press(...event);
    assert.equal(guide.mode, 'root');
    assert.equal(scene.inputFocus, 0);
    assert.equal(scene.closed, 0);
    assert.deepEqual(scene.calls, []);
    assert.deepEqual(scene.overlays, []);
    assert.match(guide.message, /No command/);
  }
});

test('Help and places remain available inside the guide', () => {
  press(':');
  choose('More keys & app limits', 'help');
  assert.equal(guide.mode, 'help');
  assert.match(text(guide.render(cx)), /find any command/);
  press(':');
  assert.equal(guide.mode, 'commands');
  press('backspace');
  press('w');
  assert.equal(guide.mode, 'places');
  assert.equal(scene.closed, 0);
  assert.deepEqual(scene.calls, []);
  assert.deepEqual(scene.overlays, []);
  forbidExternalPalette();
});

test('Search typing reaches native input without invoking prefix shortcuts', () => {
  press(':');
  for (const [key, modifiers] of [['c', {}], ['1', {}], ['5', { shift: true }], ['v', {}], ['q', {}]]) {
    const stopped = scene.stopped;
    press(key, modifiers);
    assert.equal(scene.stopped, stopped, 'Typing must remain with native Input');
  }
  guide.input.type('focus pane right');
  assert.equal(guide.query, 'focus pane right');
  assert.equal(guide.at, 0);
  assert.deepEqual(scene.calls, []);
  guide.input.submit();
  assert.deepEqual(scene.calls, [['pane.go', { direction: 'right' }]]);
});

test('Every expanded direction, tab step, and pane cycle runs its selected action', () => {
  for (const [label, expected] of [
    ['Focus pane left', ['pane.go', { direction: 'left' }]],
    ['Focus pane down', ['pane.go', { direction: 'down' }]],
    ['Focus pane up', ['pane.go', { direction: 'up' }]],
    ['Focus pane right', ['pane.go', { direction: 'right' }]],
    ['Previous tab', ['tab.prev', {}]], ['Next tab', ['tab.next', {}]],
    ['Previous pane', ['pane.focus', { pane: 'p3' }]], ['Next pane', ['pane.focus', { pane: 'p2' }]],
  ]) {
    fresh(); choose(label);
    assert.deepEqual(scene.calls, [expected], label);
  }
});

test('Empty-query arrows select rows, clamp at the ends, and reset after input changes', () => {
  search();
  press('up'); assert.equal(guide.at, 0);
  press('down'); assert.equal(guide.at, 1);
  press('pagedown'); assert.equal(guide.at, 9);
  let tree = guide.render(cx);
  assert.ok(walk(tree).some(node => node.nodeId === `command-${guide.searchRows()[9].id}`), 'Selected row stays rendered');
  for (let i = 0; i < 20; i++) press('pagedown');
  assert.equal(guide.at, guide.searchRows().length - 1);
  guide.input.type('no such command zzzz');
  assert.equal(guide.at, 0);
  press('down'); assert.equal(guide.at, 0);
  guide.input.submit();
  assert.deepEqual(scene.calls, []);
  assert.match(text(guide.render(cx)), /No matching commands/);
  guide.input.type('zoom');
  assert.equal(guide.at, 0);
});

test('Search back navigation respects editable text and Escape closes without acting', () => {
  search('zoom');
  const stopped = scene.stopped;
  press('backspace');
  assert.equal(guide.mode, 'commands');
  assert.equal(scene.stopped, stopped, 'Nonempty Backspace belongs to native Input');
  guide.input.type('');
  press('backspace');
  assert.equal(guide.mode, 'root');
  assert.equal(scene.closed, 0);
  search('zoom'); press('b', { control: true });
  assert.equal(guide.mode, 'root');
  search('zoom'); press('escape');
  assert.equal(scene.closed, 1);
  assert.deepEqual(scene.calls, []);
});

test('Former direct shortcuts remain reachable through named search actions', () => {
  for (const [label, expected] of [
    ['Zoom in', ['app.zoom_in', {}]], ['Zoom out', ['app.zoom_out', {}]], ['Reset zoom', ['app.zoom_reset', {}]],
    ['Move tab left', ['tab.move', { id: 't1', by: -1 }]], ['Move tab right', ['tab.move', { id: 't1', by: 1 }]],
    ['Swap pane left', ['pane.swap', { direction: 'left' }]], ['Swap pane right', ['pane.swap', { direction: 'right' }]],
    ['Swap pane up', ['pane.swap', { direction: 'up' }]], ['Swap pane down', ['pane.swap', { direction: 'down' }]],
    ['Minimize; keep terminals', ['window.minimize', {}]], ['Maximize / restore window', ['window.maximize', {}]],
  ]) {
    fresh(); choose(label);
    assert.deepEqual(scene.calls, [expected], label);
  }
  fresh(); choose('Quit Herdr…');
  assert.equal(guide.mode, 'confirm');
  assert.deepEqual(scene.calls, []);
  press('enter');
  assert.deepEqual(scene.calls, [['app.quit', {}]]);
});

test('Generic confirmations preserve the selected command and its captured arguments', () => {
  choose('Stop current terminal…');
  assert.equal(guide.mode, 'confirm');
  assert.match(text(guide.render(cx)), /terminal and its sub-agents/);
  assert.deepEqual(scene.calls, []);
  scene.focus = { space: 'changed-space', tab: 'changed-tab', pane: 'changed-pane', terminal: 'changed-terminal' };
  press('enter');
  assert.deepEqual(scene.calls, [['terminal.kill', { terminal: 'term1' }]]);
  fresh(); choose('Restore the default screen and keys…');
  assert.match(text(guide.render(cx)), /layout and keys aside/);
  scene.focus.space = 'changed';
  press('y');
  assert.deepEqual(scene.calls, [['app.reset', {}]], 'App commands must not inherit a space ID');
  fresh(); choose('Close tab…');
  scene.focus.tab = 'changed'; press('enter');
  assert.deepEqual(scene.calls, [['tab.close', { id: 't1', confirmed: true }]]);
});

test('Canceling any generic confirmation never executes its pending command', () => {
  for (const key of ['n', 'backspace', 'escape']) {
    fresh(); choose('Stop current terminal…'); press(key);
    assert.deepEqual(scene.calls, []);
    assert.equal(key === 'escape' ? scene.closed : guide.mode, key === 'escape' ? 1 : 'root');
  }
});

test('Layout and theme choices update from live snapshots and invoke concrete names', () => {
  search();
  scene.layouts.push('workbench'); scene.themes.push({ name: 'custom-night' });
  choose('Layout: workbench');
  assert.deepEqual(scene.calls, [['layout.switch', { name: 'workbench' }]]);
  fresh(); scene.themes.push({ name: 'custom-night' }); choose('Theme: custom night');
  assert.deepEqual(scene.calls, [['app.theme', { name: 'custom-night' }]]);
  fresh(); choose('Theme: terminal');
  assert.deepEqual(scene.calls, [['app.theme', { name: 'terminal' }]]);
  fresh(); choose('Duplicate current layout');
  assert.deepEqual(scene.calls, [['layout.clone', { name: 'keyboard' }]]);
});

test('Named native dialogs receive their expected arguments without raw command entry', () => {
  choose('Duplicate mod…');
  assert.deepEqual(scene.calls, []);
  assert.deepEqual(scene.overlays, [{ mod: 'prompt', kind: 'dialog', width: 380, props: {
    title: 'Duplicate mod', hint: 'Mod to copy; creates <name>-copy', command: { name: 'mod.clone', args: {} },
  } }]);
  fresh(); choose('Rename tab…');
  assert.deepEqual(scene.calls, [['tab.rename', {}]], 'Native rename command opens its name dialog');
  fresh(); choose('Start an agent…');
  assert.equal(scene.overlays[0].mod, 'new-menu');
});

test('Catalogue filters no-op and missing commands while admitting safe new metadata', () => {
  scene.commands.push({ name: 'app.inspect_session', args: [], about: 'session inspection' },
    { name: 'app.raw_target', args: [{ name: 'target', required: true }], about: 'raw identifier' });
  scene.commands = scene.commands.filter(command => command.name !== 'app.zoom_in');
  const rows = search();
  assert.equal(new Set(rows.map(row => row.id)).size, rows.length);
  assert.ok(!rows.some(row => ['app.hide', 'app.hide_others', 'app.show_all', 'app.palette', 'app.help', 'app.zoom_in', 'app.raw_target'].includes(row.command)));
  assert.ok(!rows.some(row => row.command === 'mod.open' && row.args.name === 'picker'));
  choose('Inspect session app');
  assert.deepEqual(scene.calls, [['app.inspect_session', {}]]);
  forbidExternalPalette();
});

test('Places search selects a named remote settled tab without launching a picker', () => {
  press('w'); guide.input.type('server logs');
  assert.equal(guide.searchRows().length, 1);
  guide.input.submit();
  assert.deepEqual(scene.calls, [['tab.select', { id: 'remote/t3' }]]);
  assert.deepEqual(scene.overlays, []);
  forbidExternalPalette();
});

test('Empty context keeps global commands usable and explains unavailable pane actions', () => {
  scene.focus = null; scene.spaces = []; scene.panes = []; scene.terminals = []; scene.agents = [];
  choose('Focus pane right');
  assert.deepEqual(scene.calls, []);
  assert.match(guide.message, /Focus a pane first/);
  choose('Zoom in');
  assert.deepEqual(scene.calls, [['app.zoom_in', {}]]);
});

test('Search opened directly by a mod command initializes its input and restores focus', () => {
  fresh({ mode: 'commands' });
  assert.equal(guide.mode, 'commands');
  assert.ok(guide.input);
  const focused = scene.inputFocus;
  guide.command('focus', cx);
  assert.equal(scene.inputFocus, focused + 1);
  guide.input.type('zoom in'); guide.input.submit();
  assert.deepEqual(scene.calls, [['app.zoom_in', {}]]);
});

test('Named panel actions select before showing, and Add machine opens its native dialog', () => {
  for (const [label, child] of [['Show files panel', 'files'], ['Show changes panel', 'changes']]) {
    fresh(); choose(label);
    assert.deepEqual(scene.calls, [
      ['layout.select', { stack: 'panel-body', child }], ['layout.show', { id: 'panel' }],
    ]);
    assert.equal(scene.closed, 1);
  }
  fresh(); choose('Hide side panel');
  assert.deepEqual(scene.calls, [['layout.hide', { id: 'panel' }]]);
  fresh(); choose('Add machine…');
  assert.deepEqual(scene.calls, [['mod.open', { name: 'machine-add' }]]);
  assert.deepEqual(scene.probes, []);
});

function assertReadOnlyProbes(cwd, on) {
  assert.deepEqual(scene.probes.map(({ program, args, options }) => [program, args, options]), [
    ['git', ['rev-parse', '--absolute-git-dir'], { cwd, on }],
    ['git', ['rev-parse', '--path-format=absolute', '--git-common-dir'], { cwd, on }],
  ], 'Removal preflight may only inspect Git; it must never mutate a checkout');
  assert.deepEqual(scene.calls, [], 'No terminal or space should be changed by the preflight');
}
async function resolveProbes(gitDir, common) {
  scene.probes[0].resolve(gitDir);
  scene.probes[1].resolve(common);
  await Promise.all(scene.tasks);
}
async function asyncTest(name, fn) {
  fresh();
  await fn();
  console.log(`ok ${++count} - ${name}`);
}
async function checkWorktreeRemoval() {
  await asyncTest('Main-checkout removal reports a limit without opening a native removal dialog', async () => {
    scene.focus.cwd = '/repo/src';
    choose('Remove worktree…');
    assertReadOnlyProbes('/repo/src', null);
    assert.deepEqual(scene.overlays, []);
    await resolveProbes({ code: 0, stdout: '/repo/.git\n' }, { code: 0, stdout: '/repo/.git\n' });
    assert.match(guide.message, /main checkout.*Only a linked worktree/s);
    assert.deepEqual(scene.overlays, []);
    assert.equal(scene.closed, 0);
    assertReadOnlyProbes('/repo/src', null);
  });

  await asyncTest('A main checkout with a separate Git directory cannot be removed as a linked worktree', async () => {
    scene.focus.cwd = '/repo/src';
    choose('Remove worktree…');
    await resolveProbes({ code: 0, stdout: '/metadata/repo.git/\n' }, { code: 0, stdout: '/metadata/repo.git\n' });
    assert.match(guide.message, /main checkout.*Only a linked worktree/s);
    assert.deepEqual(scene.overlays, []);
    assert.equal(scene.closed, 0);
    assertReadOnlyProbes('/repo/src', null);
  });

  await asyncTest('Failed or rejected Git probes never open a removal dialog', async () => {
    for (const failure of ['gitDir', 'common', 'rejected']) {
      fresh();
      choose('Remove worktree…');
      if (failure === 'rejected') {
        scene.probes[0].reject(new Error('remote unavailable'));
        scene.probes[1].resolve({ code: 0, stdout: '/repo/.git\n' });
        await Promise.all(scene.tasks);
        assert.match(guide.message, /Could not check.*remote unavailable/);
      } else {
        await resolveProbes({ code: failure === 'gitDir' ? 128 : 0, stdout: '/repo/.git/worktrees/task\n' },
          { code: failure === 'common' ? 128 : 0, stdout: '/repo/.git\n' });
        assert.match(guide.message, /not in an available Git checkout/);
      }
      assertReadOnlyProbes('/tmp', null);
      assert.deepEqual(scene.overlays, []);
      assert.equal(scene.closed, 0);
    }
  });

  await asyncTest('Linked-worktree removal retains the captured remote space and folder for the native dialog', async () => {
    scene.focus = { space: 'remote/s2', tab: 'remote/t3', pane: 'remote/p3', terminal: 'remote/term3', cwd: '/worktrees/task/src' };
    choose('Remove worktree…');
    assertReadOnlyProbes('/worktrees/task/src', 'remote');
    scene.focus = { space: 's1', tab: 't1', pane: 'p1', terminal: 'term1', cwd: '/different' };
    await resolveProbes({ code: 0, stdout: '/repo/.git/worktrees/task\n' }, { code: 0, stdout: '/repo/.git\n' });
    assert.deepEqual(scene.overlays, [{ mod: 'worktree', kind: 'dialog', width: 560, height: 300,
      props: { space: 'remote/s2', folder: '/worktrees/task/src', action: 'remove' } }]);
    assert.equal(scene.closed, 1);
    assertReadOnlyProbes('/worktrees/task/src', 'remote');
  });

  await asyncTest('Closing a guide during checkout probes never opens a late removal dialog', async () => {
    for (const close of [() => press('escape'), () => guide.close()]) {
      fresh();
      choose('Remove worktree…');
      close();
      await resolveProbes({ code: 0, stdout: '/repo/.git/worktrees/task\n' }, { code: 0, stdout: '/repo/.git\n' });
      assert.deepEqual(scene.overlays, []);
      assertReadOnlyProbes('/tmp', null);
    }
  });
  console.log(`${count} unified command checks passed`);
}
checkWorktreeRemoval().catch(error => { console.error(error); process.exitCode = 1; });
