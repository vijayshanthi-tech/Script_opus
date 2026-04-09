# Week 17, Day 100 (Thu) — Variables Hygiene & Secrets Management

## Today's Objective

Master Terraform variable organisation, handle sensitive values securely, integrate with Google Secret Manager, and establish patterns that prevent secrets from leaking into state or version control.

**Source:** [Terraform: Input Variables](https://developer.hashicorp.com/terraform/language/values/variables) | [Secret Manager](https://cloud.google.com/secret-manager/docs) | [Sensitive Data in State](https://developer.hashicorp.com/terraform/language/state/sensitive-data)

**Deliverable:** A working Terraform config that reads secrets from Secret Manager + a `.gitignore` that protects sensitive files

---

## Part 1: Concept (30 minutes)

### 1.1 Variable Organisation

```
Linux analogy:

/etc/default/myapp          ──►    variables.tf      (definitions)
/etc/myapp/myapp.env        ──►    terraform.tfvars   (values)
export DB_PASS="xxx"        ──►    TF_VAR_db_pass     (env var)
vault read secret/db        ──►    google_secret_      (Secret Manager)
                                   manager_secret_
                                   version
```

### 1.2 Variable Precedence (Highest to Lowest)

```
┌─────────────────────────────────────────────────┐
│  1. -var="key=value"         (command line)      │  ← Highest
│  2. -var-file="prod.tfvars"  (explicit file)     │
│  3. *.auto.tfvars            (auto-loaded)       │
│  4. terraform.tfvars         (auto-loaded)       │
│  5. TF_VAR_name              (environment var)   │
│  6. default in variables.tf  (fallback)          │  ← Lowest
└─────────────────────────────────────────────────┘
```

### 1.3 Variable Types & Validation

| Type | Example | Use Case |
|---|---|---|
| `string` | `"europe-west2"` | Region, names |
| `number` | `10` | Disk size, count |
| `bool` | `true` | Feature flags |
| `list(string)` | `["a","b"]` | Zones, CIDRs |
| `map(string)` | `{env="dev"}` | Labels |
| `object({...})` | Complex structs | Module inputs |

```hcl
variable "environment" {
  type        = string
  description = "Deployment environment"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Must be dev, staging, or prod."
  }
}
```

### 1.4 Sensitive Variables

```hcl
variable "db_password" {
  type        = string
  sensitive   = true   # Masks in plan/apply output
  description = "Database admin password"
}
```

**WARNING:** `sensitive = true` only hides the value from CLI output. **The value is still stored in plain text in the state file!**

```
┌──────────────────────────────────────────────────────┐
│  Where Secrets Can Leak                               │
│                                                       │
│  ✅ terraform plan output  → masked by sensitive=true │
│  ✅ terraform apply output → masked by sensitive=true │
│  ❌ terraform.tfstate      → PLAIN TEXT               │
│  ❌ terraform.tfvars       → PLAIN TEXT on disk/git   │
│  ❌ CI/CD logs             → depends on masking       │
└──────────────────────────────────────────────────────┘
```

### 1.5 Secret Manager Integration Pattern

```
┌────────────────┐     create secret     ┌──────────────────┐
│ Admin / CI/CD  │ ────────────────────► │ Secret Manager   │
│                │                       │                  │
└────────────────┘                       │ db-password      │
                                         │ api-key          │
┌────────────────┐     read at apply     │ tls-cert         │
│ Terraform      │ ◄──────────────────── │                  │
│ data source    │                       └──────────────────┘
│                │
│ google_secret_ │──► used in resource
│ manager_secret │    configs (never in
│ _version       │    .tf files)
└────────────────┘
```

### 1.6 .gitignore for Terraform Projects

| Pattern | Why |
|---|---|
| `*.tfvars` | May contain secrets |
| `!example.tfvars` | Allowed — shows structure without real values |
| `*.tfstate` | Contains all resource attributes including secrets |
| `*.tfstate.*` | Backup state files |
| `.terraform/` | Provider binaries, not portable |
| `crash.log` | Debug output may contain secrets |

---

## Part 2: Hands-On Lab (60 minutes)

### Step 1: Set Up Lab (5 min)

```bash
export PROJECT_ID=$(gcloud config get-value project)
mkdir -p tf-secrets-lab && cd tf-secrets-lab
```

### Step 2: Create a Secret in Secret Manager (10 min)

```bash
# Enable API
gcloud services enable secretmanager.googleapis.com

# Create a secret
echo -n "SuperS3cretP@ss!" | gcloud secrets create db-admin-password \
  --replication-policy="user-managed" \
  --locations="europe-west2" \
  --data-file=-

# Verify
gcloud secrets list --format="table(name,replication.userManaged.replicas.location)"

# View metadata only (not the value!)
gcloud secrets describe db-admin-password

# Read value (admin only — verify it works)
gcloud secrets versions access latest --secret=db-admin-password
```

### Step 3: Create Variable Definitions (10 min)

```hcl
# variables.tf
variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "region" {
  type        = string
  description = "GCP region"
  default     = "europe-west2"
}

variable "environment" {
  type        = string
  description = "Deployment environment"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Must be dev, staging, or prod."
  }
}

variable "db_tier" {
  type        = string
  description = "Cloud SQL machine tier"
  default     = "db-f1-micro"
}

# NEVER define secrets as variables with defaults!
# variable "db_password" { ... }  ← WRONG!
```

### Step 4: Create tfvars and Example Files (5 min)

```hcl
# example.tfvars  ← Committed to git (template)
project_id  = "REPLACE_ME"
environment = "dev"
db_tier     = "db-f1-micro"

# terraform.tfvars  ← NOT committed (real values)
# project_id  = "my-actual-project"
# environment = "dev"
# db_tier     = "db-f1-micro"
```

```bash
# Create real tfvars
cat > terraform.tfvars <<EOF
project_id  = "${PROJECT_ID}"
environment = "dev"
db_tier     = "db-f1-micro"
EOF
```

### Step 5: Read Secret in Terraform (15 min)

```hcl
# main.tf
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
  region  = var.region
}

# Read secret from Secret Manager (not from tfvars!)
data "google_secret_manager_secret_version" "db_password" {
  secret = "db-admin-password"
}

# Use the secret in a resource
resource "google_compute_instance" "app" {
  name         = "${var.environment}-secrets-lab-vm"
  machine_type = "e2-micro"
  zone         = "${var.region}-a"

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 10
    }
  }

  network_interface {
    network = "default"
  }

  # Pass secret via metadata (encrypted in transit)
  metadata = {
    db-password = data.google_secret_manager_secret_version.db_password.secret_data
  }

  labels = {
    env  = var.environment
    week = "17"
  }
}

output "vm_name" {
  value = google_compute_instance.app.name
}

# Show that secret output is masked
output "db_password_status" {
  value     = "Secret loaded: ${length(data.google_secret_manager_secret_version.db_password.secret_data) > 0 ? "yes" : "no"}"
  sensitive = true
}
```

### Step 6: Create .gitignore (5 min)

```bash
cat > .gitignore <<'EOF'
# Terraform state (contains secrets in plain text)
*.tfstate
*.tfstate.*

# Provider binaries
.terraform/
.terraform.lock.hcl

# Variable files (may contain secrets)
*.tfvars
!example.tfvars

# Crash logs (may contain secrets)
crash.log
crash.*.log

# Override files
override.tf
override.tf.json
*_override.tf
*_override.tf.json

# CLI config
.terraformrc
terraform.rc

# OS files
.DS_Store
Thumbs.db
EOF
```

### Step 7: Apply and Verify (5 min)

```bash
terraform init
terraform plan
terraform apply -auto-approve

# Note: db_password_status output shows (sensitive value)
terraform output db_password_status
```

### Step 8: Demonstrate TF_VAR_ Environment Variables (5 min)

```bash
# Override environment via env var (no file needed)
TF_VAR_environment="staging" terraform plan

# This takes precedence over terraform.tfvars value
```

### Step 9: Clean Up

```bash
terraform destroy -auto-approve

# Delete the secret
gcloud secrets delete db-admin-password --quiet

cd ~
rm -rf tf-secrets-lab
```

---

## Part 3: Revision (15 minutes)

- **Variable precedence** — CLI > -var-file > auto.tfvars > terraform.tfvars > TF_VAR_ > default
- **`sensitive = true`** masks CLI output only — state still contains plain text
- **Never store secrets** in `.tf` files, `terraform.tfvars`, or environment variables in CI logs
- **Secret Manager** is the correct pattern — Terraform reads secrets at apply time via data source
- **`.gitignore`** must exclude `*.tfvars`, `*.tfstate`, `.terraform/`, `crash.log`
- **`example.tfvars`** should be committed — shows the structure without real values
- **Validation blocks** on variables catch bad inputs early

### Key Commands
```bash
gcloud secrets create NAME --data-file=-          # Create secret
gcloud secrets versions access latest --secret=N   # Read secret
TF_VAR_foo="bar" terraform plan                    # Env var override
terraform output -json                             # View outputs
```

---

## Part 4: Quiz (15 minutes)

**Q1:** `sensitive = true` on a variable — what does it protect and what does it NOT protect?
<details><summary>Answer</summary>It <b>masks the value</b> in <code>terraform plan</code> and <code>terraform apply</code> CLI output (shows <code>(sensitive value)</code>). It does <b>NOT</b> encrypt the value in the state file — the state still contains the secret in plain text. This is why state files must be stored in encrypted, access-controlled backends (GCS with IAM), never in git.</details>

**Q2:** You need to pass a database password to Terraform. Rank these approaches from worst to best.
<details><summary>Answer</summary>
<b>Worst to best:</b><br>
1. <b>Hardcoded in .tf file</b> — committed to git, visible to everyone<br>
2. <b>In terraform.tfvars</b> — better but still a file on disk, might be committed accidentally<br>
3. <b>TF_VAR_ env var</b> — not on disk, but may leak in CI/CD logs<br>
4. <b>Secret Manager data source</b> — best: secret lives in a managed service with IAM, audit logging, rotation support. Terraform reads it at apply time only.
</details>

**Q3:** What happens if you define a variable in both `terraform.tfvars` and via `TF_VAR_` env var?
<details><summary>Answer</summary>The <code>terraform.tfvars</code> value wins because it has <b>higher precedence</b> than environment variables. The precedence order (highest first) is: <code>-var</code> flag → <code>-var-file</code> → <code>*.auto.tfvars</code> → <code>terraform.tfvars</code> → <code>TF_VAR_</code> → default. To override a tfvars value, use <code>-var="key=value"</code> on the command line.</details>

**Q4:** A team member committed `terraform.tfvars` containing a database password to git. What should you do?
<details><summary>Answer</summary>
1. <b>Rotate the password immediately</b> — it's compromised the moment it was pushed<br>
2. Remove the file from the repo: <code>git rm terraform.tfvars</code><br>
3. Add <code>*.tfvars</code> to <code>.gitignore</code><br>
4. Use <code>git filter-branch</code> or <code>BFG Repo Cleaner</code> to purge it from history<br>
5. Move the secret to Secret Manager and use a data source instead<br>
Treat this like any credential leak — the secret is in git history forever unless explicitly purged.
</details>
