#!/usr/bin/env python3
"""
Onboarding v2 — notch-native theme.

Goal: make onboarding feel like the notch itself — pure black, the hanging notch
silhouette (flush top edge, deep-rounded bottom), monochrome line icons, one
restrained accent (the macOS blue), generous negative space, and minimal chrome.

Flow (only what earns its keep up front):
    Welcome -> Microphone -> Music -> Calendar -> Done
Everything else (Screen Recording, Accessibility, Automation, Reminders) is asked
just-in-time, dropped from the notch the moment a task needs it (jit-permission.svg).

Edit copy/layout here, then: python3 _generate_v2.py
Glows are radial gradients (not SVG filters) so they survive Figma's
createNodeFromSvg import unchanged.
"""

import os

W, H = 400, 600
DISP = "SF Pro Display, -apple-system, Helvetica, Arial, sans-serif"
TEXT = "SF Pro Text, -apple-system, Helvetica, Arial, sans-serif"

# notch panel geometry
PX0, PX1, PTOP, PBOT, RB, RT = 26, 374, 0, 562, 46, 18

ACCENT = "#0A84FF"
HEAD = "#f3f3f5"
SUB = "#8b8b92"
MUT = "#5c5c63"
ICON = "#ededf0"

DEFS = """<defs>
<linearGradient id="backdrop" x1="0" y1="0" x2="0" y2="1">
<stop offset="0" stop-color="#0a0a0e"/><stop offset="1" stop-color="#050506"/>
</linearGradient>
<radialGradient id="halo" cx="0.5" cy="0.0" r="0.7">
<stop offset="0" stop-color="#2c5cff" stop-opacity="0.16"/>
<stop offset="1" stop-color="#2c5cff" stop-opacity="0"/>
</radialGradient>
<linearGradient id="topline" x1="0" y1="0" x2="1" y2="0">
<stop offset="0" stop-color="#ffffff" stop-opacity="0"/>
<stop offset="0.5" stop-color="#ffffff" stop-opacity="0.12"/>
<stop offset="1" stop-color="#ffffff" stop-opacity="0"/>
</linearGradient>
</defs>"""


def panel_path(x0=PX0, x1=PX1, top=PTOP, bot=PBOT, rb=RB, rt=RT):
    return (f'M{x0+rt},{top} H{x1-rt} A{rt},{rt} 0 0 1 {x1},{top+rt} '
            f'V{bot-rb} A{rb},{rb} 0 0 1 {x1-rb},{bot} '
            f'H{x0+rb} A{rb},{rb} 0 0 1 {x0},{bot-rb} '
            f'V{top+rt} A{rt},{rt} 0 0 1 {x0+rt},{top} Z')


def frame_open(bot=PBOT):
    cam = (  # the physical notch camera housing
        '<rect x="158" y="9" width="84" height="17" rx="8.5" fill="#000000"/>'
        '<circle cx="200" cy="17.5" r="2.1" fill="#23232a"/>'
    )
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" '
        f'viewBox="0 0 {W} {H}">' + DEFS +
        f'<rect x="0" y="0" width="{W}" height="{H}" rx="0" fill="url(#backdrop)"/>'
        f'<ellipse cx="200" cy="-10" rx="240" ry="150" fill="url(#halo)"/>'
        f'<path d="{panel_path(bot=bot)}" fill="#0b0b0d" stroke="#ffffff" '
        f'stroke-opacity="0.07"/>'
        f'<rect x="{PX0+34}" y="1" width="{PX1-PX0-68}" height="1.5" '
        f'fill="url(#topline)"/>' + cam
    )


def frame_close():
    return "</svg>\n"


def segs(active, y, total=5):
    sw, gap = 16, 7
    total_w = total * sw + (total - 1) * gap
    x = 200 - total_w / 2
    out = []
    for i in range(total):
        on = i == active
        col = ACCENT if on else "#ffffff"
        op = "1" if on else "0.14"
        out.append(f'<rect x="{x:.1f}" y="{y}" width="{sw}" height="3" rx="1.5" '
                   f'fill="{col}" fill-opacity="{op}"/>')
        x += sw + gap
    return "".join(out)


def ring_icon(cy, glyph, r=37):
    ring = (f'<circle cx="200" cy="{cy}" r="{r}" fill="none" stroke="#ffffff" '
            f'stroke-opacity="0.09"/>')
    g = (f'<g transform="translate(200,{cy})" stroke="{ICON}" fill="none" '
         f'stroke-width="2" stroke-linecap="round" stroke-linejoin="round">{glyph}</g>')
    return ring + g


