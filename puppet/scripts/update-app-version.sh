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
COMMIT_SHA="${2:-}"
COMMIT_B64_INPUT="${3:-}"
DEPLOY_TIME="${4:-$(date -u '+%Y-%m-%dT%H:%M:%SZ')}"
RUN_ID="${5:-production}"
STATUS="${6:-Successful}"
MESSAGE="${7:-Successfully deployed through CI/CD pipeline. Puppet Agent pulled and applied the latest configuration from Puppet Master.}"

if [ -z "$IMAGE_INPUT" ]; then
  echo "ERROR: Target container image reference or tag required." >&2
  echo "Usage: $0 <IMAGE_REF_OR_TAG> [COMMIT_SHA] [COMMIT_B64] [DEPLOY_TIME] [RUN_ID] [STATUS] [MESSAGE]" >&2
  echo "Example: $0 ghcr.io/ragnarstark79/campus.lost.and.found.portal:sha-a1b2c3d a1b2c3d '<BASE64_MSG>' '2026-11-18T14:45:00Z' 12345" >&2
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

# Derive commit SHA if omitted
if [ -z "$COMMIT_SHA" ]; then
  if [[ "$FULL_IMAGE" =~ :sha-([a-f0-9]+) ]]; then
    COMMIT_SHA="${BASH_REMATCH[1]}"
  else
    COMMIT_SHA="0bf459f"
  fi
fi

# If COMMIT_B64_INPUT was omitted by caller ($# < 3), set default base64 commit message
if [ "$#" -lt 3 ]; then
  COMMIT_B64_INPUT=$(printf '%s' "feat: automated deployment via GitHub Actions and Puppet" | base64 | tr -d '\r\n')
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

# Safely update or insert lostandfound parameters in Hiera
if command -v python3 >/dev/null 2>&1; then
  python3 -c "
import sys, re, json, base64, binascii

path = sys.argv[1]
image = sys.argv[2]
commit_sha = sys.argv[3]
commit_b64 = sys.argv[4]
deploy_time = sys.argv[5]
run_id = sys.argv[6]
status = sys.argv[7]
message = sys.argv[8]
out_path = sys.argv[9]

# Decode and strictly validate base64 commit message using Python standard library
if not commit_b64:
    commit_msg = ''
else:
    try:
        decoded_bytes = base64.b64decode(commit_b64.encode('ascii'), validate=True)
        commit_msg = decoded_bytes.decode('utf-8')
    except (binascii.Error, ValueError, UnicodeDecodeError) as err:
        sys.stderr.write(f'ERROR: Failed to decode base64 commit message: {err}\n')
        sys.exit(1)

with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

image_tag = image.split(':')[-1] if ':' in image else image

# Robust JSON payload constructed using Python standard json.dumps
# Handles quotes, backslashes, newlines, tabs, and control characters natively
metadata_dict = {
    'deployment_status': status,
    'deployment_message': message,
    'deployment_pipeline': 'GitHub Actions',
    'deployment_path': 'GitHub Actions → GHCR → Puppet Master → Puppet Agent',
    'deployment_timestamp_utc': deploy_time,
    'deployment_commit': commit_sha[:7],
    'deployment_commit_message': commit_msg,
    'deployment_image_tag': image_tag,
    'deployment_workflow_run': str(run_id),
}
json_string = json.dumps(metadata_dict, indent=2)

updates = {
    'lostandfound::image': image,
    'lostandfound::deployment_status': status,
    'lostandfound::deployment_message': message,
    'lostandfound::deployment_timestamp_utc': deploy_time,
    'lostandfound::deployment_commit': commit_sha[:7],
    'lostandfound::deployment_commit_message': commit_msg,
    'lostandfound::deployment_image_tag': image_tag,
    'lostandfound::deployment_workflow_run': str(run_id),
    'lostandfound::deployment_json': json_string,
}

for key, val in updates.items():
    # Escape single quotes for YAML single-quoted string
    safe_val = str(val).replace(\"'\", \"''\")
    pattern = rf'^({re.escape(key)}:\s*).*$'
    if re.search(pattern, content, flags=re.MULTILINE):
        content = re.sub(
            pattern,
            lambda m, sv=safe_val: f\"{m.group(1)}'{sv}'\",
            content,
            flags=re.MULTILINE
        )
    else:
        content = content.rstrip() + f\"\n{key}: '{safe_val}'\n\"

with open(out_path, 'w', encoding='utf-8') as f:
    f.write(content)
" "$HIERA_FILE" "$FULL_IMAGE" "$COMMIT_SHA" "$COMMIT_B64_INPUT" "$DEPLOY_TIME" "$RUN_ID" "$STATUS" "$MESSAGE" "$TMP_HIERA"
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
