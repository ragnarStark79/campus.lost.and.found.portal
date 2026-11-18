# Campus Lost and Found Portal

> **Course:** INT333 — DevOps Advance Configuration Management
> **Status:** Revised Architecture Blueprint (7-Phase Multi-Tier Deployment)

---

## Project Description

The **Campus Lost and Found Portal** is a web application that helps students
and staff report, search for, and reclaim lost items on campus.

The project doubles as a full-stack DevOps showcase, demonstrating automated
deployment, infrastructure-as-code, configuration management, containerisation,
and monitoring — all integrated through a CI/CD pipeline.

---

## Project Objectives

| # | Objective |
|---|-----------|
| 1 | Build a functional Flask web application for reporting and browsing lost items |
| 2 | Containerise the application with Docker |
| 3 | Provision cloud infrastructure on AWS EC2 using Terraform |
| 4 | Manage server configuration with Puppet |
| 5 | Automate testing and deployment with GitHub Actions and GHCR |
| 6 | Monitor application and server health with Nagios Core |

---

## Technology Stack

| Layer | Technology |
|-------|-----------|
| Backend | Python 3.13 · Flask |
| Frontend | HTML · CSS · JavaScript |
| Database | SQLite (EBS-backed persistent storage) |
| Version Control | Git · GitHub |
| CI/CD | GitHub Actions |
| Containerisation | Docker · Docker Compose |
| Container Registry | GitHub Container Registry (GHCR) |
| Cloud Platform | AWS EC2 (Custom VPC `10.30.0.0/16`, Dual Subnets) |
| Infrastructure as Code | Terraform (Multi-tier: Master + Agent, IAM, SSM) |
| Configuration Management | Puppet 8 Master-Agent (Port 8140, Dynamic Catalogs) |
| Secret Management | AWS SSM Parameter Store (`SecureString`) & IAM Instance Profiles |
| Monitoring | Nagios Core 4 & NRPE (Host, HTTP 5001, Metrics, Container) |

---

## Project Structure

```text
DevOps/
├── app/                   # Flask application package
│   ├── __init__.py        # Application factory & error handlers
│   ├── routes.py          # URL routes and view functions
│   ├── models.py          # Item dataclass & SQLite queries
│   ├── database.py        # SQLite connection & schema initialisation
│   ├── forms.py           # Server-side input validation
│   ├── config.py          # Environment-based configuration
│   ├── templates/         # Jinja2 HTML templates
│   └── static/            # CSS, JS, images
├── tests/                 # Pytest test suite (51 database & route tests)
├── docker/                # Additional Docker helper files
├── .github/
│   └── workflows/
│       └── ci-cd.yml      # GitHub Actions CI/CD & GHCR workflow
├── docs/
│   └── implementation/    # Authoritative Architecture & Planning Blueprints
│       ├── REVISED_PROJECT_ARCHITECTURE.md  # Detailed 2-node architecture & network spec
│       ├── REVISED_PHASE_ROADMAP.md         # 7-Phase implementation lifecycle & gates
│       └── ARCHITECTURE_DECISIONS.md       # Architecture Decision Records (ADRs 001-009)
├── terraform/             # Terraform IaC for AWS (Custom VPC, Master & Agent EC2, IAM)
│   ├── modules/
│   └── environments/
├── puppet/                # Puppet 8 Master-Agent manifests & modules
│   ├── manifests/
│   │   └── site.pp
│   └── modules/
│       └── lostandfound/
│           ├── files/sync-data-owner.sh
│           ├── manifests/init.pp
│           └── templates/
├── nagios/                # Nagios Core monitoring configurations
│   ├── configs/
│   └── scripts/
├── scripts/               # Utility shell/Python scripts
├── pytest.ini             # Pytest discovery configuration
├── run.py                 # Application entry point
├── requirements.txt       # Production dependencies
├── requirements-dev.txt   # Development dependencies
├── .env.example           # Environment variable template
├── .gitignore
├── .dockerignore
├── Dockerfile
├── docker-compose.yml
├── README.md
└── LICENSE
```

---

## Local Environment Setup

### Prerequisites

- Python 3.11 or higher (3.13 recommended)
- Git
- Docker Desktop (for containerised execution)
- (Optional for later phases) Terraform, AWS CLI

### Step-by-step

```bash
# 1. Clone the repository (replace placeholders with your GitHub remote)
git clone https://github.com/<github-owner>/<repo-name>.git
cd <repo-name>

# 2. Create and activate a virtual environment
python3 -m venv .venv
source .venv/bin/activate        # macOS / Linux
# .venv\Scripts\activate         # Windows

# 3. Install runtime dependencies
pip install -r requirements.txt

# 4. Install development dependencies (testing, linting, type-checking)
pip install -r requirements-dev.txt

# 5. Copy and edit the environment file
cp .env.example .env
# Edit .env — set a strong random SECRET_KEY
```

