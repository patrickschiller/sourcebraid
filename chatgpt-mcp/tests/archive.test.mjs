import test from 'node:test';
import assert from 'node:assert/strict';
import { validateArchive, connectArchive, callArchiveTool } from '../src/archive.mjs';

const HEAD = 'a'.repeat(40);
const TREE = 'b'.repeat(40);
const ROOT = 'c'.repeat(40);
const CLIP = 'd'.repeat(40);
const props = { repo: 'review-owner/review-archive', branch: 'main', root: 'web-clips', githubToken: 'synthetic-secret', userId: 42, login: 'review-owner' };
const markdown = '---\ntitle: "Local first knowledge"\nurl: "https://example.com/knowledge"\ntags: ["research"]\n---\nLocal first knowledge keeps sources portable.\n';
const clip = (path = 'example.md', sha = CLIP) => ({ path, type: 'blob', mode: '100644', sha, size: Buffer.byteLength(markdown) });

function mockGitHub(overrides = {}) {
  const calls = [];
  const prefix = `/repos/${props.repo}`;
  const responses = {
    '/user': { id: 42, login: 'review-owner' },
    [prefix]: { private: true, full_name: props.repo, default_branch: 'main' },
    [`${prefix}/git/ref/heads/main`]: { object: { sha: HEAD } },
    [`${prefix}/git/commits/${HEAD}`]: { tree: { sha: TREE } },
    [`${prefix}/git/trees/${TREE}`]: { tree: [{ path: 'web-clips', type: 'tree', sha: ROOT }], truncated: false },
    [`${prefix}/git/trees/${ROOT}`]: { tree: [clip()], truncated: false },
    [`${prefix}/git/trees/${ROOT}?recursive=1`]: { tree: [clip()], truncated: false },
    [`${prefix}/git/blobs/${CLIP}`]: { size: Buffer.byteLength(markdown), encoding: 'base64', content: Buffer.from(markdown).toString('base64') },
    ...overrides,
  };
  const fetch = async (url, options) => {
    assert.ok(url.startsWith('https://api.github.com/'));
    assert.equal(options.method, 'GET');
    assert.equal(options.redirect, 'manual');
    assert.equal(options.headers.Authorization, 'Bearer synthetic-secret');
    const path = url.slice('https://api.github.com'.length);
    calls.push(path);
    if (!Object.hasOwn(responses, path) && !path.startsWith('/search/code?')) throw new Error(`Unmocked GitHub endpoint ${path}`);
    const payload = responses[path] ?? (path.startsWith('/search/code?') ? (overrides.search ?? { items: [], total_count: 0, incomplete_results: false }) : undefined);
    return payload instanceof Response ? payload : new Response(JSON.stringify(payload), { headers: { 'content-type': 'application/json' } });
  };
  return { fetch, calls };
}

test('archive settings bind one repository, branch and normalized root', () => {
  assert.deepEqual(validateArchive({ repo: props.repo }), { repo: props.repo, branch: 'main', root: 'web-clips' });
  assert.equal(validateArchive({ ...props, branch: 'feature/research', root: 'notes/clips' }).branch, 'feature/research');
  for (const settings of [{ repo: '../repo' }, { repo: 'owner/../repo' }, { ...props, root: '/' }, { ...props, root: 'clips/../private' }, { ...props, branch: 'main?ref=other' }, { ...props, root: 'clips\\secret' }, { ...props, root: '.github' }, { ...props, root: 'archive/.GIT/clips' }]) {
    assert.throws(() => validateArchive(settings));
  }
});

test('connection verifies private repository and identity without returning them from tools', async () => {
  const fixture = mockGitHub();
  assert.deepEqual(await connectArchive(props, props.githubToken, fixture.fetch), props);
  const result = await callArchiveTool('sourcebraid_status', {}, props, fixture.fetch);
  assert.equal(result.read_only, true);
  assert.equal(result.documents, 1);
  assert.equal(result.head_sha, HEAD);
  assert.ok(!JSON.stringify(result).includes(props.githubToken));
  assert.equal(fixture.calls.filter(path => path === '/user').length, 2);
});

test('search returns saved provenance and fetch returns complete verified Markdown', async () => {
  const fixture = mockGitHub();
  const result = await callArchiveTool('search', { query: 'local first' }, props, fixture.fetch);
  assert.deepEqual(result.results, [{ id: 'web-clips/example.md', title: 'Local first knowledge', url: 'https://example.com/knowledge' }]);
  assert.equal(result.incomplete, false);
  const fetched = await callArchiveTool('fetch', { id: 'web-clips/example.md' }, props, fixture.fetch);
  assert.equal(fetched.text, markdown);
  assert.equal(fetched.metadata.path, 'web-clips/example.md');
  assert.equal(fetched.metadata.head_sha, HEAD);
});

