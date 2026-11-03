import { parseTodo, parseLocal, formatDue, describeRepeat, isOverdue, isToday, startOfDay, toLocalDate, toLocalTime } from './lib/parse.js'
import { Store, LocalStorageAdapter, status, completionTimes } from './lib/memory.js'
import { insights, briefContext } from './lib/proactive.js'
import { AiClient } from './lib/ai.js'

const $ = id => document.getElementById(id)
const h = (tag, attrs = {}, ...kids) => {
  const el = document.createElement(tag)
  for (const [k, v] of Object.entries(attrs)) {
    if (v === false || v == null) continue
    if (k.startsWith('on')) el.addEventListener(k.slice(2), v)
    else if (k === 'class') el.className = v
    else el.setAttribute(k, v === true ? '' : v)
  }
  for (const kid of kids.flat()) if (kid != null && kid !== false) el.append(kid)
  return el
}

// ---------- settings (per-device, never synced) ----------
const SETTINGS_KEY = 'aitodo.settings'
const readSettings = () => { try { return { ai: true, notify: false, token: '', lastDigest: '', briefs: {}, ...JSON.parse(localStorage.getItem(SETTINGS_KEY)) } } catch { return { ai: true, notify: false, token: '', lastDigest: '', briefs: {} } } }
const settings = readSettings()
const saveSettings = () => { try { localStorage.setItem(SETTINGS_KEY, JSON.stringify(settings)) } catch { /* ignore */ } }

const store = new Store(new LocalStorageAdapter(), { onError: () => toast('Could not save — storage is full or blocked.') })
const ai = new AiClient(() => settings.token)
const aiOn = () => ai.available && settings.ai
const REPEAT_PRESETS = { day: { unit: 'day', interval: 1 }, weekdays: { unit: 'week', interval: 1, weekdays: [1, 2, 3, 4, 5] }, week: { unit: 'week', interval: 1 }, month: { unit: 'month', interval: 1 } }
const repeatKey = r => (!r ? '' : Object.keys(REPEAT_PRESETS).find(k => JSON.stringify(REPEAT_PRESETS[k]) === JSON.stringify(r)) || 'custom')
const rank = (a, b) => b.priority - a.priority || (a.due && b.due ? new Date(a.due) - new Date(b.due) : 0)

// ---------- toast ----------
let toastTimer
function toast (msg, action) {
  const el = $('toast')
  el.replaceChildren(...[h('span', {}, msg), action && h('button', { onclick: () => { clearTimeout(toastTimer); el.hidden = true; action.run() } }, action.label)].filter(Boolean))
  el.hidden = false
  clearTimeout(toastTimer)
  toastTimer = setTimeout(() => { el.hidden = true }, action ? 6000 : 3500)
}

// ---------- rendering ----------
let flashId = null
let briefState = { message: '', focus: [], loading: false }

function todoRow (t, { done = false } = {}) {
  const now = new Date()
  const meta = []
  if (t.due) meta.push(h('span', { class: isOverdue(t, now) ? 'late' : '' }, formatDue(t.due, t.allDay, now)))
  if (t.repeat) meta.push(h('span', {}, '↻ ' + describeRepeat(t.repeat)))
  if (t.tags.length) meta.push(h('span', {}, t.tags.map(x => '#' + x).join(' ')))
  if (t.note) meta.push(h('span', {}, '✎ note'))
  const n = completionTimes(t).length
  if (n > 1) meta.push(h('span', {}, `done ${n}×`))
  return h('li', { class: `todo pri-${t.priority}${done ? ' done' : ''}${flashId === t.id ? ' flash' : ''}`, 'data-id': t.id },
    h('input', { type: 'checkbox', checked: done, 'aria-label': (done ? 'Mark not done: ' : 'Complete: ') + t.title, onchange: () => (done ? undoDone(t.id) : complete(t.id)) }),
    h('button', { class: 'main', onclick: () => openEdit(t.id), 'aria-label': 'Edit ' + t.title },
      h('div', { class: 'title' }, briefState.focus.includes(t.id) ? h('span', { class: 'star', title: 'Suggested focus' }, '★ ') : null, t.title),
      meta.length ? h('div', { class: 'meta' }, meta) : null))
}

