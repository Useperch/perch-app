# Perch

Perch is a macOS companion that lives in the MacBook notch. Hold `⌃ control + ⌥ option`
to talk to it, or press **Control twice** to type. It sees your screen, answers in
streamed text + voice, and can dispatch a real autonomous agent to go do things for you.

This is the **open-source client** — the Swift app that runs on your Mac. It talks only
to the Perch gateway (a Cloudflare Worker) over HTTPS; no third-party API keys ever ship
in the app.

## Open core — what's here, what isn't

- **In this repo:** the full notch app — voice answer + point, the daily brief, the
  dashboard, onboarding, and all the client-side logic. Built from source, it runs
  against the hosted Perch gateway on the **free tier (25 messages / month)**.
- **Ships in the official download, not in this repo:** the autonomous browser/desktop
  **agent** is a closed binary. Building from source gives you everything except that
  agent target — its absence is expected.
- **Not open:** the gateway Worker (which holds the provider keys), the account/billing
  backend, and the agent sidecar.

## Build

Requires Xcode (macOS 14.2+). Build + run with:

```sh
./scripts/build-perch.sh
```

It's menu-bar/notch only (`LSUIElement=true`) — find it in the notch after launch.

## Accounts & pricing

- Enter your email at onboarding (optional) — no password, no code.
- Free: 25 messages a month (voice or text).
- Pro ($20/mo): unlimited messages + the autonomous agent. Upgrade from inside the app;
  it links to your email automatically.

## License

MIT — see [LICENSE](./LICENSE).
