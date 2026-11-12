# Campus Lost and Found Portal

> **Course:** INT333 — DevOps Advance Configuration Management
> **Phase:** 2 — CI/CD and Container Registry (GitHub Actions & GHCR)

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
| Database | SQLite |
| Version Control | Git · GitHub |
| CI/CD | GitHub Actions |
| Containerisation | Docker · Docker Compose |
| Container Registry | GitHub Container Registry (GHCR) |
| Cloud Platform | AWS EC2 |
| Infrastructure as Code | Terraform |
| Configuration Management | Puppet |
| Monitoring | Nagios Core |

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
├── tests/                 # Pytest test suite (database & route tests)
├── docker/                # Additional Docker helper files
├── .github/
│   └── workflows/
│       └── ci-cd.yml      # GitHub Actions CI/CD & GHCR workflow
├── terraform/             # Terraform IaC for AWS (Phase 3)
│   ├── modules/
│   └── environments/
├── puppet/                # Puppet configuration management (Phase 3)
│   ├── manifests/
│   └── modules/
├── nagios/                # Nagios monitoring configs (Phase 4)
│   ├── configs/
│   └── scripts/
├── scripts/               # Utility shell/Python scripts
├── docs/                  # Architecture diagrams, screenshots, notes
├── pytest.ini             # Pytest discovery configuration
├── run.py                 # Application entry point
├── requirements.txt       # Production dependencies
├── requirements-dev.txt   # Development dependencies
├── .env.example           # Environment variable template
├── .gitignore
├── .dockerignore
├── Dockerfile
├── docker-compose.yml
└── README.md
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

> **Repository remote note:** `git remote -v` is currently empty in this local
> workspace (no GitHub remote has been linked yet). Replace `<github-owner>` and
> `<repo-name>` below with your verified GitHub repository owner and name once
> you attach a remote (`git remote add origin git@github.com:<github-owner>/<repo-name>.git`).

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

## Implementation Phases

| Phase | Title | Status |
|-------|-------|--------|
| **0** | Project Foundation and Environment Setup | ✅ Complete |
| **1** | Core Application Features | ✅ Complete |
| **2** | Docker · GitHub Actions · GHCR | ✅ Current |
| **3** | Terraform · AWS EC2 · Puppet | ⏳ Pending |
| **4** | Nagios Monitoring and Alerting | ⏳ Pending |
| **5** | Final Integration, Testing and Documentation | ⏳ Pending |

> Development runs locally first; CI/CD publishes images to GHCR while AWS EC2 remains stopped until Phase 3 deployment and demonstrations.

---

## License

[MIT](LICENSE)
