import { OAuthProvider } from '@cloudflare/workers-oauth-provider';
import { handleConsent, publicOrigin, readLimited, READ_SCOPE, secureHeaders, VERSION } from './auth.mjs';
import { handleMcp } from './protocol.mjs';

const defaultHandler = { async fetch(request, env) {
  const path = new URL(request.url).pathname;
  if (path === '/authorize') return handleConsent(request, env);
  if (request.method === 'GET' && path === '/health') return Response.json({ service: 'SourceBraid', version: VERSION, readOnly: true }, { headers: secureHeaders() });
  if (request.method === 'GET' && path === '/.well-known/openai-apps-challenge' && env.OPENAI_VERIFICATION_TOKEN) return new Response(env.OPENAI_VERIFICATION_TOKEN, { headers: secureHeaders({ 'Content-Type': 'text/plain; charset=utf-8' }) });
  if (request.method === 'GET' && path === '/') return new Response('SourceBraid read-only MCP. Connect through your application using OAuth. Documentation: https://github.com/patrickschiller/sourcebraid/blob/main/docs/CHATGPT_PLUGIN.md', { headers: secureHeaders({ 'Content-Type': 'text/plain; charset=utf-8' }) });
  return new Response('Not found', { status: 404, headers: secureHeaders() });
} };

export default { async fetch(incoming, env, ctx) {
  try {
    const origin = publicOrigin(env);
    const url = new URL(incoming.url);
    if (url.origin !== origin || incoming.url.length > 8192) return new Response('Invalid origin or URL', { status: 400, headers: secureHeaders() });
    if (incoming.headers.has('origin') && incoming.headers.get('origin') !== origin) return new Response('Origin not allowed', { status: 403, headers: secureHeaders() });
    const limiter = url.pathname === '/mcp' ? env.MCP_RATE_LIMITER : env.AUTH_RATE_LIMITER;
    if (!limiter || !(await limiter.limit({ key: incoming.headers.get('cf-connecting-ip') || 'unknown' })).success) return new Response('Rate limit reached', { status: 429, headers: secureHeaders({ 'Retry-After': '60' }) });
    // Bound OAuth/DCR bodies as well as MCP bodies before the provider parses them.
    let request = incoming;
    if (!['GET', 'HEAD'].includes(request.method)) {
      let body;
      try { body = await readLimited(request, 65_536); } catch { return new Response('Request body too large', { status: 413, headers: secureHeaders() }); }
      request = new Request(request, { body });
    }
    const provider = new OAuthProvider({
      apiRoute: '/mcp', apiHandler: { fetch: handleMcp }, defaultHandler,
      authorizeEndpoint: '/authorize', tokenEndpoint: '/oauth/token', clientRegistrationEndpoint: '/oauth/register',
      accessTokenTTL: 3600, refreshTokenTTL: 2_592_000,
      // Published clients must not silently disappear when a registration TTL expires.
      // User grants still expire; remove unused registrations deliberately during maintenance.
      clientRegistrationTTL: undefined,
      allowImplicitFlow: false, allowPlainPKCE: false, clientIdMetadataDocumentEnabled: true,
      scopesSupported: [READ_SCOPE],
      resourceMetadata: { resource: `${origin}/mcp`, authorization_servers: [origin], scopes_supported: [READ_SCOPE], resource_name: 'SourceBraid' },
      tokenExchangeCallback: options => ({ accessTokenProps: { ...options.props, scopes: options.requestedScope } }),
      // Error descriptions from OAuth/upstream libraries must not enter request logs.
      onError: () => {},
    });
    const response = await provider.fetch(request, env, ctx);
    const headers = new Headers(response.headers);
    for (const [name, value] of Object.entries(secureHeaders())) headers.set(name, value);
    return new Response(response.body, { status: response.status, statusText: response.statusText, headers });
  } catch { return new Response('SourceBraid service unavailable', { status: 503, headers: secureHeaders() }); }
} };
