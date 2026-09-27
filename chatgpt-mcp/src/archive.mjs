/** Read-only, repository-bound GitHub archive access for the hosted MCP service. */

const API = 'https://api.github.com';
const MAX_JSON_BYTES = 2 * 1024 * 1024;
const MAX_DOCUMENT_BYTES = 200 * 1024;
const MAX_SCANNED_DOCUMENTS = 20;
const MAX_REQUESTS = 48;
const MAX_DURATION_MS = 25_000;
const SHA = /^(?:[a-f0-9]{40}|[a-f0-9]{64})$/i;

export class ArchiveError extends Error {}
function fail(message) { throw new ArchiveError(message); }
function object(value) { return value && typeof value === 'object' && !Array.isArray(value); }
function relativePath(value, name) {
  if (typeof value !== 'string' || !value || value.length > 1024 || /[\\\x00-\x1f\x7f]/u.test(value)
      || value.split('/').some(part => !part || part === '.' || part === '..') || value.split('/').length > 20) {
    fail(`${name} must be a normalized relative repository path.`);
  }
  return value;
}

export function validateArchive(input) {
  if (!object(input)) fail('Archive settings must be an object.');
  const { repo, branch = 'main', root = 'web-clips' } = input;
  if (typeof repo !== 'string' || !/^[A-Za-z0-9][A-Za-z0-9-]{0,38}\/[A-Za-z0-9._-]{1,100}$/.test(repo)
      || ['.', '..'].includes(repo.split('/')[1])) fail('Repository must use OWNER/REPO.');
  if (typeof branch !== 'string' || !branch || branch.length > 255 || branch === '@' || branch.startsWith('-')
      || branch.includes('..') || branch.includes('@{') || /[\s\x00-\x1f\x7f~^:?*\[\\]/u.test(branch)
      || branch.endsWith('.') || branch.split('/').some(part => !part || part.startsWith('.') || part.endsWith('.lock'))) {
    fail('Branch must be a valid GitHub branch name.');
  }
  relativePath(root, 'Archive root');
  if (root.split('/').some(part => ['.git', '.github'].includes(part.toLowerCase()))) fail('Archive root cannot use repository configuration directories.');
  return { repo, branch, root };
}

function session(githubToken, fetchImpl) {
  if (typeof githubToken !== 'string' || !githubToken || githubToken.length > 512 || /[\s\x00-\x1f\x7f]/u.test(githubToken)) {
    fail('A valid GitHub access token is required.');
  }
  let requests = 0;
  const deadline = Date.now() + MAX_DURATION_MS;
  return async function request(path, maximum = MAX_JSON_BYTES) {
    if (++requests > MAX_REQUESTS || Date.now() >= deadline) fail('Archive request limit reached; narrow the request and try again.');
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), Math.min(12_000, deadline - Date.now()));
    try {
      const response = await fetchImpl(`${API}${path}`, {
        // Workerd supports manual/follow. Reject manual 3xx below without ever
        // forwarding the GitHub credential to a redirected destination.
        method: 'GET', redirect: 'manual', signal: controller.signal,
        headers: { Accept: 'application/vnd.github+json', Authorization: `Bearer ${githubToken}`,
          'X-GitHub-Api-Version': '2022-11-28', 'User-Agent': 'SourceBraid-ChatGPT' },
      });
      if (!response.ok) {
        const status = [401, 403, 404, 429].includes(response.status) ? response.status : 'upstream';
        fail(`GitHub access failed (${status}); check the selected private repository, token permissions and rate limits.`);
      }
      if (Number(response.headers.get('content-length')) > maximum) fail('GitHub response exceeds the supported size limit.');
      const chunks = [];
      let size = 0;
      if (response.body) {
        const reader = response.body.getReader();
        try {
          while (true) {
            const { done, value } = await reader.read();
            if (done) break;
            size += value.byteLength;
            if (size > maximum) { await reader.cancel(); fail('GitHub response exceeds the supported size limit.'); }
            chunks.push(value);
          }
        } finally { reader.releaseLock(); }
      }
      const bytes = new Uint8Array(size);
      let offset = 0;
      for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
      let payload;
      try { payload = JSON.parse(new TextDecoder().decode(bytes)); }
      catch { fail('GitHub returned an invalid response.'); }
      if (!object(payload)) fail('GitHub returned an invalid response.');
      return payload;
    } catch (error) {
      // Never relay a network implementation's exception: it can contain request headers.
      if (error instanceof ArchiveError) throw error;
      fail('GitHub could not be reached within the request timeout. Please try again.');
    } finally { clearTimeout(timer); }
  };
}

