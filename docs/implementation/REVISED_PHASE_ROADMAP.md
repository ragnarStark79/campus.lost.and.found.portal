# Revised Seven-Phase Implementation Roadmap
## Campus Lost and Found Portal — DevOps Advanced Configuration Management (INT333)

**Project:** Campus Lost and Found Portal
**Course:** INT333 — DevOps Advanced Configuration Management
**Status:** Approved Implementation Blueprint
**Date:** November 2026

---

## Executive Roadmap Summary

The original project synopsis outlined eight sequential demonstration phases (Phases 0 through 7) based on a single-node deployment model. Following our comprehensive audit and the technical requirements of **INT333 Practical #4**, the project lifecycle is now restructured into a **Seven-Phase Multi-Tier Deployment Roadmap**:

```text
┌────────────────────────────────────────────────────────────────────────┐
│ Phase 1: Application Foundation and Containerization                   │ ✅ COMPLETE
└──────────────────────────────────┬─────────────────────────────────────┘
                                   │
┌──────────────────────────────────▼─────────────────────────────────────┐
│ Phase 2: CI Pipeline and Container Registry                            │ ✅ COMPLETE
└──────────────────────────────────┬─────────────────────────────────────┘
                                   │
┌──────────────────────────────────▼─────────────────────────────────────┐
│ Phase 3: AWS Infrastructure with Terraform                             │ ⏳ CURRENT (IN PROGRESS)
└──────────────────────────────────┬─────────────────────────────────────┘
                                   │
┌──────────────────────────────────▼─────────────────────────────────────┐
│ Phase 4: Puppet 8 Master-Agent Configuration                           │ 📋 PLANNED
└──────────────────────────────────┬─────────────────────────────────────┘
                                   │
┌──────────────────────────────────▼─────────────────────────────────────┐
│ Phase 5: Automated Application Deployment through Puppet               │ 📋 PLANNED
└──────────────────────────────────┬─────────────────────────────────────┘
                                   │
┌──────────────────────────────────▼─────────────────────────────────────┐
│ Phase 6: Nagios Core and NRPE Monitoring                               │ 📋 PLANNED
└──────────────────────────────────┬─────────────────────────────────────┘
                                   │
┌──────────────────────────────────▼─────────────────────────────────────┐
│ Phase 7: End-to-End Validation, Security and Viva Demonstration        │ 📋 PLANNED
└────────────────────────────────────────────────────────────────────────┘
```

---

## Phase 1: Application Foundation and Containerization

### 1.1 Responsibilities
- Develop a Python 3.13 Flask application with SQLite database storage for reporting and browsing lost/found belongings.
- Implement robust domain models, form validations, search/filtering by category, campus location, date range, and keyword.
- Package the application into a secure, multi-stage `Dockerfile` running as a non-root system user (`appuser`).
- Provide local development support via `docker-compose.yml` mapped to host port `5001` (avoiding macOS port 5000 AirPlay conflicts).

### 1.2 Dependencies
- **Upstream:** Python 3.13+, virtual environment (`.venv`), Git repository initialization.
- **Downstream:** Feeds source code and test suite into Phase 2 (CI/CD) and container specifications into Phase 5 (Puppet deployment).

### 1.3 Deliverables
- `app/__init__.py`, `app/config.py`, `app/database.py`, `app/models.py`, `app/routes.py`, `app/forms.py`
- `app/templates/` (`base.html`, `index.html`, `items.html`, `item_detail.html`, `report_lost.html`, `report_found.html`, `404.html`, `500.html`)
- `app/static/css/main.css`, `app/static/js/main.js`
- `Dockerfile` (multi-stage: `builder` + `runtime` with `USER appuser`)
- `docker-compose.yml` (host `5001:5000`, volume `./data:/app/data`, healthcheck)
- `tests/conftest.py`, `tests/test_database.py`, `tests/test_routes.py` (51 tests)
- `requirements.txt`, `requirements-dev.txt`, `pytest.ini`

