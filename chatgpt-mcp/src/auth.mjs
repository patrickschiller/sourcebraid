import { ArchiveError, connectArchive } from './archive.mjs';

export const READ_SCOPE = 'archive:read';
export const VERSION = '1.0.1';
const COOKIE = '__Host-SourceBraidConsent';
const CONSENT_TTL = 600;
const enc = new TextEncoder();

export function publicOrigin(env) {
  const url = new URL(env.PUBLIC_ORIGIN);
  if (url.protocol !== 'https:' || url.username || url.password || url.pathname !== '/' || url.search || url.hash) {
    throw new Error('PUBLIC_ORIGIN must be an HTTPS origin.');
  }
  return url.origin;
}

export function secureHeaders(extra = {}) {
  return {
    'Cache-Control': 'no-store', 'Referrer-Policy': 'no-referrer',
    'X-Content-Type-Options': 'nosniff', 'X-Frame-Options': 'DENY',
    'Strict-Transport-Security': 'max-age=31536000',
    'Content-Security-Policy': "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'",
    ...extra,
  };
}

export async function readLimited(request, limit) {
  if (Number(request.headers.get('content-length')) > limit) throw new Error('body_limit');
  if (!request.body) return '';
  const reader = request.body.getReader();
  const chunks = [];
  let bytes = 0;
  let timer;
  const timeout = new Promise((_, reject) => { timer = setTimeout(() => { void reader.cancel(); reject(new Error('body_timeout')); }, 5000); });
  try {
    while (true) {
      const { done, value } = await Promise.race([reader.read(), timeout]);
      if (done) break;
      bytes += value.byteLength;
      if (bytes > limit) { await reader.cancel(); throw new Error('body_limit'); }
      chunks.push(value);
    }
    const result = new Uint8Array(bytes);
    let offset = 0;
    for (const chunk of chunks) { result.set(chunk, offset); offset += chunk.byteLength; }
    return new TextDecoder('utf-8', { fatal: true }).decode(result);
  } finally { clearTimeout(timer); reader.releaseLock(); }
}

