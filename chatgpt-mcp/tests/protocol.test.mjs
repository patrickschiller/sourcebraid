import test from 'node:test';
import assert from 'node:assert/strict';
import { handleMcp, TOOLS } from '../src/protocol.mjs';
import { ArchiveError } from '../src/archive.mjs';

const ORIGIN = 'https://mcp.sourcebraid.test';
const env = { PUBLIC_ORIGIN: ORIGIN };
const ctx = { props: { scopes: ['archive:read'], githubToken: 'synthetic-private-token' } };
function request(method, params, options = {}) {
  return new Request(`${ORIGIN}/mcp`, { method: 'POST', headers: { 'Content-Type': 'application/json', Accept: 'application/json, text/event-stream', ...options.headers }, body: JSON.stringify({ jsonrpc: '2.0', id: 1, method, ...(params ? { params } : {}) }) });
}
test('initialization negotiates supported protocol and read-only tools without secrets', async () => {
  const response = await handleMcp(request('initialize', { protocolVersion: '2099-01-01', capabilities: {}, clientInfo: { name: 'test', version: '1' } }), env, ctx);
  assert.equal((await response.json()).result.protocolVersion, '2025-06-18');
  const result = await (await handleMcp(request('tools/list'), env, ctx)).json();
  assert.deepEqual(result.result.tools, TOOLS);
  assert.equal(TOOLS.length, 4);
  assert.ok(TOOLS.every(tool => tool.annotations.readOnlyHint && !tool.annotations.destructiveHint));
  assert.doesNotMatch(JSON.stringify(result), /synthetic-private-token/);
});
test('tools dispatch receives server-bound props; result is structured and readable', async () => {
  const response = await handleMcp(request('tools/call', { name: 'search', arguments: { query: 'markdown' } }), env, ctx, async (name, args, props) => {
    assert.equal(name, 'search'); assert.equal(args.query, 'markdown'); assert.equal(props, ctx.props);
    return { results: [{ id: 'web-clips/review.md', title: 'Synthetic source', url: 'https://example.com/review' }], incomplete: false };
  });
  const { result } = await response.json();
  assert.deepEqual(JSON.parse(result.content[0].text), result.structuredContent); assert.equal(result.isError, false);
});
test('authentication and browser origin are enforced', async () => {
  assert.equal((await handleMcp(request('ping'), env, { props: {} })).status, 401);
  assert.equal((await handleMcp(request('ping', {}, { headers: { Origin: 'https://evil.example' } }), env, ctx)).status, 403);
  assert.equal((await handleMcp(request('ping', {}, { headers: { 'MCP-Protocol-Version': 'invalid' } }), env, ctx)).status, 400);
});
test('malformed JSON, batches, null IDs and bad arguments are rejected', async () => {
  for (const body of ['{', '[]', '{"jsonrpc":"2.0","id":null,"method":"ping"}']) {
    const response = await handleMcp(new Request(`${ORIGIN}/mcp`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body }), env, ctx);
    assert.equal(response.status, 400);
  }
  for (const params of [{ name: 'delete', arguments: {} }, { name: 'search', arguments: [] }]) {
    assert.equal((await (await handleMcp(request('tools/call', params), env, ctx)).json()).error.code, -32602);
  }
});
test('transport rejects oversized bodies and unsupported methods/content negotiation', async () => {
  assert.equal((await handleMcp(new Request(`${ORIGIN}/mcp`), env, ctx)).status, 405);
  assert.equal((await handleMcp(request('ping', {}, { headers: { Accept: 'text/event-stream' } }), env, ctx)).status, 406);
  assert.equal((await handleMcp(request('ping', {}, { headers: { 'Content-Type': 'text/plain' } }), env, ctx)).status, 415);
  assert.equal((await handleMcp(request('tools/call', { name: 'search', arguments: { query: 'a'.repeat(70000) } }), env, ctx)).status, 413);
});
test('notifications have no JSON-RPC response and unsupported methods fail', async () => {
  const notification = new Request(`${ORIGIN}/mcp`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ jsonrpc: '2.0', method: 'notifications/initialized' }) });
  assert.equal((await handleMcp(notification, env, ctx)).status, 202);
  assert.equal((await (await handleMcp(request('unknown'), env, ctx)).json()).error.code, -32601);
});
test('upstream failures redact raw exceptions, known archive errors stay actionable', async () => {
  for (const error of [new Error('synthetic-private-token'), new ArchiveError('GitHub access failed (401); reconnect.')]) {
    const response = await handleMcp(request('tools/call', { name: 'sourcebraid_status' }), env, ctx, async () => { throw error; });
    const { result } = await response.json(); assert.equal(result.isError, true);
    assert.doesNotMatch(JSON.stringify(result), /synthetic-private-token/);
    if (error instanceof ArchiveError) assert.match(result.content[0].text, /401/);
  }
});
