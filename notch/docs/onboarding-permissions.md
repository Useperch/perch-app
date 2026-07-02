# Perch Onboarding — Permissions Spec

Source of truth for the onboarding flow rebuild. Cross-references `Info.plist`
declared usage descriptions, the `PerchCapabilityToggles` (Vision / Microphone /
Accessibility) enforcement layer, and the actual macOS grant mechanism for each.

## Ordering principle

**Hear → See → Act.** Lead with the three core capabilities that define the
product (mirrors how a real interaction flows and front-loads value while user
motivation is highest), then defer optional notch widgets and the legacy camera
mirror so they can be skipped without breaking the core loop.

## Flow

| # | Screen | Permission(s) | Why | Grant mechanism | Skippable |
|---|--------|---------------|-----|-----------------|-----------|
| 0 | Download / Install | — | Drag to Applications, first launch | — | — |
| 1 | Welcome | — | Value prop: see / hear / act for you | — | — |
| 2 | Microphone | Microphone + Speech Recognition | Push-to-talk voice (Ears) + on-device transcription | Two in-app prompts, instant; fire back-to-back as one "Voice" step | No (core) |
| 3 | Screen Recording | Screen Recording | Vision/Eyes — screenshot on ⌃⌥ hold | System prompt; historically needs app relaunch to take effect | No (core) |
| 4 | Accessibility | Accessibility (via XPC helper) | Hands — cursor / click / type; replaces system HUD | No toggle-prompt; deep-link to System Settings, poll to verify | No (core) |
| 5 | Automation | Apple Events | Desktop workflows + Spotify/Apple Music control | Prompts per target app at first use; onboarding can pre-warm only | Recommended |
| 6 | Calendar | Calendars (full) | Upcoming events in the notch | In-app prompt | Yes (optional) |
| 7 | Reminders | Reminders (full) | Show / check off reminders | In-app prompt | Yes (optional) |
| 8 | Camera | Camera | Notch "mirror" feature (inherited boring.notch) | In-app prompt | Yes — candidate to drop |
| 9 | All set | — | Finish / open Settings | — | — |

## Declared vs. requested (current state)

Current `OnboardingView.swift` walks: Welcome → Camera → Calendar → Reminders →
Accessibility → Music-source → Finish.

**Gaps (requested lazily on first use, not in onboarding):**
- Microphone — `BuddyDictationManager`, first push-to-talk
- Speech Recognition — `BuddyDictationManager:834`
- Screen Recording — `CompanionScreenCaptureUtility`, first SCShareableContent grab
- Automation / Apple Events — `WorkflowAgentActuator:519`, first NSAppleScript

The current flow asks for **Camera** (a minor inherited mirror feature) while
skipping **Microphone** and **Screen Recording** — two of Perch's three core
pillars (Vision / Microphone / Accessibility per `PerchPermissionsMenuContent`).

## Open questions
- (a) Drop Camera entirely?
- (b) Is Input Monitoring required for the global push-to-talk modifier tap?
  Verify against the event-tap code before adding it as a step.
- Music-source selection is not a permission; keep it as a separate post-permissions
  configuration step or fold into Settings.
