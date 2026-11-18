#!/usr/bin/env bash
# ==============================================================================
# Puppet Orchestration Runner — Master & Agent Execution
# Campus Lost and Found Portal — INT333 DevOps Project (Phase 4 / Phase 5)
# ==============================================================================
# Strict SSH Security:
#   - Enforces BatchMode=yes, ConnectTimeout=10, StrictHostKeyChecking=yes
#   - UserKnownHostsFile points to protected known_hosts file
#   - Strictly removes all SSM dependencies and insecure SSH bypasses
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PUPPET_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MODE="${1:-}"

# Default location of existing EC2 SSH key (devpupAsia.pem)
DEFAULT_KEY="$HOME/Downloads/devpupAsia.pem"
if [ ! -f "$DEFAULT_KEY" ] && [ -f "$HOME/.ssh/campus-devops/devpupAsia.pem" ]; then
  DEFAULT_KEY="$HOME/.ssh/campus-devops/devpupAsia.pem"
fi
DEFAULT_KNOWN_HOSTS="$HOME/.ssh/known_hosts"

print_usage() {
  cat <<EOF
Usage:
  # Local node execution (inside respective EC2 instance):
  $0 --local-master
  $0 --local-agent
  $0 --local-sign
  $0 --local-test

  # Remote orchestration via strict SSH (from Mac development workstation / runner):
  $0 --ssh <MASTER_PUBLIC_IP> <AGENT_PUBLIC_IP> [KEY_PATH] [KNOWN_HOSTS_PATH]
  $0 --ssh-master-setup <MASTER_PUBLIC_IP> [KEY_PATH] [KNOWN_HOSTS_PATH]
  $0 --ssh-agent-setup <AGENT_PUBLIC_IP> [KEY_PATH] [KNOWN_HOSTS_PATH]
  $0 --ssh-sign <MASTER_PUBLIC_IP> [KEY_PATH] [KNOWN_HOSTS_PATH]
  $0 --ssh-verify <AGENT_PUBLIC_IP> [KEY_PATH] [KNOWN_HOSTS_PATH]
  $0 --ssh-deploy-app <MASTER_PUBLIC_IP> <AGENT_PUBLIC_IP> <IMAGE_TAG> [KEY_PATH] [KNOWN_HOSTS_PATH]
EOF
  exit 1
}

if [ -z "$MODE" ]; then
  print_usage
fi

verify_ssh_prerequisites() {
  local target_ip="$1"
  local key_path="$2"
  local hosts_path="$3"
  local role_label="$4"

  # 1. Key file verification
  if [ ! -f "$key_path" ]; then
    echo "ERROR: SSH private key not found at: $key_path" >&2
    echo "Please verify that the existing devpupAsia.pem is present at $HOME/Downloads/devpupAsia.pem or specify KEY_PATH." >&2
    exit 1
  fi

  # Check permissions (must not be group/world accessible)
  local key_perms
  key_perms="$(stat -f '%Lp' "$key_path" 2>/dev/null || stat -c '%a' "$key_path" 2>/dev/null || echo '0400')"
  if [ "$key_perms" != "400" ] && [ "$key_perms" != "600" ]; then
    echo "ERROR: SSH private key $key_path has permissions $key_perms (expected 0400 or 0600)." >&2
    echo "Per security policy, please ensure the file is secured via: chmod 0400 $key_path" >&2
    exit 1
  fi

  # 2. Known hosts verification
  if [ ! -f "$hosts_path" ]; then
    echo "ERROR: known_hosts file not found at: $hosts_path" >&2
    echo "To configure trusted host verification, perform independent fingerprint validation:" >&2
    echo "  1. Retrieve trusted fingerprints from EC2 console output:" >&2
    echo "     aws ec2 get-console-output --instance-id <INSTANCE_ID> --output text | grep -A 10 'SSH HOST KEY FINGERPRINTS'" >&2
    echo "  2. Compare against keys scanned locally:" >&2
    echo "     ssh-keyscan -H -T 10 $target_ip > /tmp/host_key" >&2
    echo "     ssh-keygen -lf /tmp/host_key" >&2
    echo "  3. Append to $hosts_path only after fingerprints match:" >&2
    echo "     cat /tmp/host_key >> $hosts_path && rm /tmp/host_key" >&2
    exit 1
  fi

  if ! ssh-keygen -F "$target_ip" -f "$hosts_path" >/dev/null 2>&1; then
    echo "ERROR: StrictHostKeyChecking: Host key for $role_label ($target_ip) not found in $hosts_path." >&2
    echo "To enroll trusted host key after independent verification:" >&2
    echo "  1. Verify fingerprint matches EC2 console output for $role_label." >&2
    echo "  2. Append verified key to $hosts_path:" >&2
    echo "     ssh-keyscan -H -T 10 $target_ip >> $hosts_path" >&2
    exit 1
  fi

  # 3. Port 22 preflight check
  echo "[Preflight] Verifying TCP connectivity to $role_label ($target_ip:22)..."
  if ! nc -zv -w 5 "$target_ip" 22 2>/dev/null; then
    echo "ERROR: Cannot reach $role_label ($target_ip) on port 22." >&2
    echo "Verify that:" >&2
    echo "  1. The EC2 instance is in 'running' state." >&2
    echo "  2. Your current workstation IP ($(curl -s https://checkip.amazonaws.com 2>/dev/null || echo 'unknown')) is authorized in security group ingress." >&2
    exit 1
  fi
}

