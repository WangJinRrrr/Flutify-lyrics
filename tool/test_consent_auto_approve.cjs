// Exercise the exact JavaScript injected into the WebView with a synthetic DOM.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const { test } = require('node:test');
const source = fs.readFileSync('lib/services/auth/web_login_flow.dart', 'utf8');
const script = source.match(/const String kConsentAutoApproveScript = r'''([\s\S]*?)''';/)[1];

function button(label, overrides = {}) {
  return {
    innerText: label, clicks: 0, disabled: false,
    getAttribute() { return null; },
    closest() { return null; },
    getClientRects() { return [{}]; },
    click() { this.clicks++; },
    ...overrides,
  };
}

function page(nodes = [], url = 'https://accounts.spotify.com/en/authorize') {
  const observers = [];
  const timers = new Map();
  const context = vm.createContext({
    location: new URL(url), window: {},
    document: { documentElement: {}, querySelectorAll: () => nodes },
    getComputedStyle: n => ({ visibility: 'visible', display: 'block', opacity: '1', ...n.style }),
    MutationObserver: class {
      constructor(callback) { this.callback = callback; observers.push(this); }
      observe() { this.active = true; }
      disconnect() { this.active = false; }
    },
    setTimeout: callback => { const id = {}; timers.set(id, callback); return id; },
    clearTimeout: id => timers.delete(id),
  });
  return {
    nodes, context, observers, timers,
    run: () => vm.runInContext(script, context),
    mutate: () => observers.filter(o => o.active).forEach(o => o.callback()),
  };
}

test('localized Continue-to-app buttons work in login completion and authorization', () => {
  for (const text of ['Continue to app', ' CONTINUE  TO APP ', '继续使用应用', '繼續使用應用程式',
    'Weiter zur App', "Continuer vers l'application", 'Continuar a la aplicación',
    'Continuar para o aplicativo', "Continua nell'app", 'Doorgaan naar de app',
    'Fortsätt till appen', 'Przejdź do aplikacji', 'Uygulamaya devam et',
    'Перейти в приложение', 'アプリに進む', '앱으로 계속', 'Lanjutkan ke aplikasi', 'المتابعة إلى التطبيق']) {
    const node = button(text);
    const p = page([node], 'https://accounts.spotify.com/en/status');
    p.run();
    p.run();
    assert.equal(node.clicks, 1, text);
  }
});

test('localized consent labels apply only on authorization pages', () => {
  for (const label of ['同意', 'Agree', 'Zustimmen', "J'accepte", '동의', '同意する']) {
    const node = button(label);
    page([node], 'https://accounts.spotify.com/login?client_id=test').run();
    assert.equal(node.clicks, 0);
    page([node]).run();
    assert.equal(node.clicks, 1);
  }
});

test('generic login, social, cancel and substring labels remain untouched', () => {
  const nodes = ['Continue', '继续', 'Continue with Google', 'Agree to marketing', 'Cancel', '拒绝',
    'Do not continue to app', 'Continue to application settings'].map(s => button(s));
  page(nodes).run();
  assert(nodes.every(n => n.clicks === 0));
});

test('hidden, disabled, inert and transparent controls are excluded', () => {
  const nodes = [
    button('Continue to app', { disabled: true }),
    button('Continue to app', { getAttribute: () => 'true' }),
    button('Continue to app', { closest: () => ({}) }),
    button('Continue to app', { getClientRects: () => [] }),
    button('Continue to app', { style: { opacity: '0' } }),
    button('Continue to app', { style: { visibility: 'hidden' } }),
  ];
  page(nodes).run();
  assert(nodes.every(n => n.clicks === 0));
});

test('observer handles late rendering and enabling, disconnecting after click', () => {
  const p = page();
  p.run(); p.run();
  assert.equal(p.observers.length, 1);
  const node = button('继续使用应用', { disabled: true });
  p.nodes.push(node);
  p.mutate();
  assert.equal(node.clicks, 0);
  node.disabled = false;
  p.mutate(); p.mutate(); p.run();
  assert.equal(node.clicks, 1);
  assert.equal(p.observers[0].active, false);
});

test('observer expires and a later poll can observe again', () => {
  const p = page();
  p.run();
  [...p.timers.values()][0]();
  assert.equal(p.observers[0].active, false);
  p.run();
  assert.equal(p.observers.length, 2);
});

test('origin guard rejects HTTP, lookalike hosts, ports and credentials', () => {
  for (const url of ['http://accounts.spotify.com/authorize', 'https://accounts.spotify.com.evil.test/authorize',
    'https://accounts.spotify.com:8443/authorize', 'https://x@accounts.spotify.com/authorize',
    'https://open.spotify.com/authorize']) {
    const node = button('Continue to app');
    const p = page([node], url);
    p.run();
    assert.equal(node.clicks, 0, url);
    assert.equal(p.observers.length, 0);
  }
});

test('observer rechecks origin and stage before acting after navigation', () => {
  const p = page();
  p.run();
  p.context.location = new URL('https://accounts.spotify.com/login');
  const consent = button('Agree');
  p.nodes.push(consent);
  p.mutate();
  assert.equal(consent.clicks, 0);
  p.context.location = new URL('https://example.test/');
  const proceed = button('Continue to app');
  p.nodes.push(proceed);
  p.mutate();
  assert.equal(proceed.clicks, 0);
  assert.equal(p.observers[0].active, false);
});
