// Proactive insights computed locally from memory — works offline, no AI required.
import { isOpen, completionTimes, titleKey } from './memory.js'
import { isOverdue, isToday, startOfDay } from './parse.js'

const DAY = 86400000
const median = xs => { const s = [...xs].sort((a, b) => a - b); const m = s.length >> 1; return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2 }

/** Habits: things you keep doing at a steady rhythm that you haven't re-added yet. */
export function detectHabits (todos, now = new Date()) {
  const groups = new Map()
  for (const t of todos) {
    const k = titleKey(t.title)
    if (!k) continue
    const g = groups.get(k) || { key: k, title: t.title, latest: 0, times: [], open: false, sample: t }
    g.times.push(...completionTimes(t))
    if (isOpen(t)) g.open = true
    if (t.updated > g.latest) { g.latest = t.updated; g.title = t.title; g.sample = t }
    groups.set(k, g)
  }
  const habits = []
  for (const g of groups.values()) {
    if (g.open) continue
    // One completion per calendar day, so double-taps don't fake a rhythm.
    const days = [...new Set(g.times.map(x => startOfDay(new Date(x)).getTime()))].sort((a, b) => a - b)
    if (days.length < 3) continue
    const gaps = days.slice(1).map((d, i) => Math.round((d - days[i]) / DAY)).filter(x => x >= 1)
    if (gaps.length < 2) continue
    const typical = Math.max(1, Math.round(median(gaps)))
    const since = Math.floor((startOfDay(now) - days[days.length - 1]) / DAY)
    if (since >= typical * 0.85 && since <= typical * 3) habits.push({ title: g.title, typical, since, count: days.length, sample: g.sample })
  }
  return habits.sort((a, b) => b.since / b.typical - a.since / a.typical)
}

/**
 * Returns insights, most important first:
 * { id, kind: 'overdue'|'today'|'stale'|'habit', text, todoIds, actions: [{label, do}], title? }
 */
export function insights (todos, now = new Date()) {
  const open = todos.filter(isOpen)
  const out = []

  const overdue = open.filter(t => isOverdue(t, now)).sort((a, b) => new Date(a.due) - new Date(b.due))
  if (overdue.length) {
    out.push({
      id: 'overdue',
      kind: 'overdue',
      text: overdue.length === 1 ? `Overdue: ${overdue[0].title}` : `${overdue.length} overdue — oldest is “${overdue[0].title}”`,
      todoIds: overdue.map(t => t.id),
      actions: [{ label: 'Move to today', do: 'reschedule-today' }]
    })
  }

  const today = open.filter(t => isToday(t, now))
  if (today.length) {
    out.push({ id: 'today', kind: 'today', text: today.length === 1 ? `Due today: ${today[0].title}` : `${today.length} things due today`, todoIds: today.map(t => t.id), actions: [] })
  }

  const cutoff = now.getTime() - 14 * DAY
  const stale = open.filter(t => !t.due && t.updated < cutoff).sort((a, b) => a.updated - b.updated)[0]
  if (stale) {
    const age = Math.floor((now.getTime() - stale.updated) / DAY)
    out.push({
      id: 'stale:' + stale.id,
      kind: 'stale',
      text: `“${stale.title}” has sat untouched for ${age} days. Still want it?`,
      todoIds: [stale.id],
      actions: [{ label: 'Do today', do: 'schedule-today' }, { label: 'Drop it', do: 'drop' }]
    })
  }

  for (const h of detectHabits(todos, now).slice(0, 2)) {
    const every = h.typical === 1 ? 'every day' : h.typical === 7 ? 'every week' : `every ~${h.typical} days`
    out.push({
      id: 'habit:' + titleKey(h.title),
      kind: 'habit',
      text: `You usually do “${h.title}” ${every} — last time was ${h.since === 0 ? 'today' : h.since + (h.since === 1 ? ' day' : ' days') + ' ago'}.`,
      todoIds: [],
      title: h.title,
      habitId: h.sample.id,
      actions: [{ label: 'Add it', do: 'add-habit' }]
    })
  }
  return out
}

/** Small summary handed to the AI so its daily brief is grounded in real memory. */
export function briefContext (todos, now = new Date()) {
  const open = todos.filter(isOpen)
  const recent = todos.flatMap(t => completionTimes(t).map(ts => ({ title: t.title, ts }))).sort((a, b) => b.ts - a.ts).slice(0, 10)
  return {
    open: open.slice(0, 40).map(t => ({ id: t.id, title: t.title, due: t.due, allDay: t.allDay, priority: t.priority, tags: t.tags, overdue: isOverdue(t, now), ageDays: Math.floor((now.getTime() - t.created) / DAY) })),
    recentlyDone: recent.map(r => ({ title: r.title, daysAgo: Math.floor((now.getTime() - r.ts) / DAY) })),
    habits: detectHabits(todos, now).slice(0, 3).map(h => ({ title: h.title, everyDays: h.typical, daysSince: h.since }))
  }
}

