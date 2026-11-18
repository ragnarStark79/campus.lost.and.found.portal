# Architecture Decision Records (ADR)
## Campus Lost and Found Portal — DevOps Advance Configuration Management (INT333)

**Project:** Campus Lost and Found Portal
**Course:** INT333 — DevOps Advanced Configuration Management
**Status:** Approved Architecture Blueprint
**Date:** November 2026

---

## Index of Decisions

- [ADR 001: Two-Instance Topology (Master + Agent) vs Single-Node Deployment](#adr-001-two-instance-topology-master--agent-vs-single-node-deployment)
- [ADR 002: Dedicated Custom VPC with Dual-Subnet Routing vs Default AWS VPC](#adr-002-dedicated-custom-vpc-with-dual-subnet-routing-vs-default-aws-vpc)
- [ADR 003: Operating System Selection — Ubuntu 24.04 LTS (Noble Numbat) on Both Instances](#adr-003-operating-system-selection--ubuntu-2404-lts-noble-numbat-on-both-instances)
- [ADR 004: Secure Credential Management via AWS Systems Manager (SSM) Parameter Store and IAM Instance Profiles](#adr-004-secure-credential-management-via-aws-systems-manager-ssm-parameter-store-and-iam-instance-profiles)
- [ADR 005: Puppet 8 Client-Server Architecture (Master-Agent) vs Standalone Masterless Execution](#adr-005-puppet-8-client-server-architecture-master-agent-vs-standalone-masterless-execution)
- [ADR 006: Multi-Tier Infrastructure and Application Monitoring via Nagios Core 4 and NRPE](#adr-006-multi-tier-infrastructure-and-application-monitoring-via-nagios-core-4-and-nrpe)
- [ADR 007: Container Registry Strategy — Preservation of GHCR and Deferred Remote CI Verification](#adr-007-container-registry-strategy--preservation-of-ghcr-and-deferred-remote-ci-verification)
- [ADR 008: Non-Root Container Security and Dynamic EBS Host Volume Permission Synchronization](#adr-008-non-root-container-security-and-dynamic-ebs-host-volume-permission-synchronization)
- [ADR 009: Codebase Preservation and Legacy Phase 3 File Redesign Strategy](#adr-009-codebase-preservation-and-legacy-phase-3-file-redesign-strategy)

---

## ADR 001: Two-Instance Topology (Master + Agent) vs Single-Node Deployment

### Context
The initial implementation plan (Phase 3 prototype) provisioned a single `t3.micro` EC2 instance that executed Puppet in masterless standalone mode (`puppet apply`) to deploy the Dockerized web portal. While functional for a minimal smoke test, this approach did not demonstrate the core curriculum requirements of **INT333: DevOps Advanced Configuration Management**, specifically client-server configuration enforcement, centralized certificate management, and remote infrastructure monitoring.

### Decision
Adopt a **two-tier, two-instance EC2 architecture**:
1. **`puppet-master` (`10.30.1.10`)**:
   - Hostname: `puppet-master`
   - Sizing: `t3.small` (2 vCPU, 2 GiB RAM) — required to comfortably run Puppet Server JVM (tuned to 512 MiB heap), Nagios Core 4, and Apache 2.
   - Roles: Central Configuration Authority (Puppet Server 8 CA and compiler) and Central Monitoring Server (Nagios Core 4).
2. **`puppet-agent` (`10.30.2.10`)**:
   - Hostname: `puppet-agent`
   - Sizing: `t3.small` (or `t3.micro`) (2 vCPU, 1–2 GiB RAM).
   - Roles: Managed node running Puppet 8 Agent, Docker Engine CE, the Campus Lost and Found Portal container (`lostandfound_web`), and the Nagios Remote Plugin Executor (NRPE) daemon.

### Consequences
- **Positive:** Accurately reflects real-world enterprise infrastructure; directly fulfills INT333 Practical #4 learning outcomes; separates operational tooling (Puppet Master, Nagios) from application compute.
- **Negative:** Slightly higher hourly AWS EC2 cost (~$0.0416/hr combined in `ap-south-1` vs ~$0.0104/hr for a single `t3.micro`). Mitigated by stopping or destroying resources immediately after demonstration sessions (`terraform destroy`).

---

## ADR 002: Dedicated Custom VPC with Dual-Subnet Routing vs Default AWS VPC

### Context
Deploying directly into AWS's Default VPC creates unpredictable private IP addressing, lacks network isolation, introduces conflicting CIDR blocks across student accounts, and prevents deterministic static IP assignment required for Puppet and Nagios configurations.

### Decision
Provision a **greenfield, dedicated AWS VPC** via Terraform with explicit static addressing:
- **VPC CIDR:** `10.30.0.0/16` with DNS resolution and DNS hostnames enabled.
- **Internet Gateway (IGW):** Attached to the VPC to enable outbound internet access (for package installation and GHCR pulls) and inbound administrative access.
- **Master Subnet:** `10.30.1.0/24` located in Availability Zone `ap-south-1a`.
- **Agent Subnet:** `10.30.2.0/24` located in Availability Zone `ap-south-1b` (demonstrating multi-AZ layout).
- **Static Private IPs:**
  - `puppet-master`: `10.30.1.10`
  - `puppet-agent`: `10.30.2.10`
- **Security Groups with Cross-Referencing:**
  - Security group ingress rules reference peer Security Group IDs rather than CIDR blocks where possible, ensuring that port 8140 (Puppet) and port 5666 (NRPE) remain closed to the internet and open only to the authorized counterpart.

### Consequences
- **Positive:** Fully deterministic network layout; static IPs allow hardcoded local `/etc/hosts` resolution and deterministic Nagios/Puppet target definitions; high security posture through least-privilege security group referencing.
- **Negative:** Additional Terraform networking resources to define (VPC, IGW, 2 subnets, route tables, associations, and ingress rules).

---

## ADR 003: Operating System Selection — Ubuntu 24.04 LTS (Noble Numbat) on Both Instances

### Context
INT333 Practical #4 was originally written for Ubuntu 22.04 LTS (Jammy). However, Ubuntu 24.04 LTS (Noble Numbat) is the current long-term support release, offering enhanced Linux kernel security, modernized systemd implementations, and newer package dependencies. We must ensure Puppet 8 and Docker CE compatibility on Ubuntu 24.04.

### Decision
Standardize on **Ubuntu 24.04 LTS (Noble Numbat)** for both `puppet-master` and `puppet-agent`.
- Dynamic AMI lookup via Terraform data source `aws_ami` using Canonical's official owner ID (`099720109477`) and filter `ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*`.
- Utilize official Puppet 8 release package for Noble: `puppet8-release-noble.deb`.
- Utilize official Docker CE repository for Noble (`noble` release channel with modern signed-by keyrings in `/etc/apt/keyrings/docker.asc`).

### Consequences
- **Positive:** Modern OS foundation aligned with the current production ecosystem; long-term support lifecycle through 2029; identical base images across both nodes reduce user-data divergence.
- **Negative:** Required verifying that `puppetserver` 8 and `nagios4` packages install cleanly on Noble without unresolvable package manager conflicts.

---

## ADR 004: Secure Credential Management via AWS Systems Manager (SSM) Parameter Store and IAM Instance Profiles

### Context
Certain package distribution channels and private registries require credentials during host bootstrapping:
1. **Puppet Core APT Repository (`apt-puppetcore.puppet.com`):** Perforce / Puppet introduced subscription/authenticated package streams where Debian/Ubuntu APT requires an authentication drop-in file:
   `/etc/apt/auth.conf.d/apt-puppetcore-puppet.conf`
   ```text
   machine apt-puppetcore.puppet.com
   login forge-key
   password YOUR_API_KEY
   ```
   *Analysis of credential purpose:* The username `login forge-key` is literal (a service identifier for Perforce's package proxy), while `password` is an API key / token generated from a Puppet Forge or customer account. This is distinct from public community packages on `apt.puppet.com`.
2. **Application Secrets:** `FLASK_SECRET_KEY` and optional private GHCR credentials.

Hardcoding secrets in Terraform variables, git repositories, or plain-text user-data scripts is an unacceptable security violation.

### Decision
1. Store all sensitive installation and runtime credentials in **AWS Systems Manager Parameter Store** as encrypted `SecureString` parameters under the hierarchical namespace `/devops/puppet/`:
   - `/devops/puppet/apt_key` (Type: `SecureString`, KMS key: default AWS managed key `alias/aws/ssm`).
   - `/devops/puppet/flask_secret_key` (Type: `SecureString`).
2. Attach an **IAM Instance Profile** (`aws_iam_instance_profile`) to both EC2 instances backed by an IAM role granting least-privilege `ssm:GetParameter` and `ssm:GetParameters` permissions scoped strictly to `arn:aws:ssm:ap-south-1:<account-id>:parameter/devops/puppet/*`.
3. In cloud-init `user_data`, install the AWS CLI, query the parameter securely at boot time over IMDSv2-authenticated instance profile credentials, and stream the output directly to `/etc/apt/auth.conf.d/apt-puppetcore-puppet.conf` with file permissions restricted to `0600` (root-only).
4. **Verification Rule:** If the deployment utilizes open community packages (`apt.puppet.com`), the bootstrap script checks for the presence of the SSM parameter; if omitted, it falls back gracefully to public repositories without stalling execution.

### Consequences
- **Positive:** Zero secret leakage in Git, Terraform state files (`.tfstate`), EC2 console user-data logs, or GitHub Actions workflow runs; adheres to AWS Well-Architected Security Pillar.
- **Negative:** Requires creating the SSM parameter in the AWS account as an initial one-time manual prerequisite before executing `terraform apply`.

---

## ADR 005: Puppet 8 Client-Server Architecture (Master-Agent) vs Standalone Masterless Execution

### Context
In Phase 3 prototyping, Puppet was invoked locally via `puppet apply`. However, the course learning objective requires students to demonstrate automated configuration management, catalog compilation, drift correction, and certificate exchange across separate hosts.

### Decision
Implement the **Puppet 8 Master-Agent model**:
- **Puppet Server:** Installed on `puppet-master`. Listens on TCP port `8140`.
- **Hostname Resolution:** Static `/etc/hosts` entries on both instances mapping `10.30.1.10` to `puppet-master` and `10.30.2.10` to `puppet-agent`.
- **Run Interval:** Configured to `runinterval = 60` (seconds) on the agent to facilitate live viva demonstration and rapid configuration enforcement.
- **Certificate Signing Security:**
  - *Academic / Demonstration Approach:* Configure `/etc/puppetlabs/puppet/autosign.conf` on the master with an exact FQDN whitelist (`puppet-agent`), combined with AWS Security Groups restricting access to port 8140 exclusively to the agent's private security group.
  - *Production Hardening Discussion (Viva Point):* Address policy-based autosigning via custom executable scripts verifying challenge tokens passed in `/etc/puppetlabs/puppet/csr_attributes.yaml` (`pp_preshared_secret`).
- **Catalog Responsibilities:**
  - `puppet-master` compiles and serves the `lostandfound` class.
  - `puppet-agent` requests the catalog, converges local state (installs Docker, pulls image, writes `.env`, creates systemd unit, manages SQLite volume), and reports compliance.

### Consequences
- **Positive:** Centralized configuration control; automatic drift remediation every 60 seconds; demonstrates authentic DevOps configuration management.
- **Negative:** Puppet Server requires JVM heap tuning (`-Xms512m -Xmx512m` in `/etc/default/puppetserver`) to avoid exhausting instance memory on small EC2 instances.

---

## ADR 006: Multi-Tier Infrastructure and Application Monitoring via Nagios Core 4 and NRPE

### Context
System observability is mandatory. The portal must be monitored at both the network layer (host availability), the infrastructure layer (CPU, memory, disk), and the application layer (HTTP status codes, `/health` response).

### Decision
Deploy **Nagios Core 4** on the `puppet-master` host and **Nagios Remote Plugin Executor (NRPE)** on `puppet-agent`:
1. **Nagios Server (`puppet-master`):**
   - Package: `nagios4`, `nagios4-cgi`, `nagios-nrpe-plugin`, `monitoring-plugins`.
   - Web Dashboard: Served via Apache 2 on port 80 (`/nagios4/`), protected by HTTP Digest authentication (`/etc/nagios4/htdigest.users`) and restricted to the administrator's CIDR (`admin_cidr`).
2. **NRPE Daemon (`puppet-agent`):**
   - Package: `nagios-nrpe-server`, `monitoring-plugins-basic`.
   - Managed declaratively by Puppet.
   - Listens on TCP port `5666`, strictly accepting requests only from the master's private IP (`10.30.1.10`).
3. **Monitored Services:**
   - `PING`: Network reachability and packet loss via ICMP.
   - `HTTP Portal`: Queries `http://10.30.2.10:5001/` expecting HTTP 200.
   - `HTTP Health`: Queries `http://10.30.2.10:5001/health` verifying application database connectivity.
   - `NRPE Load`: Host CPU load metrics.
   - `NRPE Disk`: Persistent storage disk usage on `/opt/lostandfound/data`.
   - `NRPE Docker`: Validates that the `lostandfound_web` container is actively running.

### Consequences
- **Positive:** Complete observability stack; permits live demonstration of failure simulation (stopping container triggers CRITICAL alert; Puppet self-healing triggers recovery to OK).
- **Negative:** Requires coordinating Nagios host configuration files on the master with Puppet manifests applied on the agent.

---

## ADR 007: Container Registry Strategy — Preservation of GHCR and Deferred Remote CI Verification

### Context
GitHub Actions pipeline execution initially experienced a temporary GitHub account billing hold. A decision was made to maintain GitHub Container Registry (GHCR) as specified in the project synopsis rather than migrating to Docker Hub. The account benefits activated and workflow run `43176357332` succeeded, publishing both `:latest` and `:sha-0bf459f` to GHCR.

### Decision
**Preserve GitHub Container Registry (GHCR) and keep `.github/workflows/ci-cd.yml` untouched.**
- Do not migrate to Docker Hub. Introducing Docker Hub would add unnecessary third-party credential dependencies and violate the approved project synopsis.
- GHCR image publishing is verified via GitHub Actions run `43176357332`.
- Retain the local Docker Buildx smoke test and lowercase image naming normalization (`ghcr.io/ragnarstark79/campus.lost.and.found.portal:latest`).
- External package pull permissions depend on package visibility (Private requires `docker login ghcr.io`, Public does not).

### Consequences
- **Positive:** Preserves clean Git history; maintains tight integration with GitHub Packages; avoids third-party Docker Hub rate limits.
- **Negative:** Live EC2 deployment cannot pull the remote image from GHCR until the account benefits activate or a manual image seed is performed.

---

## ADR 008: Non-Root Container Security and Dynamic EBS Host Volume Permission Synchronization

### Context
The application container drops root privileges and runs as an unprivileged system user `appuser:appgroup` (`Dockerfile`). When mounting a persistent host directory (`/opt/lostandfound/data:/app/data`) on Linux EC2, the host directory is created by default with `root:root` ownership (`0755`). This causes SQLite to fail with:
`sqlite3.OperationalError: attempt to write a readonly database`

### Decision
1. Preserve the container's hardened non-root security posture (`USER appuser`).
2. Utilize the Puppet module script `sync-data-owner.sh` (`lostandfound-sync-owner`):
   - Inspects the container image dynamically to extract `appuser` UID and GID (`docker run --rm --entrypoint id <image> -u`).
   - Executes `chown -R <uid>:<gid> /opt/lostandfound/data` before starting the application container.
   - Verifies ownership idempotently (`--check` mode) so subsequent Puppet runs produce zero unwanted catalog churn.

### Consequences
- **Positive:** Zero vulnerability from running containers as root; persistent SQLite database remains writable across container re-deployments; fully automated via Puppet.
- **Negative:** Requires an auxiliary helper script managed by Puppet prior to starting `lostandfound.service`.

---

## ADR 009: Codebase Preservation and Legacy Phase 3 File Redesign Strategy

### Context
In Phase 3 prototyping, initial versions of Terraform and Puppet files were authored for a single-instance architecture. We must transition to the two-instance architecture without destroying working code or invalidating previous phase milestones.

### Decision
1. **Preserve Intact:**
   - `app/*`: Complete Flask application, database helpers, models, forms, templates.
   - `tests/*`: 51 unit and integration tests.
   - `Dockerfile` & `docker-compose.yml`: Multi-stage build and local Compose specifications.
   - `.github/workflows/ci-cd.yml`: CI lint/type-check/test/build pipeline.
   - `puppet/modules/lostandfound/files/sync-data-owner.sh`: Reused directly in the agent manifest.
   - `puppet/modules/lostandfound/templates/lostandfound.service.epp`: Reused for the agent systemd service.
2. **Redesign for Phase 3 Implementation:**
   - `terraform/providers.tf`: Update AWS provider and tags.
   - `terraform/variables.tf`: Declare variables for custom VPC, dual subnets, static private IPs, and instance types.
   - `terraform/network.tf` (New): Custom VPC, IGW, 2 subnets, route tables, associations.
   - `terraform/security_groups.tf`: Redesign into `master_sg` and `agent_sg` with cross-referenced ingress rules.
   - `terraform/iam.tf` (New): IAM role, SSM policy, and instance profile for EC2.
   - `terraform/compute.tf` (Redesigned from `main.tf`): Provision `aws_instance.master` and `aws_instance.agent`.
   - `terraform/userdata_master.sh` & `terraform/userdata_agent.sh`: Separate specialized bootstrap scripts.
   - `terraform/outputs.tf`: Output master/agent public IPs, Nagios URL, and application URL.
3. **Redesign for Phase 4 Implementation:**
   - `puppet/manifests/site.pp`: Master node classification separating `node 'puppet-master'` and `node 'puppet-agent'`.

### Consequences
- **Positive:** 100% of functional application code and tests remain untouched; infrastructure cleanly evolves from prototype to multi-tier enterprise architecture with full traceability.