### 1.4 Validation Criteria & Commands
- **Linting:** `flake8 app/ tests/ --max-line-length=100` exits 0.
- **Type Checking:** `mypy app/ --ignore-missing-imports` exits 0 (`Success: no issues found`).
- **Test Suite:** `pytest tests/ -v` passes 51/51 tests in < 0.5s.
- **Local Application:** `python run.py` serves `http://127.0.0.1:5001/` and `http://127.0.0.1:5001/health` returning HTTP 200.
- **Local Container:** `docker compose up --build` returns `healthy` status and persists SQLite records in `./data/lostandfound.db`.

### 1.5 Completion Condition & Status
- **Status:** **COMPLETE** (Verified and locked).

---

## Phase 2: CI Pipeline and Container Registry

### 2.1 Responsibilities
- Automate continuous integration checks upon every code push and pull request targeting `main`.
- Validate coding standards (Flake8), type annotations (Mypy), and unit tests (Pytest) in clean GitHub-hosted runners.
- Build the multi-stage Docker image using Docker Buildx and execute a live container smoke test verifying `/health` and `/` endpoints.
- Authenticate to GitHub Container Registry using `GITHUB_TOKEN` (`packages: write`) and publish versioned tags (`sha-<commit>` and `latest`).

### 2.2 Dependencies
- **Upstream:** Phase 1 application code, test suite, and `Dockerfile`.
- **Downstream:** Phase 5 pulls the published GHCR container image onto the EC2 agent instance.

### 2.3 Deliverables
- `.github/workflows/ci-cd.yml` (multi-job workflow: `ci` and `docker`).
- Lowercase GHCR repository target: `ghcr.io/ragnarstark79/campus.lost.and.found.portal`.

### 2.4 Validation Criteria & Commands
- **Local Workflow Validation:** `act --validate --strict` confirms YAML syntax and action schemas.
- **Remote CI Run:** GitHub Actions workflow run `43176357332` passed on branch `main`:
  - `Lint, Type-Check & Test` passed in 19s (flake8, mypy, pytest 51/51).
  - `Build Docker Image & Publish to GHCR` passed in 35s (Buildx, smoke test `/health` and `/`).
- **Registry Publishing:** Tags `ghcr.io/ragnarstark79/campus.lost.and.found.portal:latest` and `sha-0bf459f` pushed successfully (digest `sha256:821071da8b48d23e9cde3063e628caf30288521cb6091befde6a548baa2bc160`).

### 2.5 Completion Condition & Status
- **Status:** **COMPLETE** (Verified via GitHub Actions run `43176357332`).
- **Operational Note:** External package pull permissions depend on repository package visibility (Private by default; requires `docker login ghcr.io` unless toggled to Public).

---

## Phase 3: AWS Infrastructure with Terraform

### 3.1 Responsibilities
- Define and provision a dedicated, isolated AWS Virtual Private Cloud (`10.30.0.0/16`) in `ap-south-1`.
- Provision dual subnets across distinct Availability Zones (`10.30.1.0/24` in `1a` and `10.30.2.0/24` in `1b`).
- Provision an Internet Gateway, public route table, and associations.
- Provision an AWS Systems Manager Parameter Store `SecureString` (`/devops/puppet/apt_key`) and an IAM Instance Profile granting least-privilege `ssm:GetParameter` access.
- Provision security groups with cross-referencing:
  - `master_sg`: Ports 22 (SSH from admin), 80 (Nagios Web from admin), 8140 (Puppet from `agent_sg`).
  - `agent_sg`: Ports 22 (SSH from admin), 5001 (App from allowed CIDRs), 5666 (NRPE from `master_sg`), ICMP (from `master_sg`).
- Provision two EC2 instances running Ubuntu 24.04 LTS:
  - `aws_instance.master` (`10.30.1.10`, `t3.small`).
  - `aws_instance.agent` (`10.30.2.10`, `t3.small` or `t3.micro`).
- Provision and attach an encrypted 10 GB GP3 EBS volume to the agent instance at `/dev/sdf`.
- Inject boot-time bootstrap scripts via `templatefile()`.