function render () {
  const now = new Date()
  const open = store.open()
  const groups = [
    ['overdue', 'Overdue', open.filter(t => isOverdue(t, now)).sort(rank)],
    ['today', 'Today', open.filter(t => isToday(t, now)).sort(rank)],
    ['upcoming', 'Upcoming', open.filter(t => t.due && !isOverdue(t, now) && !isToday(t, now)).sort((a, b) => new Date(a.due) - new Date(b.due) || b.priority - a.priority)],
    ['anytime', 'Anytime', open.filter(t => !t.due).sort((a, b) => b.priority - a.priority || b.created - a.created)]
  ].filter(g => g[2].length)
  $('lists').replaceChildren(...groups.map(([cls, name, items]) =>
    h('section', { class: 'group ' + cls }, h('h2', {}, name), h('ul', { class: 'todos' }, items.map(t => todoRow(t))))))
  $('empty').hidden = open.length > 0
  $('empty').textContent = store.all().length ? 'All clear. Everything you finish stays in memory — type to recall it.' : 'Nothing on your plate. Write a todo above — I’ll remember it.'

  const done = store.all().filter(t => t.done && !t.deleted).sort((a, b) => b.done - a.done).slice(0, 15)
  $('doneBox').hidden = !done.length
  $('doneCount').textContent = done.length ? `(${done.length})` : ''
  $('doneList').replaceChildren(...done.map(t => todoRow(t, { done: true })))
  flashId = null
  renderBrief()
  renderPreview()
}

function renderBrief () {
  const items = insights(store.all(), new Date())
  const box = $('brief')
  const nodes = []
  if (briefState.message) nodes.push(h('p', {}, briefState.message))
  for (const i of items) {
    nodes.push(h('div', { class: 'insight ' + i.kind },
      h('span', { class: 'txt' }, i.text),
      i.actions.map(a => h('button', { onclick: () => runAction(i, a.do) }, a.label))))
  }
  if (aiOn() && !briefState.message && !briefState.loading && store.open().length) nodes.push(h('div', { class: 'insight' }, h('button', { onclick: () => loadBrief(true) }, '✨ Brief me')))
  box.hidden = !nodes.length
  box.replaceChildren(...(nodes.length ? [h('h2', {}, briefState.loading ? 'Thinking…' : 'Heads up'), ...nodes] : []))
}

function renderPreview () {
  const text = $('input').value
  const chips = $('preview')
  const rec = $('recall')
  if (!text.trim()) { chips.replaceChildren(); rec.hidden = true; return }
  const now = new Date()
  const p = parseTodo(text, now)
  const c = []
  if (p.due) c.push(h('span', { class: 'chip' }, '📅 ' + formatDue(p.due, p.allDay, now)))
  if (p.repeat) c.push(h('span', { class: 'chip' }, '↻ ' + describeRepeat(p.repeat)))
  if (p.priority) c.push(h('span', { class: 'chip' }, '!'.repeat(p.priority)))
  p.tags.forEach(t => c.push(h('span', { class: 'chip' }, '#' + t)))
  const prior = store.findPrior(p.title)
  if (prior && (prior.tags.length || prior.priority || prior.note)) c.push(h('span', { class: 'chip hint' }, `🧠 I'll reuse details from “${prior.title}”`))
  chips.replaceChildren(...c)

  const hits = store.recall(text, { limit: 4 })
  rec.hidden = !hits.length
  rec.replaceChildren(...(hits.length ? [h('h2', {}, 'From your memory'), ...hits.map(({ todo: t }) => memRow(t))] : []))
}

function memRow (t) {
  const st = status(t)
  const n = completionTimes(t).length
  const when = ts => new Date(ts).toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' })
  const line = st === 'open' ? 'On your list' + (t.due ? ' · ' + formatDue(t.due, t.allDay) : '')
    : st === 'done' ? `Done ${n > 1 ? n + '× · last ' : ''}${when(t.done || completionTimes(t).slice(-1)[0])}`
      : `Deleted ${when(t.deleted)}`
  return h('div', { class: 'mem' },
    h('div', { class: 'body' }, h('div', { class: 't' }, t.title), h('div', { class: 'm' }, line + (t.note ? ' · ' + t.note.slice(0, 60) : ''))),
    st === 'open' ? h('button', { onclick: () => { flashId = t.id; $('input').value = ''; render(); document.querySelector(`[data-id="${t.id}"]`)?.scrollIntoView({ block: 'center', behavior: 'smooth' }) } }, 'Show')
      : h('button', { onclick: () => readd(t.id) }, st === 'deleted' ? 'Restore' : 'Add again'))
}

// ---------- actions ----------
function addTodo (text) {
  const r = store.add(text)
  if (r.error) return
  if (r.duplicate) { flashId = r.duplicate.id; render(); toast('Already on your list.'); return }
  flashId = r.todo.id
  $('input').value = ''
  render()
  toast(r.inherited.length ? `Added — reused ${r.inherited.join(', ')} from “${r.prior.title}”` : 'Added')
  if (aiOn()) refine(r.todo, text)
}

