#!/usr/bin/env bash
# ==============================================================================
# Puppet Agent Node — Phase 3 Infrastructure Readiness Bootstrap
# Campus Lost and Found Portal — INT333 DevOps Project
# ==============================================================================
# Scope: Phase 3 Infrastructure & System Readiness ONLY
# (Puppet Agent configuration, Docker runtime, and NRPE monitoring are deferred
#  to Phase 4, Phase 5, and Phase 6 respectively)
# ==============================================================================

set -euo pipefail

MASTER_PRIVATE_IP="${master_private_ip}"
AGENT_PRIVATE_IP="${agent_private_ip}"
MASTER_HOSTNAME="${master_hostname}"
AGENT_HOSTNAME="${agent_hostname}"
AWS_REGION="${aws_region}"
SSM_PARAMETER_NAME="${ssm_parameter_name}"

LOG_FILE="/var/log/lostandfound-agent-bootstrap.log"
exec > >(tee -a "$LOG_FILE" /dev/console) 2>&1

echo "=========================================================="
echo "Starting Agent Infrastructure Readiness Bootstrap: $AGENT_HOSTNAME"
echo "Timestamp: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo "=========================================================="

# 1. Hostname and /etc/hosts Static Name Resolution
echo "[System] Setting hostname to $AGENT_HOSTNAME..."
hostnamectl set-hostname "$AGENT_HOSTNAME"

echo "[System] Configuring /etc/hosts..."
cat > /etc/hosts <<EOF
127.0.0.1 localhost
$MASTER_PRIVATE_IP $MASTER_HOSTNAME puppet
$AGENT_PRIVATE_IP $AGENT_HOSTNAME
EOF

# 2. Base Operating System Package Preparation
echo "[Packages] Updating apt and installing core infrastructure prerequisites..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y \
  ca-certificates \
  curl \
  wget \
  gnupg \
  lsb-release \
  awscli \
  jq

# 3. AWS Systems Manager (SSM) Agent Verification
echo "[SSM] Verifying AWS Systems Manager Agent status..."
if systemctl is-active --quiet snap.amazon-ssm-agent.amazon-ssm-agent.service; then
  echo "[SSM] snap.amazon-ssm-agent is active and running."
elif systemctl is-active --quiet amazon-ssm-agent; then
  echo "[SSM] amazon-ssm-agent is active and running."
else
  echo "[SSM] Starting amazon-ssm-agent service..."
  systemctl enable --now snap.amazon-ssm-agent.amazon-ssm-agent.service 2>/dev/null || \
  systemctl enable --now amazon-ssm-agent 2>/dev/null || true
fi

# 4. Application Persistent Data Directory Preparation on Root Volume
echo "[Storage] Preparing application persistent data path /opt/lostandfound/data on root volume..."
DATA_MOUNT="/opt/lostandfound/data"
mkdir -p "$DATA_MOUNT"
chmod 755 "$DATA_MOUNT"
echo "[Storage] Pre-created persistent data directory $DATA_MOUNT on root volume."

# 5. SSM Parameter Store Credential Check for Puppet Repository
echo "[SSM] Checking SSM Parameter Store for $SSM_PARAMETER_NAME..."
APT_KEY_VALUE=$(aws ssm get-parameter --name "$SSM_PARAMETER_NAME" --with-decryption --region "$AWS_REGION" --query "Parameter.Value" --output text 2>/dev/null || true)
if [ -n "$APT_KEY_VALUE" ] && [ "$APT_KEY_VALUE" != "None" ]; then
  echo "[SSM] Retrieved key from SSM Parameter Store. Configuring authenticated APT drop-in..."
  mkdir -p /etc/apt/auth.conf.d
  cat > /etc/apt/auth.conf.d/apt-puppetcore-puppet.conf <<EOF
machine apt-puppetcore.puppet.com
login forge-key
password $APT_KEY_VALUE
EOF
  chmod 600 /etc/apt/auth.conf.d/apt-puppetcore-puppet.conf
else
  echo "[SSM] Parameter $SSM_PARAMETER_NAME not present or empty. Standard public apt.puppet.com will be used."
fi

# 6. Repository Preparation for Phase 4 (Puppet 8 Noble)
echo "[Puppet-Repo] Installing official Puppet 8 repository release package for Ubuntu 24.04..."
TMP_DEB="/tmp/puppet8-release-noble.deb"
wget -q "https://apt.puppet.com/puppet8-release-noble.deb" -O "$TMP_DEB"
dpkg -i "$TMP_DEB"
rm -f "$TMP_DEB"
apt-get update -y

# 7. Phase 3 Infrastructure Readiness Completion Marker
touch /var/lib/lostandfound-agent-bootstrap.complete

echo "=========================================================="
echo "Agent Infrastructure Readiness Bootstrap Complete"
echo "Timestamp: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo "Phase 3 Status: READY FOR PHASE 4 (Puppet Agent Configuration)"
echo "=========================================================="
