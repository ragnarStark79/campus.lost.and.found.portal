#!/bin/bash
# Align ownership of the persistent SQLite directory on the host to match the
# non-root `appuser` UID:GID inside the Campus Lost and Found Docker image.
# Usage:
#   lostandfound-sync-owner --check <image> <data_dir>   (exit 0 if aligned)
#   lostandfound-sync-owner <image> <data_dir>           (apply ownership)

set -euo pipefail

MODE="apply"
if [ "${1:-}" = "--check" ]; then
  MODE="check"
  shift
fi

IMAGE="${1:?image required}"
DATA_DIR="${2:?data_dir required}"

APP_UID="$(/usr/bin/docker run --rm --entrypoint id "$IMAGE" -u)"
APP_GID="$(/usr/bin/docker run --rm --entrypoint id "$IMAGE" -g)"
TARGET_OWNER="${APP_UID}:${APP_GID}"
CURRENT_OWNER="$(/usr/bin/stat -c '%u:%g' "$DATA_DIR")"

if [ "$MODE" = "check" ]; then
  [ "$CURRENT_OWNER" = "$TARGET_OWNER" ]
  exit $?
fi

/bin/chown "$TARGET_OWNER" "$DATA_DIR"
/usr/bin/find "$DATA_DIR" -mindepth 1 -maxdepth 1 ! -name 'lost+found' -exec /bin/chown -R "$TARGET_OWNER" {} +
