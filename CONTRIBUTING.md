# Contributing to Perch

Thanks for your interest! A few things to know before you dive in.

## Open core

Perch is open-core. **This repo is the macOS client.** The gateway Worker (which holds
all third-party API keys), the account/billing backend, and the autonomous agent sidecar
are closed and live elsewhere. The client reaches all paid capabilities through the hosted
gateway — you never need a provider key to build or run it.

Practical consequences:

- The app builds and runs fully for **voice answers, screen-aware help, the daily brief,
  and the dashboard** against the hosted gateway (free tier: 25 messages/month).
- The **autonomous agent** target is a closed binary shipped only in the official
  download. Building from source, that feature is unavailable — this is expected, not a
  bug.

## Where things go

- App source: `perch/notch/` — the SwiftUI front-end plus `PerchBackend/` (voice pipeline,
  orchestration, identity, dashboard, workflows).

## Conventions

- SwiftUI for UI; `@MainActor` for all UI state; async/await for async work.
- Prefer clarity over cleverness; favor long, descriptive names.
- Keep files focused (200–400 lines typical).

## Pull requests

- Branch as `feature/<desc>` or `fix/<desc>`.
- Commit messages: imperative mood, explain the "why".
- Keep changes scoped to what you describe in the PR.
