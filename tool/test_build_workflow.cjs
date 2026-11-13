const { test } = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');

const workflow = readFileSync(join(__dirname, '../.github/workflows/build.yml'), 'utf8');

function job(name) {
  const start = workflow.indexOf(`\n  ${name}:`);
  assert.notEqual(start, -1, `Missing ${name} job`);
  const content = workflow.slice(start + 1);
  const next = content.slice(1).search(/^  [a-z][a-z0-9_-]*:/m);
  return next === -1 ? content : content.slice(0, next + 1);
}

test('release builds only Android and Windows', () => {
  assert.doesNotMatch(workflow, /^  macos:$/m);
  assert.doesNotMatch(workflow, /^  linux:$/m);
  assert.doesNotMatch(workflow, /flutter build macos|flutter build linux/);
  assert.doesNotMatch(workflow, /FLUTTER_VERSION_MACOS/);
});

test('Android and Windows builds use the validated build label', () => {
  for (const name of ['android', 'windows']) {
    const section = job(name);
    assert.match(section, /needs: prepare/);
    assert.match(section, /BUILD_LABEL: \$\{\{ needs\.prepare\.outputs\.label \}\}/);
  }
});

test('release waits for Android and Windows and includes their packages in checksums', () => {
  const release = job('release');
  assert.match(release, /needs: \[prepare, android, windows\]/);
  assert.match(release, /pattern: '\{android,windows-\*\}'/);
  assert.match(release, /merge-multiple: true/);
  assert.match(release, /android-universal\.apk; do/);
  assert.match(release, /-eq 8/);
  assert.match(release, /sha256sum Flutify-\*/);
});

test('Windows release still smoke-tests the desktop lyrics window', () => {
  const windows = job('windows');
  assert.match(windows, /desktop_lyrics_smoke\.ps1 -Mode VerifyNew/);
  assert.match(windows, /name: desktop-lyrics-smoke/);
});