build_ssh_cmd() {
  local key_path="$1"
  local hosts_path="$2"
  echo "ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=yes -o UserKnownHostsFile=$hosts_path -i $key_path"
}

build_scp_cmd() {
  local key_path="$1"
  local hosts_path="$2"
  echo "scp -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=yes -o UserKnownHostsFile=$hosts_path -i $key_path"
}

case "$MODE" in
  --local-master)
    echo "=== [Phase 4] Executing Master Setup Locally ==="
    bash "$SCRIPT_DIR/setup-master.sh"
    bash "$SCRIPT_DIR/deploy-puppet-code.sh"
    ;;

  --local-agent)
    echo "=== [Phase 4] Executing Agent Setup Locally ==="
    bash "$SCRIPT_DIR/setup-agent.sh"
    ;;

  --local-sign)
    echo "=== [Phase 4] Signing Agent Certificate Locally on Master ==="
    bash "$SCRIPT_DIR/sign-agent-cert.sh" "puppet-agent"
    ;;

  --local-test)
    echo "=== [Phase 4] Testing Agent Catalog Application Locally ==="
    bash "$SCRIPT_DIR/test-agent-catalog.sh"
    ;;

  --ssh)
    MASTER_IP="${2:?Master public IP required}"
    AGENT_IP="${3:?Agent public IP required}"
    KEY_PATH="${4:-$DEFAULT_KEY}"
    KNOWN_HOSTS_PATH="${5:-$DEFAULT_KNOWN_HOSTS}"

    verify_ssh_prerequisites "$MASTER_IP" "$KEY_PATH" "$KNOWN_HOSTS_PATH" "Puppet Master"
    verify_ssh_prerequisites "$AGENT_IP" "$KEY_PATH" "$KNOWN_HOSTS_PATH" "Puppet Agent"

    SSH_CMD=$(build_ssh_cmd "$KEY_PATH" "$KNOWN_HOSTS_PATH")
    SCP_CMD=$(build_scp_cmd "$KEY_PATH" "$KNOWN_HOSTS_PATH")

    # If PUPPET_FORGE_API_KEY is present in environment, configure auth file on Master over stdin
    if [ -n "${PUPPET_FORGE_API_KEY:-}" ]; then
      echo "[Auth] Pipelining Puppet Core credentials securely to Master via SSH stdin..."
      $SSH_CMD "ubuntu@$MASTER_IP" "sudo mkdir -p /etc/apt/auth.conf.d && sudo sh -c 'cat > /etc/apt/auth.conf.d/apt-puppetcore-puppet.conf && chmod 0600 /etc/apt/auth.conf.d/apt-puppetcore-puppet.conf'" <<EOF
