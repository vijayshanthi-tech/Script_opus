# Day 48 — PROJECT: Publish Portfolio v1

> **Week 8 — Portfolio & Review** | ⏱ 2 hours | Region: `europe-west2`

---

## Project Overview

Combine all 8 weeks of work into a polished, GitHub-ready portfolio. This is the final deliverable — the artefact that represents your GCP infrastructure skills to employers.

---

## Architecture: The Complete Portfolio

```
┌──────────────────────────────────────────────────────────────────────┐
│                   GCP INFRASTRUCTURE PORTFOLIO                       │
│                                                                      │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │  README.md (Portfolio Index)                                   │  │
│  │  "GCP Infrastructure Engineer — Project Portfolio"             │  │
│  │  • Overview of all 8 projects                                 │  │
│  │  • Skills demonstrated                                        │  │
│  │  • Architecture diagram (overview)                            │  │
│  └────────────────────────────────────────────────────────────────┘  │
│                                                                      │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────────┐   │
│  │ Week 1-2     │  │ Week 3       │  │ Week 4-5                │   │
│  │ NETWORKING   │  │ MONITORING   │  │ TERRAFORM               │   │
│  │              │  │              │  │                          │   │
│  │ • Secure VPC │  │ • Ops Agent  │  │ • Modules structure     │   │
│  │ • Subnets    │  │ • Alerts     │  │ • Multi-env (dev/prod)  │   │
│  │ • IAP SSH    │  │ • Dashboard  │  │ • Remote state          │   │
│  │ • Cloud NAT  │  │ • Custom     │  │ • Landing Zone          │   │
│  │ • Firewalls  │  │   metrics    │  │                          │   │
│  └──────────────┘  └──────────────┘  └──────────────────────────┘   │
│                                                                      │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────────┐   │
│  │ Week 6       │  │ Week 7       │  │ Week 8                  │   │
│  │ STORAGE &    │  │ AUTOMATION   │  │ PORTFOLIO               │   │
│  │ BACKUP       │  │ & OPS        │  │                          │   │
│  │              │  │              │  │ • Clean repo structure   │   │
│  │ • GCS + life │  │ • Startup    │  │ • READMEs + diagrams    │   │
│  │ • Snapshots  │  │   scripts    │  │ • Troubleshooting       │   │
│  │ • Images     │  │ • Monitoring │  │ • Mock interview prep   │   │
│  │ • Runbook    │  │ • Golden VM  │  │ • Portfolio index       │   │
│  └──────────────┘  └──────────────┘  └──────────────────────────┘   │
└──────────────────────────────────────────────────────────────────────┘
```

---

## Implementation

### Phase 1 — Portfolio Index README (20 min)

Create the main `README.md` that will be the first thing anyone sees on your GitHub repo.

```markdown
# GCP Infrastructure Portfolio

> Cloud Infrastructure Engineer | ACE Certified | 6 Years Linux Experience

A collection of hands-on GCP infrastructure projects demonstrating network design, security hardening, automation, monitoring, backup strategies, and Infrastructure as Code with Terraform.

## Skills Demonstrated

| Skill Area | Technologies | Projects |
|---|---|---|
| **Networking** | VPC, Subnets, Firewall Rules, Cloud NAT, IAP | Secure VPC, Landing Zone |
| **Compute** | Compute Engine, Instance Templates, Machine Images | Golden VM, Backup & Restore |
| **Storage** | Cloud Storage, Lifecycle, Versioning, Snapshots | Backup & Restore |
| **Security** | IAM, SSH Hardening, CIS Baselines, fail2ban, auditd | Secure VPC, Golden VM |
| **Monitoring** | Cloud Monitoring, Ops Agent, Custom Metrics, Alerting | Monitoring Pack |
| **Automation** | Startup Scripts, cron, logrotate, Bash | Golden VM Automation |
| **IaC** | Terraform (modules, remote state, multi-env) | Landing Zone, all projects |
| **Operations** | Runbooks, Troubleshooting, Backup/Restore | Backup Runbook, Ops Runbook |

## Projects

### 1. Secure VPC Landing Zone
**[View Project →](projects/01-secure-vpc/)**

Production-ready VPC with private subnets, IAP-only SSH, Cloud NAT, and deny-all-default firewall rules.

```
Internet → Cloud NAT (egress) → VPC → Private Subnet → VMs (no public IP)
SSH: Via IAP only (35.235.240.0/20)
```

**Key Skills:** VPC design, firewall rules, IAP, Cloud NAT, Terraform modules

---

### 2. Cloud Monitoring Pack
**[View Project →](projects/02-monitoring-pack/)**

Automated monitoring setup with Ops Agent, custom metrics, alert policies, and fleet dashboard.

```
VMs + Ops Agent → Cloud Monitoring → Alert Policies → Email/Slack
Custom Scripts → Custom Metrics API → Dashboard
```

**Key Skills:** Cloud Monitoring, Ops Agent, custom metrics, alerting, Bash

---

### 3. Terraform Landing Zone
**[View Project →](projects/03-terraform-landing-zone/)**

Multi-environment IaC with reusable modules, remote state, and environment separation.

```
modules/vpc + modules/compute + modules/storage
  ↓                ↓                ↓
