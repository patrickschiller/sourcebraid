import test from 'node:test';
import assert from 'node:assert/strict';
import { handleConsent, publicOrigin, readLimited } from '../src/auth.mjs';
import { ArchiveError } from '../src/archive.mjs';

const ORIGIN = 'https://mcp.sourcebraid.test';
const token = 'github_pat_synthetic_review_only';
const auth = { responseType: 'code', clientId: 'synthetic-client', redirectUri: 'https://client.example/callback', scope: ['archive:read'], state: 'synthetic-state', codeChallenge: 'a'.repeat(43), codeChallengeMethod: 'S256' };
function fixture(overrides = {}) {
  const values = new Map();
  const completed = [];
  const env = {
    PUBLIC_ORIGIN: ORIGIN,
    OAUTH_KV: { async put(key, value, options) { assert.equal(options.expirationTtl, 600); values.set(key, JSON.parse(value)); }, async get(key) { return values.get(key); }, async delete(key) { values.delete(key); } },
    OAUTH_PROVIDER: { async parseAuthRequest() { return { ...auth, ...overrides }; }, async lookupClient() { return { clientName: '<script>untrusted</script>' }; }, async completeAuthorization(value) { completed.push(value); return { redirectTo: `${auth.redirectUri}?code=synthetic-code&state=${auth.state}` }; } },
  };
  return { env, values, completed };
}
async function start(state) {
  const response = await handleConsent(new Request(`${ORIGIN}/authorize`), state.env);
  const html = await response.text();
  const nonce = /name="nonce" value="([a-f0-9-]+)"/.exec(html)?.[1];
  return { response, html, nonce, cookie: response.headers.get('set-cookie')?.split(';')[0] };
}
function post(started, changes = {}, headers = {}) {
  const form = new URLSearchParams({ nonce: started.nonce, repo: 'review/archive', branch: 'main', root: 'web-clips', token, consent: 'yes', action: 'connect', ...changes });
  return new Request(`${ORIGIN}/authorize`, { method: 'POST', headers: { Origin: ORIGIN, Cookie: started.cookie, 'Content-Type': 'application/x-www-form-urlencoded', ...headers }, body: form });
}
const connect = async (archive, githubToken) => ({ ...archive, githubToken, userId: 42, login: 'synthetic-user' });

test('consent displays escaped client identity, scope, data flow and secure cookie', async () => {
  const state = fixture();
  const { response, html } = await start(state);
  assert.equal(response.status, 200);
  assert.match(html, /&lt;script&gt;untrusted&lt;\/script&gt;/);
  assert.doesNotMatch(html, /<script>/);
  assert.match(html, /Contents: Read-only/);
  assert.match(response.headers.get('set-cookie'), /Secure; HttpOnly; SameSite=Lax; Path=\//);
  assert.match(response.headers.get('content-security-policy'), /frame-ancestors 'none'/);
  assert.equal(response.headers.get('cache-control'), 'no-store');
});

test('explicit consent verifies archive and passes token only to encrypted grant props', async () => {
  const state = fixture(); const started = await start(state);
  assert.doesNotMatch(JSON.stringify([...state.values]), new RegExp(token));
  const response = await handleConsent(post(started), state.env, connect);
  assert.equal(response.status, 303);
  assert.equal(state.completed.length, 1);
  assert.equal(state.completed[0].props.githubToken, token);
  assert.deepEqual(state.completed[0].scope, ['archive:read']);
  assert.equal(state.completed[0].userId, 'github-42');
  assert.doesNotMatch(JSON.stringify(state.completed[0].metadata), new RegExp(token));
  assert.doesNotMatch(response.headers.get('location'), new RegExp(token));
  assert.equal(state.values.size, 0);
  assert.equal((await handleConsent(post(started), state.env, connect)).status, 400);
});

test('consent rejects foreign origin, missing cookie, forged state and duplicate form fields', async () => {
  for (const headers of [{ Origin: 'https://attacker.example' }, { Cookie: '' }, { Cookie: '__Host-SourceBraidConsent=invalid' }, { 'Sec-Fetch-Site': 'cross-site' }]) {
    const state = fixture(); const started = await start(state);
    assert.equal((await handleConsent(post(started, {}, headers), state.env, connect)).status, 400);
    assert.equal(state.completed.length, 0);
  }
  const state = fixture(); const started = await start(state);
  const request = post(started); const body = `${await request.text()}&repo=attacker/other`;
  const response = await handleConsent(new Request(request, { body }), state.env, connect);
  assert.equal(response.status, 400); assert.equal(state.completed.length, 0);
});

test('consent rejects unsupported scopes, plain PKCE and insecure redirects', async () => {
  for (const changes of [{ scope: ['archive:write'] }, { scope: ['archive:read', 'extra'] }, { codeChallengeMethod: 'plain' }, { codeChallenge: '' }, { redirectUri: 'http://client.example/callback' }]) {
    const state = fixture(changes); assert.equal((await start(state)).response.status, 400); assert.equal(state.values.size, 0);
  }
});

test('cancel, absent consent, expired session and classic PAT do not connect', async () => {
  for (const changes of [{ action: 'cancel' }, { consent: 'no' }, { token: 'ghp_synthetic' }]) {
    const state = fixture(); const started = await start(state);
    const response = await handleConsent(post(started, changes), state.env, connect);
    assert.equal(response.status, changes.action === 'cancel' ? 200 : 400); assert.equal(state.completed.length, 0);
  }
  const state = fixture(); const started = await start(state);
  for (const value of state.values.values()) value.created = 0;
  assert.equal((await handleConsent(post(started), state.env, connect)).status, 400);
});

test('unexpected upstream errors and credentials are never rendered', async () => {
  const state = fixture(); const started = await start(state);
  const response = await handleConsent(post(started), state.env, async () => { throw new Error(`Authorization: ${token}`); });
  assert.equal(response.status, 400); assert.doesNotMatch(await response.text(), new RegExp(token));
  const state2 = fixture(); const started2 = await start(state2);
  const rejected = await handleConsent(post(started2), state2.env, async () => { throw new ArchiveError('Private repository required.'); });
  assert.match(await rejected.text(), /Private repository required/);
});

test('origin and streamed body limits fail closed', async () => {
  for (const value of ['http://insecure.example', 'https://example.test/path', 'https://user:pass@example.test', 'https://example.test?x=1']) assert.throws(() => publicOrigin({ PUBLIC_ORIGIN: value }));
  assert.equal(publicOrigin({ PUBLIC_ORIGIN: ORIGIN }), ORIGIN);
  await assert.rejects(readLimited(new Request(ORIGIN, { method: 'POST', body: '12345' }), 4));
  assert.equal(await readLimited(new Request(ORIGIN, { method: 'POST', body: '1234' }), 4), '1234');
});
