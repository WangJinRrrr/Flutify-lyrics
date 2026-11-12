const { test } = require('node:test');
const assert = require('node:assert/strict');
const { mkdtempSync, readFileSync, rmSync, writeFileSync } = require('node:fs');
const { tmpdir } = require('node:os');
const { join } = require('node:path');
const { spawnSync, execFileSync } = require('node:child_process');
const { createHash } = require('node:crypto');

const script = join(__dirname, 'create_self_test_android_key.sh');

function fixture(t) {
  const directory = mkdtempSync(join(tmpdir(), 'flutify-self-test-key-'));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  const envFile = join(directory, 'github-env');
  const keyFile = join(directory, 'flutify-self-test.p12');
  const run = () => spawnSync('bash', [script], {
    env: { ...process.env, RUNNER_TEMP: directory, GITHUB_ENV: envFile },
    encoding: 'utf8',
  });
  return { envFile, keyFile, run };
}

test('self-test signing creates a working key and pins its actual certificate', (t) => {
  const { envFile, keyFile, run } = fixture(t);
  const result = run();
  assert.equal(result.status, 0, result.stderr);
  const values = Object.fromEntries(readFileSync(envFile, 'utf8').trim().split('\n').map((line) => {
    const separator = line.indexOf('=');
    return [line.slice(0, separator), line.slice(separator + 1)];
  }));
  assert.equal(values.ANDROID_KEYSTORE_PATH, keyFile);
  assert.equal(values.ANDROID_KEY_ALIAS, 'flutify-self-test');
  assert.ok(/^[a-f0-9]{48}$/.test(values.ANDROID_KEYSTORE_PASSWORD), 'Use a generated password');
  assert.ok(values.ANDROID_KEYSTORE_PASSWORD === values.ANDROID_KEY_PASSWORD, 'PKCS12 passwords must match');
  assert.ok(result.stdout.includes(`::add-mask::${values.ANDROID_KEYSTORE_PASSWORD}\n`), 'Mask the password before later CI steps');
  assert.ok(!result.stderr.includes(values.ANDROID_KEYSTORE_PASSWORD), 'Do not log the password');
  const certificate = execFileSync('keytool', [
    '-exportcert', '-keystore', keyFile, '-alias', values.ANDROID_KEY_ALIAS,
    '-storepass:env', 'TEST_KEY_PASSWORD',
  ], { env: { ...process.env, TEST_KEY_PASSWORD: values.ANDROID_KEYSTORE_PASSWORD } });
  assert.equal(createHash('sha256').update(certificate).digest('hex'), values.ANDROID_SIGNING_CERT_SHA256);
  const second = fixture(t);
  assert.equal(second.run().status, 0);
  assert.notEqual(readFileSync(second.envFile, 'utf8').match(/ANDROID_SIGNING_CERT_SHA256=(\w+)/)[1], values.ANDROID_SIGNING_CERT_SHA256);
});

test('self-test signing never overwrites an existing key', (t) => {
  const { keyFile, run } = fixture(t);
  writeFileSync(keyFile, 'existing key must survive');
  const result = run();
  assert.notEqual(result.status, 0);
  assert.equal(readFileSync(keyFile, 'utf8'), 'existing key must survive');
  assert.match(result.stderr, /already exists/);
});