environments/dev    environments/prod
(e2-micro, 10GB)   (e2-standard-2, 20GB, snapshots)
```

**Key Skills:** Terraform modules, remote state, .gitignore, multi-env

---

### 4. Backup & Restore Solution
**[View Project →](projects/04-backup-restore/)**

Complete backup strategy with snapshot scheduling, GCS lifecycle, custom images, and tested restore runbook.

```
VMs → Snapshot Schedule (daily/hourly) → Restore tested + documented
GCS → Lifecycle (STD→NEARLINE→COLDLINE→DELETE) + Versioning
Golden Image → Image Family → Instance Template
```

**Key Skills:** Snapshots, resource policies, GCS lifecycle, custom images, RPO/RTO

---

### 5. Golden VM Automation
**[View Project →](projects/05-golden-vm/)**

Automated VM baseline with idempotent startup scripts, OS hardening, monitoring, and log rotation.

```
GCS Scripts → Startup Script → Hardened VM
  ├── Packages (nginx, fail2ban, auditd)
  ├── SSH hardening (no root, no password)
  ├── Kernel hardening (sysctl)
  ├── Monitoring (cron, custom metrics)
  └── Housekeeping (logrotate, cleanup)
```

**Key Skills:** Startup scripts, idempotency, CIS hardening, cron, logrotate

---

## Environment

| Component | Value |
|---|---|
| **Region** | europe-west2 (London) |
| **IaC** | Terraform >= 1.5 |
| **Provider** | hashicorp/google ~> 5.0 |
| **OS** | Debian 12 |
| **Certification** | Google Cloud Associate Cloud Engineer |

## Repo Structure

```
├── projects/
│   ├── 01-secure-vpc/
│   │   ├── README.md
│   │   ├── modules/
│   │   └── environments/
│   ├── 02-monitoring-pack/
│   ├── 03-terraform-landing-zone/
│   ├── 04-backup-restore/
│   └── 05-golden-vm/
├── docs/
│   ├── troubleshooting/
│   └── runbooks/
└── README.md (this file)
```

## Getting Started

### Prerequisites
- GCP project with billing enabled
- `gcloud` CLI authenticated
- Terraform >= 1.5 installed

### Quick Start
```bash
# Clone the repo
git clone https://github.com/USERNAME/gcp-infra-portfolio.git
cd gcp-infra-portfolio

# Start with any project
cd projects/01-secure-vpc/environments/dev
cp terraform.tfvars.example terraform.tfvars
terraform init && terraform plan
```

## Contact

- **LinkedIn:** [Your LinkedIn]
- **Email:** [Your Email]
- **Certification:** [GCP ACE Badge Link]
```

### Phase 2 — Project Directory Layout (10 min)

Create the physical directory structure for the portfolio:

