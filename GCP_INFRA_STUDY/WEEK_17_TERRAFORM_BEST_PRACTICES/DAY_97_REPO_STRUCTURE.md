# Week 17, Day 97 (Mon) — Terraform Repo Structure

## Today's Objective

Learn how to organise a production-grade Terraform repository using the envs/modules pattern, separate backend configs per environment, and decide between workspaces and directory-based environment separation.

**Source:** [HashiCorp: Standard Module Structure](https://developer.hashicorp.com/terraform/language/modules/develop/structure) | [Google Cloud Best Practices for Terraform](https://cloud.google.com/docs/terraform/best-practices)

**Deliverable:** A skeleton Terraform repo with dev/staging/prod environments and shared modules

---

## Part 1: Concept (30 minutes)

### 1.1 Why Repo Structure Matters

Think of Terraform repo layout like how you'd organise `/etc/` on a well-managed Linux server. Random config files in `/etc/` lead to drift; likewise, dumping all `.tf` files in one directory leads to state bloat and blast-radius problems.

```
Linux analogy:

/etc/                              terraform-infra/
├── nginx/                         ├── modules/          (reusable configs)
│   ├── nginx.conf                 │   ├── vpc/
│   └── sites-enabled/             │   ├── gke/
├── sysctl.d/                      │   └── iam/
│   └── 99-custom.conf             ├── envs/             (per-env state)
└── cron.d/                        │   ├── dev/
    └── backup                     │   ├── staging/
                                   │   └── prod/
                                   └── scripts/
```

### 1.2 The envs/modules Pattern

```
terraform-infra/
│
├── modules/                    ← Reusable building blocks
│   ├── vpc/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── compute/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── iam/
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
│
├── envs/                       ← One directory per environment
│   ├── dev/
│   │   ├── main.tf             ← Calls modules with dev values
│   │   ├── backend.tf          ← Dev state bucket
│   │   ├── variables.tf
│   │   ├── terraform.tfvars    ← Dev-specific values
│   │   └── outputs.tf
│   ├── staging/
│   │   ├── main.tf
│   │   ├── backend.tf          ← Staging state bucket
│   │   ├── variables.tf
│   │   ├── terraform.tfvars
│   │   └── outputs.tf
│   └── prod/
│       ├── main.tf
│       ├── backend.tf          ← Prod state bucket
│       ├── variables.tf
│       ├── terraform.tfvars
│       └── outputs.tf
│
├── scripts/                    ← Helper scripts (lint, plan, apply)
│   ├── lint.sh
│   └── plan-all.sh
│
├── .gitignore
├── .pre-commit-config.yaml
└── README.md
```

### 1.3 Backend Configuration Per Environment

Each environment has its own state file and its own GCS bucket (or prefix).

| Environment | GCS Bucket | State Path | Lock |
|---|---|---|---|
| dev | `myproj-tf-state-dev` | `terraform/state/default.tfstate` | GCS object lock |
| staging | `myproj-tf-state-staging` | `terraform/state/default.tfstate` | GCS object lock |
| prod | `myproj-tf-state-prod` | `terraform/state/default.tfstate` | GCS object lock |

```hcl
# envs/dev/backend.tf
terraform {
  backend "gcs" {
    bucket = "myproj-tf-state-dev"
    prefix = "terraform/state"
  }
}
```

### 1.4 Workspace vs Directory-Based Separation

| Aspect | Workspaces | Directory-Based |
|---|---|---|
| **State isolation** | Same bucket, different keys | Separate buckets entirely |
| **Config drift** | All envs share same code | Each env can diverge slightly |
| **Blast radius** | Can accidentally apply to wrong ws | Harder to mis-target (separate dirs) |
| **CI/CD** | `terraform workspace select prod` | `cd envs/prod && terraform apply` |
| **Recommended for** | Quick prototyping | Production environments |
| **Linux analogy** | Symlinks to same config | Separate config dirs per host |

**Best practice:** Use directory-based separation for production. Workspaces are fine for short-lived feature branches or personal sandboxes.

### 1.5 Module Structure Standard

Every module should follow this structure:

```
modules/vpc/
├── main.tf            ← Resources
├── variables.tf       ← Input variables
├── outputs.tf         ← Exported values
├── versions.tf        ← Provider + TF version constraints
├── README.md          ← Usage examples
└── examples/          ← Example configurations (optional)
    └── simple/
        └── main.tf
```

| File | Purpose | Linux Analogy |
|---|---|---|
| `main.tf` | Core resources | Main config (`nginx.conf`) |
| `variables.tf` | Input parameters | Environment variables |
| `outputs.tf` | Exported values | Return codes / stdout |
| `versions.tf` | Version pinning | Package version locks (`yum versionlock`) |

---

## Part 2: Hands-On Lab (60 minutes)

### Step 1: Create the Repo Skeleton (15 min)

```bash
# Create the directory structure
mkdir -p terraform-infra/{modules/{vpc,compute,iam},envs/{dev,staging,prod},scripts}

# Create module files
for mod in vpc compute iam; do
  for f in main.tf variables.tf outputs.tf versions.tf; do
    touch terraform-infra/modules/$mod/$f
  done
done

# Create env files
for env in dev staging prod; do
  for f in main.tf backend.tf variables.tf terraform.tfvars outputs.tf; do
    touch terraform-infra/envs/$env/$f
  done
done

# Verify
find terraform-infra -type f | sort
```

### Step 2: Create the VPC Module (15 min)

```hcl
# modules/vpc/versions.tf
terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

# modules/vpc/variables.tf
variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "europe-west2"
}

variable "network_name" {
  description = "VPC network name"
  type        = string
}

variable "subnet_cidr" {
  description = "Subnet CIDR range"
  type        = string
}

variable "environment" {
  description = "Environment name (dev/staging/prod)"
  type        = string
}

# modules/vpc/main.tf
resource "google_compute_network" "vpc" {
  name                    = var.network_name
  project                 = var.project_id
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnet" {
  name          = "${var.network_name}-subnet-${var.region}"
  project       = var.project_id
  region        = var.region
  network       = google_compute_network.vpc.id
  ip_cidr_range = var.subnet_cidr

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# modules/vpc/outputs.tf
output "network_id" {
  description = "VPC network ID"
  value       = google_compute_network.vpc.id
}

output "network_name" {
  description = "VPC network name"
  value       = google_compute_network.vpc.name
}

output "subnet_id" {
  description = "Subnet ID"
  value       = google_compute_subnetwork.subnet.id
}

output "subnet_cidr" {
  description = "Subnet CIDR"
  value       = google_compute_subnetwork.subnet.ip_cidr_range
}
```

### Step 3: Wire Up the Dev Environment (15 min)

```hcl
# envs/dev/backend.tf
terraform {
  backend "gcs" {
    bucket = "YOUR_PROJECT-tf-state-dev"
    prefix = "terraform/state"
  }
}

# envs/dev/variables.tf
variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "europe-west2"
}

# envs/dev/terraform.tfvars
project_id = "YOUR_PROJECT_ID"
region     = "europe-west2"

# envs/dev/main.tf
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

module "vpc" {
  source       = "../../modules/vpc"
  project_id   = var.project_id
  region       = var.region
  network_name = "dev-vpc"
  subnet_cidr  = "10.10.0.0/24"
  environment  = "dev"
}

# envs/dev/outputs.tf
output "vpc_network_id" {
  value = module.vpc.network_id
}

output "subnet_id" {
  value = module.vpc.subnet_id
}
```

### Step 4: Create Helper Scripts (10 min)

```bash
# scripts/lint.sh
#!/bin/bash
set -euo pipefail
echo "=== Running terraform fmt check ==="
terraform fmt -check -recursive .

echo "=== Running terraform validate ==="
for env in envs/*/; do
  echo "Validating $env ..."
  (cd "$env" && terraform init -backend=false -input=false && terraform validate)
done

echo "All checks passed!"
```

```bash
# .gitignore
*.tfstate
*.tfstate.*
.terraform/
*.tfvars
!example.tfvars
crash.log
override.tf
override.tf.json
*_override.tf
*_override.tf.json
.terraformrc
terraform.rc
```

### Step 5: Validate the Structure (5 min)

```bash
cd terraform-infra/envs/dev

# Init without connecting to backend (validation only)
terraform init -backend=false

# Validate syntax and module references
terraform validate

# Check formatting
terraform fmt -check -recursive ../../
```

### Step 6: Clean Up

```bash
cd ~
rm -rf terraform-infra
```

---

## Part 3: Revision (15 minutes)

- **envs/modules pattern** — modules hold reusable code, envs call modules with environment-specific values
- **One state per environment** — separate GCS buckets or prefixes, never share state across envs
- **Directory-based separation > workspaces** for production — harder to accidentally destroy prod
- **Standard module structure** — `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`
- **Backend config per env** — each `envs/<env>/backend.tf` points to its own bucket
- **`.gitignore`** must exclude `.terraform/`, `*.tfstate`, and `*.tfvars` (secrets)

### Key Commands
```bash
terraform init -backend=false       # Validate without backend
terraform fmt -check -recursive .   # Check formatting
terraform validate                  # Syntax + reference checks
find . -name "*.tf" | head -20      # Quick structure overview
```

---

## Part 4: Quiz (15 minutes)

**Q1:** Why use directory-based env separation instead of Terraform workspaces for production?
<details><summary>Answer</summary>Directory-based separation provides <b>complete state isolation</b> (separate buckets), makes it harder to accidentally apply to the wrong environment, and allows each environment to have slight config differences. Workspaces share the same code and bucket, increasing the risk of cross-environment mistakes. Think of it like having separate <code>/etc/nginx/</code> directories per server vs symlinks to the same config.</details>

**Q2:** What files should every Terraform module contain?
<details><summary>Answer</summary><code>main.tf</code> (resources), <code>variables.tf</code> (inputs), <code>outputs.tf</code> (exports), and <code>versions.tf</code> (provider/TF version constraints). Optionally a <code>README.md</code> and <code>examples/</code> directory.</details>

**Q3:** Why should each environment have its own backend configuration?
<details><summary>Answer</summary>To isolate state files. If dev and prod share a state bucket, a mistake in dev could corrupt prod state. Separate backends also allow different access controls — e.g., only CI/CD can write to the prod state bucket. Like keeping <code>/var/log</code> on separate partitions per environment.</details>

**Q4:** What should `.gitignore` exclude in a Terraform repo and why?
<details><summary>Answer</summary><code>*.tfstate</code> and <code>*.tfstate.*</code> (state contains secrets), <code>.terraform/</code> (provider binaries), <code>*.tfvars</code> (may contain secrets — commit an <code>example.tfvars</code> instead), and <code>crash.log</code>. State should live in a remote backend (GCS), not in git.</details>
