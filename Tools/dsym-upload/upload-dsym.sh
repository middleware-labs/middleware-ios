#!/usr/bin/env bash
# Copyright © 2024 Middleware. Licensed under the Apache License, Version 2.0
#
# Thin wrapper around @middleware.io/sourcemap-uploader `upload-dsym`.
# Prefers a local sourcemap-uploader checkout, then npx.
#
# Usage:
#   upload-dsym.sh --api-key <key> --version <app.version> --path <dSYM|zip|dir>
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

API_KEY="${MW_API_KEY:-}"
APP_VERSION="${MW_APP_VERSION:-}"
BACKEND_URL="${MW_BACKEND_URL:-}"
DSYM_PATH=""
DELETE_AFTER=""
BASE_PATH=""

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Upload dSYM files via @middleware.io/sourcemap-uploader (upload-dsym).

Required:
  --api-key <key>       RUM account key (or MW_API_KEY)
  --version <version>   App version matching RUM app.version (or MW_APP_VERSION)
  --path <path>         .dSYM, .dSYM.zip, or directory

Optional:
  --backend-url <url>   Override SAS endpoint (or MW_BACKEND_URL)
  --base-path <prefix>  Optional object-storage prefix
  --delete-after-upload Delete source .dSYM.zip after success
  -h, --help

See also: https://www.npmjs.com/package/@middleware.io/sourcemap-uploader
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --api-key) API_KEY="${2:-}"; shift 2 ;;
    --version) APP_VERSION="${2:-}"; shift 2 ;;
    --path) DSYM_PATH="${2:-}"; shift 2 ;;
    --backend-url) BACKEND_URL="${2:-}"; shift 2 ;;
    --base-path) BASE_PATH="${2:-}"; shift 2 ;;
    --delete-after-upload) DELETE_AFTER=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

[ -n "$API_KEY" ]     || { echo "ERROR: pass --api-key or set MW_API_KEY" >&2; exit 1; }
[ -n "$APP_VERSION" ] || { echo "ERROR: pass --version or set MW_APP_VERSION" >&2; exit 1; }
[ -n "$DSYM_PATH" ]   || { echo "ERROR: pass --path" >&2; exit 1; }

resolve_uploader() {
  # 1) Explicit override
  if [ -n "${MW_SOURCEMAP_UPLOADER:-}" ] && [ -f "${MW_SOURCEMAP_UPLOADER}" ]; then
    echo "node:${MW_SOURCEMAP_UPLOADER}"
    return
  fi

  # 2) Sibling checkout: code/sourcemap-uploader next to code/rum-agents
  #    SCRIPT_DIR = …/rum-agents/middleware-ios/Tools/dsym-upload
  local candidates=(
    "${SCRIPT_DIR}/../../../../sourcemap-uploader/dist/index.js"
    "${SCRIPT_DIR}/../../../../../sourcemap-uploader/dist/index.js"
    "${HOME}/code/sourcemap-uploader/dist/index.js"
  )
  local c
  for c in "${candidates[@]}"; do
    if [ -f "$c" ]; then
      echo "node:$c"
      return
    fi
  done

  # 3) Globally / locally installed CLI
  if command -v sourcemap-uploader >/dev/null 2>&1; then
    echo "bin:sourcemap-uploader"
    return
  fi

  # 4) npx published package
  echo "npx:@middleware.io/sourcemap-uploader"
}

RUNNER="$(resolve_uploader)"
ARGS=(upload-dsym -k "$API_KEY" -av "$APP_VERSION" -p "$DSYM_PATH")
[ -n "$BACKEND_URL" ] && ARGS+=(-bu "$BACKEND_URL")
[ -n "$BASE_PATH" ] && ARGS+=(-bp "$BASE_PATH")
[ -n "$DELETE_AFTER" ] && ARGS+=(-d true)

echo "[MiddlewareDsym] Using uploader: $RUNNER"

case "$RUNNER" in
  node:*)
    node "${RUNNER#node:}" "${ARGS[@]}"
    ;;
  bin:*)
    sourcemap-uploader "${ARGS[@]}"
    ;;
  npx:*)
    npx --yes "@middleware.io/sourcemap-uploader" "${ARGS[@]}"
    ;;
  *)
    echo "ERROR: could not resolve sourcemap-uploader" >&2
    exit 1
    ;;
esac