### 3.2 Dependencies
- **Upstream:** Valid AWS CLI credentials configured locally; SSH public key (`~/.ssh/id_ed25519.pub`); admin public IPv4 address (`admin_cidr`).
- **Downstream:** Hands off running EC2 instances with mounted storage and initial packages to Phase 4 (Puppet) and Phase 6 (Nagios).

### 3.3 Deliverables
- `terraform/providers.tf` (TF `>= 1.5.0`, AWS provider `~> 5.0`, default tags)
- `terraform/variables.tf` (declarations with validation rules)
- `terraform/network.tf` (VPC, IGW, subnets, route tables, associations)
- `terraform/security_groups.tf` (`master_sg` and `agent_sg` with cross-referenced rules)
- `terraform/iam.tf` (IAM role, policy for SSM, instance profile)
- `terraform/compute.tf` (master and agent instances, EBS volume and attachment)
- `terraform/userdata_master.sh` and `terraform/userdata_agent.sh` (cloud-init bootstrap scripts)
- `terraform/outputs.tf` (public IPs, private IPs, Nagios URL, application URL, SSH commands)
- `terraform/terraform.tfvars.example` and `terraform/.gitignore`
- `terraform/README.md`

### 3.4 Validation Criteria & Commands
- **Formatting:** `terraform -chdir=terraform fmt -check -diff` exits 0.
- **Validation:** `terraform -chdir=terraform validate` outputs `Success! The configuration is valid.`.
- **Syntax Check:** `bash -n terraform/userdata_master.sh && bash -n terraform/userdata_agent.sh` exits 0.
- **Dry-Run Plan:** `terraform -chdir=terraform plan` outputs a clean execution preview (expecting 19+ managed resources).
- **Manual Gate:** Explicit user approval required before running `terraform apply`.

### 3.5 Completion Condition & Status
- **Status:** **PLANNED (NEXT IMMEDIATE IMPLEMENTATION TASK)**

---

## Phase 4: Puppet 8 Master-Agent Configuration

### 4.1 Responsibilities
- Configure `puppet-master` as the centralized Puppet Server 8 and Certificate Authority (CA).
- Configure `puppet-agent` as a managed Puppet 8 node connecting to `puppet-master` over port 8140.
- Implement secure SSM credential retrieval during bootstrap to create `/etc/apt/auth.conf.d/apt-puppetcore-puppet.conf` with `0600` permissions.
- Tune Puppet Server JVM memory limits (`-Xms512m -Xmx512m` in `/etc/default/puppetserver`) to run reliably on `t3.small`.
- Establish static host resolution via `/etc/hosts` on both nodes.
- Configure secure certificate signing (autosign whitelist for `puppet-agent` combined with security group isolation).
- Verify end-to-end SSL certificate exchange and catalog compilation.

### 4.2 Dependencies
- **Upstream:** Phase 3 Terraform-provisioned VPC, security groups (port 8140 open between instances), and IAM instance profile.
- **Downstream:** Enables Phase 5 to deliver the application configuration via compiled catalogs.

### 4.3 Deliverables
- `puppet/manifests/site.pp` (node definitions for `puppet-master` and `puppet-agent`).
- `puppet/modules/` module hierarchy on the Master.
- Configuration templates for `/etc/puppetlabs/puppet/puppet.conf` on both nodes.
- Autosign configuration `/etc/puppetlabs/puppet/autosign.conf`.
- Systemd service enablement for `puppetserver` (Master) and `puppet` (Agent).

### 4.4 Validation Criteria & Commands
- **Master Daemon:** `sudo systemctl status puppetserver` is `active (running)`.
- **Port Reachability:** From Agent, `nc -zv 10.30.1.10 8140` succeeds.
- **Certificate Verification:** On Master, `sudo /opt/puppetlabs/bin/puppetserver ca list --all` displays `puppet-agent` as `Signed`.
- **Agent Catalog Run:** On Agent, `sudo /opt/puppetlabs/bin/puppet agent -t` exits with code 0 or 2 (successful convergence).
- **Idempotency:** Second run of `sudo /opt/puppetlabs/bin/puppet agent -t` produces zero catalog changes.

