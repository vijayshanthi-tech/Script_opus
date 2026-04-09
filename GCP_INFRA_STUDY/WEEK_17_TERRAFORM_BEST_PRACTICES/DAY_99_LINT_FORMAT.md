# Week 17, Day 99 (Wed) — Terraform Lint, Format & Standards

## Today's Objective

Enforce code quality in Terraform using `terraform fmt`, `terraform validate`, tflint for advanced linting, checkov for security scanning, and pre-commit hooks to automate checks before every commit.

**Source:** [terraform fmt](https://developer.hashicorp.com/terraform/cli/commands/fmt) | [tflint](https://github.com/terraform-linters/tflint) | [checkov](https://www.checkov.io/1.Welcome/Quick%20Start.html)

**Deliverable:** A Terraform project with pre-commit hooks running fmt, validate, tflint, and checkov

---

## Part 1: Concept (30 minutes)

### 1.1 Why Lint & Format?

```
Linux analogy:

shellcheck myscript.sh     ──►    tflint .
shfmt -w myscript.sh       ──►    terraform fmt -recursive .
rpmlint my.spec             ──►    checkov -d .
pre-commit hook in .git/    ──►    .pre-commit-config.yaml
```

Just like `shellcheck` catches bash anti-patterns before they hit production, Terraform linting catches misconfigurations before they become live infrastructure.

### 1.2 The Quality Toolchain

```
Developer writes .tf files
         │
         ▼
┌─────────────────────────────────────────────────────────┐
│                    PRE-COMMIT PIPELINE                    │
│                                                          │
│  ┌──────────┐   ┌──────────┐   ┌───────┐   ┌────────┐  │
│  │terraform │   │terraform │   │tflint │   │checkov │  │
│  │  fmt     │──►│ validate │──►│       │──►│        │  │
│  │          │   │          │   │       │   │        │  │
│  │Formatting│   │ Syntax + │   │Best   │   │Security│  │
│  │standards │   │ refs OK  │   │practice│  │scanning│  │
│  └──────────┘   └──────────┘   └───────┘   └────────┘  │
│                                                          │
│  If ANY step fails → commit blocked                      │
└─────────────────────────────────────────────────────────┘
         │
         ▼ (all pass)
    git commit succeeds
```

### 1.3 Tool Comparison

| Tool | What It Checks | Catches | Speed |
|---|---|---|---|
| `terraform fmt` | Whitespace, indentation, alignment | Style inconsistencies | Instant |
| `terraform validate` | HCL syntax, provider refs, type errors | Broken configs | Fast (needs init) |
| `tflint` | Provider-specific rules, naming, best practices | Bad machine types, missing tags | Fast |
| `checkov` | Security misconfigs (CIS benchmarks, OWASP) | Public buckets, no encryption, open FW | Medium |

### 1.4 Common checkov Findings on GCP

| Check ID | What It Catches | Severity |
|---|---|---|
| `CKV_GCP_2` | Compute instance without OS Login | MEDIUM |
| `CKV_GCP_6` | Cloud SQL without SSL enforcement | HIGH |
| `CKV_GCP_11` | GCS bucket without versioning | MEDIUM |
| `CKV_GCP_26` | VM with default service account | HIGH |
| `CKV_GCP_32` | GKE cluster without network policy | HIGH |
| `CKV_GCP_62` | Cloud SQL without backup | HIGH |

### 1.5 Pre-Commit Hooks

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/antonbabenko/pre-commit-terraform
    rev: v1.88.0
    hooks:
      - id: terraform_fmt
      - id: terraform_validate
      - id: terraform_tflint
        args:
          - --args=--config=__GIT_WORKING_DIR__/.tflint.hcl
      - id: terraform_checkov
        args:
          - --args=--quiet
          - --args=--compact
```

```
Linux analogy:

.git/hooks/pre-commit     ←──►   .pre-commit-config.yaml
  #!/bin/bash                      repos:
  shellcheck *.sh                    - terraform_fmt
  shfmt -d *.sh                      - terraform_validate
  exit $?                            - terraform_tflint
```

---

## Part 2: Hands-On Lab (60 minutes)

### Step 1: Create Lab Project (5 min)

```bash
mkdir -p tf-lint-lab && cd tf-lint-lab

cat > main.tf <<'EOF'
terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = "europe-west2"
}

variable "project_id" {
  type = string
}

resource "google_compute_network" "vpc" {
name                    = "lint-lab-vpc"
auto_create_subnetworks = false
}

resource "google_compute_firewall" "allow_all" {
  name    = "lint-lab-allow-all"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  source_ranges = ["0.0.0.0/0"]
}

resource "google_storage_bucket" "data" {
  name     = "${var.project_id}-lint-lab-data"
  location = "europe-west2"
}
EOF
```

### Step 2: terraform fmt (10 min)

```bash
# Check formatting (notice the VPC resource is badly indented)
terraform fmt -check -diff .

# Auto-fix formatting
terraform fmt -recursive .

# Verify the fix
terraform fmt -check .
echo "Exit code: $?"   # 0 = all formatted
```

### Step 3: terraform validate (5 min)

```bash
# Must init first (downloads provider schemas)
terraform init -backend=false

# Validate
terraform validate
```

### Step 4: Install and Run tflint (15 min)

```bash
# Install tflint (Linux/macOS)
curl -s https://raw.githubusercontent.com/terraform-linters/tflint/master/install_linux.sh | bash