---

## Running the Flask Application Locally

```bash
# Option A — directly with Python (recommended; defaults to 127.0.0.1:5001)
python run.py

# Option B — using the Flask CLI
flask --app run run --debug --port 5001
```

Open your browser at:

- **Homepage:** <http://localhost:5001/>
- **Browse / Search Items:** <http://localhost:5001/items>
- **Report Lost Item:** <http://localhost:5001/report/lost>
- **Report Found Item:** <http://localhost:5001/report/found>
- **Health check:** <http://localhost:5001/health>

> **Why port 5001?** macOS reserves port 5000 for the AirPlay Receiver service.
> To use a different port: `FLASK_PORT=8080 python run.py`

### Running Local Checks

```bash
flake8 app/ tests/ --max-line-length=100
mypy app/ --ignore-missing-imports
pytest tests/ -v
```

---

## Running with Docker Compose

The container runs Flask internally on `0.0.0.0:5000` (matching `EXPOSE 5000` and
the `HEALTHCHECK` in `Dockerfile`), mapped to host port `5001` via
`docker-compose.yml`, with `./data` mounted to `/app/data` for SQLite persistence.

```bash
# Validate Compose configuration
docker compose config

# Build and start in detached mode
docker compose up -d --build

# Check container status and health
docker compose ps

# Stop and remove container (data in ./data persists)
docker compose down
```

Access the containerised application at:

- **Homepage:** <http://localhost:5001/>
- **Health check:** <http://localhost:5001/health>

---

## CI/CD & GitHub Container Registry (GHCR)

> **Repository & GHCR image:** Linked to `git@github.com:ragnarStark79/campus.lost.and.found.portal.git`.
> Because GitHub Container Registry requires lowercase image names, `.github/workflows/ci-cd.yml`
> normalizes the repository path to `ghcr.io/ragnarstark79/campus.lost.and.found.portal`.
> **Publication Verified:** GitHub Actions workflow run `43176357332` executed successfully on `main`,
> passing both CI checks (flake8, mypy, pytest) and the Docker smoke test, and publishing images with tags
> `:latest` and `:sha-0bf459f` (digest `sha256:821071da8b48d23e9cde3063e628caf30288521cb6091befde6a548baa2bc160`).
> *Note on package access:* By default, GHCR initializes packages as Private unless changed to Public in GitHub package settings. If kept private, pulling requires `docker login ghcr.io`.

### CI/CD Architecture

The pipeline in [`.github/workflows/ci-cd.yml`](.github/workflows/ci-cd.yml)
separates validation from container publishing and separates image publishing
from cloud deployment (which happens on-demand on EC2 in Phase 3):

```text
  push / PR to main
         │
         ▼
  ┌───────────────────────────────────────────────────┐
  │ Job 1: ci  (permissions: contents: read)          │
  │  1. Checkout code (actions/checkout@v4)           │
  │  2. Setup Python 3.13 + pip cache                 │
  │  3. Install requirements.txt & requirements-dev   │
  │  4. Flake8 lint  →  Mypy types  →  Pytest (51)    │
  └──────────────────────┬────────────────────────────┘
                         │ (only if ci succeeds)
                         ▼
  ┌───────────────────────────────────────────────────┐
  │ Job 2: docker  (contents: read, packages: write)  │
  │  5. Lowercase ghcr.io/<owner>/<repo> image name   │
  │  6. Setup Docker Buildx                           │
  │  7. Build image (Dockerfile runtime stage)        │
  │  8. Run container smoke test (/ and /health)      │
  │  9. On push to main ONLY:                         │
  │     • Login to ghcr.io using GITHUB_TOKEN         │
  │     • Push tags: latest + sha-<commit>            │
  └───────────────────────────────────────────────────┘
```

### GitHub Actions Workflow Explanation

- **Triggers (`on`):**
  - `push` to `main`: runs full validation, builds & smoke-tests the Docker
    image, and publishes it to GHCR.
  - `pull_request` targeting `main`: runs full validation plus Docker build and
    container smoke test, **without** authenticating to or pushing to GHCR.
- **Permissions (Least Privilege):**
  - Top-level and `ci` job: `contents: read` only.
  - `docker` job: adds `packages: write` solely so `GITHUB_TOKEN` can publish
    packages to GHCR on `main` pushes; no Personal Access Token (PAT) is stored
    or required.
