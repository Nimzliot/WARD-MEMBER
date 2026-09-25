#!/usr/bin/env bash
# Netlify build for the Flutter web app. Runs from app/ (see netlify.toml).
set -euo pipefail

for v in SUPABASE_URL SUPABASE_ANON_KEY API_BASE_URL; do
  if [ -z "${!v:-}" ]; then
    echo "ERROR: environment variable $v is not set (Netlify → Site configuration → Environment variables)"
    exit 1
  fi
done

# Install Flutter once; Netlify caches this folder between builds.
FLUTTER_DIR="${NETLIFY_CACHE_DIR:-$HOME}/flutter-${FLUTTER_VERSION:-stable}"
if [ ! -x "$FLUTTER_DIR/bin/flutter" ]; then
  git clone --depth 1 --branch "${FLUTTER_VERSION:-stable}" https://github.com/flutter/flutter.git "$FLUTTER_DIR"
fi
export PATH="$FLUTTER_DIR/bin:$PATH"

flutter --version
flutter config --no-analytics --enable-web
flutter pub get
flutter build web --release --base-href / \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" \
  --dart-define=API_BASE_URL="$API_BASE_URL"