test('private repository and identity are revalidated on every call', async () => {
  for (const overrides of [{ [`/repos/${props.repo}`]: { private: false, full_name: props.repo } }, { '/user': { id: 43, login: 'other-user' } }]) {
    const fixture = mockGitHub(overrides);
    await assert.rejects(callArchiveTool('search', { query: 'anything' }, props, fixture.fetch));
    assert.ok(!fixture.calls.some(path => path.includes('/git/blobs/')));
  }
});

test('invalid tool arguments and path traversal make no GitHub requests', async () => {
  let called = false;
  const fetch = async () => { called = true; throw new Error('Must not execute'); };
  for (const [name, args] of [['fetch', { id: 'web-clips/../../secret.md' }], ['fetch', { id: 'other/private.md' }], ['fetch', { id: 'web-clips/index.jsonl' }], ['search', { query: '' }], ['sourcebraid_list', { limit: true }], ['search', { query: 'x', repo: 'other/repo' }], ['sourcebraid_delete', { path: 'web-clips/example.md' }]]) {
    await assert.rejects(callArchiveTool(name, args, props, fetch));
  }
  assert.equal(called, false);
});

test('fetch rejects symlinks instead of following them outside the root', async () => {
  const fixture = mockGitHub({ [`/repos/${props.repo}/git/trees/${ROOT}`]: { tree: [{ ...clip(), mode: '120000' }] } });
  await assert.rejects(callArchiveTool('fetch', { id: 'web-clips/example.md' }, props, fixture.fetch), /regular Markdown/);
  assert.ok(!fixture.calls.some(path => path.includes('/git/blobs/')));
});

test('bounded search reports partial results and never claims a full archive search', async () => {
  const clips = Array.from({ length: 25 }, (_, number) => clip(`document-${String(number).padStart(2, '0')}.md`));
  const fixture = mockGitHub({ [`/repos/${props.repo}/git/trees/${ROOT}?recursive=1`]: { tree: clips, truncated: true } });
  const result = await callArchiveTool('search', { query: 'local' }, props, fixture.fetch);
  assert.equal(result.incomplete, true);
  assert.equal(result.scanned_documents, 20);
  assert.equal(result.discovered_documents, 25);
  assert.ok(result.warnings.some(warning => warning.includes('incomplete archive tree')));
  assert.ok(result.warnings.some(warning => warning.includes('first 20')));
  assert.equal(fixture.calls.filter(path => path.includes('/git/blobs/')).length, 20);
});

test('oversized sources and API responses fail within bounded memory', async () => {
  const oversized = mockGitHub({ [`/repos/${props.repo}/git/trees/${ROOT}`]: { tree: [{ ...clip(), size: 300_000 }] } });
  await assert.rejects(callArchiveTool('fetch', { id: 'web-clips/example.md' }, props, oversized.fetch), /200 KiB/);
  assert.ok(!oversized.calls.some(path => path.includes('/git/blobs/')));
  const largeBody = mockGitHub({ '/user': new Response('x'.repeat(2 * 1024 * 1024 + 1)) });
  await assert.rejects(connectArchive(props, props.githubToken, largeBody.fetch), /size limit/);
});

test('network and GitHub errors never expose tokens or upstream bodies', async () => {
  const failure = async () => { throw new Error(`Authorization: Bearer ${props.githubToken}`); };
  await assert.rejects(connectArchive(props, props.githubToken, failure), error => !error.message.includes(props.githubToken));
  const denied = mockGitHub({ '/user': new Response(props.githubToken, { status: 401 }) });
  await assert.rejects(connectArchive(props, props.githubToken, denied.fetch), error => error.message.includes('401') && !error.message.includes(props.githubToken));
});

test('GitHub redirects are rejected without forwarding the credential', async () => {
  const fixture = mockGitHub({ '/user': new Response(null, { status: 302, headers: { location: 'https://untrusted.example/collect' } }) });
  await assert.rejects(connectArchive(props, props.githubToken, fixture.fetch), /GitHub access failed/);
  assert.deepEqual(fixture.calls, ['/user']);
});

test('missing capture directory is a valid empty archive', async () => {
  const fixture = mockGitHub({ [`/repos/${props.repo}/git/trees/${TREE}`]: { tree: [] } });
  const result = await callArchiveTool('search', { query: 'anything' }, props, fixture.fetch);
  assert.deepEqual(result.results, []);
  assert.equal(result.incomplete, false);
  assert.equal(result.scanned_documents, 0);
});

