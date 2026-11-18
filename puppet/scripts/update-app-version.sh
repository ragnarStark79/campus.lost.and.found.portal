#!/usr/bin/env bash
# ==============================================================================
# Puppet Durable Application Version Updater — Master Node
# Campus Lost and Found Portal — INT333 DevOps Project (Phase 4 / Phase 5)
# ==============================================================================
# Scope: Atomically updates 'lostandfound::image' in Hiera common.yaml on the
#        Puppet Master. Ensures durable application deployments so subsequent
#        Puppet agent runs do not revert the container image.
# Idempotent & Atomic: Uses temporary staging file and YAML verification.
# ==============================================================================

set -euo pipefail

IMAGE_INPUT="${1:-}"

if [ -z "$IMAGE_INPUT" ]; then
  echo "ERROR: Target container image reference or tag required." >&2
  echo "Usage: $0 <IMAGE_REF_OR_TAG>" >&2
  echo "Example: $0 ghcr.io/ragnarstark79/campus.lost.and.found.portal:sha-a1b2c3d" >&2
  echo "Example: $0 sha-a1b2c3d" >&2
  exit 1
fi

# Normalize image reference if only tag was provided
DEFAULT_REGISTRY="ghcr.io/ragnarstark79/campus.lost.and.found.portal"
if [[ "$IMAGE_INPUT" == sha-* ]] || [[ "$IMAGE_INPUT" == "latest" ]] || [[ "$IMAGE_INPUT" =~ ^v[0-9] ]]; then
  FULL_IMAGE="${DEFAULT_REGISTRY}:${IMAGE_INPUT}"
elif [[ "$IMAGE_INPUT" == *:* ]]; then
  FULL_IMAGE="$IMAGE_INPUT"
else
  FULL_IMAGE="${DEFAULT_REGISTRY}:${IMAGE_INPUT}"
fi

# Input validation: ensure no unsafe shell characters
if ! [[ "$FULL_IMAGE" =~ ^[a-zA-Z0-9_./:-]+$ ]]; then
  echo "ERROR: Invalid characters detected in image reference: $FULL_IMAGE" >&2
  exit 1
fi

# Locate Hiera common.yaml across production environment or local search paths
HIERA_FILE="/etc/puppetlabs/code/environments/production/data/common.yaml"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PUPPET_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ ! -f "$HIERA_FILE" ]; then
  if [ -f "$PUPPET_ROOT/data/common.yaml" ]; then
    HIERA_FILE="$PUPPET_ROOT/data/common.yaml"
  else
    echo "ERROR: Hiera common.yaml not found at $HIERA_FILE or $PUPPET_ROOT/data/common.yaml." >&2
    exit 1
  fi
fi

echo "========================================================================"
echo "Updating Durable Application Image in Hiera"
echo "Target File : $HIERA_FILE"
echo "Target Image: $FULL_IMAGE"
echo "Timestamp   : $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo "========================================================================"

TMP_HIERA="$(mktemp "${HIERA_FILE}.tmp.XXXXXX")"
trap 'rm -f "$TMP_HIERA"' EXIT

# Safely update or insert lostandfound::image using Python or awk
if command -v python3 >/dev/null 2>&1; then
  python3 -c "
import sys, re

path = sys.argv[1]
image = sys.argv[2]
out_path = sys.argv[3]

with open(path, 'r') as f:
    content = f.read()

pattern = r'^(lostandfound::image:\s*).*$'
replacement = r'\g<1>' + f\"'{image}'\"
if re.search(pattern, content, flags=re.MULTILINE):
    new_content = re.sub(pattern, replacement, content, flags=re.MULTILINE)
else:
    new_content = content + f\"\nlostandfound::image: '{image}'\n\"

with open(out_path, 'w') as f:
    f.write(new_content)
" "$HIERA_FILE" "$FULL_IMAGE" "$TMP_HIERA"
else
  # Fallback using awk
  awk -v img="$FULL_IMAGE" '
    BEGIN { found = 0 }
    /^lostandfound::image:/ {
      print "lostandfound::image: '\''" img "'\''"
      found = 1
      next
    }
    { print }
    END {
      if (!found) {
        print "lostandfound::image: '\''" img "'\''"
      }
    }
  ' "$HIERA_FILE" > "$TMP_HIERA"
fi

# Verify the file is non-empty and contains the new image
if ! grep -q "lostandfound::image: '$FULL_IMAGE'" "$TMP_HIERA"; then
  echo "ERROR: Verification failed; new image tag not found in staged file." >&2
  exit 1
fi

# Atomically replace target file
chmod 0644 "$TMP_HIERA"
chown puppet:puppet "$TMP_HIERA" 2>/dev/null || true
mv "$TMP_HIERA" "$HIERA_FILE"
trap - EXIT

echo "SUCCESS: Hiera common.yaml durably updated with image $FULL_IMAGE."
echo "Current Hiera application configuration:"
grep -E '^lostandfound::' "$HIERA_FILE" || true
echo "========================================================================"
