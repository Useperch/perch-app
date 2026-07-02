# Onboarding v2 — Refined

A prettier, higher-converting take on the onboarding flow. See `preview.png`.

## What changed vs v1

**Fewer upfront permission gates.** v1 marched the user through 9 screens, most of
them permission prompts. v2 asks only for what earns its keep on day one and defers
the rest to **just-in-time** prompts.

### Upfront flow (5 screens)
1. `1-welcome.svg` — value first ("Meet Perch")
2. `2-microphone.svg` — the core interaction (push-to-talk, on-device)
3. `3-music.svg` — Now Playing source picker
4. `4-calendar.svg` — glanceable next event
5. `5-finish.svg` — "You're all set" (also primes the just-in-time model)

### Just-in-time (asked only when a task needs it)
`jit-permission.svg` is the pattern for everything **not** asked during setup:
**Screen Recording · Accessibility · Automation · Reminders**. The permission is
requested in-context, the moment a task requires it — never as an upfront wall.

## Visual direction
- Vertical background gradient + brand-tinted top spotlight (depth, not flat).
- Gradient app orb / icon tiles with a soft blue glow + drop shadow.
- Slim progress dots (active = pill).
- One confident gradient CTA with a blue glow; secondary action is a quiet text link
  to cut decision friction.
- An on-device privacy reassurance line under permission asks.

## Regenerating
Edit copy/layout in `_generate_v2.py`, then:

```
python3 _generate_v2.py
```

> Gotcha baked into the generator: icon-tile glyphs use a **solid** stroke, not the
> `url(#accent)` gradient. Straight-line glyphs (calendar, accessibility) have a
> zero-area bounding box, and an objectBoundingBox gradient stroke silently fails to
> render on them.

## Pushing to Figma
These are the review artifacts. The companion file **"Perch — Onboarding Mockups"**
already holds the v1 import; v2 lands on a new **"Onboarding v2 — Refined"** page via
the Figma MCP (native frames with real gradient fills, layer-blur glow, and drop
shadows for full fidelity). Pending a Figma Starter-plan MCP rate-limit reset.
