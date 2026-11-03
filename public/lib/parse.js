// Natural-language todo parsing and date helpers. Pure, no DOM, runs in browser and Node.

const DAYS = ['sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday']
const MONTHS = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec']
const DAY_RE = '(sunday|sun|monday|mon|tuesday|tues|tue|wednesday|wed|thursday|thurs|thur|thu|friday|fri|saturday|sat)'
const MONTH_RE = '(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)'

export const startOfDay = d => { const x = new Date(d); x.setHours(0, 0, 0, 0); return x }
export const addDays = (d, n) => { const x = new Date(d); x.setDate(x.getDate() + n); return x }
export const sameDay = (a, b) => startOfDay(a).getTime() === startOfDay(b).getTime()
const dayIndex = name => DAYS.findIndex(d => d.startsWith(name.slice(0, 3)))
const monthIndex = name => MONTHS.indexOf(name.slice(0, 3))

export function addMonths (d, n) {
  const x = new Date(d)
  const day = x.getDate()
  x.setDate(1)
  x.setMonth(x.getMonth() + n)
  const last = new Date(x.getFullYear(), x.getMonth() + 1, 0).getDate()
  x.setDate(Math.min(day, last))
  return x
}

function nextWeekday (from, dow, inclusive) {
  let diff = (dow - from.getDay() + 7) % 7
  if (diff === 0 && !inclusive) diff = 7
  return addDays(startOfDay(from), diff)
}

function hourFromBare (h) { return h >= 1 && h <= 6 ? h + 12 : h } // "at 5" means 5pm, "at 9" means 9am

/**
 * Parse free text such as "call mum tomorrow 5pm #family !" into a structured todo.
 * due is an ISO string (or null); allDay is true when no time of day was given.
 */