```bash
PORTFOLIO="/tmp/gcp-infra-portfolio"
mkdir -p ${PORTFOLIO}/projects/01-secure-vpc/{modules/vpc,environments/dev,environments/prod}
mkdir -p ${PORTFOLIO}/projects/02-monitoring-pack/{scripts,alerts}
mkdir -p ${PORTFOLIO}/projects/03-terraform-landing-zone/{modules/vpc,modules/compute,modules/storage,environments/dev,environments/prod}
mkdir -p ${PORTFOLIO}/projects/04-backup-restore/{modules,scripts,runbooks}
mkdir -p ${PORTFOLIO}/projects/05-golden-vm/{scripts,terraform,verification}
mkdir -p ${PORTFOLIO}/docs/{troubleshooting,runbooks,diagrams}

echo "=== Portfolio structure ==="
find ${PORTFOLIO} -type d | sort
```

### Phase 3 — Consistent README Template (10 min)

Create a template that each project README follows:

```bash
cat > ${PORTFOLIO}/docs/README-TEMPLATE.md << 'EOF'
# Project Title

> One-line description of what this project does.

## What

2-3 sentences describing the project.

## Why

What problem does it solve? What skills does it demonstrate?

## Architecture

```
[ASCII or Mermaid diagram here]
```

## Tech Stack

| Component | Technology |
|---|---|
| IaC | Terraform ~> 5.0 |
| Cloud | GCP (europe-west2) |
| Services | [list services] |

## Usage

### Prerequisites
- GCP project with billing
- gcloud CLI + Terraform

### Deploy
```bash
cd environments/dev
cp terraform.tfvars.example terraform.tfvars
terraform init && terraform apply
```

## Key Decisions

| Decision | Rationale |
|---|---|
| [choice] | [why] |

## Troubleshooting

| Issue | Fix |
|---|---|
| [issue] | [fix] |

## Cleanup

```bash
terraform destroy -auto-approve
```
EOF
```

### Phase 4 — Essential Docs (10 min)

```bash
# Troubleshooting index
cat > ${PORTFOLIO}/docs/troubleshooting/README.md << 'EOF'
# Troubleshooting Guides

Quick references for common GCP infrastructure issues.

## Quick Diagnosis

```bash
gcloud compute instances get-serial-port-output VM --zone=ZONE  # Boot/startup issues
gcloud compute firewall-rules list                                # Network issues
gcloud logging read "severity>=ERROR" --limit=10                  # Error logs
terraform plan                                                     # State drift
gcloud compute regions describe REGION                            # Quota issues
```

## Guides

| Topic | Common Issues |
|---|---|
| [Compute & SSH](compute-ssh.md) | VM won't start, SSH timeout, permission denied |
| [Networking](networking.md) | No internet, can't reach other VMs, firewall blocks |
| [Terraform](terraform.md) | Apply fails, state drift, destroy hangs |
| [Startup Scripts](startup-scripts.md) | Script not running, partial execution, debug |
| [Storage](storage.md) | Permission denied, lifecycle not working |
EOF

# Runbook index
cat > ${PORTFOLIO}/docs/runbooks/README.md << 'EOF'
# Operational Runbooks

Standard operating procedures for GCP infrastructure.

## Runbooks

| Runbook | Use When |
|---|---|
| [VM Provisioning](vm-provisioning.md) | Creating a new production VM |
| [Backup & Restore](backup-restore.md) | Taking backups or restoring from failure |
| [Incident Response](incident-response.md) | Responding to monitoring alerts |
| [Image Update](image-update.md) | Building a new golden image version |
EOF
```

### Phase 5 — Git Setup (5 min)