async function verifyArchive(archive, request, expectedUserId) {
  const user = await request('/user');
  if (!Number.isSafeInteger(user.id) || user.id <= 0 || typeof user.login !== 'string') fail('GitHub did not return a valid user identity.');
  if (expectedUserId !== undefined && String(user.id) !== String(expectedUserId)) fail('GitHub identity changed; reconnect SourceBraid.');
  const repository = await request(`/repos/${archive.repo}`);
  if (repository.private !== true || typeof repository.full_name !== 'string'
      || repository.full_name.toLowerCase() !== archive.repo.toLowerCase()) {
    fail('SourceBraid requires the exact selected private GitHub repository.');
  }
  return { userId: user.id, login: user.login, defaultBranch: repository.default_branch };
}

export async function connectArchive(input, githubToken, fetchImpl = fetch) {
  const archive = validateArchive(input);
  const request = session(githubToken, fetchImpl);
  const { userId, login } = await verifyArchive(archive, request);
  await snapshot(archive, request);
  return { ...archive, githubToken, userId, login };
}

function checkedSha(value) { if (typeof value !== 'string' || !SHA.test(value)) fail('GitHub returned an invalid object identifier.'); return value; }
async function getTree(archive, sha, request, recursive = false) {
  const tree = await request(`/repos/${archive.repo}/git/trees/${checkedSha(sha)}${recursive ? '?recursive=1' : ''}`);
  if (!Array.isArray(tree.tree)) fail('GitHub returned an invalid repository tree.');
  return tree;
}
async function descend(archive, sha, segments, request) {
  for (const segment of segments) {
    const tree = await getTree(archive, sha, request);
    if (tree.truncated) fail('GitHub returned an incomplete directory; the requested path cannot be verified.');
    const entry = tree.tree.find(item => item.path === segment && item.type === 'tree');
    if (!entry) return null;
    sha = checkedSha(entry.sha);
  }
  return sha;
}
async function snapshot(archive, request) {
  const ref = await request(`/repos/${archive.repo}/git/ref/heads/${encodeURIComponent(archive.branch)}`);
  const head = checkedSha(ref.object?.sha);
  const commit = await request(`/repos/${archive.repo}/git/commits/${head}`);
  const tree = checkedSha(commit.tree?.sha);
  const rootTree = await descend(archive, tree, archive.root.split('/'), request);
  return { head, rootTree };
}

async function inventory(archive, state, request) {
  if (!state.rootTree) return { clips: [], incomplete: false };
  const tree = await getTree(archive, state.rootTree, request, true);
  const clips = [];
  for (const item of tree.tree) {
    if (!object(item) || item.type !== 'blob' || !['100644', '100755'].includes(item.mode)
        || typeof item.path !== 'string' || !item.path.toLowerCase().endsWith('.md')) continue;
    const path = `${archive.root}/${relativePath(item.path, 'Clip path')}`;
    clips.push({ path, sha: checkedSha(item.sha), size: Number.isSafeInteger(item.size) ? item.size : null });
  }
  clips.sort((a, b) => b.path.localeCompare(a.path));
  return { clips, incomplete: tree.truncated === true };
}

