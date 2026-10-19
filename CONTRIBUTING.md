# Contributing to Sorcerer

Thanks for wanting to help! Sorcerer is a native macOS app (SwiftUI) plus a small TypeScript web stack for the landing page. Most contributions land in the app, `apps/macos`.

## Project layout

```
sorcerer/
├── apps/
│   ├── macos/                  the app: SwiftUI, Swift Package, no dependencies
│   │   ├── Package.swift
│   │   ├── Sources/Sorcerer/   all app code (see map below)
│   │   ├── Tests/SorcererTests/
│   │   ├── bundle.sh           builds Sorcerer.app with the icon
│   │   ├── dmg.sh              builds the ad-hoc signed DMG
│   │   └── icon.swift          renders the pixel-hat icon
│   ├── web/                    landing page (React, TanStack Router, Tailwind, Vite)
│   ├── server/                 API server (Hono + tRPC)
│   └── api/                    API modules and router
├── packages/                   shared ui, db (Drizzle), env, config, arara
└── docs/                       web-stack notes, icon and screenshots
```

Where things live in `apps/macos/Sources/Sorcerer/`:

| File | What's in it |
| --- | --- |
| `AI.swift` | talks to the `claude` and `codex` CLIs and to Ollama; parses replies, streaming and usage limits |
| `Engine.swift` | the simulation: rounds, posts, reactions, actions, polls |
| `Models.swift` | data types, environments and the experiment templates (`Template.all`) |
| `Store.swift` / `Workspace.swift` | app state and persistence |
| `NewExperiment.swift`, `Onboarding.swift` | the creation and first-run flows |
| `FeedViews.swift`, `CharacterScreen.swift`, `ReportScreen.swift`, `ContextScreen.swift` | main screens |
| `Sources.swift` | reading a repo, folder, site or files into the brief |
| `Share.swift` | export (experiment JSON, scenario bundle, report Markdown) |
| `SettingsWindow.swift`, `Navigation.swift`, `Theme.swift`, `Avatar.swift`, `Updater.swift` | settings, navigation, styling, avatars, updates |

## The macOS app

Requirements: macOS 15+, Xcode with Swift 6, and, to actually run experiments, at least one of the `claude` CLI, the `codex` CLI or [Ollama](https://ollama.com).

```bash
cd apps/macos
swift run                         # run in development
swift test                        # engine, parsing, navigation and safety tests (what CI runs)
SORCERER_LIVE=claude swift test   # also play a real round against your CLI (uses your quota)
./bundle.sh                       # build Sorcerer.app next to the script
UNIVERSAL=1 ./bundle.sh           # Apple silicon + Intel
UNIVERSAL=1 VERSION=0.1.0 ./dmg.sh  # universal ad-hoc signed DMG, like the releases
```

Tip: Ollama is the cheapest way to test. It's local and free, so you don't burn your Claude or ChatGPT limits.

The app has no third-party dependencies. Please keep it that way unless the issue says otherwise.

## The web stack (landing page)

Requirements: [Bun](https://bun.sh) 1.3+ (the repo pins `bun@1.3.14`).

```bash
bun install
bun run dev:web        # landing at http://localhost:3001
bun run dev:server     # API server
bun run dev            # everything, via Turbo
bun run build          # build all packages
bun run check-types    # type-check all packages
bun run check          # Biome lint + format (writes fixes)
```

Production build of the landing (what Cloudflare Pages runs): `bun install --frozen-lockfile && cd apps/web && bun run build`, with output in `apps/web/dist`.

Database, GetMonitor and other setup notes are in [docs/web-stack.md](docs/web-stack.md). You don't need any of it to work on the app.

## Picking a first issue

1. Browse issues labeled [`good first issue`](https://github.com/gbrasil720/sorcerer/labels/good%20first%20issue) (small and well scoped) or [`help wanted`](https://github.com/gbrasil720/sorcerer/labels/help%20wanted) (bigger, or needs some design thought).
2. Comment "I'd like to take this" so nobody duplicates work. If there's been no activity for 2 weeks, the issue is open again.
3. Not sure about the approach? Ask in the issue before writing a lot of code.
4. Have your own idea? Open a feature request first (the template asks the right questions).

## Pull requests

- Branch from `main`. Use one focused change per PR.
- Fill in the PR template: **What**, **Why**, **Screenshots** (for anything visible, before and after) and the checks:
  - `swift test` passes in `apps/macos` (app changes)
  - `bun run build` passes in `apps/web` (landing changes)
  - no keys, tokens or personal experiment data in the diff
- Run `bun run check` for TypeScript changes. For Swift, follow the style of the surrounding code.
- Add or update tests in `apps/macos/Tests/SorcererTests` when you change engine, parsing or navigation logic.
- Write short, imperative commit messages (e.g. `Add Ollama host setting`). Link the issue in the PR with `Closes #123`.
- Privacy is a feature: never make the app read `.env` files, keys or credentials, and never send data anywhere except the AI tool the user picked.

Releases are cut by the maintainer by pushing a `vX.Y.Z` tag (see `.github/workflows/release.yml`).

## Code of conduct

Be kind, assume good intent, and keep feedback about the code. This project follows the [Contributor Covenant](https://www.contributor-covenant.org/version/2/1/code_of_conduct/) (see `CODE_OF_CONDUCT.md`). Report problems to the maintainer, [@gbrasil720](https://github.com/gbrasil720).

## License

By contributing you agree that your contributions are licensed under the [MIT License](LICENSE).
