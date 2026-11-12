const { test } = require('node:test');
const assert = require('node:assert/strict');
const { releaseConfig } = require('./release_config.cjs');
const base = { GITHUB_EVENT_NAME: 'workflow_dispatch', GITHUB_REF: 'refs/heads/main', GITHUB_REF_NAME: 'main', GITHUB_SHA: 'abc123' };

test('branch builds and default manual runs never publish', () => {
  for (const event of ['push', 'workflow_dispatch']) {
    assert.deepEqual(releaseConfig({ ...base, GITHUB_EVENT_NAME: event, RELEASE_TAG: 'v0.04-beta' }, () => null),
      { publish: 'false', tag: '', label: 'main' });
  }
});
test('explicit manual publishing uses the requested tag on this commit', () => {
  for (const existing of [null, base.GITHUB_SHA]) {
    assert.deepEqual(releaseConfig({ ...base, PUBLISH_RELEASE: 'true', RELEASE_TAG: 'v0.04-beta' }, () => existing),
      { publish: 'true', tag: 'v0.04-beta', label: 'v0.04-beta' });
  }
});
test('tag pushes publish and label all packages with the tag', () => {
  assert.equal(releaseConfig({ ...base, GITHUB_EVENT_NAME: 'push', GITHUB_REF: 'refs/tags/v1.2.3', GITHUB_REF_NAME: 'v1.2.3' }, () => base.GITHUB_SHA).publish, 'true');
});
test('publishing rejects missing, malformed, injected and conflicting tags', () => {
  for (const tag of ['', 'main', 'v1\nlabel=oops', 'v1.2;echo bad', '../v1.2', 'v1.2$(bad)']) {
    assert.throws(() => releaseConfig({ ...base, PUBLISH_RELEASE: 'true', RELEASE_TAG: tag }, () => null));
  }
  assert.throws(() => releaseConfig({ ...base, PUBLISH_RELEASE: 'true', RELEASE_TAG: 'v0.04-beta' }, () => 'oldcommit'), /another commit/);
});