async function refine (todo, text) {
  const stamp = todo.updated
  const memory = store.recall(todo.title, { limit: 5, exclude: todo.id }).map(({ todo: m }) => ({ title: m.title, note: m.note, tags: m.tags, status: status(m), timesDone: completionTimes(m).length }))
  try {
    const out = await ai.assist(text, memory)
    const cur = store.get(todo.id)
    if (!cur || cur.updated !== stamp) return // user edited meanwhile; never overwrite
    const patch = {}
    if (out.title) patch.title = out.title
    if (out.note && !cur.note) patch.note = out.note
    if (out.due && !cur.due) Object.assign(patch, (({ due, allDay }) => ({ due, allDay }))(parseLocal(out.due) || {}))
    if (out.repeat && !cur.repeat) patch.repeat = out.repeat
    if (out.priority && !cur.priority) patch.priority = out.priority
    if (out.tags && !cur.tags.length) patch.tags = out.tags
    if (Object.keys(patch).length) { store.update(todo.id, patch); toast('✨ Refined “' + (patch.title || cur.title) + '”') }
  } catch { /* AI is optional; local parse already saved the todo */ }
}

function complete (id) {
  const r = store.complete(id)
  if (!r) return
  toast(r.rolled ? `Done — next one ${formatDue(r.todo.due, r.todo.allDay).toLowerCase()}` : 'Done', { label: 'Undo', run: () => { store.replace(r.before); } })
}
const undoDone = id => store.uncomplete(id)
function readd (id) {
  const r = store.readd(id)
  if (r.todo) { flashId = r.todo.id; $('input').value = ''; render(); toast(r.restored ? 'Restored' : 'Added again') }
}

function runAction (insight, what) {
  const today = startOfDay(new Date()).toISOString()
  if (what === 'reschedule-today') insight.todoIds.forEach(id => store.update(id, { due: today, allDay: true }))
  else if (what === 'schedule-today') store.update(insight.todoIds[0], { due: today, allDay: true })
  else if (what === 'drop') {
    const snap = JSON.parse(JSON.stringify(store.get(insight.todoIds[0])))
    store.remove(snap.id)
    toast('Dropped — it stays in memory', { label: 'Undo', run: () => store.replace(snap) })
  } else if (what === 'add-habit') {
    const r = store.add(insight.title)
    if (r.todo) { store.update(r.todo.id, { due: today, allDay: true }); flashId = r.todo.id; toast('Added to today') }
  }
}

