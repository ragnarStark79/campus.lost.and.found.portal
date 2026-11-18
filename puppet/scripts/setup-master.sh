#!/usr/bin/env bash
# ==============================================================================
# Puppet Master Automation Script — Ubuntu 24.04 LTS (Noble)
# Campus Lost and Found Portal — INT333 DevOps Project (Phase 4)
# ==============================================================================
# Scope: Installs, tunes, configures, and starts Puppet Server 8 on puppet-master.
# Strict Security: No SSM dependency; no silent Jammy .deb fallback; fails fast.
# Idempotent: Safe to execute repeatedly without duplicating configuration.
# ==============================================================================

set -euo pipefail

# ── Configuration Variables ──────────────────────────────────────────────────
MASTER_HOSTNAME="${MASTER_HOSTNAME:-puppet-master}"
AGENT_HOSTNAME="${AGENT_HOSTNAME:-puppet-agent}"
MASTER_PRIVATE_IP="${MASTER_PRIVATE_IP:-10.30.1.10}"
AGENT_PRIVATE_IP="${AGENT_PRIVATE_IP:-10.30.2.10}"
JVM_MIN_HEAP="${JVM_MIN_HEAP:-512m}"
JVM_MAX_HEAP="${JVM_MAX_HEAP:-512m}"
PUPPET_ENV_DIR="/etc/puppetlabs/code/environments/production"
PUPPET_AGENT_VERSION="${PUPPET_AGENT_VERSION:-8.10.0-1noble}"
PUPPET_SERVER_VERSION="${PUPPET_SERVER_VERSION:-8.9.13-1noble}"
LOG_FILE="/var/log/lostandfound-puppet-master-setup.log"

exec > >(tee -a "$LOG_FILE" /dev/console) 2>&1

echo "========================================================================"
echo "Starting Puppet 8 Master Automation on: $MASTER_HOSTNAME"
echo "Timestamp: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo "========================================================================"

# ── 1. Hostname & Static Name Resolution ─────────────────────────────────────
echo "[System] Configuring hostname and static name resolution..."
if [ "$(hostname)" != "$MASTER_HOSTNAME" ]; then
  hostnamectl set-hostname "$MASTER_HOSTNAME"
  echo "[System] Hostname set to $MASTER_HOSTNAME."
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

# ── 3. Check for Authenticated Puppet Core Repository Credentials ───────────
AUTH_CONF="/etc/apt/auth.conf.d/apt-puppetcore-puppet.conf"
USE_AUTHENTICATED_REPO=false

if [ -f "$AUTH_CONF" ]; then
  echo "[Puppet-Repo] Detected drop-in APT authentication config at $AUTH_CONF."
  chmod 0600 "$AUTH_CONF"
  USE_AUTHENTICATED_REPO=true
else
  echo "[Puppet-Repo] No $AUTH_CONF found; public apt.puppet.com repository will be used."
fi

# ── 4. Install Puppet 8 Repository Package, OpenJDK 17 & Puppet Server 8 ─────
echo "[Puppet-Repo] Configuring official Puppet 8 repository for Ubuntu 24.04 Noble..."
export DEBIAN_FRONTEND=noninteractive
TMP_REPO_DEB="/tmp/puppet8-release-noble.deb"

if ! dpkg -l puppet8-release >/dev/null 2>&1; then
  if [ "$USE_AUTHENTICATED_REPO" = true ]; then
    echo "[Puppet-Repo] Downloading authenticated Puppet Core release package..."
    if ! wget -q "https://apt-puppetcore.puppet.com/public/puppet8-release-noble.deb" -O "$TMP_REPO_DEB"; then
      echo "[Puppet-Repo] ERROR: Failed to download release package from apt-puppetcore.puppet.com." >&2
      echo "[Puppet-Repo] Please verify network egress and repository authentication credentials." >&2
      rm -f "$TMP_REPO_DEB"
      exit 1
    fi
    dpkg -i "$TMP_REPO_DEB"
    rm -f "$TMP_REPO_DEB"

    if ! apt-get update -y; then
      echo "[Puppet-Repo] ERROR: apt-get update failed on apt-puppetcore.puppet.com repository." >&2
      echo "[Puppet-Repo] Verify Forge API key permissions or token validity." >&2
      exit 1
    fi
  else
    echo "[Puppet-Repo] Downloading public Puppet 8 release package (apt.puppet.com)..."
    wget -q "https://apt.puppet.com/puppet8-release-noble.deb" -O "$TMP_REPO_DEB"
    dpkg -i "$TMP_REPO_DEB"
    rm -f "$TMP_REPO_DEB"
    apt-get update -y
  fi
