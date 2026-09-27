import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
import { Miniflare, convertV4MiniflareOptions } from 'miniflare';

const ORIGIN = 'https://mcp.sourcebraid.test';
const REPO = 'synthetic-review/archive';
const TOKEN = 'github_pat_synthetic_worker_test_only';
const REDIRECT = 'https://client.example/callback';
const HEAD = 'a'.repeat(40);
const TREE = 'b'.repeat(40);
const ROOT = 'c'.repeat(40);
const CLIP = 'd'.repeat(40);
const MARKDOWN = '---\ntitle: "Synthetic portable archive"\nurl: "https://example.com/synthetic-archive"\ntags: ["review"]\n---\nA portable weave of Markdown files.\n';

test('real Worker OAuth consent, PKCE, encrypted grant, MCP, refresh and revocation', { timeout: 60_000 }, async t => {
  const bundled = await build({
    entryPoints: [fileURLToPath(new URL('../src/worker.mjs', import.meta.url))],
    bundle: true, format: 'esm', platform: 'browser', target: 'es2022',
    external: ['cloudflare:workers'], write: false, logLevel: 'silent',
  });
  const configuration = JSON.parse(await readFile(new URL('../wrangler.jsonc', import.meta.url), 'utf8'));
  const githubCalls = [];
  const unexpectedCalls = [];
  const fixture = {
    '/user': { id: 42, login: 'synthetic-review' },
    [`/repos/${REPO}`]: { private: true, full_name: REPO },
    [`/repos/${REPO}/git/ref/heads/main`]: { object: { sha: HEAD } },
    [`/repos/${REPO}/git/commits/${HEAD}`]: { tree: { sha: TREE } },
    [`/repos/${REPO}/git/trees/${TREE}`]: { tree: [{ path: 'web-clips', type: 'tree', sha: ROOT }], truncated: false },
    [`/repos/${REPO}/git/trees/${ROOT}`]: { tree: [{ path: 'example.md', type: 'blob', mode: '100644', sha: CLIP, size: Buffer.byteLength(MARKDOWN) }], truncated: false },
    [`/repos/${REPO}/git/trees/${ROOT}?recursive=1`]: { tree: [{ path: 'example.md', type: 'blob', mode: '100644', sha: CLIP, size: Buffer.byteLength(MARKDOWN) }], truncated: false },
    [`/repos/${REPO}/git/blobs/${CLIP}`]: { encoding: 'base64', size: Buffer.byteLength(MARKDOWN), content: Buffer.from(MARKDOWN).toString('base64') },
  };
  const worker = new Miniflare(convertV4MiniflareOptions({
    modules: true, script: bundled.outputFiles[0].text,
    compatibilityDate: configuration.compatibility_date, compatibilityFlags: configuration.compatibility_flags,
    bindings: { PUBLIC_ORIGIN: ORIGIN, OPENAI_VERIFICATION_TOKEN: 'synthetic-domain-challenge' },
    kvNamespaces: configuration.kv_namespaces.map(namespace => namespace.binding),
    ratelimits: Object.fromEntries(configuration.ratelimits.map(({ name, ...value }) => [name, value])),
    // Every outgoing request terminates here; there is no fallback to network access.
    outboundService: async request => {
      const url = new URL(request.url);
      const path = `${url.pathname}${url.search}`;
      if (url.origin !== 'https://api.github.com' || request.method !== 'GET'
          || request.headers.get('authorization') !== `Bearer ${TOKEN}`) {
        unexpectedCalls.push(`${request.method} ${url.origin}${url.pathname}`);
        return new Response('Unexpected synthetic upstream request', { status: 403 });
      }
      githubCalls.push(path);
      if (url.pathname === '/search/code') return Response.json({ message: 'Synthetic code search unavailable' }, { status: 503 });
      if (!Object.hasOwn(fixture, path)) {
        unexpectedCalls.push(path);
        return new Response('No matching synthetic response', { status: 404 });
      }
      return Response.json(fixture[path]);
    },
  }));
  t.after(async () => { await worker.dispose(); });

  const request = (path, options = {}) => worker.dispatchFetch(`${ORIGIN}${path}`, { ...options, redirect: 'manual' });
  const readJson = async response => {
    const text = await response.text();
    assert.ok(!text.includes(TOKEN), 'HTTP response must not expose the synthetic GitHub credential');
    return JSON.parse(text);
  };
  const form = (path, body) => request(path, {
    method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams(body).toString(),
  });
  const mcp = (accessToken, method, params = {}) => request('/mcp', {
    method: 'POST', headers: {
      'content-type': 'application/json', accept: 'application/json',
      ...(accessToken ? { authorization: `Bearer ${accessToken}` } : {}),
    }, body: JSON.stringify({ jsonrpc: '2.0', id: 1, method, params }),
  });

  const health = await request('/health');
  assert.equal(health.status, 200);
  assert.equal((await readJson(health)).readOnly, true);
  assert.equal(health.headers.get('cache-control'), 'no-store');
  const challenge = await request('/.well-known/openai-apps-challenge');
  assert.equal(await challenge.text(), 'synthetic-domain-challenge');
  const metadata = await readJson(await request('/.well-known/oauth-authorization-server'));
  assert.equal(metadata.authorization_endpoint, `${ORIGIN}/authorize`);
  assert.equal(metadata.token_endpoint, `${ORIGIN}/oauth/token`);
  assert.deepEqual(metadata.code_challenge_methods_supported, ['S256']);
  const resource = await readJson(await request('/.well-known/oauth-protected-resource'));
  assert.equal(resource.resource, `${ORIGIN}/mcp`);
  const unauthorized = await mcp(null, 'tools/list');
  assert.equal(unauthorized.status, 401);
  assert.match(unauthorized.headers.get('www-authenticate'), /resource_metadata/);
  assert.equal((await mcp('synthetic-invalid-access-token', 'tools/list')).status, 401);

  const registration = await request('/oauth/register', {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ client_name: 'Synthetic integration client', redirect_uris: [REDIRECT],
      grant_types: ['authorization_code', 'refresh_token'], response_types: ['code'], token_endpoint_auth_method: 'none' }),
  });
  assert.equal(registration.status, 201);
  const client = await readJson(registration);
  assert.ok(client.client_id);
  const verifier = 'synthetic-local-pkce-verifier-'.repeat(2);
  const codeChallenge = createHash('sha256').update(verifier).digest('base64url');
  const authorization = new URLSearchParams({
    response_type: 'code', client_id: client.client_id, redirect_uri: REDIRECT,
    scope: 'archive:read', state: 'synthetic-state', code_challenge: codeChallenge,
    code_challenge_method: 'S256', resource: `${ORIGIN}/mcp`,
  });
  const consent = await request(`/authorize?${authorization}`);
  assert.equal(consent.status, 200);
  const html = await consent.text();
  const nonce = /name="nonce" value="([a-f0-9-]+)"/.exec(html)?.[1];
  const cookie = consent.headers.get('set-cookie')?.split(';')[0];
  assert.ok(nonce && cookie);
  assert.match(html, /Synthetic integration client/);
  const approve = await request('/authorize', {
    method: 'POST', headers: { origin: ORIGIN, cookie, 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ nonce, repo: REPO, branch: 'main', root: 'web-clips', token: TOKEN, consent: 'yes', action: 'connect' }).toString(),
  });
  const approvalBody = await approve.text();
  assert.ok(!approvalBody.includes(TOKEN));
  const approvalError = /<h2>([^<]+)<\/h2><p>([^<]+)/.exec(approvalBody)?.slice(1).join(': ');
  assert.equal(approve.status, 303, `${approvalError || 'Consent must redirect to the registered client'}; mocked requests: ${githubCalls.join(', ')}`);
  const location = new URL(approve.headers.get('location'));
  assert.equal(location.origin + location.pathname, REDIRECT);
  assert.equal(location.searchParams.get('state'), 'synthetic-state');
  const code = location.searchParams.get('code');
  assert.ok(code);

  const exchanged = await form('/oauth/token', {
    grant_type: 'authorization_code', client_id: client.client_id, code,
    redirect_uri: REDIRECT, code_verifier: verifier, resource: `${ORIGIN}/mcp`,
  });
  assert.equal(exchanged.status, 200);
  const tokens = await readJson(exchanged);
  assert.ok(tokens.access_token && tokens.refresh_token);
  assert.equal(tokens.scope, 'archive:read');
  const kv = await worker.getKVNamespace('OAUTH_KV');
  const stored = await kv.list();
  assert.ok(stored.keys.length > 0);
  for (const { name } of stored.keys) {
    const value = await kv.get(name);
    assert.ok(!value.includes(TOKEN), 'KV grant records must encrypt the GitHub credential');
  }

  const initialized = await readJson(await mcp(tokens.access_token, 'initialize', {
    protocolVersion: '2025-06-18', capabilities: {}, clientInfo: { name: 'synthetic-review', version: '1.0.0' },
  }));
  assert.equal(initialized.result.serverInfo.name, 'SourceBraid');
  const listed = await readJson(await mcp(tokens.access_token, 'tools/list'));
  assert.deepEqual(listed.result.tools.map(tool => tool.name), ['search', 'fetch', 'sourcebraid_list', 'sourcebraid_status']);
  assert.ok(listed.result.tools.every(tool => tool.annotations.readOnlyHint && !tool.annotations.destructiveHint));
  const search = await readJson(await mcp(tokens.access_token, 'tools/call', { name: 'search', arguments: { query: 'portable weave' } }));
  assert.equal(search.result.isError, false);
  assert.equal(search.result.structuredContent.results[0].id, 'web-clips/example.md');
  const fetched = await readJson(await mcp(tokens.access_token, 'tools/call', { name: 'fetch', arguments: { id: 'web-clips/example.md' } }));
  assert.equal(fetched.result.structuredContent.text, MARKDOWN);

  const refresh = await form('/oauth/token', {
    grant_type: 'refresh_token', refresh_token: tokens.refresh_token, client_id: client.client_id,
    scope: 'archive:read', resource: `${ORIGIN}/mcp`,
  });
  assert.equal(refresh.status, 200);
  const refreshed = await readJson(refresh);
  assert.ok(refreshed.access_token && refreshed.refresh_token);
  assert.equal((await mcp(refreshed.access_token, 'tools/list')).status, 200);
  const revoked = await form('/oauth/token', {
    token: refreshed.refresh_token, token_type_hint: 'refresh_token', client_id: client.client_id,
  });
  assert.equal(revoked.status, 200);
  assert.equal((await mcp(refreshed.access_token, 'tools/list')).status, 401);
  assert.deepEqual(unexpectedCalls, []);
  assert.ok(Object.keys(fixture).every(path => githubCalls.includes(path)));
});
