// Zero-dependency server: static PWA + a thin, authenticated, rate-limited AI proxy.
import http from 'node:http'
import { readFile, stat } from 'node:fs/promises'
import path from 'node:path'
import crypto from 'node:crypto'
import { fileURLToPath } from 'node:url'
import { createAi } from './ai.js'

const HERE = path.dirname(fileURLToPath(import.meta.url))
const MIME = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8', '.json': 'application/json', '.webmanifest': 'application/manifest+json', '.png': 'image/png', '.svg': 'image/svg+xml', '.ico': 'image/x-icon' }
const SECURITY = {
  'content-security-policy': "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; manifest-src 'self'; worker-src 'self'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'",
  'x-content-type-options': 'nosniff',
  'referrer-policy': 'no-referrer',
  'permissions-policy': 'camera=(), microphone=(), geolocation=()'
}
const MAX_BODY = 64 * 1024

export function createApp ({ ai = createAi({}), token = '', publicDir = path.join(HERE, '..', 'public'), rateLimit = 60, trustProxy = false } = {}) {
  const hits = new Map()
  const limited = ip => {
    const now = Date.now()
    const h = hits.get(ip)
    if (!h || h.reset < now) { hits.set(ip, { n: 1, reset: now + 60000 }); return false }
    return ++h.n > rateLimit
  }
  const sweep = setInterval(() => { const now = Date.now(); for (const [k, v] of hits) if (v.reset < now) hits.delete(k) }, 60000)
  sweep.unref()

  const send = (res, code, body, headers = {}) => {
    const isObj = body !== null && typeof body === 'object' && !Buffer.isBuffer(body)
    res.writeHead(code, { ...SECURITY, ...(isObj ? { 'content-type': 'application/json', 'cache-control': 'no-store' } : {}), ...headers })
    res.end(isObj ? JSON.stringify(body) : body)
  }

  const authorized = req => {
    if (!token) return true
    const given = Buffer.from((req.headers.authorization || '').replace(/^Bearer\s+/i, ''))
    const want = Buffer.from(token)
    return given.length === want.length && crypto.timingSafeEqual(given, want)
  }

  async function readJSON (req) {
    let size = 0
    const chunks = []
    for await (const c of req) {
      size += c.length
      if (size > MAX_BODY) throw Object.assign(new Error('too large'), { code: 413 })
      chunks.push(c)
    }
    try { return JSON.parse(Buffer.concat(chunks).toString('utf8')) } catch { throw Object.assign(new Error('bad json'), { code: 400 }) }
  }

  async function api (req, res, url) {
    if (url.pathname === '/api/config' && req.method === 'GET') return send(res, 200, { ai: ai.enabled, authRequired: !!token })
    if (!authorized(req)) return send(res, 401, { error: 'unauthorized' })
    const ip = (trustProxy && String(req.headers['x-forwarded-for'] || '').split(',')[0].trim()) || req.socket.remoteAddress || 'unknown'
    if (limited(ip)) return send(res, 429, { error: 'slow down' }, { 'retry-after': '30' })
    if (req.method !== 'POST' || !['/api/assist', '/api/brief'].includes(url.pathname)) return send(res, 404, { error: 'not found' })
    if (!ai.enabled) return send(res, 503, { error: 'ai disabled' })
    try {
      const body = await readJSON(req)
      if (typeof body !== 'object' || body === null) return send(res, 400, { error: 'bad request' })
      if (url.pathname === '/api/assist') {
        if (typeof body.text !== 'string' || !body.text.trim()) return send(res, 400, { error: 'text required' })
        return send(res, 200, await ai.assist(body))
      }
      if (!body.context) return send(res, 400, { error: 'context required' })
      return send(res, 200, await ai.brief(body))
    } catch (e) {
      if (e.code === 413 || e.code === 400) return send(res, e.code, { error: e.message })
      console.error('ai error:', e.message)
      return send(res, 502, { error: 'ai unavailable' })
    }
  }

  async function serveStatic (req, res, url) {
    if (req.method !== 'GET' && req.method !== 'HEAD') return send(res, 405, 'Method not allowed')
    let rel
    try { rel = decodeURIComponent(url.pathname) } catch { return send(res, 400, 'Bad request') }
    if (rel.endsWith('/')) rel += 'index.html'
    const file = path.join(publicDir, rel)
    if (file !== publicDir && !file.startsWith(publicDir + path.sep)) return send(res, 403, 'Forbidden')
    try {
      const st = await stat(file)
      if (!st.isFile()) throw new Error('not file')
      const etag = `"${st.size.toString(16)}-${Math.floor(st.mtimeMs).toString(16)}"`
      const headers = { 'content-type': MIME[path.extname(file)] || 'application/octet-stream', etag, 'cache-control': 'no-cache' }
      if (req.headers['if-none-match'] === etag) return send(res, 304, '', headers)
      return send(res, 200, req.method === 'HEAD' ? '' : await readFile(file), headers)
    } catch {
      return send(res, 404, 'Not found')
    }
  }

  return http.createServer(async (req, res) => {
    try {
      const url = new URL(req.url, 'http://localhost')
      if (url.pathname === '/healthz') return send(res, 200, { ok: true })
      if (url.pathname.startsWith('/api/')) return await api(req, res, url)
      return await serveStatic(req, res, url)
    } catch (e) {
      console.error(e)
      if (!res.headersSent) send(res, 500, 'Server error')
    }
  })
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const ai = createAi({ apiKey: process.env.ANTHROPIC_API_KEY, model: process.env.AI_MODEL || undefined })
  const app = createApp({ ai, token: process.env.ACCESS_TOKEN || '', trustProxy: process.env.TRUST_PROXY === '1' })
  const port = +process.env.PORT || 3000
  app.listen(port, process.env.HOST || '0.0.0.0', () => {
    console.log(`AI Todo on :${port} — AI ${ai.enabled ? `enabled (${ai.model})` : 'disabled (set ANTHROPIC_API_KEY)'}${process.env.ACCESS_TOKEN ? ', token required' : ''}`)
  })
  for (const sig of ['SIGINT', 'SIGTERM']) process.on(sig, () => app.close(() => process.exit(0)))
}
