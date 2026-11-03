import test from 'node:test'
import assert from 'node:assert/strict'
import { createApp } from '../server/server.js'
import { createAi, sanitizeAssist, sanitizeBrief, extractJSON } from '../server/ai.js'

async function boot (opts) {
  const app = createApp(opts)
  await new Promise(r => app.listen(0, '127.0.0.1', r))
  const base = `http://127.0.0.1:${app.address().port}`
  return { base, close: () => new Promise(r => { app.close(r); app.closeAllConnections() }) }
}
const post = (base, p, body, headers = {}) => fetch(base + p, { method: 'POST', headers: { 'content-type': 'application/json', ...headers }, body: JSON.stringify(body) })

test('serves the app shell with security headers, blocks traversal', async () => {
  const { base, close } = await boot()
  const r = await fetch(base + '/')
  assert.equal(r.status, 200)
  assert.match(r.headers.get('content-security-policy'), /default-src 'self'/)
  assert.match(await r.text(), /<title>/)
  assert.equal((await fetch(base + '/lib/parse.js')).status, 200)
  assert.equal((await fetch(base + '/..%2fpackage.json')).status, 403)
  assert.equal((await fetch(base + '/nope.js')).status, 404)
  assert.equal((await (await fetch(base + '/healthz')).json()).ok, true)
  await close()
})

test('AI endpoints are off without a key', async () => {
  const { base, close } = await boot()
  assert.deepEqual(await (await fetch(base + '/api/config')).json(), { ai: false, authRequired: false })
  assert.equal((await post(base, '/api/assist', { text: 'x' })).status, 503)
  await close()
})

test('assist validates input, enforces token, and sanitizes model output', async () => {
  let seen
  const fetchImpl = async (url, init) => {
    seen = JSON.parse(init.body)
    return new Response(JSON.stringify({ content: [{ type: 'text', text: 'Sure! {"title":"Call mum","due":"2026-11-04T17:00","tags":["#Family","x y!"],"priority":9,"repeat":{"unit":"fortnight"},"evil":"<script>"}' }] }))
  }
  const ai = createAi({ apiKey: 'k', fetchImpl })
  const { base, close } = await boot({ ai, token: 's3cret' })
  assert.equal((await post(base, '/api/assist', { text: 'x' })).status, 401)
  const h = { authorization: 'Bearer s3cret' }
  assert.equal((await post(base, '/api/assist', {}, h)).status, 400)
  const r = await post(base, '/api/assist', { text: 'call mum tmrw 5pm', now: '2026-11-03T10:00', tz: 'UTC', memory: [{ title: 'Call mum', tags: ['family'], status: 'done', timesDone: 4 }] }, h)
  assert.deepEqual(await r.json(), { title: 'Call mum', due: '2026-11-04T17:00', tags: ['family', 'xy'] })
  assert.equal(seen.model, 'claude-haiku-5-5')
  assert.match(seen.messages[0].content, /<memory>.*Call mum/)
  await close()
})

test('upstream failure becomes 502, oversize body 413, rate limit 429', async () => {
  const ai = createAi({ apiKey: 'k', fetchImpl: async () => new Response('boom', { status: 500 }) })
  const { base, close } = await boot({ ai, rateLimit: 3 })
  assert.equal((await post(base, '/api/assist', { text: 'x' })).status, 502)
  assert.equal((await post(base, '/api/assist', { text: 'x'.repeat(70000) })).status, 413)
  await post(base, '/api/assist', { text: 'x' })
  assert.equal((await post(base, '/api/assist', { text: 'x' })).status, 429)
  await close()
})

test('sanitizers', () => {
  assert.deepEqual(sanitizeAssist({ title: '  Hi  ', note: 5, due: 'tomorrow', priority: 1, repeat: { unit: 'week', interval: 2, weekdays: [1, 9, 1] } }), { title: 'Hi', priority: 1, repeat: { unit: 'week', interval: 2, weekdays: [1] } })
  assert.deepEqual(sanitizeBrief({ message: 'Hello', focus: ['a', 'zzz'] }, new Set(['a'])), { message: 'Hello', focus: ['a'] })
  assert.throws(() => sanitizeBrief({}, new Set()))
  assert.throws(() => extractJSON('no json'))
})
