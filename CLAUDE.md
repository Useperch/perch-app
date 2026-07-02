# CLAUDE.md — beta-app-perch

## Repository

- **This folder → GitHub repo:** `Useperch/perch-app` (**primary clone**, branch **`main`**)
- **Role:** Canonical checkout of the macOS "notch" app — **this folder owns the real
  `.git` object store**. Tracks `main` (the beta/release line). The `dev` development
  line is a **linked worktree** at `../dev-perch/app`.
- **Org:** all Perch code lives under the **`Useperch`** GitHub org:
  - `Useperch/perch-app` — this app (Swift notch client)
  - `Useperch/perch-backend` — backend / gateway / worker
  - `Useperch/perch-site` — marketing website
  - `Useperch/perch-monorepo-archive` — **archived** original monorepo (read-only, history only)
