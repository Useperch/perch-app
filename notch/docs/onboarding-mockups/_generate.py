#!/usr/bin/env python3
"""Generate pixel-accurate SVG mockups of the Perch onboarding flow.

One 400x600 SVG per screen (matches the real onboarding NSWindow). Text is
emitted as <text>/<tspan> so Figma imports each line as an editable text layer.
Run:  python3 _generate.py   ->  writes *.svg next to this file.
"""
import os

W, H = 400, 600
OUT = os.path.dirname(os.path.abspath(__file__))

# ---- palette ---------------------------------------------------------------
BG_TOP = "#1f1f22"
BG_BOT = "#161618"
WHITE = "#ffffff"
SECONDARY = "#98989f"
TERTIARY = "#6b6b71"
ACCENT = "#0A84FF"
STROKE = "#3a3a3e"
CARD = "#2a2a2e"

FONT = "SF Pro Text, -apple-system, Helvetica, Arial, sans-serif"
FONT_D = "SF Pro Display, -apple-system, Helvetica, Arial, sans-serif"


def esc(s):
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def text(x, y, s, size=13, fill=WHITE, weight=400, anchor="middle",
         font=FONT, spacing=None):
    ls = f' letter-spacing="{spacing}"' if spacing else ""
    return (f'<text x="{x}" y="{y}" font-family="{font}" font-size="{size}" '
            f'font-weight="{weight}" fill="{fill}" text-anchor="{anchor}"{ls}>'
            f'{esc(s)}</text>')


def paragraph(x, y, lines, size=13, fill=SECONDARY, lh=19, anchor="middle"):
    out = []
    for i, ln in enumerate(lines):
        out.append(text(x, y + i * lh, ln, size=size, fill=fill, anchor=anchor))
    return "\n".join(out)


def button(cx, y, w, label, filled=True, h=34):
    x = cx - w / 2
    if filled:
        rect = (f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="8" '
                f'fill="{ACCENT}"/>')
        lbl = text(cx, y + h / 2 + 5, label, size=14, fill=WHITE, weight=600)
    else:
        rect = (f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="8" '
                f'fill="none" stroke="{STROKE}" stroke-width="1.5"/>')
        lbl = text(cx, y + h / 2 + 5, label, size=14, fill=WHITE, weight=500)
    return rect + "\n" + lbl


def two_buttons(y, left, right):
    # Not Now (bordered) | Allow (filled), centered pair
    gap = 12
    bw = 132
    total = bw * 2 + gap
    lx = W / 2 - total / 2 + bw / 2
    rx = W / 2 + total / 2 - bw / 2
    return button(lx, y, bw, left, filled=False) + "\n" + button(rx, y, bw, right, filled=True)


def chip(cx, y, label, color=TERTIARY):
    w = 8 + len(label) * 6.2
    x = cx - w / 2
    return (f'<rect x="{x}" y="{y}" width="{w}" height="18" rx="9" fill="none" '
            f'stroke="{STROKE}" stroke-width="1"/>' +
            text(cx, y + 13, label, size=10, fill=color, weight=600, spacing="0.4"))


def privacy(cx, y, note):
    # lock.shield glyph + small note on one line, centered as a group.
    icon_w, gap = 12, 8
    text_w = len(note) * 5.55          # ~width of 11px note text
    total = icon_w + gap + text_w
    ix = cx - total / 2                # icon left edge
    tx = ix + icon_w + gap             # text start (left-anchored)
    g = (f'<g transform="translate({ix},{y - 9})" stroke="{TERTIARY}" '
         f'fill="none" stroke-width="1.4">'
         f'<path d="M6 1 L11 3 V7 C11 10 8.5 12 6 13 C3.5 12 1 10 1 7 V3 Z"/>'
         f'<rect x="3.6" y="6" width="4.8" height="4" rx="1" fill="{TERTIARY}" stroke="none"/>'
         f'</g>')
    return g + text(tx, y + 4, note, size=11, fill=TERTIARY, anchor="start")


