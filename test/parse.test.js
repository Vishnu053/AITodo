import test from 'node:test'
import assert from 'node:assert/strict'
import { parseTodo, nextDue, formatDue, parseLocal, describeRepeat, isOverdue } from '../public/lib/parse.js'

// Tuesday 3 Nov 2026, 10:00 local
const NOW = new Date(2026, 10, 3, 10, 0, 0)
const local = iso => { const d = new Date(iso); return [d.getFullYear(), d.getMonth() + 1, d.getDate(), d.getHours(), d.getMinutes()] }

test('plain text stays a title', () => {
  const p = parseTodo('buy oat milk', NOW)
  assert.equal(p.title, 'Buy oat milk')
  assert.equal(p.due, null)
})

test('tomorrow + time + tag + priority', () => {
  const p = parseTodo('call mum tomorrow at 5pm #family !!', NOW)
  assert.equal(p.title, 'Call mum')
  assert.deepEqual(local(p.due), [2026, 11, 4, 17, 0])
  assert.equal(p.allDay, false)
  assert.deepEqual(p.tags, ['family'])
  assert.equal(p.priority, 2)
})

test('weekday means the next one, not today', () => {
  assert.deepEqual(local(parseTodo('review on friday', NOW).due).slice(0, 3), [2026, 11, 6])
  assert.deepEqual(local(parseTodo('standup tuesday', NOW).due).slice(0, 3), [2026, 11, 10])
})

test('bare ambiguous short words are not dates', () => {
  assert.equal(parseTodo('watch the sun set', NOW).due, null)
  assert.equal(parseTodo('mon', NOW).title, 'Mon')
})

test('relative times', () => {
  assert.equal(new Date(parseTodo('stretch in 2 hours', NOW).due).getTime(), NOW.getTime() + 7200000)
  assert.deepEqual(local(parseTodo('renew passport in 3 days', NOW).due).slice(0, 3), [2026, 11, 6])
})

test('time-only rolls to tomorrow when already passed', () => {
  assert.deepEqual(local(parseTodo('gym 7am', NOW).due), [2026, 11, 4, 7, 0])
  assert.deepEqual(local(parseTodo('lunch at 12:30', NOW).due), [2026, 11, 3, 12, 30])
})

test('explicit dates, year rollover', () => {
  assert.deepEqual(local(parseTodo('dentist nov 20', NOW).due).slice(0, 3), [2026, 11, 20])
  assert.deepEqual(local(parseTodo('taxes 5 jan', NOW).due).slice(0, 3), [2027, 1, 5])
  assert.deepEqual(local(parseTodo('send invoice nov 1', NOW).due).slice(0, 3), [2026, 11, 1]) // recent past stays overdue
  assert.deepEqual(local(parseTodo('flight 2027-03-09', NOW).due).slice(0, 3), [2027, 3, 9])
})

test('repetition', () => {
  assert.deepEqual(parseTodo('water plants every 3 days', NOW).repeat, { unit: 'day', interval: 3 })
  const w = parseTodo('team sync every monday 9am', NOW)
  assert.deepEqual(w.repeat, { unit: 'week', interval: 1, weekdays: [1] })
  assert.deepEqual(local(w.due), [2026, 11, 9, 9, 0])
  assert.equal(w.title, 'Team sync')
  assert.equal(parseTodo('floss daily', NOW).repeat.unit, 'day')
  assert.equal(describeRepeat(parseTodo('x every weekday', NOW).repeat), 'Every weekday')
})

test('empty-after-parse keeps something sensible', () => {
  assert.equal(parseTodo('tomorrow', NOW).title, 'Tomorrow')
})

test('nextDue rolls forward past today', () => {
  const t = { due: new Date(2026, 10, 3).toISOString(), allDay: true, repeat: { unit: 'day', interval: 1 } }
  assert.deepEqual(local(nextDue(t, NOW)).slice(0, 3), [2026, 11, 4])
  const late = { due: new Date(2026, 9, 1).toISOString(), allDay: true, repeat: { unit: 'week', interval: 1, weekdays: [1] } }
  assert.deepEqual(local(nextDue(late, NOW)).slice(0, 3), [2026, 11, 9])
  const monthly = { due: new Date(2026, 0, 31).toISOString(), allDay: true, repeat: { unit: 'month', interval: 1 } }
  assert.equal(new Date(nextDue(monthly, NOW)).getMonth(), 10)
})

test('formatting and overdue', () => {
  assert.equal(formatDue(new Date(2026, 10, 3).toISOString(), true, NOW, 'en-US'), 'Today')
  assert.equal(formatDue(new Date(2026, 10, 4, 17, 0).toISOString(), false, NOW, 'en-US'), 'Tomorrow, 5:00 PM')
  assert.equal(isOverdue({ due: new Date(2026, 10, 3).toISOString(), allDay: true }, NOW), false)
  assert.equal(isOverdue({ due: new Date(2026, 10, 2).toISOString(), allDay: true }, NOW), true)
  assert.equal(isOverdue({ due: new Date(2026, 10, 3, 9).toISOString(), allDay: false }, NOW), true)
})

test('parseLocal', () => {
  assert.equal(parseLocal('nope'), null)
  assert.equal(parseLocal('2026-11-05').allDay, true)
  assert.equal(parseLocal('2026-11-05T14:30').allDay, false)
})
