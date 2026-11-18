#!/usr/bin/env bash
# ==============================================================================
# Puppet Agent Automation Script — Ubuntu 24.04 LTS (Noble)
# Campus Lost and Found Portal — INT333 DevOps Project (Phase 4)
# ==============================================================================
# Scope: Installs, configures, connects, and starts Puppet Agent 8 on puppet-agent.
# Idempotent: Safe to execute repeatedly without duplicating configuration.
# ==============================================================================

set -euo pipefail

# ── Configuration Variables ──────────────────────────────────────────────────
MASTER_HOSTNAME="${MASTER_HOSTNAME:-puppet-master}"
AGENT_HOSTNAME="${AGENT_HOSTNAME:-puppet-agent}"
MASTER_PRIVATE_IP="${MASTER_PRIVATE_IP:-10.30.1.10}"
AGENT_PRIVATE_IP="${AGENT_PRIVATE_IP:-10.30.2.10}"
PUPPET_AGENT_VERSION="${PUPPET_AGENT_VERSION:-8.10.0-1noble}"
DATA_MOUNT="/opt/lostandfound/data"
LOG_FILE="/var/log/lostandfound-puppet-agent-setup.log"

exec > >(tee -a "$LOG_FILE" /dev/console) 2>&1

echo "========================================================================"
echo "Starting Puppet 8 Agent Automation on: $AGENT_HOSTNAME"
echo "Timestamp: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo "========================================================================"

# ── 1. Hostname & Static Name Resolution ─────────────────────────────────────
echo "[System] Configuring hostname and static name resolution..."
if [ "$(hostname)" != "$AGENT_HOSTNAME" ]; then
  hostnamectl set-hostname "$AGENT_HOSTNAME"
  echo "[System] Hostname set to $AGENT_HOSTNAME."
fi

# Ensure /etc/hosts contains deterministic mappings
if ! grep -q "$MASTER_HOSTNAME" /etc/hosts; then
  cat >> /etc/hosts <<EOF
$MASTER_PRIVATE_IP $MASTER_HOSTNAME puppet
EOF
fi

if ! grep -q "$AGENT_HOSTNAME" /etc/hosts; then
  cat >> /etc/hosts <<EOF
$AGENT_PRIVATE_IP $AGENT_HOSTNAME
EOF
fi

# ── 2. Base System Package Preparation ───────────────────────────────────────
echo "[Packages] Updating apt cache and installing core prerequisites..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y --no-install-recommends \
  ca-certificates \
  curl \
  wget \
  gnupg \
  lsb-release \
  jq \
  net-tools

# ── 3. Application Persistent Data Path Preparation on Root Volume ───────────
echo "[Storage] Verifying persistent data path at $DATA_MOUNT..."
mkdir -p "$DATA_MOUNT"
chmod 0755 "$DATA_MOUNT"
echo "[Storage] Verified persistent data path $DATA_MOUNT on root volume."

# ── 4. Install Puppet 8 Noble Repository Package & Puppet Agent 8 ─────────────
echo "[Puppet-Repo] Configuring official Puppet 8 repository for Ubuntu 24.04 Noble..."
export DEBIAN_FRONTEND=noninteractive
TMP_DEB="/tmp/puppet8-release-noble.deb"

if ! dpkg -l puppet8-release >/dev/null 2>&1; then
  echo "[Puppet-Repo] Downloading public Puppet 8 repository package (apt.puppet.com)..."
  wget -q "https://apt.puppet.com/puppet8-release-noble.deb" -O "$TMP_DEB"
  dpkg -i "$TMP_DEB"
  rm -f "$TMP_DEB"
  apt-get update -y
fi

echo "[Puppet-Install] Installing Puppet Agent 8 ($PUPPET_AGENT_VERSION)..."
if ! dpkg -l puppet-agent >/dev/null 2>&1; then
  if ! apt-get install -y --no-install-recommends "puppet-agent=$PUPPET_AGENT_VERSION"; then
    echo "[Puppet-Install] ERROR: apt-get install failed for puppet-agent." >&2
    exit 1
  fi
  echo "[Puppet-Install] puppet-agent package installed successfully."
else
  echo "[Puppet-Install] puppet-agent package is already installed."
fi

# Verify puppet binary exists
if [ ! -f /opt/puppetlabs/bin/puppet ]; then
  echo "[Puppet-Install] ERROR: /opt/puppetlabs/bin/puppet binary not found after installation." >&2
  exit 1
fi

# Ensure standard binary symlink
ln -sf /opt/puppetlabs/bin/puppet /usr/local/bin/puppet

# ── 5. Configure Puppet Agent Identity & Master Association ──────────────────
echo "[Puppet-Config] Configuring /etc/puppetlabs/puppet/puppet.conf..."
mkdir -p /etc/puppetlabs/puppet
cat > /etc/puppetlabs/puppet/puppet.conf <<EOF
[main]
certname = $AGENT_HOSTNAME
server = $MASTER_HOSTNAME
environment = production
runinterval = 30m
EOF

# ── 6. Wait for Puppet Server Connectivity on Port 8140 ──────────────────────
echo "[Connectivity] Verifying network reachability of Puppet Master ($MASTER_PRIVATE_IP:8140)..."
MASTER_REACHABLE=false
for attempt in $(seq 1 60); do
  if timeout 3 bash -c "</dev/tcp/$MASTER_PRIVATE_IP/8140" 2>/dev/null; then
    MASTER_REACHABLE=true
    echo "[Connectivity] Successfully connected to Puppet Master on TCP port 8140 (attempt $attempt/60)."
    break
  fi
  echo "[Connectivity] Waiting for Master port 8140 at $MASTER_PRIVATE_IP ($attempt/60)..."
  sleep 3
done

if [ "$MASTER_REACHABLE" = false ]; then
  echo "[Connectivity] ERROR: Unable to reach Puppet Master at $MASTER_PRIVATE_IP:8140 within 180 seconds."
  echo "[Connectivity] Please verify Master status and security group ingress rule."
  exit 1
fi

# ── 7. Submit SSL Certificate Request (CSR) ──────────────────────────────────
echo "[SSL] Generating SSL credentials and submitting CSR to Master..."
if ! /opt/puppetlabs/bin/puppet ssl verify 2>/dev/null; then
  echo "[SSL] Certificate not yet verified. Submitting certificate request..."
  /opt/puppetlabs/bin/puppet ssl submit_request || true
else
  echo "[SSL] Agent certificate already verified and trusted."
fi

# ── 8. Start and Enable Puppet Agent Service ─────────────────────────────────
echo "[Service] Enabling and starting puppet.service..."
systemctl daemon-reload
systemctl enable puppet
systemctl restart puppet

touch /var/lib/lostandfound-puppet-agent-ready
echo "========================================================================"
echo "Puppet 8 Agent Automation Completed Successfully"
echo "Status: CSR SUBMITTED & AGENT SERVICE ENABLED"
echo "Timestamp: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo "========================================================================"
