import test from 'node:test'
import assert from 'node:assert/strict'
import { Store, MemoryAdapter, tokens } from '../public/lib/memory.js'
import { insights, detectHabits } from '../public/lib/proactive.js'

const day = n => new Date(2026, 10, 3 + n, 10, 0, 0)
const mk = (t = day(0)) => { const clock = { t }; const s = new Store(new MemoryAdapter(), { now: () => clock.t }); return { s, clock } }

test('add persists through the adapter and survives reload', () => {
  const adapter = new MemoryAdapter()
  const s = new Store(adapter, { now: () => day(0) })
  s.add('Book flights #travel')
  const again = new Store(adapter)
  assert.equal(again.all().length, 1)
  assert.deepEqual(again.all()[0].tags, ['travel'])
})

test('open duplicates are caught', () => {
  const { s } = mk()
  s.add('Buy oat milk')
  const r = s.add('buy oat milk!')
  assert.ok(r.duplicate)
  assert.equal(s.all().length, 1)
})

test('nothing is forgotten: done and deleted items are recalled', () => {
  const { s } = mk()
  const a = s.add('Renew car insurance #car').todo
  const b = s.add('Call plumber about kitchen tap').todo
  s.complete(a.id)
  s.remove(b.id)
  assert.equal(s.recall('insurance')[0].todo.id, a.id)
  assert.equal(s.recall('plumb')[0].todo.id, b.id) // prefix while typing
  assert.equal(s.recall('plumb ').length, 0) // finished word must match fully
  assert.equal(s.recall('kitchen tap')[0].todo.id, b.id)
  assert.equal(s.recall('zebra').length, 0)
})

test('writing a todo recalls and reuses what you did before', () => {
  const { s, clock } = mk()
  const first = s.add('Pay rent #home !').todo
  s.update(first.id, { note: 'Transfer to Ana, ref 2204' })
  s.complete(first.id)
  clock.t = day(30)
  const r = s.add('pay the rent')
  assert.equal(r.prior.id, first.id)
  assert.deepEqual(r.todo.tags, ['home'])
  assert.equal(r.todo.priority, 1)
  assert.equal(r.todo.note, 'Transfer to Ana, ref 2204')
  assert.deepEqual(r.inherited.sort(), ['note', 'priority', 'tags'])
})

test('explicit input beats inherited memory', () => {
  const { s } = mk()
  const first = s.add('Pay rent #home').todo
  s.complete(first.id)
  const r = s.add('Pay rent #bills')
  assert.deepEqual(r.todo.tags, ['bills'])
})

test('completing a repeating todo rolls it forward and remembers each completion', () => {
  const { s, clock } = mk()
  const t = s.add('Water plants every 2 days').todo
  s.complete(t.id)
  const after = s.get(t.id)
  assert.equal(after.done, null)
  assert.equal(after.completions.length, 1)
  assert.ok(new Date(after.due) > clock.t)
})

test('undo restores a snapshot', () => {
  const { s } = mk()
  const t = s.add('One off').todo
  const { before } = s.complete(t.id)
  assert.ok(s.get(t.id).done)
  s.replace(before)
  assert.equal(s.get(t.id).done, null)
})

test('readd recreates a finished todo, restores a deleted one', () => {
  const { s } = mk()
  const a = s.add('Take vitamins #health').todo
  s.complete(a.id)
  const r = s.readd(a.id)
  assert.notEqual(r.todo.id, a.id)
  assert.deepEqual(r.todo.tags, ['health'])
  const b = s.add('Something else').todo
  s.remove(b.id)
  assert.equal(s.readd(b.id).todo.id, b.id)
  assert.equal(s.get(b.id).deleted, null)
})

test('export / import round-trips and merges by recency', () => {
  const { s } = mk()
  s.add('Alpha'); s.add('Beta')
  const dump = s.exportJSON()
  const { s: other } = mk()
  assert.equal(other.importJSON(dump), 2)
  assert.equal(other.importJSON(dump), 0)
  assert.throws(() => other.importJSON('{"nope":1}'))
})

test('tokens stem and drop stop words', () => {
  assert.deepEqual(tokens('Buying the 3 apples'), ['buy', '3', 'apple'])
})

test('insights: overdue, today, stale', () => {
  const { s } = mk()
  const o = s.add('Send invoice yesterday').todo
  s.update(o.id, { due: day(-1).toISOString(), allDay: true })
  s.add('Email Sam today')
  const old = s.add('Learn piano').todo
  s.update(old.id, { updated: day(-40).getTime() }, { touch: false })
  const kinds = insights(s.all(), day(0)).map(i => i.kind)
  assert.deepEqual(kinds, ['overdue', 'today', 'stale'])
})

test('insights: learns a weekly habit and nudges when due again', () => {
  const { s, clock } = mk(day(-21))
  for (const n of [-21, -14, -7]) {
    clock.t = day(n)
    const t = s.add('Take out recycling').todo
    s.complete(t.id)
  }
  const habits = detectHabits(s.all(), day(0))
  assert.equal(habits.length, 1)
  assert.equal(habits[0].typical, 7)
  assert.equal(insights(s.all(), day(0)).find(i => i.kind === 'habit').actions[0].do, 'add-habit')
  assert.equal(detectHabits(s.all(), day(-3)).length, 0) // too soon
  s.add('Take out recycling')
  assert.equal(detectHabits(s.all(), day(0)).length, 0) // already open
})
