#!/bin/bash
set -euo pipefail

# =============================================================================
# setup-signing-identity.sh — Create the stable self-signed code-signing
# identity used by build-perch.sh (one-time setup).
#
# WHY: Without a paid Apple Developer identity we sign the local build ourselves.
# Ad-hoc signing (`-s -`) produces a new cdhash every build, which makes macOS
# TCC reset ALL permission grants (Accessibility, Screen Recording, Microphone)
# on every rebuild. A stable self-signed cert fixes that: TCC keys its grants off
# the signature's Designated Requirement, which references this cert. Same cert →
# same requirement → grants persist across rebuilds.
#
# HOW (the trick that avoids any GUI/password prompt): the cert lives in a
# DEDICATED keychain whose password this script sets. Because we own that
# password, we can set the key's partition list non-interactively — the step that
# otherwise fails with errSecInternalComponent or pops a system auth dialog when
# done against the login keychain. The cert does NOT need to be system-trusted
# for codesign to sign with it. The password protects only this throwaway local
# signing keychain; override it with PERCH_SIGN_KEYCHAIN_PASSWORD if you like.
#
# Run once:  ./scripts/setup-signing-identity.sh
# Then:      ./scripts/build-perch.sh   (uses the identity automatically)
#
# After the FIRST build signed with this identity, re-grant the permissions once.
# They will then survive all subsequent rebuilds.
# =============================================================================

CN="Perch Self Signed"
KCNAME="perchdev.keychain"
PW="${PERCH_SIGN_KEYCHAIN_PASSWORD:-perch}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "▶︎ Generating self-signed code-signing certificate…"
openssl req -x509 -newkey rsa:2048 -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
    -days 3650 -nodes \
    -subj "/CN=${CN}" \
    -addext "extendedKeyUsage=codeSigning" \
    -addext "basicConstraints=critical,CA:false" \
    -addext "keyUsage=critical,digitalSignature" >/dev/null 2>&1

# -legacy: macOS Security framework can't read OpenSSL 3's default PKCS12 MAC.
openssl pkcs12 -export -legacy -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -out "$WORK/cert.p12" -passout "pass:${PW}" -name "${CN}" >/dev/null 2>&1

echo "▶︎ Creating dedicated keychain (password we control)…"
security delete-keychain "${KCNAME}" 2>/dev/null || true
security create-keychain -p "${PW}" "${KCNAME}"
security set-keychain-settings "${KCNAME}"            # disable auto-lock timeout
security unlock-keychain -p "${PW}" "${KCNAME}"

echo "▶︎ Importing identity and allowing codesign to use it…"
security import "$WORK/cert.p12" -k "${KCNAME}" -P "${PW}" -T /usr/bin/codesign -A >/dev/null 2>&1

echo "▶︎ Setting key partition list (no GUI — we own the keychain password)…"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "${PW}" "${KCNAME}" >/dev/null 2>&1

echo "▶︎ Adding keychain to the user search list (keeping existing)…"
EXISTING=$(security list-keychains -d user | sed 's/[",]//g' | xargs)
security list-keychains -d user -s ${EXISTING} "${KCNAME}"

echo "▶︎ Verifying codesign can sign with it…"
TESTBIN="$WORK/signtest"
printf '#!/bin/sh\necho hi\n' > "$TESTBIN"; chmod +x "$TESTBIN"
if codesign --force --sign "${CN}" --timestamp=none "$TESTBIN" >/dev/null 2>&1; then
    echo "✅ Signing identity '${CN}' is ready. Run ./scripts/build-perch.sh to build."
else
    echo "❌ Test sign failed — identity not usable."
    exit 1
fi