// ---------- edit dialog ----------
let editing = null
function openEdit (id) {
  const t = store.get(id)
  if (!t) return
  editing = id
  const f = $('editForm')
  f.title.value = t.title
  f.note.value = t.note
  const d = t.due ? new Date(t.due) : null
  f.date.value = d ? toLocalDate(d) : ''
  f.time.value = d && t.allDay === false ? toLocalTime(d) : ''
  const key = repeatKey(t.repeat)
  for (const o of [...f.repeat.options]) if (o.value === 'custom') o.remove()
  if (key === 'custom') f.repeat.append(h('option', { value: 'custom' }, describeRepeat(t.repeat)))
  f.repeat.value = key
  f.priority.value = String(t.priority)
  f.tags.value = t.tags.join(', ')
  const n = completionTimes(t).length
  $('editHistory').textContent = `Written ${new Date(t.created).toLocaleDateString(undefined, { dateStyle: 'medium' })}` + (n ? ` · completed ${n}×, last ${new Date(completionTimes(t).slice(-1)[0]).toLocaleDateString(undefined, { dateStyle: 'medium' })}` : '')
  $('editDlg').showModal()
}
$('editForm').addEventListener('submit', e => {
  const f = e.target
  const t = store.get(editing)
  if (!t) return
  let due = null; let allDay = true
  if (f.date.value) {
    const p = parseLocal(f.time.value ? `${f.date.value}T${f.time.value}` : f.date.value)
    if (p) { due = p.due; allDay = p.allDay }
  }
  const rk = f.repeat.value
  store.update(editing, {
    title: f.title.value.trim() || t.title,
    note: f.note.value.trim(),
    due, allDay,
    repeat: rk === 'custom' ? t.repeat : (REPEAT_PRESETS[rk] || null),
    priority: +f.priority.value,
    tags: [...new Set(f.tags.value.split(/[\s,]+/).map(x => x.replace(/^#/, '').toLowerCase()).filter(Boolean))].slice(0, 8),
    notified: null
  })
})
$('editCancel').onclick = () => $('editDlg').close()
$('editDelete').onclick = () => {
  const snap = JSON.parse(JSON.stringify(store.get(editing)))
  store.remove(editing)
  $('editDlg').close()
  toast('Deleted — it stays in memory', { label: 'Undo', run: () => store.replace(snap) })
}

// ---------- menu / settings ----------
function openMenu () {
  const all = store.all()
  $('aiStatus').textContent = ai.available ? 'AI is connected on the server.' : 'AI is off (no API key on the server). Everything still works locally.'
  $('aiToggle').checked = settings.ai && ai.available
  $('aiToggle').disabled = !ai.available
  $('notifyToggle').checked = settings.notify && 'Notification' in window && Notification.permission === 'granted'
  $('tokenRow').hidden = !ai.config.authRequired
  $('tokenInput').value = settings.token
  $('stats').textContent = `${all.length} todos remembered · ${all.filter(t => t.done).length} done · stored on this device`
  $('menuDlg').showModal()
}
$('menuBtn').onclick = openMenu
$('menuClose').onclick = () => $('menuDlg').close()
$('aiToggle').onchange = e => { settings.ai = e.target.checked; saveSettings(); renderBrief() }
$('tokenInput').onchange = e => { settings.token = e.target.value.trim(); saveSettings(); loadBrief(false) }
$('notifyToggle').onchange = async e => {
  if (!e.target.checked) { settings.notify = false; saveSettings(); return }
  const perm = 'Notification' in window ? await Notification.requestPermission() : 'denied'
  settings.notify = perm === 'granted'
  e.target.checked = settings.notify
  saveSettings()
  if (!settings.notify) toast('Notifications are blocked in this browser.')
}
$('exportBtn').onclick = () => {
  const a = h('a', { href: URL.createObjectURL(new Blob([store.exportJSON()], { type: 'application/json' })), download: `aitodo-${toLocalDate(new Date())}.json` })
  document.body.append(a); a.click(); a.remove()
}
$('importBtn').onclick = () => $('importFile').click()
$('importFile').onchange = async e => {
  const file = e.target.files[0]
  if (!file) return
  try { toast(`Imported ${store.importJSON(await file.text())} todos`) } catch { toast('That file is not an AI Todo export.') }
  e.target.value = ''
}

// ---------- AI brief ----------
async function loadBrief (force) {
  if (!aiOn() || !store.open().length) return
  const key = toLocalDate(new Date())
  const cached = settings.briefs[key]
  if (cached && !force) { briefState = { ...cached, loading: false }; renderBrief(); return }
  briefState = { ...briefState, loading: true }
  renderBrief()
  try {
    const out = await ai.brief(briefContext(store.all(), new Date()))
    briefState = { message: out.message, focus: out.focus, loading: false }
    settings.briefs = { [key]: { message: out.message, focus: out.focus } }
    saveSettings()
  } catch { briefState = { message: '', focus: [], loading: false } }
  render()
}

// ---------- reminders ----------
async function notify (title, body, tag) {
  try {
    const reg = await navigator.serviceWorker?.ready
    if (reg) await reg.showNotification(title, { body, tag, icon: 'icons/icon-192x192.png' })
    else new Notification(title, { body, tag })
  } catch { /* ignore */ }
}
function tick () {
  const now = new Date()
  renderGreeting(now)
  if (!settings.notify || !('Notification' in window) || Notification.permission !== 'granted') return
  for (const t of store.open()) {
    if (t.allDay !== false || !t.due || t.notified === t.due) continue
    if (new Date(t.due) <= now) { store.update(t.id, { notified: t.due }, { touch: false }); notify(t.title, formatDue(t.due, false), t.id) }
  }
  const day = toLocalDate(now)
  if (settings.lastDigest !== day && now.getHours() >= 8) {
    const due = store.open().filter(t => isToday(t, now) || isOverdue(t, now))
    settings.lastDigest = day
    saveSettings()
    if (due.length) notify(`${due.length} for today`, due.slice(0, 3).map(t => t.title).join(' · '), 'digest')
  }
}

function renderGreeting (now) {
  const hr = now.getHours()
  $('greeting').textContent = hr < 5 ? 'Still up?' : hr < 12 ? 'Good morning' : hr < 18 ? 'Good afternoon' : 'Good evening'
  $('date').textContent = now.toLocaleDateString(undefined, { weekday: 'long', month: 'long', day: 'numeric' })
}

// ---------- wiring ----------
$('capture').addEventListener('submit', e => { e.preventDefault(); addTodo($('input').value) })
$('input').addEventListener('input', renderPreview)
$('input').addEventListener('keydown', e => { if (e.key === 'Escape') { $('input').value = ''; renderPreview() } })
document.addEventListener('keydown', e => { if (e.key === '/' && !/INPUT|TEXTAREA|SELECT/.test(document.activeElement.tagName) && !document.querySelector('dialog[open]')) { e.preventDefault(); $('input').focus() } })
store.subscribe(() => { render() })
document.addEventListener('visibilitychange', () => { if (!document.hidden) { renderGreeting(new Date()); render(); tick() } })

;(async () => {
  renderGreeting(new Date())
  render()
  if (navigator.storage?.persist) navigator.storage.persist().catch(() => {})
  if ('serviceWorker' in navigator) navigator.serviceWorker.register('sw.js').catch(() => {})
  await ai.init()
  render()
  loadBrief(false)
  tick()
  setInterval(tick, 30000)
})()