export function parseTodo (input, now = new Date()) {
  let s = ' ' + String(input || '').replace(/\s+/g, ' ').trim() + ' '
  const original = s.trim()
  const out = { title: '', due: null, allDay: true, repeat: null, priority: 0, tags: [] }
  const take = (re, fn) => {
    const m = re.exec(s)
    if (!m) return false
    s = s.slice(0, m.index) + ' ' + s.slice(m.index + m[0].length)
    fn(m)
    return true
  }

  s = s.replace(/(\s)#([\p{L}\p{N}][\p{L}\p{N}_-]*)/gu, (_, sp, t) => {
    const tag = t.toLowerCase()
    if (!out.tags.includes(tag)) out.tags.push(tag)
    return sp
  })
  s = s.replace(/(\s)(!{1,3})(?=\s)/g, (_, sp, bang) => { out.priority = Math.min(2, bang.length); return sp })

  // Repetition
  let weekdaysAnchor = null
  take(/\bevery\s+(\d+)\s+(day|week|month|year)s?\b/i, m => {
    const unit = m[2].toLowerCase()
    out.repeat = unit === 'year' ? { unit: 'month', interval: 12 * +m[1] } : { unit, interval: +m[1] }
  }) ||
  take(/\bevery\s+weekday\b/i, () => { out.repeat = { unit: 'week', interval: 1, weekdays: [1, 2, 3, 4, 5] } }) ||
  take(new RegExp(`\\bevery\\s+${DAY_RE}\\b`, 'i'), m => {
    const dow = dayIndex(m[1].toLowerCase())
    out.repeat = { unit: 'week', interval: 1, weekdays: [dow] }
    weekdaysAnchor = dow
  }) ||
  take(/\b(?:every\s+(day|week|month|year)|(daily|weekly|monthly|yearly))\b/i, m => {
    const w = (m[1] || m[2]).toLowerCase()
    const unit = w.startsWith('day') || w === 'daily' ? 'day' : w.startsWith('week') ? 'week' : 'month'
    out.repeat = { unit, interval: w.startsWith('year') ? 12 : 1 }
  })

  // Relative durations: "in 2 hours", "in 3 days"
  let date = null
  let minutes = null // [h, m]
  let rel = null
  take(/\bin\s+(\d+)\s*(minutes?|mins?|hours?|hrs?|h|days?|d|weeks?|w)\b/i, m => {
    const n = +m[1]
    const u = m[2].toLowerCase()
    if (u.startsWith('m')) rel = new Date(now.getTime() + n * 60000)
    else if (u.startsWith('h')) rel = new Date(now.getTime() + n * 3600000)
    else if (u.startsWith('d')) date = addDays(startOfDay(now), n)
    else date = addDays(startOfDay(now), n * 7)
  })

  // Explicit dates
  if (!rel && !date) {
    take(/\b(\d{4})-(\d{2})-(\d{2})\b/, m => { date = new Date(+m[1], +m[2] - 1, +m[3]) }) ||
    take(new RegExp(`\\b(?:on\\s+)?${MONTH_RE}\\.?\\s+(\\d{1,2})(?:st|nd|rd|th)?(?:,?\\s+(\\d{4}))?\\b`, 'i'), m => {
      date = datePick(monthIndex(m[1].toLowerCase()), +m[2], m[3] ? +m[3] : null, now)
    }) ||
    take(new RegExp(`\\b(?:on\\s+)?(\\d{1,2})(?:st|nd|rd|th)?\\s+${MONTH_RE}\\b(?:,?\\s+(\\d{4}))?`, 'i'), m => {
      date = datePick(monthIndex(m[2].toLowerCase()), +m[1], m[3] ? +m[3] : null, now)
    }) ||
    take(/\b(today|tonight|tomorrow|tmrw|tmr)\b/i, m => {
      const w = m[1].toLowerCase()
      date = startOfDay(now)
      if (w !== 'today' && w !== 'tonight') date = addDays(date, 1)
      if (w === 'tonight') minutes = [20, 0]
    }) ||
    take(new RegExp(`\\b(?:(on|next|this|by)\\s+)?${DAY_RE}\\b`, 'i'), m => {
      // Bare short names ("sat", "sun", "mon") are too ambiguous without a preposition.
      const word = m[2].toLowerCase()
      if (!m[1] && word.length <= 4 && !DAYS.includes(word)) { s = s.slice(0, m.index) + m[0] + s.slice(m.index); return }
      date = nextWeekday(now, dayIndex(word), false)
    })
  }

  // Time of day
  take(/\b(?:at\s+|@\s*)?(\d{1,2})(?::(\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)(?=\s|[.,;!?]|$)/i, m => {
    let h = +m[1] % 12
    if (/^p/i.test(m[3])) h += 12
    minutes = [h, +(m[2] || 0)]
  }) ||
  take(/\b(?:at|@)\s*([01]?\d|2[0-3]):([0-5]\d)\b/i, m => { minutes = [+m[1], +m[2]] }) ||
  take(/\bat\s+(1[0-2]|[1-9])\b(?!\s*(?:st|nd|rd|th|people|things|items))/i, m => { minutes = [hourFromBare(+m[1]), 0] }) ||
  take(/\b(noon|midday)\b/i, () => { minutes = [12, 0] }) ||
  take(/\bmidnight\b/i, () => { minutes = [23, 59] })

  // Compose the due date
  if (rel) {
    out.due = rel.toISOString()
    out.allDay = false
  } else {
    if (!date && out.repeat) {
      date = weekdaysAnchor !== null
        ? nextWeekday(now, weekdaysAnchor, true)
        : out.repeat.weekdays ? firstWeekdayOnOrAfter(now, out.repeat.weekdays) : startOfDay(now)
    }
    if (!date && minutes) {
      date = startOfDay(now)
      const t = new Date(date); t.setHours(minutes[0], minutes[1])
      if (t <= now) date = addDays(date, 1)
    }
    if (date) {
      if (minutes) { date.setHours(minutes[0], minutes[1], 0, 0); out.allDay = false }
      out.due = date.toISOString()
    }
  }

  let title = s.replace(/\s+/g, ' ').trim()
  title = title.replace(/^(?:by|due|on|at)\s+/i, '').replace(/\s+(?:on|at|by|due|in|from|until|before|for|every|next|this)$/i, '').replace(/[\s,;:-]+$/, '').trim()
  if (!title) title = original.replace(/^\s+|\s+$/g, '')
  out.title = title.charAt(0).toUpperCase() + title.slice(1)
  return out
}

