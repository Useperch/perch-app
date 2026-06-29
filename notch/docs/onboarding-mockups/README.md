# Perch Onboarding — Mockups

Pixel-accurate mockups of the redesigned onboarding flow (9 screens, 400×600 each,
matching the real onboarding `NSWindow`). Permission order follows
[`../onboarding-permissions.md`](../onboarding-permissions.md): **Hear → See → Act**.

```
0-download · 1-welcome · 2-microphone · 3-screen-recording · 4-accessibility
5-automation · 6-calendar · 7-reminders · 8-finish
```

## Edit the source
SVGs are generated — edit copy/layout in `_generate.py`, then:
```bash
python3 _generate.py            # rewrites the 9 *.svg
python3 figma-plugin/build.py   # re-bundles them into the plugin
```
Each text line is a real `<text>` element, so it stays editable after import.

## Get them into Figma — two ways

### A. One native Figma file (recommended)
The `figma-plugin/` builds all 9 as native, editable frames on a fresh page:
1. Figma → **Plugins → Development → Import plugin from manifest…**
2. Select `figma-plugin/manifest.json`
3. **Plugins → Development → Perch Onboarding Builder** → Run
4. It creates a **“Perch Onboarding”** page with the 9 frames laid out in order.

### B. Drag-and-drop
Drag the `*.svg` files straight onto the Figma canvas — each imports as an editable frame.

> The hosted Figma MCP (`mcp.figma.com`) is **read/codegen-only** — it can't author
> frames, so it isn't a path for *creating* these. Once connected it's useful for
> pulling code/specs back *out* of the file.

## Notes / open questions
- Branding uses **“Perch”** (matches the `Info.plist` permission trust copy and
  `WelcomeView.swift`, both now renamed from the upstream “Boring Notch”).
- **Camera** is intentionally omitted (drop candidate per the spec).
- Possible extra step: **Input Monitoring** for the global push-to-talk modifier tap —
  verify against the event-tap code before adding.