def frame(body, label):
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">
<defs>
<linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
<stop offset="0" stop-color="{BG_TOP}"/><stop offset="1" stop-color="{BG_BOT}"/>
</linearGradient>
<radialGradient id="spot" cx="0.5" cy="0.05" r="0.75">
<stop offset="0" stop-color="#ffffff" stop-opacity="0.16"/>
<stop offset="1" stop-color="#ffffff" stop-opacity="0"/>
</radialGradient>
</defs>
<rect x="0.5" y="0.5" width="{W-1}" height="{H-1}" rx="16" fill="url(#bg)" stroke="#000000" stroke-opacity="0.4"/>
{body}
</svg>
'''


# ---- shared icon helper: large rounded accent-tinted circle + glyph --------
def icon_badge(cx, cy, glyph_svg, r=44):
    return (f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="{ACCENT}" fill-opacity="0.14"/>'
            f'<g transform="translate({cx},{cy})" stroke="{ACCENT}" fill="none" '
            f'stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round">'
            f'{glyph_svg}</g>')


# glyphs centered at (0,0)
GLYPH = {
    "mic": '<rect x="-7" y="-18" width="14" height="24" rx="7"/>'
           '<path d="M-12 -2 a12 12 0 0 0 24 0"/><line x1="0" y1="10" x2="0" y2="18"/>'
           '<line x1="-7" y1="18" x2="7" y2="18"/>',
    "screen": '<rect x="-18" y="-14" width="36" height="24" rx="3"/>'
              '<line x1="-7" y1="16" x2="7" y2="16"/><line x1="0" y1="10" x2="0" y2="16"/>',
    "hand": '<path d="M-2 8 V-8 a3 3 0 0 1 6 0 V-2 M4 -4 a3 3 0 0 1 6 0 V6 '
            'a12 12 0 0 1 -12 12 a12 12 0 0 1 -10 -7 l-3 -6 a2.5 2.5 0 0 1 4 -3 l3 4 '
            'M-8 -2 a3 3 0 0 1 6 0 M-2 -4 a3 3 0 0 1 6 0"/>',
    "wand": '<line x1="-12" y1="12" x2="10" y2="-10"/>'
            '<path d="M10 -16 l1.5 3 3 1.5 -3 1.5 -1.5 3 -1.5 -3 -3 -1.5 3 -1.5 z"/>'
            '<circle cx="-12" cy="-8" r="0.6"/><circle cx="-4" cy="-14" r="0.6"/>',
    "cal": '<rect x="-16" y="-13" width="32" height="28" rx="4"/>'
           '<line x1="-16" y1="-5" x2="16" y2="-5"/><line x1="-8" y1="-18" x2="-8" y2="-9"/>'
           '<line x1="8" y1="-18" x2="8" y2="-9"/>',
    "check": '<path d="M-14 -10 h22 M-14 0 h22 M-14 10 h14"/>'
             '<path d="M-18 -10 l-1 -1" /><circle cx="-17" cy="-10" r="1.4"/>'
             '<circle cx="-17" cy="0" r="1.4"/><circle cx="-17" cy="10" r="1.4"/>',
    "spark": '<path d="M0 -18 C2 -6 6 -2 18 0 C6 2 2 6 0 18 C-2 6 -6 2 -18 0 C-6 -2 -2 -6 0 -18 Z"/>'
             '<path d="M14 -16 l0.8 2.5 2.5 0.8 -2.5 0.8 -0.8 2.5 -0.8 -2.5 -2.5 -0.8 2.5 -0.8 z"/>',
}


# ===========================================================================
# 0. DOWNLOAD / INSTALL  (DMG drag-to-Applications)
# ===========================================================================
def s_download():
    b = []
    b.append(text(W/2, 70, "Install Perch", size=26, fill=WHITE, weight=600, font=FONT_D))
    b.append(text(W/2, 96, "Drag Perch into your Applications folder", size=13, fill=SECONDARY))
    # app icon
    b.append('<g transform="translate(120,200)">'
             '<rect x="-46" y="-46" width="92" height="92" rx="20" fill="#2c2c30" stroke="#444"/>'
             '<rect x="-26" y="-30" width="52" height="34" rx="10" fill="#3a1d22"/>'
             '<circle cx="0" cy="-8" r="11" fill="#6f4b86"/>'
             '<rect x="-15" y="14" width="30" height="8" rx="4" fill="#0A84FF"/></g>')
    b.append(text(120, 270, "Perch", size=13, fill=WHITE, weight=600))
    # arrow
    b.append(f'<g stroke="{ACCENT}" stroke-width="3" fill="none" stroke-linecap="round">'
             f'<line x1="172" y1="200" x2="226" y2="200"/>'
             f'<path d="M218 191 l10 9 -10 9"/></g>')
    # applications folder
    b.append('<g transform="translate(280,200)">'
             '<path d="M-44 -30 h28 l8 9 h8 a8 8 0 0 1 8 8 v34 a8 8 0 0 1 -8 8 '
             'h-52 a8 8 0 0 1 -8 -8 v-43 a8 8 0 0 1 8 -8 z" fill="#2c2c30" stroke="#4a90d9"/>'
             '<circle cx="0" cy="6" r="13" fill="none" stroke="#7fb3e8" stroke-width="2"/>'
             '<line x1="0" y1="6" x2="0" y2="-7" stroke="#7fb3e8" stroke-width="2"/></g>')
    b.append(text(280, 270, "Applications", size=13, fill=WHITE, weight=600))
    b.append(button(W/2, 470, 200, "Open Perch"))
    b.append(text(W/2, 540, "v1.0  ·  the Boring Team", size=11, fill=TERTIARY))
    return frame("\n".join(b), "0-download")


# ===========================================================================
# 1. WELCOME  (spotlight + sparkles + logo)
# ===========================================================================
def s_welcome():
    b = []
    # spotlight cone
    b.append('<path d="M200 40 L300 470 L100 470 Z" fill="url(#spot)"/>')
    b.append('<rect x="0" y="0" width="400" height="600" fill="url(#spot)" opacity="0.5"/>')
    # sparkles
    for (x, y, r) in [(120, 120, 1.6), (300, 150, 2), (90, 240, 1.4), (320, 280, 1.8),
                      (150, 90, 1.2), (260, 100, 1.5), (110, 330, 1.6), (300, 360, 1.4)]:
        b.append(f'<circle cx="{x}" cy="{y}" r="{r}" fill="#ffffff" opacity="0.55"/>')
    # logo (notch character)
    b.append('<g transform="translate(200,210)">'
             '<rect x="-50" y="-50" width="100" height="100" rx="24" fill="#2c2c30"/>'
             '<rect x="-30" y="-34" width="60" height="40" rx="12" fill="#3a1d22"/>'
             '<circle cx="0" cy="-8" r="13" fill="#6f4b86"/>'
             '<circle cx="-5" cy="-9" r="2.3" fill="#fff"/><circle cx="5" cy="-9" r="2.3" fill="#fff"/>'
             '</g>')
    b.append(text(W/2, 320, "Perch", size=34, fill=WHITE, weight=700, font=FONT_D))
    b.append(text(W/2, 352, "Welcome", size=20, fill=SECONDARY, font=FONT_D))
    b.append(button(W/2, 430, 170, "Get started"))
    b.append(text(W/2, 552, "the Boring Team", size=13, fill="#cfcfd4", anchor="middle",
                  font="Snell Roundhand, cursive"))
    return frame("\n".join(b), "1-welcome")


# ===========================================================================
# generic permission screen
# ===========================================================================
def perm(glyph, title, desc_lines, privacy_note, left, right, chip_label=None,
         foot=None):
    b = []
    b.append(icon_badge(W/2, 130, GLYPH[glyph]))
    y = 230
    if chip_label:
        b.append(chip(W/2, 196, chip_label))
    b.append(text(W/2, y, title, size=23, fill=WHITE, weight=600, font=FONT_D))
    b.append(paragraph(W/2, y + 36, desc_lines, size=13, fill=SECONDARY, lh=20))
    py = y + 36 + len(desc_lines) * 20 + 26
    if privacy_note:
        b.append(privacy(W/2, py, privacy_note))
    b.append(two_buttons(486, left, right))
    if foot:
        b.append(text(W/2, 548, foot, size=11, fill=TERTIARY))
    return b


def s_microphone():
    b = perm("mic", "Let Perch hear you",
             ["Hold ⌃⌥ and talk. Perch listens and",
              "transcribes your voice on-device so you",
              "can ask for anything, hands-free."],
             "Audio is transcribed on your Mac, never stored.",
             "Not Now", "Allow Access",
             chip_label="MICROPHONE + SPEECH",
             foot="Two quick macOS prompts: Microphone, then Speech Recognition")
    return frame("\n".join(b), "2-microphone")


def s_screen():
    b = perm("screen", "Let Perch see your screen",
             ["When you hold ⌃⌥, Perch captures the",
              "current screen so it can understand what",
              "you're looking at and help in context."],
             "Screenshots are sent only when you ask.",
             "Not Now", "Allow Access",
             chip_label="SCREEN RECORDING",
             foot="macOS may ask you to relaunch Perch after granting")
    return frame("\n".join(b), "3-screen-recording")


def s_accessibility():
    b = perm("hand", "Let Perch act for you",
             ["Accessibility lets Perch move the cursor,",
              "click, and type to carry out tasks — and to",
              "replace the system HUD with its own."],
             "Used only to act on your behalf, on request.",
             "Not Now", "Open Settings",
             chip_label="ACCESSIBILITY",
             foot="Opens System Settings → Privacy → Accessibility")
    return frame("\n".join(b), "4-accessibility")


def s_automation():
    b = perm("wand", "Run desktop workflows",
             ["Perch can drive other apps — like Spotify",
              "or Apple Music — and replay workflows you",
              "show it once, end to end."],
             "macOS asks before each app is controlled.",
             "Skip", "Allow Access",
             chip_label="AUTOMATION",
             foot="You'll be asked per app the first time it's used")
    return frame("\n".join(b), "5-automation")


def s_calendar():
    b = perm("cal", "Show your calendar",
             ["See your upcoming events right in the",
              "notch, so your next meeting is always",
              "one glance away."],
             "Calendar data stays on your Mac.",
             "Not Now", "Allow Access",
             chip_label="OPTIONAL")
    return frame("\n".join(b), "6-calendar")


def s_reminders():
    b = perm("check", "Show your reminders",
             ["Glance at your reminders next to your",
              "events, and check them off without",
              "leaving what you're doing."],
             "Reminders stay on your Mac.",
             "Not Now", "Allow Access",
             chip_label="OPTIONAL")
    return frame("\n".join(b), "7-reminders")


# ===========================================================================
# 8. FINISH
# ===========================================================================
def s_finish():
    b = []
    b.append(icon_badge(W/2, 150, GLYPH["spark"], r=50))
    b.append(text(W/2, 270, "You're all set!", size=30, fill=WHITE, weight=700, font=FONT_D))
    b.append(paragraph(W/2, 308,
                       ["Perch is ready. You can fine-tune any",
                        "of this later in Settings."], lh=21))
    b.append(button(W/2, 430, 230, "Customize in Settings", filled=False))
    b.append(button(W/2, 476, 230, "Finish"))
    return frame("\n".join(b), "8-finish")


SCREENS = [
    ("0-download", s_download),
    ("1-welcome", s_welcome),
    ("2-microphone", s_microphone),
    ("3-screen-recording", s_screen),
    ("4-accessibility", s_accessibility),
    ("5-automation", s_automation),
    ("6-calendar", s_calendar),
    ("7-reminders", s_reminders),
    ("8-finish", s_finish),
]

if __name__ == "__main__":
    for name, fn in SCREENS:
        path = os.path.join(OUT, name + ".svg")
        with open(path, "w") as f:
            f.write(fn())
        print("wrote", path)