fi

echo "[Puppet-Prereqs] Installing puppet-agent ($PUPPET_AGENT_VERSION) and openjdk-17-jre-headless..."
apt-get install -y --no-install-recommends \
  "puppet-agent=$PUPPET_AGENT_VERSION" \
  openjdk-17-jre-headless

echo "[Puppet-Install] Installing Puppet Server 8 ($PUPPET_SERVER_VERSION)..."
if ! dpkg -l puppetserver >/dev/null 2>&1; then
  echo "[Puppet-Install] Installing puppetserver from configured repository..."
  if ! apt-get install -y "puppetserver=$PUPPET_SERVER_VERSION"; then
    echo "[Puppet-Install] ERROR: puppetserver package installation failed on Ubuntu 24.04 (Noble)." >&2
    echo "[Puppet-Install] Silent Jammy package fallback is strictly disabled per Phase 4.8 policy." >&2
    echo "[Puppet-Install] Ensure apt-puppetcore credentials or native packages are available." >&2
    exit 1
  fi
  echo "[Puppet-Install] puppetserver successfully installed."
else
  echo "[Puppet-Install] puppetserver package is already installed."
fi

# Verify puppetserver binary exists under standard Puppet Labs AIO paths
if [ ! -f /opt/puppetlabs/bin/puppetserver ] && [ ! -f /opt/puppetlabs/server/apps/puppetserver/bin/puppetserver ]; then
  echo "[Puppet-Install] ERROR: puppetserver executable not found after package installation." >&2
  exit 1
fi

# ── 5. Configure Puppet Server JVM Runtime & Heap (-Xms512m -Xmx512m) ────────
echo "[JVM] Tuning Puppet Server JVM runtime (OpenJDK 17) and memory limits for t3.small..."
JAVA_ARGS_CONF='JAVA_ARGS="-Xms'"$JVM_MIN_HEAP"' -Xmx'"$JVM_MAX_HEAP"'"'
JAVA_BIN_TARGET="/usr/lib/jvm/java-17-openjdk-amd64/bin/java"

if [ -f /etc/default/puppetserver ]; then
  # Explicitly pin Java binary to OpenJDK 17 (do not rely on default Java 21)
  if [ -x "$JAVA_BIN_TARGET" ]; then
    if grep -q '^JAVA_BIN=' /etc/default/puppetserver; then
      sed -i 's|^JAVA_BIN=.*|JAVA_BIN="'"$JAVA_BIN_TARGET"'"|' /etc/default/puppetserver
    else
      echo 'JAVA_BIN="'"$JAVA_BIN_TARGET"'"' >> /etc/default/puppetserver
    fi
    echo "[JVM] Pinned Puppet Server runtime to OpenJDK 17 ($JAVA_BIN_TARGET)."
  fi

  # Explicitly configure heap limits
  if grep -q '^JAVA_ARGS=' /etc/default/puppetserver; then
    sed -i 's/^JAVA_ARGS=.*/JAVA_ARGS="-Xms'"$JVM_MIN_HEAP"' -Xmx'"$JVM_MAX_HEAP"'"/' /etc/default/puppetserver
  else
    echo "$JAVA_ARGS_CONF" >> /etc/default/puppetserver
  fi
  echo "[JVM] Verified /etc/default/puppetserver configured with $JAVA_ARGS_CONF."
fi

# ── 6. Configure Puppet Master Server & CA Identity ──────────────────────────
echo "[Puppet-Config] Configuring /etc/puppetlabs/puppet/puppet.conf..."
mkdir -p /etc/puppetlabs/puppet
cat > /etc/puppetlabs/puppet/puppet.conf <<EOF
[main]
certname = $MASTER_HOSTNAME
server = $MASTER_HOSTNAME
environment = production
runinterval = 30m

[server]
certname = $MASTER_HOSTNAME
dns_alt_names = $MASTER_HOSTNAME,puppet,$MASTER_PRIVATE_IP
EOF

# Ensure automatic certificate signing is DISABLED for strict security
rm -f /etc/puppetlabs/puppet/autosign.conf
echo "[Puppet-Config] Verified automatic certificate signing is disabled (autosign.conf absent)."

