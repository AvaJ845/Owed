#!/usr/bin/env bash
# Fetch the Owed brand fonts (all SIL OFL licensed) into Owed/Fonts/.
# Run from the project root: ./Scripts/fetch-fonts.sh
set -euo pipefail
DEST="$(dirname "$0")/../Owed/Fonts"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

dl() { curl -fsSL "$1" -o "$2"; echo "  ✓ $(basename "$2")"; }

echo "Fraunces (undercasetype/Fraunces)…"
dl "https://github.com/undercasetype/Fraunces/raw/master/fonts/static/ttf/Fraunces-SemiBold.ttf" "$DEST/Fraunces-SemiBold.ttf" || true
dl "https://github.com/undercasetype/Fraunces/raw/master/fonts/static/ttf/Fraunces-Bold.ttf" "$DEST/Fraunces-Bold.ttf" || true

echo "Public Sans (uswds/public-sans)…"
for w in Regular SemiBold Bold; do
  dl "https://github.com/uswds/public-sans/raw/master/fonts/ttf/PublicSans-$w.ttf" "$DEST/PublicSans-$w.ttf" || true
done

echo "IBM Plex Mono (google/fonts)…"
dl "https://github.com/google/fonts/raw/main/ofl/ibmplexmono/IBMPlexMono-Medium.ttf" "$DEST/IBMPlexMono-Medium.ttf" || true

echo "Done. Fonts land in Owed/Fonts and are picked up automatically on next build."