### 4.5 Completion Condition & Status
- **Status:** **PLANNED**

---

## Phase 5: Automated Application Deployment through Puppet

### 5.1 Responsibilities
- Author a modular Puppet class `lostandfound` deployed from the Puppet Master to `puppet-agent`.
- Manage Docker Engine installation (official Docker CE APT repository, GPG key, packages).
- Pull the published application image `ghcr.io/ragnarstark79/campus.lost.and.found.portal:latest`.
- Format and mount the persistent 10 GB EBS volume at `/opt/lostandfound/data`.
- Execute `sync-data-owner.sh` dynamically to align `/opt/lostandfound/data` ownership with the container's unprivileged `appuser` UID:GID, preventing SQLite write lock failures.
- Render `/opt/lostandfound/.env` (mode `0600`, diff suppressed) with production `SECRET_KEY`.
- Deploy `/etc/systemd/system/lostandfound.service` to manage the container lifecycle (`restart: always`, port mapping `5001:5000`, volume `/opt/lostandfound/data:/app/data`).
- Automate health check polling against `http://127.0.0.1:5001/health`.

### 5.2 Dependencies
- **Upstream:** Phase 2 (GHCR container image published), Phase 3 (EBS volume attached), and Phase 4 (Puppet Master-Agent operational).
- **Downstream:** Hands off the running application and host metrics to Phase 6 (Nagios).

### 5.3 Deliverables
- `puppet/modules/lostandfound/manifests/init.pp`
- `puppet/modules/lostandfound/files/sync-data-owner.sh`
- `puppet/modules/lostandfound/templates/docker.list.epp`
- `puppet/modules/lostandfound/templates/lostandfound.env.epp`
- `puppet/modules/lostandfound/templates/lostandfound.service.epp`

### 5.4 Validation Criteria & Commands
- **Docker Daemon:** `systemctl status docker` is `active (running)`.
- **Application Service:** `systemctl status lostandfound` is `active (running)`.
- **Container Health:** `docker inspect --format='{{.State.Health.Status}}' lostandfound_web` returns `healthy`.
- **HTTP Response:** `curl -sf http://127.0.0.1:5001/health` returns `{"status":"healthy","database":"connected"}`.
- **Storage Persistence:** Submitting a lost item report via the web UI persists data into `/opt/lostandfound/data/lostandfound.db`; restarting the container preserves the report.

### 5.5 Completion Condition & Status
- **Status:** **PLANNED**

---

## Phase 6: Nagios Core and NRPE Monitoring

### 6.1 Responsibilities
- Install and configure **Nagios Core 4**, CGI components, and Apache 2 on `puppet-master`.
- Configure Apache HTTP Digest authentication for administrative dashboard access (`/nagios4/`).
- Install and configure **Nagios Remote Plugin Executor (NRPE)** on `puppet-agent` via Puppet.
- Author host definitions for `puppet-agent` (`10.30.2.10`).
- Configure 5 active service checks:
  1. `PING`: Network path and ICMP latency.
  2. `HTTP Portal`: Port 5001 root availability.
  3. `HTTP Health`: Port 5001 `/health` endpoint.
  4. `NRPE Load`: CPU utilization.
  5. `NRPE Disk`: Persistent data storage usage on `/opt/lostandfound/data`.
  6. `NRPE Container`: Docker container process verification.
- Test failure alerting by simulating service degradation and verifying state recovery.

### 6.2 Dependencies
- **Upstream:** Phase 3 (port 5666 open between Master and Agent; port 80 open from admin), Phase 4 (Puppet managing NRPE on the agent), and Phase 5 (application listening on port 5001).
- **Downstream:** Provides observability evidence for Phase 7 demonstration.

