#!/bin/bash
# Publishes the built DMG to a PUBLIC releases repository, so people can download
# Flightdeck while the source repository stays private.
#
# GitHub Releases inherit their repository's visibility: an asset on a private
# repo needs an authenticated token to fetch, which a download button on a public
# website cannot provide. A second repo holding only binaries — no source — is the
# way to keep the code private and the download anonymous.
#
# Run scripts/release.sh first to produce dist/Flightdeck-<version>.dmg.
#
#   ./scripts/publish-release.sh              # publish
#   DRY_RUN=1 ./scripts/publish-release.sh    # print what it would do
#
set -euo pipefail
cd "$(dirname "$0")/.."

RELEASE_REPO="${RELEASE_REPO:-Jackpkn/Flightdeck-releases}"
VERSION="$(cat VERSION)"
TAG="v$VERSION"
DMG="dist/Flightdeck-$VERSION.dmg"
DRY_RUN="${DRY_RUN:-}"

run() {
  if [ -n "$DRY_RUN" ]; then
    echo "    [dry run] $*"
  else
    "$@"
  fi
}

echo "==> Flightdeck $TAG -> $RELEASE_REPO"

# ── preflight ───────────────────────────────────────────────────────────────
if [ ! -f "$DMG" ]; then
  echo "!! $DMG not found. Run ./scripts/release.sh first." >&2
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "!! the GitHub CLI (gh) is required: brew install gh" >&2
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "!! not logged in. Run: gh auth login" >&2
  exit 1
fi

# Refuse to publish a build that would trip Gatekeeper without saying so, unless
# the caller has acknowledged it. An unsigned public download is a real problem,
# not a detail to discover from a user's bug report.
if ! codesign -dv "dist/Flightdeck.app" 2>&1 | grep -q "Authority=Developer ID"; then
  echo
  echo "!! This build is ad-hoc signed, not notarised."
  echo "   Anyone who downloads it sees \"Apple could not verify Flightdeck is"
  echo "   free of malware\" and must right-click -> Open on first launch."
  echo
  if [ -z "${ALLOW_UNSIGNED:-}" ]; then
    echo "   Set ALLOW_UNSIGNED=1 to publish anyway, or set DEVELOPER_ID and"
    echo "   NOTARY_PROFILE and re-run ./scripts/release.sh first."
    exit 1
  fi
  echo "   ALLOW_UNSIGNED=1 set — continuing."
fi

SIZE="$(du -h "$DMG" | cut -f1 | tr -d ' ')"
ARCHS="$(lipo -archs "dist/Flightdeck.app/Contents/MacOS/Flightdeck" 2>/dev/null || echo "unknown")"

# ── the releases repo ───────────────────────────────────────────────────────
if gh repo view "$RELEASE_REPO" >/dev/null 2>&1; then
  echo "==> Using existing $RELEASE_REPO"
else
  echo "==> Creating public repository $RELEASE_REPO (binaries only, no source)"
  run gh repo create "$RELEASE_REPO" --public \
    --description "Downloads for Flightdeck — the macOS activity monitor and Claude Code cockpit."
fi

# A release needs a commit to hang its tag on, and `gh repo create` leaves the
# repository empty. Seed it with a README the first time only.
BRANCHES="$(gh api "repos/$RELEASE_REPO/branches" --jq 'length' 2>/dev/null || echo 0)"
if [ -z "$DRY_RUN" ] && [ "$BRANCHES" = "0" ]; then
  echo "==> Seeding $RELEASE_REPO with a README (empty repos cannot be tagged)"
  SEED="$(mktemp -d)"
  {
    echo "# Flightdeck — downloads"
    echo
    echo "Binaries for [Flightdeck](https://github.com/Jackpkn/Flightdeck), a macOS activity"
    echo "monitor and Claude Code cockpit. The source lives in a private repository; this one"
    echo "exists because GitHub release assets inherit their repository's visibility, and a"
    echo "download link has to work without a token."
    echo
    echo "**[Download the latest release]($([ -n "$RELEASE_REPO" ] && echo "https://github.com/$RELEASE_REPO/releases/latest"))**"
    echo
    echo "## Install"
    echo
    echo "1. Open the DMG and drag Flightdeck to Applications."
    echo "2. On first launch, right-click the app and choose **Open**."
    echo
    echo "Step 2 is needed until the app is notarised with an Apple Developer certificate."
    echo "macOS will say it cannot verify the developer; right-click → Open gives you a way"
    echo "through, where double-clicking does not."
    echo
    echo "Requires macOS 14 or later. Universal: Apple silicon and Intel."
  } > "$SEED/README.md"
  git -C "$SEED" init -q
  git -C "$SEED" add README.md
  git -C "$SEED" commit -q -m "docs: explain what this repository is and how to install"
  git -C "$SEED" branch -M main
  git -C "$SEED" remote add origin "https://github.com/$RELEASE_REPO.git"
  git -C "$SEED" push -q origin main
  rm -rf "$SEED"
fi

# ── the release ─────────────────────────────────────────────────────────────
NOTES="$(cat <<EOF
Flightdeck $TAG — universal ($ARCHS), $SIZE.

**Install**
1. Open the DMG and drag Flightdeck to Applications.
2. On first launch, right-click the app and choose **Open**.

Step 2 is needed because this build is not yet notarised with an Apple Developer
certificate. macOS will say it cannot verify the developer; right-click → Open
gives you a way through, where double-clicking does not.

**What it does**
Reads your Claude Code transcripts and the git history of the repos they touched,
and measures what the spend produced — code survival, cost per surviving file,
waste and churn. Plus a full system monitor: Mach-level CPU and memory, processes,
ports, disk. Everything stays on your Mac; there is no account and no telemetry.

Requires macOS 14 or later.
EOF
)"

if gh release view "$TAG" --repo "$RELEASE_REPO" >/dev/null 2>&1; then
  echo "==> Release $TAG exists — replacing the DMG asset"
  run gh release upload "$TAG" "$DMG" --repo "$RELEASE_REPO" --clobber
else
  echo "==> Creating release $TAG"
  run gh release create "$TAG" "$DMG" \
    --repo "$RELEASE_REPO" \
    --title "Flightdeck $VERSION" \
    --notes "$NOTES"
fi

echo
echo "==> Done."
echo "    Download: https://github.com/$RELEASE_REPO/releases/latest/download/Flightdeck-$VERSION.dmg"
echo "    Releases: https://github.com/$RELEASE_REPO/releases"
