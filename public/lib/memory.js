// Memory: an append-only-in-spirit store. Nothing is ever hard-deleted, so everything
// the user has ever written can be recalled, searched and reused.
import { parseTodo, nextDue } from './parse.js'

const STOP = new Set('a an the and or of to for in on at by with from is are be it this that my me i we you your so do get go as if into up out'.split(' '))

export function stem (w) {
  if (w.length > 5 && w.endsWith('ing')) return w.slice(0, -3)
  if (w.length > 4 && w.endsWith('ies')) return w.slice(0, -3) + 'y'
  if (w.length > 4 && w.endsWith('ed')) return w.slice(0, -2)
  if (w.length > 3 && w.endsWith('s') && !w.endsWith('ss')) return w.slice(0, -1)
  return w
}

export function tokens (text) {
  return String(text || '').toLowerCase().split(/[^\p{L}\p{N}]+/u).filter(w => w && !STOP.has(w) && (w.length > 1 || /\d/.test(w))).map(stem)
}

export const titleKey = title => [...new Set(tokens(title))].sort().join(' ')

export function jaccard (a, b) {
  const A = new Set(a); const B = new Set(b)
  if (!A.size || !B.size) return 0
  let i = 0
  for (const x of A) if (B.has(x)) i++
  return i / (A.size + B.size - i)
}

export const isOpen = t => !t.done && !t.deleted
export const status = t => (t.deleted ? 'deleted' : t.done ? 'done' : 'open')
export const completionTimes = t => (t.completions && t.completions.length ? t.completions : t.done ? [t.done] : [])

const uid = () => (globalThis.crypto && crypto.randomUUID ? crypto.randomUUID() : 'id-' + Date.now().toString(36) + Math.random().toString(36).slice(2, 10))

/** Storage adapters: { load(): object|null, save(state) }. */
export class MemoryAdapter {
  constructor (initial = null) { this.data = initial }
  load () { return this.data }
  save (s) { this.data = JSON.parse(JSON.stringify(s)) }
}

export class LocalStorageAdapter {
  constructor (key = 'aitodo.v1') { this.key = key }
  load () { try { return JSON.parse(localStorage.getItem(this.key)) } catch { return null } }
  save (s) { localStorage.setItem(this.key, JSON.stringify(s)) }
}

export class Store {
  constructor (adapter, { now = () => new Date(), onError = () => {} } = {}) {
    this.adapter = adapter
    this.now = now
    this.onError = onError
    this.listeners = new Set()
    const data = adapter.load()
    this.state = data && data.todos ? data : { v: 1, todos: {} }
  }

  subscribe (fn) { this.listeners.add(fn); return () => this.listeners.delete(fn) }

  _commit () {
    try { this.adapter.save(this.state) } catch (e) { this.onError(e) }
    this.listeners.forEach(fn => fn())
  }

  all () { return Object.values(this.state.todos) }
  get (id) { return this.state.todos[id] || null }
  open () { return this.all().filter(isOpen) }

  add (text) {
    const now = this.now()
    const p = parseTodo(text, now)
    if (!tokens(p.title).length && !p.title.trim()) return { error: 'empty' }
    const toks = tokens(p.title)
    const dup = toks.length ? this.open().find(t => jaccard(tokens(t.title), toks) >= 0.85) : null
    if (dup) return { duplicate: dup }

    const inherited = []
    const prior = this.findPrior(p.title)
    const todo = {
      id: uid(),
      title: p.title,
      note: '',
      created: now.getTime(),
      updated: now.getTime(),
      due: p.due,
      allDay: p.allDay,
      repeat: p.repeat,
      priority: p.priority,
      tags: p.tags,
      done: null,
      deleted: null,
      completions: [],
      notified: null
    }
    if (prior) {
      if (!todo.tags.length && prior.tags.length) { todo.tags = [...prior.tags]; inherited.push('tags') }
      if (!todo.priority && prior.priority) { todo.priority = prior.priority; inherited.push('priority') }
      if (prior.note) { todo.note = prior.note; inherited.push('note') }
    }
    this.state.todos[todo.id] = todo
    this._commit()
    return { todo, inherited, prior: prior || null }
  }

