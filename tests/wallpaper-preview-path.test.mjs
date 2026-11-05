import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const source = readFileSync(new URL('../shell/settings/appearance/State.qml', import.meta.url), 'utf8');
const start = source.indexOf('  function bundledPreview(');
const end = source.indexOf('  function ensurePreview()', start);
function resolve(path, shellDir = '/usr/share/pond-interface/shell') {
  const context = vm.createContext({
    Quickshell: {shellDir},
    // Actual Quickshell diagnostics use qs: URLs, not local file URLs.
    Qt: {resolvedUrl: () => ({toString: () => 'qs:/qs/wallpaper/included/'})},
  });
  vm.runInContext(source.slice(start, end), context);
  return context.bundledPreview(path);
}

test('bundled files resolve without depending on virtual QML URLs', () => {
  assert.equal(resolve('/usr/share/pond-interface/wallpaper/included/ales krivec.jpg'),
    'file:///usr/share/pond-interface/wallpaper/previews/ales%20krivec.jpg');
});
test('same-named custom images must not use bundled previews', () => {
  assert.equal(resolve('/home/josh/Pictures/ales krivec.jpg'), '');
});
test('checkout paths, Unicode, URL delimiters and trailing separators are encoded', () => {
  const path = '/home/josh/my pond/wallpaper/included/pablo merchán #1?.jpg';
  assert.equal(resolve(path, '/home/josh/my pond/shell/'),
    'file:///home/josh/my%20pond/wallpaper/previews/pablo%20merch%C3%A1n%20%231%3F.jpg');
});
test('directories and paths outside the included directory do not resolve', () => {
  assert.equal(resolve('/usr/share/pond-interface/wallpaper/included/'), '');
  assert.equal(resolve('/usr/share/pond-interface/wallpaper/included/../custom.jpg'), '');
});
