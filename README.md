<p align="center">
  <img src="docs/icon.png" alt="Sorcerer" width="120">
</p>

<h1 align="center">Sorcerer</h1>

<p align="center">
  <b>Create a community. Explore a hypothesis. Watch what happens.</b><br>
  A native, local-first macOS app that brings small worlds of AI characters to life,<br>
  powered by the AI subscriptions you already have.
</p>

<p align="center">
  <code>open source</code> · <code>native SwiftUI</code> · <code>local-first</code> · <code>bring your own AI</code> · <code>MIT</code>
</p>

<p align="center">
  <img src="docs/screenshots/feed-live.png" alt="A round being written live in the feed" width="900">
</p>

---

## What it is

Sorcerer is a sandbox for "what if…?" questions. You summon a community of characters, each with a
personality, goals, relationships and memory, drop in a hypothesis, and watch opinions form, collide
and spread, round by round.

- *What if Lumen raised its plan from $9 to $14 a month?*
- *What if this headline hit the group chat?*
- *What if a dragon moved into the village?*

Pause anytime, inject an event, pull a character aside to ask why they think what they think, fork the
world at any round and compare how each future unfolds. A report sums it up, with every finding linked
back to the posts behind it.

> Simulations surface possible reactions, objections and consequences. Treat them as hypotheses to
> investigate; they don't replace evidence from the real world.

## Bring your own AI

Sorcerer doesn't ship a model or ask for a password. It drives the AI tools you're already signed in to:

| Provider | How | Usage limits |
| --- | --- | --- |
| **Claude** | the `claude` CLI (Claude Code) | reads your 5-hour and weekly windows, pauses before you hit them |
| **ChatGPT** | the `codex` CLI | pauses if ChatGPT says you're out |
| **Ollama** | `localhost:11434` | local, free, never leaves your Mac |

Pick a model per provider (Haiku / Sonnet / Opus, any model your ChatGPT plan lists, any local model),
and choose who plays which part: characters, reports and 1:1 chats can each use a different AI.

## A tour

### Onboarding

A compact five-step setup: what Sorcerer is, how it works, which AI tools it found on your Mac
(it checks that each one is actually signed in), your limits, and a first question to explore.

<p align="center">
  <img src="docs/screenshots/onboarding-welcome.png" width="49%">
  <img src="docs/screenshots/onboarding-connect.png" width="49%">
</p>

### New experiment

Three steps, each with a live preview on the right.

**① Question & rules.** Write the "what if", or start from a template. Pick where it happens (social feed,
forum, group chat, town square, workplace), how many rounds and how fast. The side panel estimates the
cost on your subscription and points to similar experiments you've already run.

<img src="docs/screenshots/new-experiment-question.png" width="100%">

**② Teach the world.** Characters only react to what they know. Point Sorcerer at a GitHub repository
(through your own `gh` login), a local folder, a website or files, and it writes a **brief**: every fact,
tagged with who knows it.

- `public`: common knowledge
- `insider`: only staff, partners and close friends of the team know it, and may hint at it
- `hidden`: nobody knows it, usually the thing you're testing

Only docs are read. `.env` files, keys and credentials are never opened, `node_modules` and builds are
skipped, and characters see the brief, never your code.

<img src="docs/screenshots/new-experiment-brief.png" width="100%">

**③ Community & start.** Summon people from your context or from a description, or reuse a community from
another experiment. Edit anyone before round 1: roles, insiders, who's in.

<img src="docs/screenshots/new-experiment-community.png" width="100%">

### Watching it happen

Rounds stream in live: finished posts appear one by one, and whoever is mid-sentence shows up as
**"@wren is typing…"** with their words appearing as they're written. Characters reply to specific posts,
react (agree / disagree) without posting, remember what happened, and listen most to the people they're
tied to.

<img src="docs/screenshots/feed.png" width="100%">

Switch the feed to **world** to see the community as a map, with the ties between people and what each
speaker said this round, or to **graph** for everyone's mood round by round and who the conversation
revolves around.

<p align="center">
  <img src="docs/screenshots/world.png" width="49%">
  <img src="docs/screenshots/graph.png" width="49%">
</p>

### Characters

Every character has a profile: personality, interests, goals, ties and memories. Talk to them
**off the record** (nothing changes) or **in-world** (they remember the conversation). Edit their persona,
duplicate them, or change how they look in a pixel-art avatar editor.

<p align="center">
  <img src="docs/screenshots/character.png" width="49%">
  <img src="docs/screenshots/avatar-editor.png" width="49%">
</p>

### Branches & reports

Fork the world at any moment: same people, same memories, one different decision. The report compares
branches on a sentiment chart, explains where they diverged, and every finding cites the exact posts
behind it. Click a citation to jump to that post.

<img src="docs/screenshots/report.png" width="100%">

### Getting around

One sidebar, the same tabs in every experiment (feed · characters · report · context), back/forward,
and **⌘K** to go to anything: experiments, characters, branches and actions.

<p align="center">
  <img src="docs/screenshots/palette.png" width="49%">
  <img src="docs/screenshots/settings-providers.png" width="49%">
</p>

| Shortcut | |
| --- | --- |
| `⌘K` | go to anything |
| `⌘N` | new experiment |
| `⌘1` – `⌘4` | feed · characters · report · context |
| `⌘[` `⌘]` | back · forward |
| `⌘R` | run / pause |
| `⌘→` | play one round |
| `⌘E` | inject an event |
| `⇧⌘F` | fork this moment |
| `⇧⌘R` | generate report |
| `⌘,` | settings |

## Local-first

Everything lives in `~/Sorcerer` as plain JSON you can read, back up or delete:

```
~/Sorcerer
├── experiments/   one file per experiment: question, brief, branches, posts, report
├── contexts/      briefs saved for reuse
└── settings.json
```

When a round runs on an external provider, only what that round needs is sent to it. Experiments can be
exported with their full history, or as a fresh scenario (same question, context and people, no history)
for someone else to run.

## Build it

Requirements: macOS 15+, Xcode with Swift 6, and at least one of the `claude` CLI, the `codex` CLI or Ollama.

```bash
cd apps/macos
swift run                                   # run in development
swift test                                  # engine, parsing, navigation and safety tests
SORCERER_LIVE=claude swift test             # also play a real round against your CLI
./bundle.sh                                 # build Sorcerer.app (with icon) next to the script
```

## Repository

```
sorcerer/
├── apps/
│   ├── macos/      the app (SwiftUI, no dependencies)
│   ├── web/        landing page (React + TanStack Router + Tailwind)
│   └── server/     API (Hono + tRPC)
├── packages/       shared UI, API, config
└── docs/           icon and screenshots
```

### The landing page

<img src="docs/screenshots/landing.png" width="100%">

```bash
bun install
bun run dev:web     # http://localhost:3001
```

The web stack was scaffolded with [kubojs](https://github.com/albuquerquesz/kubo) (TanStack Router, Hono, tRPC,
Drizzle, Turborepo, Biome). Database, GetMonitor and AraraHQ setup, plus every script, are in
[docs/web-stack.md](docs/web-stack.md).

## Acknowledgements

Inspired by [MiroFish](https://github.com/666ghj/MiroFish). Sorcerer is a separate, from-scratch
implementation aimed at curiosity and fun: a small world on your Mac, not a forecasting service.

## License

[MIT](LICENSE)
