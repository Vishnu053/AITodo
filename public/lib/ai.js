// Client for the optional AI endpoints. Every call degrades silently: the app is fully
// usable offline and without a key, AI only ever refines what local logic already did.
const tz = () => Intl.DateTimeFormat().resolvedOptions().timeZone || ''
const localNow = d => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}T${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')} ${['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'][d.getDay()]}`

export class AiClient {
  constructor (getToken) { this.getToken = getToken; this.config = { ai: false, authRequired: false } }

  async init () {
    try {
      const r = await fetch('api/config', { cache: 'no-store' })
      if (r.ok) this.config = await r.json()
    } catch { /* offline */ }
    return this.config
  }

  get available () { return !!this.config.ai }

  async _post (path, body) {
    const headers = { 'content-type': 'application/json' }
    const token = this.getToken()
    if (token) headers.authorization = 'Bearer ' + token
    const r = await fetch(path, { method: 'POST', headers, body: JSON.stringify(body), signal: AbortSignal.timeout(20000) })
    if (!r.ok) throw new Error(String(r.status))
    return r.json()
  }

  assist (text, memory, now = new Date()) {
    return this._post('api/assist', { text, now: localNow(now), tz: tz(), memory })
  }

  brief (context, now = new Date()) {
    return this._post('api/brief', { now: localNow(now), tz: tz(), context })
  }
}