machine apt-puppetcore.puppet.com
login forge-key
password $PUPPET_FORGE_API_KEY
EOF
      echo "[Auth] Master /etc/apt/auth.conf.d/apt-puppetcore-puppet.conf configured securely."
    fi

    echo "=== [1/4] Transferring and Configuring Puppet Master ($MASTER_IP) ==="
    $SSH_CMD "ubuntu@$MASTER_IP" "mkdir -p /tmp/puppet"
    $SCP_CMD -r "$PUPPET_ROOT/"* "ubuntu@$MASTER_IP:/tmp/puppet/"
    $SSH_CMD "ubuntu@$MASTER_IP" "sudo chmod +x /tmp/puppet/scripts/*.sh && sudo bash /tmp/puppet/scripts/setup-master.sh"

    echo "=== [2/4] Transferring and Configuring Puppet Agent ($AGENT_IP) ==="
    $SSH_CMD "ubuntu@$AGENT_IP" "mkdir -p /tmp/puppet"
    $SCP_CMD -r "$PUPPET_ROOT/"* "ubuntu@$AGENT_IP:/tmp/puppet/"
    $SSH_CMD "ubuntu@$AGENT_IP" "sudo chmod +x /tmp/puppet/scripts/*.sh && sudo bash /tmp/puppet/scripts/setup-agent.sh"

    echo "=== [3/4] Signing Certificate on Master ($MASTER_IP) ==="
    $SSH_CMD "ubuntu@$MASTER_IP" "sudo bash /tmp/puppet/scripts/sign-agent-cert.sh puppet-agent"

    echo "=== [4/4] Applying & Verifying Catalog on Agent ($AGENT_IP) ==="
    $SSH_CMD "ubuntu@$AGENT_IP" "sudo bash /tmp/puppet/scripts/test-agent-catalog.sh"

    echo "=== [Phase 4 Complete] Puppet Master-Agent Configuration Verified via SSH! ==="
    ;;

  --ssh-master-setup)
    MASTER_IP="${2:?Master public IP required}"
    KEY_PATH="${3:-$DEFAULT_KEY}"
    KNOWN_HOSTS_PATH="${4:-$DEFAULT_KNOWN_HOSTS}"

    verify_ssh_prerequisites "$MASTER_IP" "$KEY_PATH" "$KNOWN_HOSTS_PATH" "Puppet Master"
    SSH_CMD=$(build_ssh_cmd "$KEY_PATH" "$KNOWN_HOSTS_PATH")
    SCP_CMD=$(build_scp_cmd "$KEY_PATH" "$KNOWN_HOSTS_PATH")

    if [ -n "${PUPPET_FORGE_API_KEY:-}" ]; then
      echo "[Auth] Pipelining Puppet Core credentials securely to Master via SSH stdin..."
      $SSH_CMD "ubuntu@$MASTER_IP" "sudo mkdir -p /etc/apt/auth.conf.d && sudo sh -c 'cat > /etc/apt/auth.conf.d/apt-puppetcore-puppet.conf && chmod 0600 /etc/apt/auth.conf.d/apt-puppetcore-puppet.conf'" <<EOF
