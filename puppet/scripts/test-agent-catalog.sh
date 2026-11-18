#!/usr/bin/env bash
# ==============================================================================
# Puppet Agent Catalog Test & Verification Script — Agent Node
# Campus Lost and Found Portal — INT333 DevOps Project (Phase 4)
# ==============================================================================
# Scope: Executes catalog application, checks exit codes, and validates state.
# Idempotent: Can be run repeatedly to verify convergence.
# ==============================================================================

set -uo pipefail

PUPPET_BIN="/opt/puppetlabs/bin/puppet"
LOG_FILE="/var/log/lostandfound-catalog-test.log"

exec > >(tee -a "$LOG_FILE" /dev/console) 2>&1

echo "========================================================================"
echo "Starting Puppet Agent Catalog Retrieval & Verification"
echo "Timestamp: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo "========================================================================"

# ── 1. Execute Puppet Agent Run with Detailed Exit Codes ──────────────────────
echo "[Catalog] Requesting and applying catalog from Puppet Master..."
set +e
$PUPPET_BIN agent --test --detailed-exitcodes
EXIT_CODE=$?
set -e

echo "[Catalog] Puppet agent run completed with exit code: $EXIT_CODE"

# Puppet detailed-exitcodes specification:
# 0: The run succeeded with no changes.
# 2: The run succeeded, and some resources were changed.
# 1: The run failed, or wasn't allowed.
# 4: The run succeeded, and some resources failed.
# 6: The run succeeded, and included both changes and failures.
case $EXIT_CODE in
  0)
    echo "[Catalog] SUCCESS: Catalog applied cleanly (0 changes needed - state in sync)."
    ;;
  2)
    echo "[Catalog] SUCCESS: Catalog applied successfully (corrective/initial changes applied)."
    ;;
  *)
    echo "[Catalog] ERROR: Catalog application failed with exit code $EXIT_CODE."
    exit 1
    ;;
esac

# ── 2. Verify Managed System Resources ───────────────────────────────────────
echo "[Verification] Auditing managed system resources..."

# Check 1: Login banner /etc/motd
if [ -f /etc/motd ] && grep -q "Managed By  : Puppet 8" /etc/motd; then
  echo "[Verification] [PASS] /etc/motd managed correctly by baseline module."
else
  echo "[Verification] [FAIL] /etc/motd does not contain expected Puppet banner."
  exit 1
fi

# Check 2: Time synchronization (chrony)
if systemctl is-active --quiet chrony; then
  echo "[Verification] [PASS] chrony time service is active and running."
else
  echo "[Verification] [FAIL] chrony service is not active."
  exit 1
fi

# Check 3: Application persistent storage directory
if [ -d "/opt/lostandfound/data" ]; then
  DATA_PERMS="$(stat -c '%a' /opt/lostandfound/data)"
  echo "[Verification] [PASS] /opt/lostandfound/data directory exists (permissions: $DATA_PERMS)."
else
  echo "[Verification] [FAIL] /opt/lostandfound/data directory missing."
  exit 1
fi

# ── 3. Inspect Last Run Summary Report ────────────────────────────────────────
SUMMARY_FILE="/opt/puppetlabs/puppet/cache/state/last_run_summary.yaml"
if [ -f "$SUMMARY_FILE" ]; then
  echo "[Report] Puppet Last Run Summary:"
  grep -A 8 'resources:' "$SUMMARY_FILE" || true
fi

touch /var/lib/lostandfound-phase4-catalog-verified
echo "========================================================================"
echo "Phase 4 Catalog Retrieval & Verification Complete: ALL TESTS PASSED"
echo "Timestamp: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo "========================================================================"
