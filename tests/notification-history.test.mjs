import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const source = readFileSync(new URL('../shell/notifications/State.qml', import.meta.url), 'utf8');
function fixture() {
  const context = vm.createContext({
    historyNotifications: [], historyLimit: 100, activeNotifications: [],
    historyLoading: true, historyWritable: false, historyDirty: false,
    historyCleared: false, historyRemoved: {}, live: {}, transientId: '',
    history: {path: '/history.json'}, recover: {running: false},
    save: {calls: 0, restart() { this.calls++; }},
  });
  vm.runInContext('var root = globalThis;', context);
  for (const name of ['restoreHistory', 'finishHistoryLoad', 'remove', 'clearAll']) {
    const start = source.indexOf(`function ${name}(`);
    let end = source.indexOf('{', start) + 1, depth = 1;
    while (depth) {
      if (source[end] === '{') depth++;
      if (source[end] === '}') depth--;
      end++;
    }
    vm.runInContext(source.slice(start, end), context);
  }
  return context;
}
const ids = state => Array.from(state.historyNotifications, n => n.id);

test('restoring unchanged history does not rewrite it', () => {
  const state = fixture();
  state.restoreHistory(JSON.stringify({notifications: [{id: 'old'}]}));
  assert.deepEqual(ids(state), ['old']);
  assert.equal(state.historyLoading, false);
  assert.equal(state.historyWritable, true);
  assert.equal(state.save.calls, 0);
});
test('live arrivals win over stale disk snapshots and remain first', () => {
  const state = fixture();
  state.historyNotifications = [{id: 'new'}, {id: 'updated', summary: 'live'}];
  state.historyDirty = true;
  state.finishHistoryLoad([{id: 'updated', summary: 'stale'}, {id: 'old'}, {id: 'old'}]);
  assert.deepEqual(ids(state), ['new', 'updated', 'old']);
  assert.equal(state.historyNotifications[1].summary, 'live');
  assert.equal(state.save.calls, 1);
});
test('dismissals during loading cannot be resurrected', () => {
  const state = fixture();
  state.remove({id: 'removed'});
  state.finishHistoryLoad([{id: 'removed'}, {id: 'kept'}]);
  assert.deepEqual(ids(state), ['kept']);
});
test('clear during loading discards old history but preserves later arrivals', () => {
  const state = fixture();
  state.clearAll();
  state.historyNotifications = [{id: 'later'}];
  state.historyDirty = true;
  state.finishHistoryLoad([{id: 'old'}]);
  assert.deepEqual(ids(state), ['later']);
  assert.equal(state.save.calls, 1);
});
test('restore enforces the history cap after merging', () => {
  const state = fixture();
  state.historyNotifications = [{id: 'live'}];
  state.finishHistoryLoad(Array.from({length: 110}, (_, i) => ({id: String(i)})));
  assert.equal(state.historyNotifications.length, 100);
  assert.equal(state.historyNotifications[0].id, 'live');
});
test('corrupt history is preserved before any replacement write', () => {
  for (const text of ['{broken', '{"notifications":{}}']) {
    const state = fixture();
    state.restoreHistory(text);
    assert.equal(state.historyWritable, false);
    assert.equal(state.recover.running, true);
    assert.equal(state.recover.command[0], 'mv');
    assert.equal(state.save.calls, 0);
  }
});
