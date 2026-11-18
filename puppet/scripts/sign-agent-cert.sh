#!/usr/bin/env bash
# ==============================================================================
# Controlled Puppet CA Certificate Signing Script — Master Node
# Campus Lost and Found Portal — INT333 DevOps Project (Phase 4)
# ==============================================================================
# Scope: Controlled inspection, signing, and verification of Agent CSRs on Master.
# Idempotent: Exits cleanly if certificate is already signed.
# ==============================================================================

set -euo pipefail

AGENT_CERTNAME="${1:-puppet-agent}"
CA_BIN="/opt/puppetlabs/bin/puppetserver ca"
LOG_FILE="/var/log/lostandfound-ca-sign.log"

exec > >(tee -a "$LOG_FILE" /dev/console) 2>&1

echo "========================================================================"
echo "Starting Puppet CA Certificate Verification for: $AGENT_CERTNAME"
echo "Timestamp: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo "========================================================================"

# ── 1. Check if Certificate is Already Signed ────────────────────────────────
echo "[CA] Checking if $AGENT_CERTNAME is already signed and active..."
if $CA_BIN list --all 2>/dev/null | awk '/Signed Certificates:/{p=1;next} /^[A-Z]/{p=0} p' | grep -q "$AGENT_CERTNAME"; then
  echo "[CA] Certificate for $AGENT_CERTNAME is already signed and active. No action needed."
  exit 0
fi

# ── 2. Poll for Pending CSR with Timeout ──────────────────────────────────────
echo "[CA] Waiting for incoming CSR from $AGENT_CERTNAME..."
CSR_FOUND=false
for attempt in $(seq 1 40); do
  if $CA_BIN list 2>/dev/null | grep -q "$AGENT_CERTNAME"; then
    CSR_FOUND=true
    echo "[CA] Detected pending CSR for $AGENT_CERTNAME (attempt $attempt/40)."
    break
  fi
  echo "[CA] Waiting for CSR from $AGENT_CERTNAME ($attempt/40)..."
  sleep 3
done

if [ "$CSR_FOUND" = false ]; then
  echo "[CA] ERROR: Pending CSR for $AGENT_CERTNAME was not received within 120 seconds."
  echo "[CA] Current CA state:"
  $CA_BIN list --all || true
  exit 1
fi

# ── 3. Sign the Certificate Request ──────────────────────────────────────────
echo "[CA] Signing CSR for $AGENT_CERTNAME..."
$CA_BIN sign --certname "$AGENT_CERTNAME"

# ── 4. Verify Active Certificate Status ──────────────────────────────────────
echo "[CA] Verifying signed certificate status in CA..."
if $CA_BIN list --all | awk '/Signed Certificates:/{p=1;next} /^[A-Z]/{p=0} p' | grep -q "$AGENT_CERTNAME"; then
  echo "[CA] SUCCESS: Certificate for $AGENT_CERTNAME successfully signed and registered."
  echo "========================================================================"
  echo "Puppet CA Signing Complete: $AGENT_CERTNAME"
  echo "Timestamp: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo "========================================================================"
  exit 0
else
  echo "[CA] ERROR: Certificate signing reported success but cert not found in active list."
  exit 1
fi
