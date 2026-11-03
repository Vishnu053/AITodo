# AI Todo (iOS)

A minimal to-do app that **remembers everything, recalls it while you write, and speaks up when something needs you** — with its AI running **on-device** on Apple's Foundation Models. No account, no server, no API key, nothing leaves the phone.

One input, one list.

## What it does

- **Remembers everything.** Nothing is ever really deleted: finished and deleted todos stay in memory and in your export.
- **Recalls while you write.** Start typing and matching todos from your whole history appear (open, done *and* deleted) with *Show*, *Add again* or *Restore*. Writing something you've written before reuses the earlier tags, priority and note, and tells you. Duplicates of open todos are caught.
- **Proactive.** A "Heads up" section surfaces overdue and due-today items, things untouched for two weeks (do it / drop it), and **habits learned from your history** ("You usually do *Take out recycling* every week — last time was 7 days ago. Add it"). Reminders are real local notifications, so they fire with the app closed.
- **Writes the way you talk.** `call mum tomorrow 5pm #family !`, `water plants every 2 days`, `review on friday`, `in 2 hours`, `nov 20`, with a live preview chip row.
- **On-device AI (Apple Intelligence).** For each new todo the model fills only what you left blank — implied date, repeat, priority, tags (reusing tags from your related past todos), a note — and writes a short daily brief with suggested focus (★). Model output is validated and clamped, only fills empty fields, and is discarded if you edit the todo first. If Apple Intelligence is unavailable, everything else still works.

## Build

Requires a Mac with **Xcode 26**. Deployment target is iOS 17; AI needs iOS 26 on an Apple Intelligence device.

```sh
brew install xcodegen
xcodegen                 # generates AIToDo.xcodeproj from project.yml
open AIToDo.xcodeproj    # set your team + bundle id (project.yml), then run
```

Edit `PRODUCT_BUNDLE_IDENTIFIER` and `DEVELOPMENT_TEAM` in `project.yml` first. The app icon is the old web icon upscaled to 1024px — replace `App/Assets.xcassets/AppIcon.appiconset/icon-1024.png`.

Tests (any platform with Swift 5.9+, Linux included): `cd Core && swift test`

## Layout

| | |
|---|---|
| `Core/` | `AIToDoCore` — pure Swift + Foundation, fully unit-tested: parser, store with recall search (IDF-weighted, stemmed, prefix-while-typing), reuse of prior todos, habit/insight detection, AI output sanitising and prompts |
| `App/` | SwiftUI app: `AppModel` (state), `TodoAssistant.swift` (Foundation Models, behind a protocol), `Reminders.swift` (local notifications), views |
| `project.yml` | XcodeGen spec |

**Storage.** One JSON file in Application Support, written atomically (`aitodo.json`), protected until first unlock. *Settings → Export* shares it; *Import* merges by recency and also accepts exports from the earlier web version.

**Limits.** English-only parsing. No sync between devices yet. The on-device model has a small context window, so the AI sees only the five most related past todos (and 20 open todos for the brief).