### 6.3 Deliverables
- `nagios/configs/nagios.cfg`, `nagios/configs/contacts.cfg`, `nagios/configs/commands.cfg`
- `nagios/configs/agent.cfg` (host definition and service checks for `puppet-agent`)
- Puppet manifest managing `/etc/nagios/nrpe.cfg` and `nagios-nrpe-server` on `puppet-agent`
- Apache CGI configuration `/etc/apache2/conf-available/nagios4-cgi.conf`

### 6.4 Validation Criteria & Commands
- **Nagios Syntax Verification:** On Master, `nagios4 -v /etc/nagios4/nagios.cfg` returns `Total Warnings: 0, Total Errors: 0`.
- **NRPE Query Test:** From Master, `/usr/lib/nagios/plugins/check_nrpe -H 10.30.2.10 -c check_load` returns `OK - load average: ...`.
- **HTTP Check Test:** From Master, `/usr/lib/nagios/plugins/check_http -H 10.30.2.10 -p 5001 -u /health` returns `HTTP OK: HTTP/1.1 200 OK`.
- **Web Dashboard:** Browser access to `http://<master_public_ip>/nagios4/` displays all services in `OK` (GREEN) state.

### 6.5 Completion Condition & Status
- **Status:** **PLANNED**

---

## Phase 7: End-to-End Validation, Security and Viva Demonstration

### 7.1 Responsibilities
- Execute the complete end-to-end deployment workflow:
  `Git Commit -> GitHub Actions CI -> GHCR Publish -> Terraform Provisioning -> Puppet Convergence -> Application Serving -> Nagios Monitoring`.
- Conduct a live **Failure Simulation & Self-Healing Demonstration**:
  - Stop the container manually (`docker stop lostandfound_web`).
  - Demonstrate Nagios transitioning to `CRITICAL` state.
  - Allow Puppet agent scheduled run (`runinterval = 60`) or trigger `puppet agent -t` to revive the systemd service.
  - Demonstrate Nagios recovering to `OK` state.
- Conduct a **Security Audit**:
  - Verify IMDSv2 enforcement on EC2.
  - Confirm SSM Parameter Store encryption and IAM least-privilege scoping.
  - Verify that no credentials exist in Git or user-data logs.
- Document cost-control procedures and verify teardown via `terraform destroy`.
- Prepare the comprehensive Viva Defense portfolio for INT333.

### 7.2 Dependencies
- **Upstream:** All preceding phases (1 through 6) fully implemented.
- **Downstream:** Course project grading, external viva examination, and academic project submission.

### 7.3 Deliverables
- `docs/implementation/VIVA_DEFENSE_GUIDE.md`
- `docs/screenshots/` (evidence captures of GitHub Actions, Terraform apply, Puppet run, Nagios dashboard, and web UI)
- Root `README.md` finalization with comprehensive operational commands.

### 7.4 Validation Criteria & Commands
- Complete demonstration executes smoothly without manual intervention outside documented gates.
- `terraform destroy` cleanly removes all 19+ AWS resources, avoiding unwanted cloud expenditure.

### 7.5 Completion Condition & Status
- **Status:** **PLANNED**

---

## Roadmap Dependency Matrix

| Phase | Direct Prerequisite | Feeds Into | Blocking Conditions |
| :---: | :--- | :--- | :--- |
| **Phase 1** | Local Python 3.13 & Docker | Phase 2, Phase 5 | None (Complete) |
| **Phase 2** | Phase 1 Code | Phase 5 | None (Complete - Run 43176357332) |
| **Phase 3** | AWS Credentials, SSH Key | Phase 4, Phase 6 | User approval for `terraform apply` |
| **Phase 4** | Phase 3 (Network & IAM) | Phase 5 | Puppet Server JVM memory limits |
| **Phase 5** | Phase 2 (Image) & Phase 4 | Phase 6 | Non-root UID:GID volume permissions |
| **Phase 6** | Phase 4 (NRPE) & Phase 5 | Phase 7 | Port 5666 / 8140 security group rules |
| **Phase 7** | All Phases (1–6) | Course Completion | Demonstration schedule |
