# CLAUDE.md — dev-perch/app

## CRITICAL: Build the right app, the right way

**This tree is NOT where the running app is built from.** The app the user
actually launches and dogfoods is **"Perch Dev.app"**, built from the *sibling*
clone at `/Users/karthikreddy/Downloads/GitHub/Perch_Project/perch` (branch
`main`). This `dev-perch/app` tree (branch `dev`) has byte-identical sources but
is a separate checkout — building or editing here does **nothing** to the
running app.

### When to build
Any time the user says "rebuild", "restart", "check the build", or wants a code
change to show up in the live notch app.

### How to build (do ALL of these)
1. **Port the change into the `perch` tree.** Apply the same edits to the
   matching files under `perch/notch/notch/...` (they mirror this tree's
   `notch/notch/...`). Editing only `dev-perch/app` will never reach the app.
2. **Build with the script, not raw `xcodebuild`:**
   ```
   cd /Users/karthikreddy/Downloads/GitHub/Perch_Project/perch
   ./scripts/build-perch-dev.sh
   ```
   This builds **Release**, renames the product to **"Perch Dev.app"**
   (bundle id `app.perch.notch.dev`), re-signs with the stable
   `Clicky Self Signed` cert (so TCC/Accessibility/Screen-Recording grants
   persist), then quits and **relaunches** Perch Dev automatically.

### Do NOT
- ❌ Don't run bare `xcodebuild ... -configuration Release` — it produces a
  plain `Perch.app` (`app.perch.notch`) that is unsigned-for-TCC and is **not**
  the bundle the user runs. Global hotkeys / screen capture silently break on it.
- ❌ Don't build only in `dev-perch/app` and assume the app updated.
- ❌ Don't build `build-perch.sh` (Debug) to test hotkeys/capture — the Debug
  stub misattributes TCC grants. Use `build-perch-dev.sh`.

### Reference
`perch/AGENTS.md` (build-flavors table) and `perch/docs/ops/BUILD_AND_RELEASE.md`
document the three flavors (Perch Dev / Perch / Perch Beta) and why identity +
signing matter for TCC persistence.