def headline(s, y, size=25):
    return (f'<text x="200" y="{y}" font-family="{DISP}" font-size="{size}" '
            f'font-weight="600" fill="{HEAD}" text-anchor="middle" '
            f'letter-spacing="-0.3">{s}</text>')


def sub(lines, y, gap=20):
    out = []
    for i, ln in enumerate(lines):
        out.append(f'<text x="200" y="{y+i*gap}" font-family="{TEXT}" font-size="13.5" '
                   f'fill="{SUB}" text-anchor="middle">{ln}</text>')
    return "".join(out)


def pill(label, y, w=240):
    x = 200 - w / 2
    return (
        f'<rect x="{x:.1f}" y="{y}" width="{w}" height="46" rx="23" fill="{ACCENT}"/>'
        f'<text x="200" y="{y+28}" font-family="{TEXT}" font-size="15" '
        f'font-weight="600" fill="#ffffff" text-anchor="middle">{label}</text>'
    )


def link(label, y, color=MUT):
    return (f'<text x="200" y="{y}" font-family="{TEXT}" font-size="13" '
            f'font-weight="500" fill="{color}" text-anchor="middle">{label}</text>')


def micro(label, y):
    return (f'<text x="200" y="{y}" font-family="{TEXT}" font-size="11" '
            f'fill="{MUT}" text-anchor="middle">{label}</text>')


# ---- glyphs (monochrome line icons) ----
G_MIC = ('<rect x="-7" y="-17" width="14" height="23" rx="7"/>'
         '<path d="M-12 -2 a12 12 0 0 0 24 0"/>'
         '<line x1="0" y1="10" x2="0" y2="17"/><line x1="-7" y1="17" x2="7" y2="17"/>')
G_CAL = ('<rect x="-15" y="-12" width="30" height="26" rx="4"/>'
         '<line x1="-15" y1="-4" x2="15" y2="-4"/>'
         '<line x1="-7" y1="-17" x2="-7" y2="-8"/><line x1="7" y1="-17" x2="7" y2="-8"/>')
G_MUSIC = ('<path d="M-7 10 V-11 L11 -14 V5"/>'
           f'<circle cx="-11" cy="10" r="3.6" fill="{ICON}" stroke="none"/>'
           f'<circle cx="7" cy="5" r="3.6" fill="{ICON}" stroke="none"/>')
G_CHECK = '<path d="M-13 1 L-4 10 L14 -10"/>'
G_A11Y = ('<circle cx="0" cy="-11" r="3"/>'
          '<path d="M-11 -3 h22"/><path d="M0 -3 V7"/>'
          '<path d="M-7 15 L0 6 L7 15"/>')
SPARK = ('<path d="M0 -15 C1.6 -5 5 -1.6 15 0 C5 1.6 1.6 5 0 15 '
         f'C-1.6 5 -5 1.6 -15 0 C-5 -1.6 -1.6 -5 0 -15 Z" fill="{ICON}" stroke="none"/>')


# ---------------- screens ----------------
def s_welcome():
    return "".join([
        frame_open(), segs(0, 64),
        ring_icon(168, SPARK),
        headline("Meet Perch", 268, size=28),
        sub(["Your Mac, one shortcut away.",
             "Hold ⌃⌥, ask out loud, done."], 302),
        pill("Get started", 452),
        micro("the Boring Team", 512),
        frame_close(),
    ])


def s_microphone():
    return "".join([
        frame_open(), segs(1, 64),
        ring_icon(168, G_MIC),
        headline("Just talk to your Mac", 268),
        sub(["Hold ⌃⌥ and speak — it stays",
             "on your Mac, never recorded."], 302),
        pill("Enable microphone", 452),
        link("Not now", 508),
        frame_close(),
    ])


