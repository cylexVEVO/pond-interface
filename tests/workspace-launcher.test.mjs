// Run with: node --test tests/workspace-launcher.test.mjs
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import vm from "node:vm";

const source = readFileSync(new URL("../shell/NiriMsg.qml", import.meta.url), "utf8");

function blockAt(start) {
  const begin = source.indexOf("{", start);
  let end = begin + 1;
  let depth = 1;
  while (depth && end < source.length) {
    if (source[end] === "{") depth++;
    if (source[end] === "}") depth--;
    end++;
  }
  assert.equal(depth, 0);
  return source.slice(begin, end);
}

function fixture() {
  const requests = [];
  const context = vm.createContext({ requests });
  vm.runInContext(`
    var root = globalThis;
    var workspaces = [], _windows = {}, overviewOpen = false, dragOrigin = null;
    var _unread = {};
    var _launcherCommands = [], launcherCommand = { running: false, command: [] };
    var workspaceLauncherCloseTimer = {
      running: false, starts: 0,
      start() { this.running = true; this.starts++; },
      stop() { this.running = false; }
    };
    function _recompute() {}
    function _isAgent() { return false; }
    function _move(actions, done) { done(true); return true; }
  `, context);
  // Use the production initial values as well as its event handling methods.
  for (const match of source.matchAll(/property bool (_workspaceLauncher\w+): (true|false)/g))
    vm.runInContext(`var ${match[1]} = ${match[2]};`, context);
  for (const name of ["_openWorkspaceLauncher", "_closeWorkspaceLauncher",
    "_syncWorkspaceLauncher", "_queueLauncherCommand", "_runNextLauncherCommand",
    "_handleEvent", "_mapWindow", "openLauncher"]) {
    const start = source.indexOf(`function ${name}(`);
    assert.ok(start >= 0, name);
    const body = source.indexOf("{", start);
    vm.runInContext(source.slice(start, body) + blockAt(start), context);
  }
  const timerStart = source.indexOf("id: workspaceLauncherCloseTimer");
  vm.runInContext("function closeTimerBody() "
    + blockAt(source.indexOf("onTriggered:", timerStart)), context);

  function drain() {
    while (context.launcherCommand.running) {
      requests.push(context.launcherCommand.command[1]);
      context.launcherCommand.running = false;
      context._runNextLauncherCommand();
    }
  }
  return {
    context, requests,
    event(value) { context._handleEvent(value); drain(); },
    open(id) { context.openLauncher(id); drain(); },
    expireClose() {
      assert.ok(context.workspaceLauncherCloseTimer.running);
      context.workspaceLauncherCloseTimer.running = false;
      context.closeTimerBody();
      drain();
    },
  };
}

function workspaceSnapshot(focused = 1) {
  return { WorkspacesChanged: { workspaces: [1, 2].map(id => ({
    id, idx: id, output: "DP-1", is_focused: id === focused,
    is_active: id === focused, active_window_id: null,
  })) } };
}
const windowsSnapshot = { WindowsChanged: { windows: [] } };
const overviewSnapshot = { OverviewOpenedOrClosed: { is_open: false } };

for (const events of [
  [workspaceSnapshot(), windowsSnapshot, overviewSnapshot],
  [windowsSnapshot, overviewSnapshot, workspaceSnapshot()],
  [overviewSnapshot, workspaceSnapshot(), windowsSnapshot],
]) {
  test(`boot stays hidden: ${events.map(e => Object.keys(e)[0]).join(" → ")}`, () => {
    const f = fixture();
    for (const event of events) f.event(event);
    // A redundant activation and subsequent snapshots are still initial state.
    f.event({ WorkspaceActivated: { id: 1, focused: true } });
    f.event(workspaceSnapshot());
    f.event(windowsSnapshot);
    assert.equal(f.requests.length, 1);
    assert.equal(f.requests[0], "vicinae://close?workspace=true");
    assert.equal(f.context._workspaceLauncherAllowed, false);
  });
}

test("boot does not open transiently before the occupied window snapshot arrives", () => {
  const f = fixture();
  f.event(workspaceSnapshot());
  f.event({ WindowsChanged: { windows: [{ id: 10, workspace_id: 1 }] } });
  assert.ok(f.requests.every(uri => !uri.includes("://open")));
});

test("genuine navigation to an empty workspace opens the launcher", () => {
  const f = fixture();
  f.event(workspaceSnapshot());
  f.event(windowsSnapshot);
  f.event({ WorkspaceActivated: { id: 2, focused: true } });
  assert.equal(f.requests.at(-1), "vicinae://open?layer=background&workspace=true&force=true");
});

test("a workspace switch reported in a workspace snapshot also opens", () => {
  const f = fixture();
  f.event(workspaceSnapshot());
  f.event(windowsSnapshot);
  f.event(workspaceSnapshot(2));
  assert.ok(f.requests.at(-1).includes("://open?"));
});

test("the sidebar plus can open the initial empty workspace explicitly", () => {
  const f = fixture();
  f.event(workspaceSnapshot());
  f.event(windowsSnapshot);
  f.open(1);
  assert.ok(f.requests.at(-1).includes("://open?"));
  assert.equal(f.context._workspaceLauncherAllowed, true);
});

test("occupied destinations still close after the transition without postponement", () => {
  const f = fixture();
  f.event(workspaceSnapshot());
  f.event({ WindowsChanged: { windows: [{ id: 10, workspace_id: 1 }] } });
  f.event({ WorkspaceActivated: { id: 2, focused: true } });
  f.event({ WorkspaceActivated: { id: 1, focused: true } });
  const starts = f.context.workspaceLauncherCloseTimer.starts;
  f.event({ WindowOpenedOrChanged: { window: { id: 10, workspace_id: 1 } } });
  assert.equal(f.context.workspaceLauncherCloseTimer.starts, starts);
  f.expireClose();
  assert.equal(f.requests.at(-1), "vicinae://close?workspace=true");
});
