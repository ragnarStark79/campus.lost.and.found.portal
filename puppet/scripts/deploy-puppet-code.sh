#!/usr/bin/env bash
# ==============================================================================
# Puppet Production Environment Code Deployment Script — Master Node
# Campus Lost and Found Portal — INT333 DevOps Project (Phase 4 / Phase 5)
# ==============================================================================
# Scope: Deploys manifests, modules, Hiera hierarchy, and data to production
#        environment directory (/etc/puppetlabs/code/environments/production).
# Durable: Preserves existing deployed container image in data/common.yaml if
#          already initialized on the Master.
# ==============================================================================

set -euo pipefail

PUPPET_ENV_DIR="/etc/puppetlabs/code/environments/production"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PUPPET_SRC_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "Deploying Puppet code from $PUPPET_SRC_DIR to $PUPPET_ENV_DIR..."

mkdir -p "$PUPPET_ENV_DIR/manifests"
mkdir -p "$PUPPET_ENV_DIR/modules"
mkdir -p "$PUPPET_ENV_DIR/data"

# 1. Copy manifests
if [ -d "$PUPPET_SRC_DIR/manifests" ]; then
  cp -r "$PUPPET_SRC_DIR/manifests/"* "$PUPPET_ENV_DIR/manifests/"
  echo "Deployed manifests:"
  ls -la "$PUPPET_ENV_DIR/manifests/"
fi

# 2. Copy modules
if [ -d "$PUPPET_SRC_DIR/modules" ]; then
  cp -r "$PUPPET_SRC_DIR/modules/"* "$PUPPET_ENV_DIR/modules/"
  echo "Deployed modules:"
  ls -la "$PUPPET_ENV_DIR/modules/"
fi

# 3. Copy Hiera configuration (hiera.yaml)
if [ -f "$PUPPET_SRC_DIR/hiera.yaml" ]; then
  cp "$PUPPET_SRC_DIR/hiera.yaml" "$PUPPET_ENV_DIR/hiera.yaml"
  echo "Deployed hiera.yaml."
fi

# 4. Copy Hiera data directory while preserving existing deployed image
if [ -d "$PUPPET_SRC_DIR/data" ]; then
  if [ -f "$PUPPET_ENV_DIR/data/common.yaml" ]; then
    echo "Existing $PUPPET_ENV_DIR/data/common.yaml detected. Preserving deployed image setting..."
    EXISTING_IMAGE=$(grep -E '^lostandfound::image:' "$PUPPET_ENV_DIR/data/common.yaml" || true)
    cp -r "$PUPPET_SRC_DIR/data/"* "$PUPPET_ENV_DIR/data/"
    if [ -n "$EXISTING_IMAGE" ]; then
      sed -i "s|^lostandfound::image:.*|$EXISTING_IMAGE|" "$PUPPET_ENV_DIR/data/common.yaml"
    fi
  else
    cp -r "$PUPPET_SRC_DIR/data/"* "$PUPPET_ENV_DIR/data/"
  fi
  echo "Deployed Hiera data:"
  ls -la "$PUPPET_ENV_DIR/data/"
fi

# 5. Copy scripts
if [ -d "$PUPPET_SRC_DIR/scripts" ]; then
  mkdir -p "$PUPPET_ENV_DIR/scripts"
  cp -r "$PUPPET_SRC_DIR/scripts/"* "$PUPPET_ENV_DIR/scripts/"
  chmod 0755 "$PUPPET_ENV_DIR/scripts/"*.sh 2>/dev/null || true
  echo "Deployed scripts:"
  ls -la "$PUPPET_ENV_DIR/scripts/"
fi

# 6. Fix ownership and permissions (0755 for directories, 0644 for files, 0755 for scripts)
find "$PUPPET_ENV_DIR" -type d -exec chmod 0755 {} +
find "$PUPPET_ENV_DIR" -type f -exec chmod 0644 {} +
find "$PUPPET_ENV_DIR/scripts" -type f -name '*.sh' -exec chmod 0755 {} + 2>/dev/null || true
chown -R puppet:puppet "$PUPPET_ENV_DIR" 2>/dev/null || true

echo "Puppet code deployment completed successfully."
