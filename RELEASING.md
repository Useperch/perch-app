# Releasing Perch

How to cut and publish a public Perch release. The whole flow is:
**bump versions → run `package-release.sh` → publish the GitHub release → push the appcast.**

Users install via [SETUP.md](SETUP.md) (which downloads
`releases/latest/download/notch.dmg`) and receive later releases automatically through
Sparkle — the app polls
[`perch/updater/appcast.xml`](perch/updater/appcast.xml) on `main` once a day and offers
any newer signed build, both via the automatic check and Settings → "Check for Updates…".

## One-time prerequisites

These already exist on the original release machine. If you're releasing from a new
machine, copy them over — **do not regenerate them** (see [Key material](#key-material-back-it-up)).

| What | Where | Why |
| --- | --- | --- |
| "Perch Self Signed" code-signing cert | `~/Library/Keychains/perchdev.keychain-db` (password `perch` by default; created by `scripts/setup-signing-identity.sh`) | Same cert every release → users' Accessibility / Screen Recording / Mic grants survive updates |
| Sparkle EdDSA private key | `~/.perch-release/sparkle_ed25519_key` (backup also in the login Keychain as "Private key for signing Sparkle updates") | Signs the DMG; installed apps only accept updates matching the `SUPublicEDKey` baked into `perch/notch/Info.plist` |
| Workflow-share client secret | `.env` at the repo root: `PERCH_WORKFLOW_SHARE_CLIENT_SECRET=…` (gitignored) | Injected into the staged Info.plist at package time; the committed plist only carries a placeholder |
| Sidecar checkout | `../beta-backend-perch/browser-subagent` (or point `PERCH_SIDECAR_SOURCE` elsewhere) | Bundled into the app; without it the agent feature is missing from the shipped build |
| `gh` CLI authenticated for `Useperch/perch-app` | `gh auth status` | Publishes the release |

## 1. Bump the version

In `perch/notch.xcodeproj` (target **notch**, or edit `project.pbxproj` directly), bump
**both**:

- `MARKETING_VERSION` — the user-facing version (e.g. `2.7.4`)
- `CURRENT_PROJECT_VERSION` — the build number (e.g. `272`)

Sparkle compares **build numbers** (`CFBundleVersion`): if `CURRENT_PROJECT_VERSION`
doesn't increase, installed apps will never see the release as an update. The package
script warns if the appcast already lists an equal-or-higher build.

Commit the bump.

## 2. Package

```sh
./scripts/package-release.sh
```

This builds Release into its own DerivedData, stages a copy, injects the workflow-share
secret from `.env`, bundles the sidecar, re-signs with "Perch Self Signed", builds
`dist/notch.dmg`, then **EdDSA-signs the DMG and prepends the release entry to
`perch/updater/appcast.xml`**. See the script header for all knobs
(`PERCH_SKIP_BUILD=1`, `PERCH_RELEASE_NOTES_HTML`, …).

To ship real release notes inside the update window instead of the default
"see the release notes" link:

```sh
PERCH_RELEASE_NOTES_HTML='<h2>What&#8217;s new</h2><ul><li>…</li></ul>' \
    ./scripts/package-release.sh
```

Re-running the script for the same build number is safe — it replaces the appcast entry
rather than duplicating it.

## 3. Publish — both steps are required

```sh
# 1. The DMG users (and the appcast enclosure URL) download:
gh release create v<VERSION> dist/notch.dmg --target main \
    --title "Perch v<VERSION>" --notes "…"

# 2. The appcast installed apps poll (served raw from main):
git add perch/updater/appcast.xml
git commit -m "chore(release): appcast for v<VERSION>"
git push
```

Updates reach users only when **both** are live: the appcast tells installed apps a new
version exists; the release asset is what they download. The asset name must stay
`notch.dmg` — SETUP.md, the site's download button, and the appcast enclosure URL all
depend on it.

## 4. Verify

- `curl -s https://raw.githubusercontent.com/Useperch/perch-app/main/perch/updater/appcast.xml | head` —
  the new `<item>` is live (raw.githubusercontent caches for ~5 minutes).
- The `length=` in the new appcast entry matches
  `stat -f %z dist/notch.dmg` and the asset size shown by
  `gh release view v<VERSION> --json assets`.
- On a machine with the **previous** version installed: Settings → "Check for Updates…"
  offers the new version and installs it. Sparkle-installed updates are not quarantined,
  so no `xattr` step is needed (that's only for first installs from the DMG).

## Key material — back it up

Two secrets can never be rotated without hurting every existing user. Keep copies of both
somewhere safe (password manager, encrypted disk):

- **`~/Library/Keychains/perchdev.keychain-db`** — lose the cert and the next update is
  signed by a new identity, which resets every user's TCC grants (Accessibility, Screen
  Recording, Microphone).
- **`~/.perch-release/sparkle_ed25519_key`** — lose the Sparkle key and shipped apps can
  **never auto-update again**; the public key they trust is baked into their Info.plist.
  Every user would have to manually download and reinstall.

## Troubleshooting

- **"Sparkle private key not found"** — restore `~/.perch-release/sparkle_ed25519_key`
  from backup, or re-export from the login Keychain of the original release machine with
  Sparkle's `generate_keys -x <path>`. Do **not** generate a fresh key.
- **"'Perch Self Signed' not found — ad-hoc fallback"** — the perchdev keychain is
  missing or locked. Restore it; never publish the ad-hoc-signed DMG.
- **Installed app says "update error" / can't check** — the appcast URL must be publicly
  reachable and the entry's `sparkle:edSignature`/`length` must match the uploaded DMG
  byte-for-byte. If you re-upload a DMG, re-run the package script (or at least re-sign)
  and push the refreshed appcast.
- **Update offered but install fails signature check** — the DMG on the release doesn't
  match the appcast signature; re-run `./scripts/package-release.sh` with
  `PERCH_SKIP_BUILD=1`, re-upload with `gh release upload v<VERSION> dist/notch.dmg --clobber`,
  and push the updated appcast.