- **Concurrency:** In-progress runs are automatically cancelled for updated pull
  requests (`cancel-in-progress: ${{ github.event_name == 'pull_request' }}`)
  while pushes to `main` are allowed to finish cleanly.

### Required GitHub Repository Settings

Before pushing to GitHub, verify these settings in your repository:

1. **Attach the Git remote locally** (if not already done):
   ```bash
   git remote add origin https://github.com/<github-owner>/<repo-name>.git
   git remote -v
   ```
2. **Enable GitHub Actions:**
   `Settings` → `Actions` → `General` → ensure Actions are enabled (`Allow all actions and reusable workflows`).
3. **Workflow `GITHUB_TOKEN` permissions:**
   `Settings` → `Actions` → `General` → `Workflow permissions` → either keep
   default (the workflow explicitly declares `packages: write` on the `docker`
   job) or confirm `Read and write permissions` is permitted by your account/org
   policy.
4. **GHCR Package Visibility & Repository Link:**
   After the first successful `main` push, visit your profile/org **Packages**
   tab → select the container package → `Package settings`:
   - Confirm it is linked to `<github-owner>/<repo-name>`.
   - Choose `Public` (allows unauthenticated `docker pull`) or keep `Private`
     (requires `docker login ghcr.io` when pulling from EC2 or locally).

### GHCR Image Naming Convention

GHCR requires strictly **lowercase** repository paths. The workflow computes
the image name dynamically from `${{ github.repository }}` using `tr '[:upper:]' '[:lower:]'`:

```text
ghcr.io/<github-owner-lowercase>/<repo-name-lowercase>:<tag>
```

| Tag | When Applied | Purpose |
|---|---|---|
| `latest` | Pushes to `main` only | Tracks the latest validated build on `main` |
| `sha-<short-sha>` | Generated via `docker/metadata-action` | Immutable commit traceability for rollbacks and audit |

### Pulling the Published Image

If the GHCR package is **public**:

```bash
docker pull ghcr.io/<github-owner-lowercase>/<repo-name-lowercase>:latest
```

If the GHCR package is **private**, authenticate with a GitHub Personal Access
Token (`read:packages` scope):

```bash
echo "$GHCR_TOKEN" | docker login ghcr.io -u <github-owner> --password-stdin
docker pull ghcr.io/<github-owner-lowercase>/<repo-name-lowercase>:latest
```

### Running the Published Image

Run the pulled image using the same `5001:5000` port mapping and a host volume
for persistent SQLite storage (replace the `SECRET_KEY` placeholder with a
strong random value):

```bash
mkdir -p data
docker run -d \
  --name lostandfound_web \
  --restart unless-stopped \
  -p 5001:5000 \
  -e FLASK_ENV=production \
  -e SECRET_KEY="$(openssl rand -hex 32)" \
  -v "$(pwd)/data:/app/data" \
  ghcr.io/<github-owner-lowercase>/<repo-name-lowercase>:latest
```

Verify it is running and healthy:

```bash
curl -i http://localhost:5001/health
docker ps --filter name=lostandfound_web
```

### Inspecting Workflow Results

- **GitHub Web UI:** Open `https://github.com/<github-owner>/<repo-name>/actions`
  to inspect job logs (`Lint, Type-Check & Test` and `Build Docker Image & Publish to GHCR`).
- **GitHub CLI (`gh`):**
  ```bash
  gh run list --limit 5
  gh run view <run-id> --log-failed
  ```
- **Local Pre-Push Validation:**
  ```bash
  flake8 app/ tests/ --max-line-length=100
  mypy app/ --ignore-missing-imports
  pytest tests/ -v
  act --validate --strict
  ```

### Troubleshooting Failed Workflows

| Failure Stage | Likely Cause | Fix |
|---|---|---|
| `Run Flake8 linter` | Style violation, long line (`>100`), unused import, missing EOF newline | Run `flake8 app/ tests/ --max-line-length=100` locally and fix reported lines |
| `Run Mypy type checker` | Type mismatch in `app/` | Run `mypy app/ --ignore-missing-imports` locally and resolve annotations |
| `Run Pytest suite` | Broken route, validation, or SQL query | Run `pytest tests/ -v` locally to reproduce and fix |
| `Build Docker image` | Missing runtime dependency in `requirements.txt` or syntax error in `Dockerfile` | Test locally with `docker compose build` |
| `Smoke-test Docker container` | Flask crashed at startup or `/health` did not return HTTP 200 | Check `docker logs` locally; verify `FLASK_HOST=0.0.0.0` and `FLASK_PORT=5000` |
| `Log in / Push to GHCR` (`403 denied`) | Workflow lacks `packages: write`, org policy blocks token write, or repo name contains uppercase letters | Verify `Settings → Actions → General → Workflow permissions`, and confirm image name is lowercase |