def s_music():
    rows = [
        ("Now Playing", "#0A84FF", True),
        ("Spotify", "#1DB954", False),
        ("Apple Music", "#FA2D6E", False),
        ("YouTube Music", "#FF3B30", False),
    ]
    parts = [frame_open(), segs(2, 64),
             headline("Your music, in the notch", 132, size=23),
             sub(["Pick where Perch reads Now Playing."], 162)]
    y = 200
    for label, color, seldot in rows:
        sel = seldot
        fill = ACCENT if sel else "#ffffff"
        fop = "0.10" if sel else "0.035"
        stroke = ACCENT if sel else "#ffffff"
        sop = "0.9" if sel else "0.07"
        sw = "1.5" if sel else "1"
        parts.append(
            f'<rect x="64" y="{y}" width="272" height="48" rx="13" fill="{fill}" '
            f'fill-opacity="{fop}" stroke="{stroke}" stroke-opacity="{sop}" '
            f'stroke-width="{sw}"/>'
        )
        parts.append(f'<circle cx="86" cy="{y+24}" r="5" fill="{color}"/>')
        parts.append(
            f'<text x="104" y="{y+29}" font-family="{TEXT}" font-size="14" '
            f'font-weight="500" fill="{HEAD}" text-anchor="start">{label}</text>'
        )
        if sel:
            parts.append(
                f'<circle cx="314" cy="{y+24}" r="9" fill="{ACCENT}"/>'
                f'<path d="M310 {y+24} l3 3 5 -6" stroke="#fff" stroke-width="2" '
                f'fill="none" stroke-linecap="round" stroke-linejoin="round"/>'
            )
        else:
            parts.append(f'<circle cx="314" cy="{y+24}" r="9" fill="none" '
                         f'stroke="#ffffff" stroke-opacity="0.2"/>')
        y += 56
    parts += [pill("Continue", 452), link("Skip for now", 508), frame_close()]
    return "".join(parts)


def s_calendar():
    return "".join([
        frame_open(), segs(3, 64),
        ring_icon(168, G_CAL),
        headline("Never miss what’s next", 268),
        sub(["Your next event, always a glance",
             "away inside the notch."], 302),
        pill("Connect calendar", 452),
        link("Not now", 508),
        frame_close(),
    ])


def s_finish():
    return "".join([
        frame_open(), segs(4, 64),
        ring_icon(168, G_CHECK),
        headline("You’re all set", 268, size=28),
        sub(["Need more access later? Perch",
             "asks in the moment, never up front."], 302),
        pill("Start using Perch", 452),
        link("Customize in Settings", 508),
        frame_close(),
    ])


def s_jit():
    """Just-in-time ask — dropped from the notch the instant a task needs it."""
    bot = 232
    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" '
        f'viewBox="0 0 {W} {H}">' + DEFS,
        f'<rect x="0" y="0" width="{W}" height="{H}" fill="#050506"/>',
        f'<ellipse cx="200" cy="-10" rx="240" ry="150" fill="url(#halo)"/>',
        # short notch panel that dropped down
        f'<path d="{panel_path(x0=70, x1=330, bot=bot, rb=40)}" fill="#0b0b0d" '
        f'stroke="#ffffff" stroke-opacity="0.08"/>',
        '<rect x="158" y="9" width="84" height="17" rx="8.5" fill="#000000"/>'
        '<circle cx="200" cy="17.5" r="2.1" fill="#23232a"/>',
        ring_icon(72, G_A11Y, r=24),
        headline("Let Perch finish the job?", 122, size=17),
        sub(["Needs Accessibility — just this once."], 148, gap=18),
    ]
    by = 168
    parts.append(
        f'<rect x="92" y="{by}" width="98" height="38" rx="19" fill="none" '
        f'stroke="#ffffff" stroke-opacity="0.16" stroke-width="1.5"/>'
        f'<text x="141" y="{by+24}" font-family="{TEXT}" font-size="13.5" '
        f'font-weight="500" fill="#e8e8ea" text-anchor="middle">Not now</text>'
    )
    parts.append(
        f'<rect x="200" y="{by}" width="110" height="38" rx="19" fill="{ACCENT}"/>'
        f'<text x="255" y="{by+24}" font-family="{TEXT}" font-size="13.5" '
        f'font-weight="600" fill="#ffffff" text-anchor="middle">Allow</text>'
    )
    parts.append(micro("Asked only when a task needs it — never during setup.", 300))
    parts.append(
        f'<text x="200" y="328" font-family="{TEXT}" font-size="10.5" fill="#46464c" '
        f'text-anchor="middle" letter-spacing="0.3">'
        f'Screen Recording · Accessibility · Automation · Reminders</text>'
    )
    parts.append(frame_close())
    return "".join(parts)


SCREENS = {
    "1-welcome.svg": s_welcome,
    "2-microphone.svg": s_microphone,
    "3-music.svg": s_music,
    "4-calendar.svg": s_calendar,
    "5-finish.svg": s_finish,
    "jit-permission.svg": s_jit,
}


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    for name, fn in SCREENS.items():
        with open(os.path.join(here, name), "w") as f:
            f.write(fn())
        print("wrote", name)


if __name__ == "__main__":
    main()
