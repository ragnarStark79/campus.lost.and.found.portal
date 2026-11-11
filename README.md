# Campus Lost and Found Portal

> **Course:** INT333 — DevOps Advance Configuration Management
> **Phase:** 0 — Project Foundation and Environment Setup

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
| Database | SQLite (dev) |
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
│   ├── __init__.py        # Application factory
│   ├── routes.py          # URL routes and view functions
│   ├── models.py          # Database models (Phase 1)
│   ├── database.py        # DB helpers (Phase 1)
│   ├── config.py          # Environment-based configuration
│   ├── templates/         # Jinja2 HTML templates
│   └── static/            # CSS, JS, images
├── tests/                 # Pytest test suite (Phase 1)
├── docker/                # Additional Docker helper files
├── .github/workflows/     # GitHub Actions CI/CD pipelines (Phase 2)
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

- Python 3.11 or higher
- Git
- (Optional for later phases) Docker Desktop, Terraform, AWS CLI

### Step-by-step

```bash
# 1. Clone the repository
git clone https://github.com/<your-username>/campus-lostandfound.git
cd campus-lostandfound

# 2. Create and activate a virtual environment
python3 -m venv .venv
source .venv/bin/activate        # macOS / Linux
# .venv\Scripts\activate         # Windows

# 3. Install runtime dependencies
pip install -r requirements.txt

# 4. Install development dependencies (optional but recommended)
pip install -r requirements-dev.txt

# 5. Copy and edit the environment file
cp .env.example .env
# Edit .env — set SECRET_KEY at minimum
```

---

## Running the Flask Application

```bash
# Option A — using the Flask CLI
flask --app run run --debug

# Option B — directly with Python
python run.py
```

Open your browser at:

- **Homepage:** <http://localhost:5000/>
- **Health check:** <http://localhost:5000/health>

---

## Running with Docker (Phase 0 — not yet built)

```bash
# Build the image
docker build -t campus-lostandfound:dev .

# Start with Docker Compose
docker compose up
```

---

## Implementation Phases

| Phase | Title | Status |
|-------|-------|--------|
| **0** | Project Foundation and Environment Setup | ✅ Current |
| **1** | Core Application Features | ⏳ Pending |
| **2** | Docker · GitHub Actions · GHCR | ⏳ Pending |
| **3** | Terraform · AWS EC2 · Puppet | ⏳ Pending |
| **4** | Nagios Monitoring and Alerting | ⏳ Pending |
| **5** | Final Integration, Testing and Documentation | ⏳ Pending |

> Development begins locally. CI/CD and AWS deployment are introduced in Phases 2 and 3.

---

## License

[MIT](LICENSE)
