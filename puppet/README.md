# Puppet 8 — Configuration Management (`lostandfound` module)

Declaratively installs Docker Engine on Ubuntu 24.04 LTS, configures persistent storage ownership and secure environment variables, authenticates to GHCR if private, pulls the container image, and runs the Flask portal as an auto-restarting `systemd` service.

## Architecture & Resources Managed

- `package`: `ca-certificates`, `curl`, `gnupg`, `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`, `docker-compose-plugin`
- `file`:
  - `/etc/apt/keyrings` and `/etc/apt/sources.list.d/docker.list`
  - `/opt/lostandfound` and `/opt/lostandfound/data` (EBS mount point)
  - `/opt/lostandfound/.env` (`mode => 0600`, `show_diff => false`)
  - `/etc/systemd/system/lostandfound.service`
- `service`: `docker` (`running`, enabled) and `lostandfound` (`running`, enabled on boot)
- `exec` (strictly guarded with `creates` / `unless` / `refreshonly`): Docker GPG key fetch, `apt-get update`, optional `docker login ghcr.io`, `docker pull`, dynamic `appuser` UID/GID `chown`, `systemctl daemon-reload`, and `/health` verification

## Validation & Execution on Ubuntu 24.04 EC2

```bash
# 1. Validate manifest syntax
puppet parser validate /opt/lostandfound/puppet/manifests/site.pp
puppet parser validate /opt/lostandfound/puppet/modules/lostandfound/manifests/init.pp

# 2. Dry-run (no changes applied)
sudo FACTER_lostandfound_secret_key="$(openssl rand -hex 32)" \
  puppet apply --noop \
  --modulepath=/opt/lostandfound/puppet/modules \
  /opt/lostandfound/puppet/manifests/site.pp

# 3. Apply configuration (for a public GHCR image)
sudo FACTER_lostandfound_secret_key="$(openssl rand -hex 32)" \
  puppet apply \
  --modulepath=/opt/lostandfound/puppet/modules \
  /opt/lostandfound/puppet/manifests/site.pp

# 4. Apply configuration (for a private GHCR image — supply read:packages PAT via Facter)
sudo FACTER_lostandfound_secret_key="$(openssl rand -hex 32)" \
  FACTER_lostandfound_image_private=true \
  FACTER_ghcr_username="ragnarStark79" \
  FACTER_ghcr_token="<PAT_WITH_READ_PACKAGES>" \
  puppet apply \
  --modulepath=/opt/lostandfound/puppet/modules \
  /opt/lostandfound/puppet/manifests/site.pp
```

## Idempotency Check

Re-running `puppet apply` without changing variables or templates reports **0 corrective changes**, confirming idempotent state enforcement.