function datePick (month, day, year, now) {
  if (year) return new Date(year, month, day)
  let d = new Date(now.getFullYear(), month, day)
  // A date a few days back is most likely an overdue item, not next year's.
  if (d < addDays(startOfDay(now), -30)) d = new Date(now.getFullYear() + 1, month, day)
  return d
}

function firstWeekdayOnOrAfter (from, weekdays) {
  let d = startOfDay(from)
  for (let i = 0; i < 7 && !weekdays.includes(d.getDay()); i++) d = addDays(d, 1)
  return d
}

/** Parse the "YYYY-MM-DD" / "YYYY-MM-DDTHH:mm" local strings used by the AI endpoint and form fields. */
export function parseLocal (str) {
  const m = /^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2}))?$/.exec(String(str || ''))
  if (!m) return null
  const d = new Date(+m[1], +m[2] - 1, +m[3], +(m[4] || 0), +(m[5] || 0))
  return isNaN(d) ? null : { due: d.toISOString(), allDay: m[4] === undefined }
}

const pad = n => String(n).padStart(2, '0')
export const toLocalDate = d => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`
export const toLocalTime = d => `${pad(d.getHours())}:${pad(d.getMinutes())}`

/** Next due date after completing a repeating todo. Returns ISO string or null. */
export function nextDue (todo, now = new Date()) {
  const r = todo.repeat
  if (!r) return null
  let d = todo.due ? new Date(todo.due) : new Date(now)
  const limit = todo.allDay === false ? now : addDays(startOfDay(now), 1)
  const inPast = x => (todo.allDay === false ? x <= limit : x < limit)
  for (let i = 0; i < 2000; i++) {
    d = step(d, r)
    if (!inPast(d)) return d.toISOString()
  }
  return d.toISOString()
}

function step (d, r) {
  if (r.weekdays && r.weekdays.length) {
    let x = addDays(d, 1)
    for (let i = 0; i < 7 && !r.weekdays.includes(x.getDay()); i++) x = addDays(x, 1)
    return x
  }
  if (r.unit === 'day') return addDays(d, r.interval)
  if (r.unit === 'week') return addDays(d, 7 * r.interval)
  return addMonths(d, r.interval)
}

export function describeRepeat (r) {
  if (!r) return ''
  if (r.weekdays && r.weekdays.length) {
    if (r.weekdays.length === 5 && !r.weekdays.includes(0) && !r.weekdays.includes(6)) return 'Every weekday'
    return 'Every ' + r.weekdays.map(d => DAYS[d].charAt(0).toUpperCase() + DAYS[d].slice(1, 3)).join(', ')
  }
  if (r.unit === 'month' && r.interval % 12 === 0) return r.interval === 12 ? 'Yearly' : `Every ${r.interval / 12} years`
  if (r.interval === 1) return { day: 'Daily', week: 'Weekly', month: 'Monthly' }[r.unit]
  return `Every ${r.interval} ${r.unit}s`
}

export function formatDue (due, allDay, now = new Date(), locale) {
  if (!due) return ''
  const d = new Date(due)
  const days = Math.round((startOfDay(d) - startOfDay(now)) / 86400000)
  let label
  if (days === 0) label = 'Today'
  else if (days === 1) label = 'Tomorrow'
  else if (days === -1) label = 'Yesterday'
  else if (days > 1 && days < 7) label = d.toLocaleDateString(locale, { weekday: 'long' })
  else label = d.toLocaleDateString(locale, d.getFullYear() === now.getFullYear() ? { month: 'short', day: 'numeric' } : { month: 'short', day: 'numeric', year: 'numeric' })
  return allDay === false ? `${label}, ${d.toLocaleTimeString(locale, { hour: 'numeric', minute: '2-digit' })}` : label
}

export function isOverdue (todo, now = new Date()) {
  if (!todo.due) return false
  const d = new Date(todo.due)
  return todo.allDay === false ? d < now : d < startOfDay(now)
}

export function isToday (todo, now = new Date()) {
  return !!todo.due && sameDay(new Date(todo.due), now) && !isOverdue(todo, now)
}