async function readBlob(archive, entry, request) {
  if (entry.size !== null && entry.size > MAX_DOCUMENT_BYTES) fail('Saved source exceeds the supported 200 KiB document limit.');
  const blob = await request(`/repos/${archive.repo}/git/blobs/${checkedSha(entry.sha)}`, Math.ceil(MAX_DOCUMENT_BYTES * 1.5));
  if (blob.encoding !== 'base64' || typeof blob.content !== 'string' || !Number.isSafeInteger(blob.size)
      || blob.size < 0 || blob.size > MAX_DOCUMENT_BYTES) fail('Saved source exceeds the supported document format or size limit.');
  let raw;
  try { raw = atob(blob.content.replace(/\s/g, '')); } catch { fail('GitHub returned invalid source content.'); }
  if (raw.length > MAX_DOCUMENT_BYTES) fail('Saved source exceeds the supported 200 KiB document limit.');
  return new TextDecoder().decode(Uint8Array.from(raw, character => character.charCodeAt(0)));
}

function metadata(text, path, archive, head) {
  const fields = {};
  const frontmatter = /^---\r?\n([\s\S]*?)\r?\n---(?:\r?\n|$)/.exec(text.slice(0, 16_384));
  for (const line of (frontmatter?.[1] || '').split(/\r?\n/)) {
    const match = /^([a-z_]+):\s*(.*?)\s*$/.exec(line);
    if (!match) continue;
    let value = match[2];
    if (value.startsWith('"') || value.startsWith('[')) {
      try { value = JSON.parse(value); } catch { /* Preserve the literal if outside the supported YAML subset. */ }
    } else if (value.startsWith("'") && value.endsWith("'")) value = value.slice(1, -1).replace(/''/g, "'");
    fields[match[1]] = value;
  }
  const repositoryUrl = `https://github.com/${archive.repo}/blob/${head}/${path.split('/').map(encodeURIComponent).join('/')}`;
  let sourceUrl = '';
  try { const url = new URL(fields.url); if (['https:', 'http:'].includes(url.protocol) && !url.username && !url.password) sourceUrl = url.href; } catch { /* Source provenance can be absent. */ }
  return { title: typeof fields.title === 'string' && fields.title ? fields.title : path,
    url: sourceUrl || repositoryUrl, source_url: sourceUrl, repository_url: repositoryUrl,
    date: typeof fields.date === 'string' ? fields.date : '',
    source: typeof fields.source === 'string' ? fields.source : typeof fields.site === 'string' ? fields.site : '',
    tags: Array.isArray(fields.tags) ? fields.tags.filter(tag => typeof tag === 'string') : [] };
}

function validateToolArguments(name, args) {
  const names = { search: ['query'], fetch: ['id'], sourcebraid_list: ['limit'], sourcebraid_status: [] };
  if (!Object.hasOwn(names, name)) fail('Unknown SourceBraid tool.');
  if (!object(args) || Object.keys(args).some(key => !names[name].includes(key))) fail('Tool arguments contain unsupported fields.');
  if (name === 'search' && (typeof args.query !== 'string' || !args.query.trim() || args.query.length > 500)) fail('Query must contain 1 to 500 characters.');
  if (name === 'fetch' && typeof args.id !== 'string') fail('Source id must be a repository path.');
  if (args.limit !== undefined && (!Number.isInteger(args.limit) || args.limit < 1 || args.limit > 20)) fail('Limit must be an integer between 1 and 20.');
}

function queryTerms(query) {
  const terms = [...new Set(query.normalize('NFKC').toLowerCase().match(/[\p{L}\p{N}_]+/gu) || [])];
  if (!terms.length || terms.length > 12 || terms.join(' ').length > 200) fail('Search supports 1 to 12 literal words, up to 200 characters.');
  return terms;
}

