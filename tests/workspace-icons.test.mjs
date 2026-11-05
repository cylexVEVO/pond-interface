import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const source = readFileSync(new URL('../shell/NiriMsg.qml', import.meta.url), 'utf8');
function fixture(windows) {
  const context = vm.createContext({
    workspaces: [{id: 1, idx: 1, output: 'DP-1', isActive: true, isFocused: true}],
    _windows: Object.fromEntries(windows.map(w => [w.id, {...w, workspaceId: 1}])),
    _unread: {}, dragOrigin: null, workspaceRows: {}, lookups: [], rows: [],
  });
  vm.runInContext(`
    function _compareWindows(a, b) { return a.id - b.id; }
    function _appInfo(id) { lookups.push(id); return {iconName: id, iconSource: 'icon:' + id}; }
    function _syncModel(model, desired) { rows = desired; }
  `, context);
  for (const name of ['_recompute', '_isAgent', '_isWorking', '_needsAttention']) {
    const start = source.indexOf(`function ${name}(`);
    let end = source.indexOf('{', start) + 1, depth = 1;
    while (depth) {
      if (source[end] === '{') depth++;
      if (source[end] === '}') depth--;
      end++;
    }
    vm.runInContext(source.slice(start, end), context);
  }
  context._recompute();
  return context;
}

test('terminal agent markers never resolve desktop icons', () => {
  const state = fixture([
    {id: 1, appId: 'kitty', title: '◐ Working'},
    {id: 2, appId: 'kitty', title: '[!] Approval'},
  ]);
  assert.deepEqual(Array.from(state.lookups), []);
  const records = JSON.parse(state.rows[0].windowsJson);
  assert.deepEqual(records.map(w => w.dotState), ['working', 'attention']);
  assert.ok(records.every(w => w.iconSource === '' && w.iconName === ''));
});
test('regular terminals and apps retain their icons', () => {
  const state = fixture([
    {id: 1, appId: 'kitty', title: 'josh@host'},
    {id: 2, appId: 'browser', title: 'Page'},
  ]);
  assert.deepEqual(Array.from(state.lookups), ['kitty', 'browser']);
  const records = JSON.parse(state.rows[0].windowsJson);
  assert.deepEqual(records.map(w => w.iconSource), ['icon:kitty', 'icon:browser']);
  assert.ok(records.every(w => w.dotState === ''));
});