  /** Re-create a todo from an earlier one ("add again"). */
  readd (id) {
    const src = this.get(id)
    if (!src) return { error: 'missing' }
    if (isOpen(src)) return { duplicate: src }
    if (src.deleted) { return { todo: this.restore(id), restored: true } }
    const now = this.now()
    const todo = { ...src, id: uid(), created: now.getTime(), updated: now.getTime(), due: null, allDay: true, done: null, deleted: null, completions: [], notified: null }
    if (src.repeat) { todo.due = nextDue({ ...src, due: null, allDay: true }, now); }
    this.state.todos[todo.id] = todo
    this._commit()
    return { todo }
  }

  update (id, patch, { touch = true } = {}) {
    const t = this.get(id)
    if (!t) return null
    Object.assign(t, patch)
    if (touch) t.updated = this.now().getTime()
    this._commit()
    return t
  }

  complete (id) {
    const t = this.get(id)
    if (!t || !isOpen(t)) return null
    const before = JSON.parse(JSON.stringify(t))
    const now = this.now()
    t.completions = [...(t.completions || []), now.getTime()]
    t.updated = now.getTime()
    t.notified = null
    const next = nextDue(t, now)
    if (t.repeat && next) t.due = next
    else t.done = now.getTime()
    this._commit()
    return { todo: t, before, rolled: !!(t.repeat && next) }
  }

  uncomplete (id) {
    const t = this.get(id)
    if (!t) return null
    t.done = null
    t.completions = (t.completions || []).slice(0, -1)
    t.updated = this.now().getTime()
    this._commit()
    return t
  }

  /** Put a todo back exactly as it was (undo). */
  replace (snapshot) {
    this.state.todos[snapshot.id] = snapshot
    this._commit()
    return snapshot
  }

  remove (id) { return this.update(id, { deleted: this.now().getTime() }) }
  restore (id) { return this.update(id, { deleted: null, done: null }) }

  /** Most recent earlier todo (any state) that is essentially the same task. */
  findPrior (title, minSim = 0.6) {
    const toks = tokens(title)
    if (!toks.length) return null
    let best = null
    let bestScore = 0
    for (const t of this.all()) {
      const s = jaccard(tokens(t.title), toks)
      if (s >= minSim && (s > bestScore || (s === bestScore && best && t.updated > best.updated))) { best = t; bestScore = s }
    }
    return best
  }

  /**
   * Recall anything ever written that relates to the query, including done and deleted items.
   * The last word is treated as a prefix so results appear while typing.
   */
  recall (query, { limit = 5, exclude = null } = {}) {
    const qt = tokens(query)
    if (!qt.length) return []
    const raw = String(query).trimEnd()
    const typing = raw.length === String(query).length // no trailing space: last word may be partial
    const todos = this.all().filter(t => t.id !== exclude)
    const docs = todos.map(t => ({
      t,
      title: new Set(tokens(t.title)),
      rest: new Set([...tokens(t.note), ...t.tags.flatMap(tokens)])
    }))
    const df = new Map()
    for (const d of docs) for (const w of new Set([...d.title, ...d.rest])) df.set(w, (df.get(w) || 0) + 1)
    const idf = w => Math.log(1 + docs.length / (1 + (df.get(w) || 0)))
    const total = qt.reduce((a, w) => a + idf(w), 0) || 1

    const results = []
    for (const d of docs) {
      let score = 0
      qt.forEach((w, i) => {
        const prefix = typing && i === qt.length - 1 && w.length >= 2
        const hit = (set, weight) => {
          if (set.has(w)) return weight
          if (prefix) for (const x of set) if (x.startsWith(w)) return weight * 0.7
          return 0
        }
        score += idf(w) * Math.max(hit(d.title, 1), hit(d.rest, 0.6))
      })
      score /= total
      if (score >= 0.5) results.push({ todo: d.t, score })
    }
    results.sort((a, b) => b.score - a.score || (b.todo.updated - a.todo.updated))
    return results.slice(0, limit)
  }

  exportJSON () { return JSON.stringify({ app: 'aitodo', ...this.state }, null, 2) }

  importJSON (text) {
    const data = JSON.parse(text)
    if (!data || typeof data.todos !== 'object') throw new Error('Not an AI Todo export')
    let added = 0
    for (const t of Object.values(data.todos)) {
      if (!t || typeof t.id !== 'string' || typeof t.title !== 'string') continue
      const existing = this.state.todos[t.id]
      if (!existing || (t.updated || 0) > (existing.updated || 0)) {
        this.state.todos[t.id] = { note: '', tags: [], priority: 0, completions: [], done: null, deleted: null, allDay: true, repeat: null, due: null, notified: null, created: Date.now(), updated: Date.now(), ...t }
        added++
      }
    }
    this._commit()
    return added
  }
}