```bash
cd ${PORTFOLIO}

# Create .gitignore
cat > .gitignore << 'EOF'
# Terraform
*.tfstate
*.tfstate.*
.terraform/
*.tfvars
!*.example.tfvars
crash.log

# Credentials
*.pem
*.key
*.json
!package.json

# OS
.DS_Store
Thumbs.db

# Editor
*.swp
.vscode/
.idea/
EOF

# Initialize repo
git init
git add .
git commit -m "Initial portfolio: 5 GCP infrastructure projects

Projects:
- 01-secure-vpc: VPC with IAP SSH, Cloud NAT, firewall rules
- 02-monitoring-pack: Ops Agent, custom metrics, alert policies
- 03-terraform-landing-zone: Multi-env IaC with modules
- 04-backup-restore: Snapshots, lifecycle, custom images, runbook
- 05-golden-vm: Automated hardened VM baseline

Includes troubleshooting guides and operational runbooks.
Region: europe-west2 | Terraform >= 1.5 | Debian 12"

echo "=== Git status ==="
git log --oneline
echo ""
echo "=== Files in repo ==="
git ls-files | head -30
```

---

## Publishing Checklist

```
PORTFOLIO STRUCTURE
  [ ] Root README.md with overview, skills table, project summaries
  [ ] Each project in its own directory under projects/
  [ ] Consistent README for each project (What, Why, Architecture, Usage)
  [ ] docs/ with troubleshooting guides and runbooks
  [ ] .gitignore excludes state, credentials, provider binaries

EACH PROJECT README
  [ ] Title + one-line description
  [ ] Architecture diagram (ASCII or Mermaid)
  [ ] Tech stack table
  [ ] Deploy commands (copy-paste ready)
  [ ] Key decisions with rationale
  [ ] Troubleshooting section
  [ ] Cleanup commands

CODE QUALITY
  [ ] Terraform files use consistent formatting (terraform fmt)
  [ ] No hardcoded project IDs or credentials
  [ ] Variables have descriptions and types
  [ ] .tfvars.example files provided (not actual .tfvars)
  [ ] Scripts have shebangs and error handling

GIT HYGIENE
  [ ] .gitignore in place before first commit
  [ ] No state files in repo
  [ ] No credentials or keys in repo
  [ ] Meaningful commit messages
  [ ] Clean commit history (no "fix typo" x20)

FINAL CHECKS
  [ ] All links in README work
  [ ] No placeholder text remaining
  [ ] Contact information updated
  [ ] Certification badge/link included
  [ ] README renders correctly on GitHub (preview locally)
```

---

## Publishing to GitHub

```bash
# Create the repo on GitHub first (via github.com or gh CLI)
# gh repo create gcp-infra-portfolio --public --description "GCP Infrastructure Portfolio — ACE Certified"

# Push to GitHub
git remote add origin https://github.com/USERNAME/gcp-infra-portfolio.git
git branch -M main
git push -u origin main
```

### Post-Publish Steps

1. **Add topics** on GitHub: `gcp`, `terraform`, `infrastructure`, `devops`, `cloud`, `portfolio`
2. **Pin the repo** to your GitHub profile
3. **Add to LinkedIn:** Projects section → link to GitHub repo
4. **Share in your CV:** "Portfolio: github.com/username/gcp-infra-portfolio"
5. **Set up GitHub Actions** (optional): Run `terraform validate` on PRs

---

## Cleanup

```bash
rm -rf /tmp/gcp-infra-portfolio
```

---

## Reflection: Portfolio Complete

You've built 5 production-quality GCP infrastructure projects in 8 weeks:

| Week | Project | Skills |
|---|---|---|
| 1-2 | Secure VPC | Networking, security, IAP |
| 3 | Monitoring Pack | Observability, alerting |
| 4-5 | Terraform Landing Zone | IaC, modules, multi-env |
| 6 | Backup & Restore | Storage, snapshots, RPO/RTO |
| 7 | Golden VM Automation | Startup scripts, hardening, ops |
| 8 | Portfolio & Review | Documentation, interview prep |

**What makes this portfolio stand out:**
- **Real architecture decisions** (not just tutorial copies)
- **Security-first design** (IAP, hardening, least privilege)
- **Operational maturity** (monitoring, backups, runbooks)
- **Clean code** (modules, .gitignore, consistent READMEs)
- **Interview-ready** (explanations practiced, troubleshooting documented)

**Next steps:**
1. Continue refining — add CI/CD, load balancer project, database project
2. Blog about one project per week on Medium/Dev.to
3. Contribute to open-source Terraform modules
4. Start GCP Professional Cloud Architect study
