# Roadmap

What's planned for Sorcerer, roughly in order. Nothing here has a date. If you'd like to pick something up,
open an issue first so we can agree on the shape (see [CONTRIBUTING.md](CONTRIBUTING.md)).

## Shipped

- [x] **Distribution:** a DMG on GitHub Releases, a one-line installer and in-app updates.
- [x] **Fork from any round + replay:** scrub back through a run and branch from any past round.
- [x] **Actions and polls:** characters buy, cancel, leave and invite; ask the whole community a question
  mid-run; both become counted metrics in the report and graph.

## Next

- [ ] **Web viewer:** open a shared `.sorcerer.json` on [sorcererapp.dev](https://sorcererapp.dev) and read the
  feed, polls and report without installing the app.
- [ ] **More providers:** Gemini CLI, LM Studio, and an API key or custom OpenAI-compatible endpoint.

## Richer simulations

- [ ] **DMs and group chats:** characters talk in private channels, so gossip spreads differently from what's
  said in public.
- [ ] **Scheduled events:** plan ahead ("news breaks in round 3, the price changes in round 5").
- [ ] **Who hears first:** start the news with an influencer or a skeptic and see whether it spreads differently.
- [ ] **You as a character:** post inside the world and see how people react.
- [ ] **Repeat runs:** run the same question several times to see how much the outcome varies.

## Seeing and understanding

- [ ] **Branches side by side:** compare two feeds round by round.
- [ ] **Narrator:** a prose summary of each round; in fiction mode, the story reads like a book.
- [ ] **Cost per experiment:** how much of your subscription each run used.
- [ ] **Report export:** PDF and image, alongside Markdown.

## People and data

- [ ] **Cast from a CSV:** build characters from customer data or interview notes.
- [ ] **Character library:** keep characters you like and reuse them across experiments.

## Editing

- [ ] Delete branches, edit or remove injected events, and undo.
- [ ] Change ties or remove a character mid-run.
- [ ] Save 1:1 chats with the experiment.
- [ ] Summarize large context files instead of cutting them at 20k characters.

## On the Mac

- [ ] A notification when a round finishes.
- [ ] A menu bar icon while a simulation runs.
- [ ] Shortcuts actions and `sorcerer://` links to open experiments.

## Other platforms

- [ ] **Windows and Linux:** today Sorcerer is a native SwiftUI app for macOS. The plan is to split the engine
  (rounds, actions, polls, reports, providers) from the interface so it can run elsewhere, then ship an app for
  Windows and Linux. The approach (Swift on Windows/Linux, or a cross-platform shell around a shared core) is
  still open; ideas welcome in an issue.

Smaller, well-scoped tasks live in the [issues](https://github.com/gbrasil720/sorcerer/issues), many tagged
`good first issue`.