# Create tflint config
cat > .tflint.hcl <<'EOF'
plugin "google" {
  enabled = true
  version = "0.27.1"
  source  = "github.com/terraform-linters/tflint-ruleset-google"
}

rule "terraform_naming_convention" {
  enabled = true
  format  = "snake_case"
}

rule "terraform_documented_variables" {
  enabled = true
}

rule "terraform_documented_outputs" {
  enabled = true
}
EOF

# Init tflint (downloads plugin)
tflint --init

# Run tflint
tflint .
```

### Step 5: Install and Run checkov (15 min)

```bash
# Install checkov
pip install checkov

# Run checkov against our Terraform
checkov -d . --compact --quiet

# You should see findings like:
#   FAILED: CKV_GCP_11 - Bucket without versioning
#   FAILED: CKV_GCP_2  - Open firewall rule (0.0.0.0/0 all ports)

# Fix the findings
cat > main_fixed.tf <<'EOF'
terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = "europe-west2"
}

variable "project_id" {
  type        = string
  description = "GCP project ID for the lint lab"
}

resource "google_compute_network" "vpc" {
  name                    = "lint-lab-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_firewall" "allow_ssh" {
  name    = "lint-lab-allow-ssh"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  # Restrict to known CIDR instead of 0.0.0.0/0
  source_ranges = ["35.235.240.0/20"]  # IAP range
}

resource "google_storage_bucket" "data" {
  name     = "${var.project_id}-lint-lab-data"
  location = "europe-west2"

  versioning {
    enabled = true
  }

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
}
EOF

# Re-run checkov on fixed file
checkov -f main_fixed.tf --compact --quiet
```

### Step 6: Set Up Pre-Commit Hooks (10 min)

```bash
# Install pre-commit
pip install pre-commit

# Initialize git repo
git init
git add .

# Create pre-commit config
cat > .pre-commit-config.yaml <<'EOF'
repos:
  - repo: https://github.com/antonbabenko/pre-commit-terraform
    rev: v1.88.0
    hooks:
      - id: terraform_fmt
      - id: terraform_validate
        args:
          - --args=-backend=false
      - id: terraform_tflint
        args:
          - --args=--config=__GIT_WORKING_DIR__/.tflint.hcl
EOF

# Install the hooks
pre-commit install

# Test: try to commit the badly-formatted original
git add .
git commit -m "test commit"
# pre-commit will block if anything fails

# Run all hooks manually
pre-commit run --all-files
```

### Step 7: Clean Up

```bash
cd ~
rm -rf tf-lint-lab
```

---

## Part 3: Revision (15 minutes)

- **`terraform fmt`** — canonical formatting; run with `-check` in CI (exit 1 on diff)
- **`terraform validate`** — checks syntax, types, references; requires `init` first
- **`tflint`** — provider-aware linting; catches wrong machine types, missing descriptions
- **`checkov`** — security scanner; checks CIS benchmarks, OWASP, PCI-DSS rules
- **Pre-commit hooks** automate all checks before code reaches the repo
- **CI/CD pipeline** should run the same checks: fmt → validate → tflint → checkov → plan

### Key Commands
```bash
terraform fmt -check -recursive .           # Format check
terraform fmt -recursive .                  # Auto-format
terraform validate                          # Syntax validation
tflint --init && tflint .                   # Lint with provider rules
checkov -d . --compact --quiet              # Security scan
pre-commit install && pre-commit run --all  # Hook setup + run
```

---

## Part 4: Quiz (15 minutes)

**Q1:** What is the difference between `terraform validate` and `tflint`?
<details><summary>Answer</summary><code>terraform validate</code> checks HCL syntax, type correctness, and internal references — but it only knows about Terraform's own grammar. <code>tflint</code> adds <b>provider-specific rules</b> (e.g., "this machine type doesn't exist in this zone") and <b>best-practice checks</b> (e.g., "variables should have descriptions"). Think of it as <code>bash -n</code> (syntax) vs <code>shellcheck</code> (best practices).</details>

**Q2:** checkov flags `CKV_GCP_2` on your firewall rule. What's wrong and how do you fix it?
<details><summary>Answer</summary><code>CKV_GCP_2</code> typically flags an <b>overly permissive firewall rule</b> — for example, <code>source_ranges = ["0.0.0.0/0"]</code> with all ports open. Fix by restricting source ranges to known CIDRs (e.g., IAP range <code>35.235.240.0/20</code>) and limiting ports to only what's needed (e.g., port 22 for SSH). Like locking down <code>iptables</code> rules on Linux.</details>

**Q3:** Why does `terraform validate` require `terraform init` first?
<details><summary>Answer</summary><code>terraform validate</code> needs the <b>provider schemas</b> to check resource arguments and types. These schemas are downloaded during <code>init</code>. Without init, Terraform doesn't know what arguments a <code>google_compute_instance</code> accepts. You can skip backend setup with <code>terraform init -backend=false</code> for validation-only workflows.</details>

**Q4:** A team member's pre-commit hooks keep failing on `terraform_fmt`. They claim their code is correct. What's happening?
<details><summary>Answer</summary>Their code may be functionally correct but not <b>canonically formatted</b>. <code>terraform fmt</code> enforces a standard style (2-space indent, alignment of <code>=</code> signs, etc.). The fix is simple: run <code>terraform fmt -recursive .</code> to auto-format, then commit. This is no different from <code>gofmt</code> or <code>black</code> — the tool is the authority on style, not the developer.</details>
