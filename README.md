# AI Todo

A minimal to-do app that **remembers everything, recalls it while you write, and speaks up when something needs you.**

One input, one list. No accounts, no build step, no dependencies.

## What it does

- **Remembers everything.** Nothing is ever really deleted — finished and deleted todos stay in memory (and in your export).
- **Recalls while you write.** Start typing and matching todos from your whole history appear (open, done *and* deleted), with *Show*, *Add again* or *Restore*. When you write something you've written before, it reuses the earlier tags, priority and note, and says so. Duplicates of open todos are caught.
- **Proactive.** A "Heads up" card surfaces what's overdue, due today, things untouched for 2+ weeks (do it / drop it), and **habits it learned from your history** ("You usually do *Take out recycling* every week — last time was 7 days ago. Add it"). Optional reminders via notifications.
- **Writes the way you talk.** `call mum tomorrow 5pm #family !`, `water plants every 2 days`, `review on friday`, `in 2 hours`, `nov 20`. Live preview shows how it was understood.
- **AI, optional.** With an Anthropic key on the server, each todo is refined by Claude *using your related past todos as context*, and you get a short daily brief with suggested focus (★). Without a key everything above still works.

Keys: `/` focuses the input, `Esc` clears it.

## Run

```sh
npm start                      # http://localhost:3000, no AI
ANTHROPIC_API_KEY=sk-ant-… ACCESS_TOKEN=pick-a-secret npm start
npm test                       # parser, memory, insights, server (Node ≥ 20, zero deps)
```

Docker: `docker build -t aitodo . && docker run -p 3000:3000 -e ANTHROPIC_API_KEY -e ACCESS_TOKEN aitodo`. See `.env.example` for all settings. It installs as a PWA and works offline.

## Design notes

| | |
|---|---|
| `public/lib/parse.js` | Natural-language parsing, repeats, date formatting (pure) |
| `public/lib/memory.js` | The store: persistence, recall search (IDF-weighted, stemmed, prefix-while-typing), reuse of prior todos |
| `public/lib/proactive.js` | Overdue / today / stale / habit detection |
| `server/ai.js` | Claude calls; every model output is validated and clamped before use |
| `server/server.js` | Static files + `/api/assist`, `/api/brief`; CSP, bearer token, rate limit, body cap |

**Local-first.** Todos live in this browser's `localStorage` (the app asks the browser for persistent storage); the server stores nothing. Use *Export/Import* to back up or move devices — there is no sync yet.

**Privacy.** With AI enabled, the todo text you write plus up to five related past todos (and for the brief, your open list) are sent to your server and on to Anthropic. Turn *Use AI* off in the menu to stop that. The API key never reaches the browser. If the server is public, set `ACCESS_TOKEN` — otherwise anyone can spend your key (rate limiting is per-IP and in-memory only).

**Limits.** Reminders fire while the app is open or running in the background of the installed PWA; there's no server push, so a fully closed app can't notify you. Parsing is English only. Date words follow the device's local time zone.
