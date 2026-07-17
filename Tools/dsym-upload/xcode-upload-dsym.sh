#!/usr/bin/env bash
# Copyright © 2024 Middleware. Licensed under the Apache License, Version 2.0
#
# Xcode Run Script Build Phase helper.
# Delegates to @middleware.io/sourcemap-uploader via upload-dsym.sh.
#
# Skips quietly when:
#   - building for simulator (set MW_UPLOAD_SIMULATOR_DSYMS=1 to force)
#   - MW_API_KEY is not set
#   - no dSYM was produced
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPLOADER="$SCRIPT_DIR/upload-dsym.sh"
chmod +x "$UPLOADER" 2>/dev/null || true

API_KEY="${MW_API_KEY:-${MIDDLEWARE_API_KEY:-}}"
BACKEND_URL="${MW_BACKEND_URL:-}"

APP_VERSION="${MW_APP_VERSION:-}"
if [ -z "$APP_VERSION" ]; then
  APP_VERSION="${MARKETING_VERSION:-}"
fi
if [ -z "$APP_VERSION" ]; then
  APP_VERSION="${CURRENT_PROJECT_VERSION:-latest}"
fi

DSYM_CANDIDATE=""
if [ -n "${DWARF_DSYM_FOLDER_PATH:-}" ] && [ -n "${DWARF_DSYM_FILE_NAME:-}" ]; then
  DSYM_CANDIDATE="${DWARF_DSYM_FOLDER_PATH}/${DWARF_DSYM_FILE_NAME}"
fi

if [ -z "$DSYM_CANDIDATE" ] || [ ! -e "$DSYM_CANDIDATE" ]; then
  SEARCH_ROOT="${DWARF_DSYM_FOLDER_PATH:-${TARGET_BUILD_DIR:-${BUILT_PRODUCTS_DIR:-}}}"
  if [ -n "$SEARCH_ROOT" ] && [ -d "$SEARCH_ROOT" ]; then
    DSYM_CANDIDATE="$(find "$SEARCH_ROOT" -maxdepth 2 -type d -name '*.dSYM' 2>/dev/null | head -n 1 || true)"
  fi
fi

PLATFORM_NAME="${PLATFORM_NAME:-}"
if [[ "$PLATFORM_NAME" == *simulator* && "${MW_UPLOAD_SIMULATOR_DSYMS:-0}" != "1" ]]; then
  echo "[MiddlewareDsym] Skipping upload for simulator build (set MW_UPLOAD_SIMULATOR_DSYMS=1 to force)."
  exit 0
fi

if [ -z "$API_KEY" ]; then
  echo "[MiddlewareDsym] MW_API_KEY not set — skipping dSYM upload."
  exit 0
fi

if [ -z "$DSYM_CANDIDATE" ] || [ ! -e "$DSYM_CANDIDATE" ]; then
  echo "[MiddlewareDsym] No dSYM found (check DEBUG_INFORMATION_FORMAT = dwarf-with-dsym). Skipping."
  exit 0
fi

echo "[MiddlewareDsym] Uploading $DSYM_CANDIDATE (version=$APP_VERSION)"

EXTRA=()
[ -n "$BACKEND_URL" ] && EXTRA+=(--backend-url "$BACKEND_URL")

exec "$UPLOADER" \
  --api-key "$API_KEY" \
  --version "$APP_VERSION" \
  --path "$DSYM_CANDIDATE" \
  "${EXTRA[@]}"