async function findClipEntry(archive, state, id, request) {
  if (!state.rootTree) return null;
  const parts = id.slice(archive.root.length + 1).split('/');
  const file = parts.pop();
  const parent = await descend(archive, state.rootTree, parts, request);
  if (!parent) return null;
  const tree = await getTree(archive, parent, request);
  if (tree.truncated) fail('GitHub returned an incomplete directory; the source cannot be verified.');
  return tree.tree.find(item => item.path === file && item.type === 'blob' && ['100644', '100755'].includes(item.mode)) || null;
}

async function searchIndexedArchive(archive, state, inventoryData, terms, request) {
  // Code Search only indexes GitHub's default branch. Human input supplies words,
  // never query syntax. Roots outside this safe qualifier alphabet use the scan fallback.
  // https://docs.github.com/en/rest/search/search#search-code
  const query = `${terms.map(term => JSON.stringify(term)).join(' ')} repo:${archive.repo} path:${archive.root}/ extension:md`;
  const payload = await request(`/search/code?q=${encodeURIComponent(query)}&per_page=20&page=1`);
  if (!Array.isArray(payload.items) || !Number.isSafeInteger(payload.total_count) || payload.total_count < 0) fail('GitHub returned an invalid search response.');
  if (!payload.items.length) return null;
  const results = [];
  const warnings = ['GitHub indexing can lag recent captures. Every returned source was verified against the reported branch commit.'];
  const byPath = new Map(inventoryData.clips.map(entry => [entry.path, entry]));
  const visited = new Set();
  let scanned = 0;
  let matched = 0;
  let incomplete = payload.incomplete_results === true || payload.total_count > payload.items.length || payload.items.length > 20;
  for (const item of payload.items.slice(0, 20)) {
    try {
      if (!object(item) || typeof item.path !== 'string' || !item.path.startsWith(`${archive.root}/`)
          || !item.path.toLowerCase().endsWith('.md') || typeof item.repository?.full_name !== 'string'
          || item.repository.full_name.toLowerCase() !== archive.repo.toLowerCase()) {
        incomplete = true;
        continue;
      }
      relativePath(item.path, 'Search result');
      if (visited.has(item.path)) continue;
      visited.add(item.path);
      const entry = byPath.get(item.path) || (inventoryData.incomplete ? await findClipEntry(archive, state, item.path, request) : null);
      if (!entry || checkedSha(entry.sha) !== checkedSha(item.sha)) {
        incomplete = true;
        warnings.push('Some indexed matches no longer matched the current archive commit and were omitted.');
        continue;
      }
      const text = await readBlob(archive, { ...entry, size: entry.size ?? null }, request);
      scanned++;
      if (!terms.every(term => `${item.path}\n${text}`.normalize('NFKC').toLowerCase().includes(term))) {
        incomplete = true;
        continue;
      }
      const meta = metadata(text, item.path, archive, state.head);
      matched++;
      if (results.length < 10) results.push({ id: item.path, title: meta.title, url: meta.url });
    } catch {
      incomplete = true;
      warnings.push('Some indexed matches could not be verified within the source-size or request limits.');
      break;
    }
  }
  if (!results.length) return null;
  if (matched > results.length) {
    incomplete = true;
    warnings.push('Only 10 matching sources are returned; narrow the query for additional results.');
  }
  if (payload.incomplete_results) warnings.push('GitHub reported an incomplete indexed search.');
  if (payload.total_count > payload.items.length || payload.items.length > 20) warnings.push('Only the first 20 indexed matches were verified; narrow the query for additional matches.');
  if (payload.total_count > 1000) warnings.push('The query exceeds GitHub’s 1,000 indexed-result limit; narrow the search terms.');
  return { results, incomplete, search_engine: 'github_code_search', scanned_documents: scanned,
    discovered_documents: inventoryData.clips.length, indexed_matches: payload.total_count,
    head_sha: state.head, result_limit: 10, warnings: [...new Set(warnings)] };
}

