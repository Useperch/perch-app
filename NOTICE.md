# Third-Party Notices

## boring.notch (GPL-3.0)

Perch began as a fork of
**[TheBoredTeam/boring.notch](https://github.com/TheBoredTeam/boring.notch)**,
which is licensed under the **GNU General Public License v3.0 (GPL-3.0)**. Perch's
notch shell — the notch window, the `NotchShape` silhouette, the closed↔open
expand-on-hover morph, the open-HUD chrome — and substantial portions of the
surrounding UI (the media controllers, live-activity HUDs, shelf, onboarding, and
many view/extension/helper files) are derived from boring.notch.

The derived files live throughout the app source under
[`perch/notch/`](./perch/notch/) — for example the notch UI under
[`perch/notch/components/Notch/`](./perch/notch/components/Notch/), the media
controllers under `perch/notch/MediaControllers/`, and the shared views,
extensions, and helpers under `perch/notch/components/`, `perch/notch/extensions/`,
and `perch/notch/helpers/`. Each such file retains its upstream authorship header
(e.g. "Created by Alexander …", the boring.notch maintainers).

The notch shape itself (`perch/notch/components/Notch/NotchShape.swift`)
originates from **[MrKai77/DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit)**,
via boring.notch, and retains that attribution in its header.

Because Perch is a derivative of boring.notch, **Perch as a whole is distributed
under GPL-3.0**. See [LICENSE](./LICENSE).

The full GPL-3.0 license text is also available at
<https://www.gnu.org/licenses/gpl-3.0.txt>.