# Ensure standard binary symlinks
ln -sf /opt/puppetlabs/bin/puppet /usr/local/bin/puppet
ln -sf /opt/puppetlabs/bin/puppetserver /usr/local/bin/puppetserver

# ── 7. Deploy Puppet Code, Environments & Hiera Configuration ────────────────
echo "[Puppet-Code] Setting up production environment at $PUPPET_ENV_DIR..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Discover source manifests and modules directory across candidate locations
SRC_DIR=""
for candidate in \
  "$SCRIPT_DIR/.." \
  "$PROJECT_ROOT/puppet" \
  "/tmp/puppet" \
  "/tmp/puppet-src" \
  "/opt/lostandfound/puppet"; do
  if [ -f "$candidate/manifests/site.pp" ]; then
    SRC_DIR="$candidate"
    break
  fi
done

if [ -n "$SRC_DIR" ]; then
  echo "[Puppet-Code] Found source directory at $SRC_DIR. Invoking deploy-puppet-code.sh..."
  if [ -f "$SRC_DIR/scripts/deploy-puppet-code.sh" ]; then
    bash "$SRC_DIR/scripts/deploy-puppet-code.sh"
  else
    mkdir -p "$PUPPET_ENV_DIR/manifests" "$PUPPET_ENV_DIR/modules" "$PUPPET_ENV_DIR/data"
    cp -r "$SRC_DIR/manifests/"* "$PUPPET_ENV_DIR/manifests/"
    cp -r "$SRC_DIR/modules/"* "$PUPPET_ENV_DIR/modules/"
    [ -f "$SRC_DIR/hiera.yaml" ] && cp "$SRC_DIR/hiera.yaml" "$PUPPET_ENV_DIR/hiera.yaml"
    [ -d "$SRC_DIR/data" ] && cp -r "$SRC_DIR/data/"* "$PUPPET_ENV_DIR/data/"
    find "$PUPPET_ENV_DIR" -type d -exec chmod 0755 {} +
    find "$PUPPET_ENV_DIR" -type f -exec chmod 0644 {} +
    chown -R puppet:puppet /etc/puppetlabs/code 2>/dev/null || true
  fi
  echo "[Puppet-Code] Successfully deployed manifests, modules, and Hiera data to $PUPPET_ENV_DIR."
else
  echo "[Puppet-Code] ERROR: Puppet source manifests not found in search paths." >&2
  exit 1
fi

# Verify site.pp exists in production environment
if [ ! -f "$PUPPET_ENV_DIR/manifests/site.pp" ]; then
  echo "[Puppet-Code] ERROR: $PUPPET_ENV_DIR/manifests/site.pp is missing." >&2
  exit 1
fi

# ── 8. Start and Enable Puppet Server Service ────────────────────────────────
echo "[Service] Starting and enabling puppetserver.service..."
systemctl daemon-reload
systemctl enable puppetserver
systemctl restart puppetserver

# ── 9. Verify TCP Port 8140 Listening (Readiness Check) ─────────────────────
echo "[Readiness] Waiting for Puppet Server port 8140 to become active..."
PORT_ACTIVE=false
for attempt in $(seq 1 60); do
  if ss -tlpn | grep -q ':8140'; then
    PORT_ACTIVE=true
    echo "[Readiness] Port 8140 is listening (attempt $attempt/60)."
    break
  elif timeout 2 bash -c "</dev/tcp/127.0.0.1/8140" 2>/dev/null; then
    PORT_ACTIVE=true
    echo "[Readiness] Port 8140 is accepting TCP connections (attempt $attempt/60)."
    break
  fi
  echo "[Readiness] Waiting for Puppet Server JVM initialization ($attempt/60)..."
  sleep 3
done

if [ "$PORT_ACTIVE" = false ]; then
  echo "[Readiness] ERROR: Puppet Server port 8140 did not become ready within 180 seconds."
  systemctl status puppetserver --no-pager || true
  exit 1
fi

# ── 10. Verify CA Service and Initial Certificate Status ─────────────────────
echo "[CA] Verifying Puppet CA service status..."
/opt/puppetlabs/bin/puppetserver ca list --all || true

touch /var/lib/lostandfound-puppet-master-ready
echo "========================================================================"
echo "Puppet 8 Master Automation Completed Successfully"
echo "Status: READY FOR AGENT HANDSHAKE"
echo "Timestamp: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo "========================================================================"