machine apt-puppetcore.puppet.com
login forge-key
password $PUPPET_FORGE_API_KEY
EOF
    fi

    echo "=== Transferring and Configuring Puppet Master ($MASTER_IP) ==="
    $SSH_CMD "ubuntu@$MASTER_IP" "mkdir -p /tmp/puppet"
    $SCP_CMD -r "$PUPPET_ROOT/"* "ubuntu@$MASTER_IP:/tmp/puppet/"
    $SSH_CMD "ubuntu@$MASTER_IP" "sudo chmod +x /tmp/puppet/scripts/*.sh && sudo bash /tmp/puppet/scripts/setup-master.sh"
    echo "=== Master Setup Completed Successfully ==="
    ;;

  --ssh-agent-setup)
    AGENT_IP="${2:?Agent public IP required}"
    KEY_PATH="${3:-$DEFAULT_KEY}"
    KNOWN_HOSTS_PATH="${4:-$DEFAULT_KNOWN_HOSTS}"

    verify_ssh_prerequisites "$AGENT_IP" "$KEY_PATH" "$KNOWN_HOSTS_PATH" "Puppet Agent"
    SSH_CMD=$(build_ssh_cmd "$KEY_PATH" "$KNOWN_HOSTS_PATH")
    SCP_CMD=$(build_scp_cmd "$KEY_PATH" "$KNOWN_HOSTS_PATH")

    echo "=== Transferring and Configuring Puppet Agent ($AGENT_IP) ==="
    $SSH_CMD "ubuntu@$AGENT_IP" "mkdir -p /tmp/puppet"
    $SCP_CMD -r "$PUPPET_ROOT/"* "ubuntu@$AGENT_IP:/tmp/puppet/"
    $SSH_CMD "ubuntu@$AGENT_IP" "sudo chmod +x /tmp/puppet/scripts/*.sh && sudo bash /tmp/puppet/scripts/setup-agent.sh"
    echo "=== Agent Setup Completed Successfully ==="
    ;;

  --ssh-sign)
    MASTER_IP="${2:?Master public IP required}"
    KEY_PATH="${3:-$DEFAULT_KEY}"
    KNOWN_HOSTS_PATH="${4:-$DEFAULT_KNOWN_HOSTS}"

    verify_ssh_prerequisites "$MASTER_IP" "$KEY_PATH" "$KNOWN_HOSTS_PATH" "Puppet Master"
    SSH_CMD=$(build_ssh_cmd "$KEY_PATH" "$KNOWN_HOSTS_PATH")

    echo "=== Signing Certificate on Master ($MASTER_IP) ==="
    $SSH_CMD "ubuntu@$MASTER_IP" "sudo bash /tmp/puppet/scripts/sign-agent-cert.sh puppet-agent"
    echo "=== Certificate Signing Completed Successfully ==="
    ;;

  --ssh-verify)
    AGENT_IP="${2:?Agent public IP required}"
    KEY_PATH="${3:-$DEFAULT_KEY}"
    KNOWN_HOSTS_PATH="${4:-$DEFAULT_KNOWN_HOSTS}"

    verify_ssh_prerequisites "$AGENT_IP" "$KEY_PATH" "$KNOWN_HOSTS_PATH" "Puppet Agent"
    SSH_CMD=$(build_ssh_cmd "$KEY_PATH" "$KNOWN_HOSTS_PATH")

    echo "=== Applying & Verifying Catalog on Agent ($AGENT_IP) ==="
    $SSH_CMD "ubuntu@$AGENT_IP" "sudo bash /tmp/puppet/scripts/test-agent-catalog.sh"
    echo "=== Catalog Verification Completed Successfully ==="
    ;;

  --ssh-deploy-app)
    MASTER_IP="${2:?Master public IP required}"
    AGENT_IP="${3:?Agent public IP required}"
    IMAGE_TAG="${4:?Image tag or reference required}"
    KEY_PATH="${5:-$DEFAULT_KEY}"
    KNOWN_HOSTS_PATH="${6:-$DEFAULT_KNOWN_HOSTS}"

    verify_ssh_prerequisites "$MASTER_IP" "$KEY_PATH" "$KNOWN_HOSTS_PATH" "Puppet Master"
    verify_ssh_prerequisites "$AGENT_IP" "$KEY_PATH" "$KNOWN_HOSTS_PATH" "Puppet Agent"

    SSH_CMD=$(build_ssh_cmd "$KEY_PATH" "$KNOWN_HOSTS_PATH")

    echo "=== [Deploy 1/3] Updating Durable Image in Master Hiera ($IMAGE_TAG) ==="
    $SSH_CMD "ubuntu@$MASTER_IP" "sudo bash /etc/puppetlabs/code/environments/production/scripts/update-app-version.sh '$IMAGE_TAG' || sudo bash /tmp/puppet/scripts/update-app-version.sh '$IMAGE_TAG'"

    echo "=== [Deploy 2/3] Triggering Catalog Application on Agent ($AGENT_IP) ==="
    $SSH_CMD "ubuntu@$AGENT_IP" "sudo /opt/puppetlabs/bin/puppet agent -t --detailed-exitcodes" || {
      CODE=$?
      if [ "$CODE" -eq 2 ]; then
        echo "Catalog applied successfully with changes (exit code 2)."
      elif [ "$CODE" -eq 0 ]; then
        echo "Catalog in sync with zero changes (exit code 0)."
      else
        echo "ERROR: Puppet agent run failed with exit code $CODE." >&2
        exit 1
      fi
    }

    echo "=== [Deploy 3/3] Verifying Application Health on Agent ==="
    $SSH_CMD "ubuntu@$AGENT_IP" "for i in \$(seq 1 15); do if curl -sf http://127.0.0.1:5001/health; then echo ''; exit 0; fi; sleep 2; done; echo 'Health check timed out'; exit 1"

    echo "=== [Deployment Complete] Application $IMAGE_TAG successfully deployed and healthy! ==="
    ;;

  *)
    print_usage
    ;;
esac