const escape = value => String(value).replace(/[&<>"']/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[char]));
function page(body, status = 200, cookie) {
  return new Response(`<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Connect SourceBraid</title><style>body{font:17px/1.5 system-ui,sans-serif;max-width:42rem;margin:3rem auto;padding:0 1.25rem;color:#17312f;background:#f7f9f8}h1{color:#166b68}label{display:block;margin-top:1rem}input:not([type=checkbox]){box-sizing:border-box;width:100%;padding:.7rem;border:1px solid #8a9e9a;border-radius:.3rem;font:inherit}button{padding:.75rem 1rem;margin:1rem .4rem 0 0;font:inherit}button[value=connect]{background:#166b68;color:white;border:0;border-radius:.3rem}.identity{padding:1rem;background:#e7eeeb;overflow-wrap:anywhere}small{display:block}a{color:#135952}</style><main><h1>SourceBraid</h1>${body}<p><a href="https://github.com/patrickschiller/sourcebraid/blob/main/PRIVACY.md">Privacy</a> · <a href="https://github.com/patrickschiller/sourcebraid/blob/main/TERMS.md">Terms</a> · <a href="https://github.com/patrickschiller/sourcebraid/issues">Support</a></p></main></html>`, {
    status, headers: secureHeaders({ 'Content-Type': 'text/html; charset=utf-8', ...(cookie ? { 'Set-Cookie': cookie } : {}) }),
  });
}
const clearCookie = () => `${COOKIE}=; Secure; HttpOnly; SameSite=Lax; Path=/; Max-Age=0`;
async function digest(value) { return Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', enc.encode(value))), byte => byte.toString(16).padStart(2, '0')).join(''); }

function validateAuthorization(auth) {
  if (auth.responseType !== 'code' || auth.codeChallengeMethod !== 'S256'
      || !/^[A-Za-z0-9_-]{43}$/.test(auth.codeChallenge || '')
      || auth.scope.length !== 1 || auth.scope[0] !== READ_SCOPE) throw new Error('invalid_authorization');
  const redirect = new URL(auth.redirectUri);
  if (redirect.protocol !== 'https:' || redirect.username || redirect.password) throw new Error('invalid_redirect');
}

export async function handleConsent(request, env, connect = connectArchive) {
  if (request.method === 'GET') {
    try {
      const auth = await env.OAUTH_PROVIDER.parseAuthRequest(request);
      validateAuthorization(auth);
      const client = await env.OAUTH_PROVIDER.lookupClient(auth.clientId);
      if (!client) throw new Error('unknown_client');
      const nonce = crypto.randomUUID();
      await env.OAUTH_KV.put(`consent:${await digest(nonce)}`, JSON.stringify({ auth, created: Date.now() }), { expirationTtl: CONSENT_TTL });
      const cookie = `${COOKIE}=${nonce}; Secure; HttpOnly; SameSite=Lax; Path=/; Max-Age=${CONSENT_TTL}`;
      return page(`<h2>Connect your private Markdown archive</h2><div class="identity">Requesting application: <strong>${escape(client.clientName || 'Unnamed application')}</strong><small>Client ID: ${escape(auth.clientId)}</small><small>Return address: ${escape(auth.redirectUri)}</small></div><p>Only continue if you recognize this application. Its name is supplied by the application, not a verification badge.</p><p>This connection can search and read Markdown in one private GitHub repository. It cannot save, edit or delete files. Requested sources pass through SourceBraid on Cloudflare to the connected application.</p><form method="post" action="/authorize"><input type="hidden" name="nonce" value="${nonce}"><label>Private repository (OWNER/REPO)<input name="repo" required maxlength="140" placeholder="your-name/your-private-archive" autocomplete="off"></label><label>Branch<input name="branch" required value="main" maxlength="255"></label><label>Archive folder<input name="root" required value="web-clips" maxlength="1024"></label><label>Fine-grained GitHub token<input type="password" name="token" required maxlength="512" autocomplete="off" spellcheck="false"></label><small>Create a separate token for only this repository, with Contents: Read-only and an expiry. Enter it only here, never in a chat. SourceBraid stores it encrypted with your OAuth grant; it is not returned to the connected application.</small><p><a href="https://github.com/settings/personal-access-tokens/new" target="_blank" rel="noopener noreferrer">Create a fine-grained GitHub token</a></p><label><input type="checkbox" name="consent" value="yes" required> I grant this application read access to this archive and understand the data flow.</label><button name="action" value="connect">Connect read-only archive</button><button name="action" value="cancel" formnovalidate>Cancel</button></form>`, 200, cookie);
    } catch { return page('<h2>Connection request rejected</h2><p>Start again from your application. SourceBraid requires a registered HTTPS return address, PKCE S256 and the archive:read scope.</p>', 400); }
  }
  if (request.method !== 'POST') return new Response(null, { status: 405, headers: secureHeaders({ Allow: 'GET, POST' }) });
  try {
    if (request.headers.get('origin') !== publicOrigin(env)
        || (request.headers.has('sec-fetch-site') && request.headers.get('sec-fetch-site') !== 'same-origin')
        || request.headers.get('content-type')?.split(';')[0].trim() !== 'application/x-www-form-urlencoded') throw new Error('invalid_request');
    const form = new URLSearchParams(await readLimited(request, 16_384));
    const allowed = ['nonce', 'repo', 'branch', 'root', 'token', 'consent', 'action'];
    if ([...form.keys()].some(key => !allowed.includes(key) || form.getAll(key).length !== 1)) throw new Error('invalid_fields');
    const nonce = form.get('nonce');
    const cookies = (request.headers.get('cookie') || '').split(';').map(value => value.trim()).filter(value => value.startsWith(`${COOKIE}=`));
    if (!/^[a-f0-9-]{36}$/.test(nonce || '') || cookies.length !== 1 || cookies[0] !== `${COOKIE}=${nonce}`) throw new Error('invalid_state');
    const key = `consent:${await digest(nonce)}`;
    const stored = await env.OAUTH_KV.get(key, 'json');
    if (!stored || Date.now() - stored.created > CONSENT_TTL * 1000) throw new Error('expired_state');
    await env.OAUTH_KV.delete(key);
    validateAuthorization(stored.auth);
    if (form.get('action') === 'cancel') return page('<h2>Connection cancelled</h2><p>No archive access was granted. You can close this window.</p>', 200, clearCookie());
    if (form.get('consent') !== 'yes' || form.get('action') !== 'connect') throw new Error('missing_consent');
    const token = form.get('token') || '';
    if (!token.startsWith('github_pat_')) throw new ArchiveError('Use a fine-grained GitHub token restricted to this repository, with Contents: Read-only.');
    const props = await connect({ repo: form.get('repo'), branch: form.get('branch'), root: form.get('root') }, token);
    const { redirectTo } = await env.OAUTH_PROVIDER.completeAuthorization({
      request: stored.auth, userId: `github-${props.userId}`, scope: [READ_SCOPE],
      metadata: { purpose: 'Read-only SourceBraid archive' }, props: { ...props, scopes: [READ_SCOPE] },
    });
    return new Response(null, { status: 303, headers: secureHeaders({ Location: redirectTo, 'Set-Cookie': clearCookie() }) });
  } catch (error) {
    return page(`<h2>Archive not connected</h2><p>${escape(error instanceof ArchiveError ? error.message : 'The connection request expired or could not be verified. Start again from your application.')}</p><p>No credentials are shown here. Check your token and private repository, then start a new connection.</p>`, 400, clearCookie());
  }
}