test('result truncation is explicit even when every candidate was scanned', async () => {
  const clips = Array.from({ length: 15 }, (_, number) => clip(`document-${number}.md`));
  const fixture = mockGitHub({ [`/repos/${props.repo}/git/trees/${ROOT}?recursive=1`]: { tree: clips, truncated: false } });
  const search = await callArchiveTool('search', { query: 'local' }, props, fixture.fetch);
  assert.equal(search.results.length, 10);
  assert.equal(search.incomplete, true);
  assert.ok(search.warnings.some(value => value.includes('Only 10 matching')));
  const listing = await callArchiveTool('sourcebraid_list', { limit: 3 }, props, fixture.fetch);
  assert.equal(listing.sources.length, 3);
  assert.equal(listing.incomplete, true);
});

test('indexed search finds verified older sources outside the first 20 archive paths', async () => {
  const clips = Array.from({ length: 30 }, (_, number) => clip(`document-${String(number).padStart(2, '0')}.md`));
  const fixture = mockGitHub({
    [`/repos/${props.repo}/git/trees/${ROOT}?recursive=1`]: { tree: clips, truncated: false },
    search: { total_count: 1, incomplete_results: false, items: [{ path: 'web-clips/document-00.md', sha: CLIP, repository: { full_name: props.repo } }] },
  });
  const result = await callArchiveTool('search', { query: 'local first' }, props, fixture.fetch);
  assert.equal(result.search_engine, 'github_code_search');
  assert.equal(result.results[0].id, 'web-clips/document-00.md');
  assert.equal(result.incomplete, false);
  assert.equal(result.head_sha, HEAD);
  assert.equal(fixture.calls.filter(path => path.includes('/git/blobs/')).length, 1);
});

test('human query cannot inject repository, path or boolean search qualifiers', async () => {
  const fixture = mockGitHub();
  await callArchiveTool('search', { query: 'local repo:other/private OR path:../secrets' }, props, fixture.fetch);
  const call = fixture.calls.find(path => path.startsWith('/search/code?'));
  const query = new URL(`https://api.github.com${call}`).searchParams.get('q');
  assert.equal(query, '"local" "repo" "other" "private" "or" "path" "secrets" repo:review-owner/review-archive path:web-clips/ extension:md');
  assert.equal((query.match(/repo:/g) || []).length, 1);
  assert.equal((query.match(/path:/g) || []).length, 1);
});

test('indexed results outside the selected root or repository are never fetched', async () => {
  const unknownSha = 'e'.repeat(40);
  const fixture = mockGitHub({ search: { total_count: 2, incomplete_results: false, items: [
    { path: 'secrets/passwords.md', sha: unknownSha, repository: { full_name: props.repo } },
    { path: 'web-clips/example.md', sha: unknownSha, repository: { full_name: 'other/private' } },
  ] } });
  const result = await callArchiveTool('search', { query: 'local' }, props, fixture.fetch);
  assert.equal(result.search_engine, 'bounded_scan');
  assert.ok(result.results.every(item => item.id.startsWith('web-clips/')));
  assert.ok(!fixture.calls.some(path => path.includes(unknownSha) || path.includes('/repos/other/')));
});

test('stale indexed blob IDs are not used as current-commit evidence', async () => {
  const staleSha = 'e'.repeat(40);
  const fixture = mockGitHub({ search: { total_count: 1, incomplete_results: false, items: [
    { path: 'web-clips/example.md', sha: staleSha, repository: { full_name: props.repo } },
  ] } });
  const result = await callArchiveTool('search', { query: 'local' }, props, fixture.fetch);
  assert.equal(result.search_engine, 'bounded_scan');
  assert.equal(result.results.length, 1);
  assert.ok(!fixture.calls.some(path => path.includes(staleSha)));
});

test('unavailable code search falls back with explicit coverage limits', async () => {
  const clips = Array.from({ length: 25 }, (_, number) => clip(`document-${number}.md`));
  const fixture = mockGitHub({
    [`/repos/${props.repo}/git/trees/${ROOT}?recursive=1`]: { tree: clips, truncated: false },
    search: new Response('synthetic-secret', { status: 403 }),
  });
  const result = await callArchiveTool('search', { query: 'local' }, props, fixture.fetch);
  assert.equal(result.search_engine, 'bounded_scan');
  assert.equal(result.incomplete, true);
  assert.equal(result.scanned_documents, 20);
  assert.ok(result.warnings.some(warning => warning.includes('unavailable')));
  assert.ok(!JSON.stringify(result).includes('synthetic-secret'));
});

test('indexed search exposes incomplete results and the GitHub 1000-result ceiling', async () => {
  const fixture = mockGitHub({ search: { total_count: 1001, incomplete_results: true, items: [
    { path: 'web-clips/example.md', sha: CLIP, repository: { full_name: props.repo } },
  ] } });
  const result = await callArchiveTool('search', { query: 'local' }, props, fixture.fetch);
  assert.equal(result.search_engine, 'github_code_search');
  assert.equal(result.incomplete, true);
  assert.equal(result.indexed_matches, 1001);
  assert.ok(result.warnings.some(warning => warning.includes('1,000')));
});