---

---

## Target Architecture & Implementation Blueprint

Following our comprehensive codebase audit and alignment with **INT333 Practical #4**, the project architecture transitions from a single-node prototype to an enterprise-grade **Two-Tier Master-Agent Architecture on AWS EC2**.

Authoritative implementation specifications and design records are located in:
- [Revised Project Architecture Specification](docs/implementation/REVISED_PROJECT_ARCHITECTURE.md)
- [Revised Seven-Phase Implementation Roadmap](docs/implementation/REVISED_PHASE_ROADMAP.md)
- [Architecture Decision Records (ADRs 001–009)](docs/implementation/ARCHITECTURE_DECISIONS.md)

### Key Architectural Pillars

1. **Two EC2 Instances on Ubuntu 24.04 LTS:**
   - `puppet-master` (`10.30.1.10`, `t3.small`): Central configuration compiler (Puppet Server 8) and monitoring server (Nagios Core 4 + Apache CGI dashboard).
   - `puppet-agent` (`10.30.2.10`, `t3.small`): Application host running Puppet 8 Agent, Docker Engine CE, the Campus Lost and Found portal (`lostandfound_web` on port 5001), and the NRPE daemon.
2. **Dedicated Greenfield AWS VPC (`10.30.0.0/16`):**
   - Subnet A (`10.30.1.0/24`) for Master; Subnet B (`10.30.2.0/24`) for Agent.
   - Cross-referenced Security Groups: Puppet port 8140 and NRPE port 5666 remain isolated between peers.
   - Public application port 5001 accessible to campus users; SSH (port 22) and Nagios Web (port 80) strictly locked to `admin_cidr`.
3. **Encrypted Secret Isolation (Zero-Secret Principle):**
   - Repository tokens and secrets stored as `SecureString` in **AWS SSM Parameter Store** (`/devops/puppet/apt_key`).
   - Retrieved securely at boot time via **IAM Instance Profiles**; zero credentials exist in Git, Terraform state, or user-data logs.
4. **Persistent EBS SQLite Storage:**
   - 10 GB GP3 EBS volume mounted at `/opt/lostandfound/data` on the Agent node.
   - Dynamic non-root `appuser` UID:GID alignment prevents SQLite readonly errors.
5. **Observability & Failure Simulation:**
   - Nagios Core 4 monitors ICMP PING, HTTP on port 5001 (`/health`), CPU load, persistent disk usage, and container health.
   - Supports live self-healing demonstrations during viva defense.

---

## Revised Seven-Phase Implementation Roadmap

| Phase | Title | Status | Scope Summary |
|:---:|:---|:---:|:---|
| **1** | Application Foundation and Containerization | ✅ **Complete** | Python 3.13 Flask, SQLite CRUD, 51/51 pytest passing, multi-stage Dockerfile, non-root user, docker-compose. |
| **2** | CI Pipeline and Container Registry | ✅ **Complete** | `.github/workflows/ci-cd.yml` executed successfully; CI and Docker/GHCR jobs passed; published tags `:latest` and `:sha-0bf459f`. |
| **3** | AWS Infrastructure with Terraform | ⏳ **Current (In Progress)** | Custom VPC (`10.30.0.0/16`), dual subnets, IAM role, SSM Parameter Store, 2 EC2 instances, EBS volume, SGs. |
| **4** | Puppet 8 Master-Agent Configuration | 📋 **Planned** | Puppet Server 8 on Master, Puppet Agent on Agent, SSM APT token retrieval, SSL CA signing, dynamic catalogs. |
| **5** | Automated Application Deployment via Puppet | 📋 **Planned** | Docker Engine CE, GHCR container pull, systemd unit `lostandfound.service` (5001:5000), persistent volume permissions. |
| **6** | Nagios Core and NRPE Monitoring | 📋 **Planned** | Nagios 4 on Master, Apache CGI web dashboard, host definition, 5 service checks (PING, HTTP, NRPE load, disk, container). |
| **7** | End-to-End Validation, Security & Viva Demo | 📋 **Planned** | Full automated pipeline test, container failure simulation & self-healing, security verification, `terraform destroy`. |

> **Development Policy:** Development and testing run locally first. Terraform and Puppet code are authoritatively planned and validated before any AWS cloud resources are provisioned. User approval is strictly required before executing `terraform apply`.

---

## License

[MIT](LICENSE)