export async function callArchiveTool(name, args, props, fetchImpl = fetch) {
  validateToolArguments(name, args);
  const terms = name === 'search' ? queryTerms(args.query) : [];
  const archive = validateArchive(props);
  if (!Number.isSafeInteger(props.userId) || props.userId <= 0) fail('Reconnect SourceBraid to verify your GitHub identity.');
  if (name === 'fetch') {
    relativePath(args.id, 'Source id');
    if (!args.id.startsWith(`${archive.root}/`) || !args.id.toLowerCase().endsWith('.md')) fail('Source id must be a Markdown path under the configured archive root.');
  }
  const request = session(props.githubToken, fetchImpl);
  const identity = await verifyArchive(archive, request, props.userId);
  const state = await snapshot(archive, request);
  if (name === 'fetch') {
    const entry = await findClipEntry(archive, state, args.id, request);
    if (!entry) fail('Saved source does not exist or is not a regular Markdown file.');
    const text = await readBlob(archive, { ...entry, size: entry.size ?? null }, request);
    const meta = metadata(text, args.id, archive, state.head);
    return { id: args.id, title: meta.title, text, url: meta.url,
      metadata: { ...meta, repo: archive.repo, branch: archive.branch, path: args.id, head_sha: state.head } };
  }
  const { clips, incomplete: incompleteTree } = await inventory(archive, state, request);
  if (name === 'sourcebraid_status') return { configured: true, repo: archive.repo, branch: archive.branch,
    root: archive.root, head_sha: state.head, documents: clips.length, incomplete: incompleteTree,
    read_only: true, root_exists: state.rootTree !== null };
  const results = [];
  const warnings = [];
  if (name === 'search' && clips.length) {
    if (identity.defaultBranch === archive.branch && /^[A-Za-z0-9._/-]{1,128}$/.test(archive.root)) {
      try {
        const indexed = await searchIndexedArchive(archive, state, { clips, incomplete: incompleteTree }, terms, request);
        if (indexed) return indexed;
        warnings.push('GitHub returned no verifiable indexed matches; a bounded scan checked recent archive paths.');
      } catch {
        warnings.push('GitHub indexed search was unavailable; a bounded scan checked recent archive paths.');
      }
    } else {
      warnings.push('GitHub indexed search supports the default branch and simple archive paths; this request used a bounded scan.');
    }
  }
  let scanned = 0;
  let matched = 0;
  let incomplete = incompleteTree || clips.length > MAX_SCANNED_DOCUMENTS;
  const limit = name === 'sourcebraid_list' ? args.limit ?? 20 : 10;
  for (const entry of clips.slice(0, MAX_SCANNED_DOCUMENTS)) {
    let text;
    try { text = await readBlob(archive, entry, request); }
    catch { incomplete = true; warnings.push('Some sources could not be read within the document, access or request limits.'); break; }
    scanned++;
    const meta = metadata(text, entry.path, archive, state.head);
    if (terms.length && !terms.every(term => `${entry.path}\n${text}`.normalize('NFKC').toLowerCase().includes(term))) continue;
    matched++;
    if (results.length < limit) results.push(name === 'search'
      ? { id: entry.path, title: meta.title, url: meta.url }
      : { path: entry.path, title: meta.title, url: meta.url, date: meta.date, source: meta.source, tags: meta.tags });
  }
  if (incompleteTree) warnings.push('GitHub returned an incomplete archive tree.');
  if (matched > results.length) {
    incomplete = true;
    warnings.push(`Only ${limit} matching sources are returned; request a larger listing limit or narrow the search.`);
  }
  if (clips.length > MAX_SCANNED_DOCUMENTS) warnings.push('Only the first 20 Markdown paths in descending path order were scanned. Fetch an exact saved path for sources outside this preview.');
  return { [name === 'search' ? 'results' : 'sources']: results, incomplete,
    ...(name === 'search' ? { search_engine: 'bounded_scan' } : {}),
    scanned_documents: scanned, discovered_documents: clips.length, head_sha: state.head,
    result_limit: limit, warnings: [...new Set(warnings)] };
}
