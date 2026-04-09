# Day 43 — Clean Terraform Repo Structure

> **Week 8 — Portfolio & Review** | ⏱ 2 hours | Region: `europe-west2`

---

## Part 1 — Concept (30 min)

### Why Repo Structure Matters

A Terraform repo that works is not enough — it needs to be **readable, maintainable, and team-friendly**. Think of it like the difference between a bash script that works and a well-structured one with functions, comments, and error handling.

**Linux analogy:**

| Bad Practice | Good Practice |
|---|---|
| Everything in one giant script | Functions in separate files |
| Hardcoded paths everywhere | Variables at the top, config files |
| No `.gitignore` | Proper ignore for temp/state files |
| "Just run it" | README with prerequisites and usage |

### Recommended Directory Layout

```
┌─────────────────────────────────────────────────────────────┐
│          Recommended Terraform Project Structure             │
│                                                             │
│  my-gcp-infra/                                              │
│  ├── README.md               ← Project overview, usage      │
│  ├── .gitignore              ← Ignore state, creds, .tfvars │
│  │                                                          │
│  ├── modules/                ← Reusable modules             │
│  │   ├── vpc/                                               │
│  │   │   ├── main.tf                                        │
│  │   │   ├── variables.tf                                   │
│  │   │   ├── outputs.tf                                     │
│  │   │   └── README.md                                      │
│  │   ├── compute/                                           │
│  │   │   ├── main.tf                                        │
│  │   │   ├── variables.tf                                   │
│  │   │   └── outputs.tf                                     │
│  │   └── storage/                                           │
│  │       ├── main.tf                                        │
│  │       ├── variables.tf                                   │
│  │       └── outputs.tf                                     │
│  │                                                          │
│  ├── environments/           ← Per-environment configs      │
│  │   ├── dev/                                               │
│  │   │   ├── main.tf        ← Calls modules                │
│  │   │   ├── variables.tf                                   │
│  │   │   ├── terraform.tfvars                               │
│  │   │   ├── backend.tf     ← GCS remote state              │
│  │   │   └── outputs.tf                                     │
│  │   ├── staging/                                           │
│  │   │   └── (same structure)                               │
│  │   └── prod/                                              │
│  │       └── (same structure)                               │
│  │                                                          │
│  └── scripts/                ← Helper scripts               │
│      ├── golden-setup.sh                                    │
│      └── validate.sh                                        │
└─────────────────────────────────────────────────────────────┘
```

### File Purposes

| File | Purpose | Contains |
|---|---|---|
| `main.tf` | Primary resource definitions | Resources, data sources, module calls |
| `variables.tf` | Input variable declarations | Variable blocks with descriptions, types, defaults |
| `outputs.tf` | Output value declarations | Output blocks for downstream use |
| `terraform.tfvars` | Variable values (per-env) | Actual values — **never commit secrets** |
| `backend.tf` | State storage config | GCS bucket for remote state |
| `providers.tf` | Provider configuration | Google provider version, project, region |
| `versions.tf` | Terraform version constraints | `required_version`, `required_providers` |

### Separating Environments

```
┌────────────────────────────────────────────────────────────┐
│         Environment Separation Strategies                   │
│                                                            │
│  Strategy 1: Separate Directories (Recommended for small)  │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  environments/dev/   → terraform apply (in this dir) │  │
│  │  environments/prod/  → terraform apply (in this dir) │  │
│  │  Each has own state file, own .tfvars                │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                            │
│  Strategy 2: Workspaces (Terraform-native)                 │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  Single directory, multiple workspaces:              │  │
│  │  terraform workspace select dev                      │  │
│  │  terraform workspace select prod                     │  │
│  │  terraform.workspace used in configs                 │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                            │
│  Strategy 3: Terragrunt (DRY for large orgs)               │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  Wrapper tool that reduces duplication               │  │
│  │  terragrunt.hcl inherits from parent                │  │
│  │  Best for 10+ environments / teams                   │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                            │
│  For your portfolio: Strategy 1 is best                    │
│  (clear, explicit, easy to explain in interviews)          │
└────────────────────────────────────────────────────────────┘
```

### Essential .gitignore

```
┌──────────────────────────────────────────────┐
│       What to IGNORE in Git                  │
│                                              │
│  *.tfstate           ← State files (secrets!)│
│  *.tfstate.*         ← State backups         │
│  .terraform/         ← Provider binaries     │
│  .terraform.lock.hcl ← (optional: some keep) │
│  *.tfvars            ← May contain secrets   │
│  crash.log           ← Debug crash logs      │
│  *.pem / *.key       ← Private keys          │
│  override.tf         ← Local overrides       │
│                                              │
│  What to KEEP in Git                         │
│  ✓ *.tf files        ← All Terraform code    │
│  ✓ README.md         ← Documentation         │
│  ✓ modules/          ← Reusable modules      │
│  ✓ *.example.tfvars  ← Example variables     │
└──────────────────────────────────────────────┘
```

---

## Part 2 — Hands-On Lab (60 min)

### Goal: Reorganize Your Terraform Code into a Clean Structure

### Step 1 — Create the Project Structure

```bash
export PROJECT_ROOT="/tmp/gcp-infra-portfolio"
mkdir -p ${PROJECT_ROOT}
cd ${PROJECT_ROOT}

# Create directory structure
mkdir -p modules/vpc
mkdir -p modules/compute
mkdir -p modules/storage
mkdir -p environments/dev
mkdir -p environments/prod
mkdir -p scripts

echo "Directory structure created:"
find . -type d | sort
```

### Step 2 — Create the .gitignore

```bash
cat > ${PROJECT_ROOT}/.gitignore << 'EOF'
# Terraform state (contains secrets — never commit!)
*.tfstate
*.tfstate.*

# Provider binaries (large, downloaded on init)
.terraform/

# Lock file (team preference: some commit this)
# .terraform.lock.hcl

# Variable files (may contain secrets)
*.tfvars
!*.example.tfvars

# Crash logs
crash.log
crash.*.log

# Private keys
*.pem
*.key

# OS files
.DS_Store
Thumbs.db

# Editor files
*.swp
*.swo
*~
.vscode/
.idea/
EOF

echo ".gitignore created"
```

### Step 3 — Create VPC Module

```bash
cat > ${PROJECT_ROOT}/modules/vpc/main.tf << 'EOF'
resource "google_compute_network" "vpc" {
  name                    = var.network_name
  auto_create_subnetworks = false
  project                 = var.project_id
}

resource "google_compute_subnetwork" "subnet" {
  name          = var.subnet_name
  ip_cidr_range = var.subnet_cidr
  region        = var.region
  network       = google_compute_network.vpc.id
  project       = var.project_id

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

resource "google_compute_firewall" "allow_ssh_iap" {
  name    = "${var.network_name}-allow-ssh-iap"
  network = google_compute_network.vpc.name
  project = var.project_id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]  # IAP range
  target_tags   = ["ssh"]
}

resource "google_compute_firewall" "allow_http" {
  name    = "${var.network_name}-allow-http"
  network = google_compute_network.vpc.name
  project = var.project_id

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["http-server"]
}
EOF

cat > ${PROJECT_ROOT}/modules/vpc/variables.tf << 'EOF'
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
  description = "Name of the VPC network"
  type        = string
}

variable "subnet_name" {
  description = "Name of the subnet"
  type        = string
}

variable "subnet_cidr" {
  description = "CIDR range for the subnet"
  type        = string
  default     = "10.0.1.0/24"
}
EOF

cat > ${PROJECT_ROOT}/modules/vpc/outputs.tf << 'EOF'
output "network_id" {
  description = "ID of the VPC network"
  value       = google_compute_network.vpc.id
}

output "network_name" {
  description = "Name of the VPC network"
  value       = google_compute_network.vpc.name
}

output "subnet_id" {
  description = "ID of the subnet"
  value       = google_compute_subnetwork.subnet.id
}

output "subnet_name" {
  description = "Name of the subnet"
  value       = google_compute_subnetwork.subnet.name
}
EOF

cat > ${PROJECT_ROOT}/modules/vpc/README.md << 'EOF'
# VPC Module

Creates a custom VPC with subnet, SSH (IAP) and HTTP firewall rules.

## Usage

```hcl
module "vpc" {
  source       = "../../modules/vpc"
  project_id   = var.project_id
  region       = "europe-west2"
  network_name = "prod-vpc"
  subnet_name  = "prod-subnet"
  subnet_cidr  = "10.0.1.0/24"
}
```

## Inputs

| Name | Description | Type | Default |
|---|---|---|---|
| project_id | GCP project ID | string | - |
| region | GCP region | string | europe-west2 |
| network_name | VPC name | string | - |
| subnet_name | Subnet name | string | - |
| subnet_cidr | CIDR range | string | 10.0.1.0/24 |

## Outputs

| Name | Description |
|---|---|
| network_id | VPC network ID |
| network_name | VPC network name |
| subnet_id | Subnet ID |
| subnet_name | Subnet name |
EOF
```

### Step 4 — Create Compute Module

```bash
cat > ${PROJECT_ROOT}/modules/compute/main.tf << 'EOF'
resource "google_compute_instance" "vm" {
  name         = var.instance_name
  machine_type = var.machine_type
  zone         = var.zone
  project      = var.project_id

  boot_disk {
    initialize_params {
      image = var.image
      size  = var.disk_size_gb
      type  = var.disk_type
    }
  }

  network_interface {
    subnetwork = var.subnet_id

    dynamic "access_config" {
      for_each = var.external_ip ? [1] : []
      content {}
    }
  }

  metadata = {
    startup-script-url = var.startup_script_url
  }

  tags   = var.tags
  labels = var.labels

  service_account {
    scopes = var.scopes
  }
}
EOF

cat > ${PROJECT_ROOT}/modules/compute/variables.tf << 'EOF'
variable "project_id" {
  type = string
}

variable "zone" {
  type    = string
  default = "europe-west2-a"
}

variable "instance_name" {
  type = string
}

variable "machine_type" {
  type    = string
  default = "e2-small"
}

variable "image" {
  type    = string
  default = "debian-cloud/debian-12"
}

variable "disk_size_gb" {
  type    = number
  default = 20
}

variable "disk_type" {
  type    = string
  default = "pd-balanced"
}

variable "subnet_id" {
  type = string
}

variable "external_ip" {
  type    = bool
  default = false
}

variable "startup_script_url" {
  type    = string
  default = ""
}

variable "tags" {
  type    = list(string)
  default = []
}

variable "labels" {
  type    = map(string)
  default = {}
}

variable "scopes" {
  type    = list(string)
  default = ["cloud-platform"]
}
EOF

cat > ${PROJECT_ROOT}/modules/compute/outputs.tf << 'EOF'
output "instance_name" {
  value = google_compute_instance.vm.name
}

output "instance_id" {
  value = google_compute_instance.vm.instance_id
}

output "internal_ip" {
  value = google_compute_instance.vm.network_interface[0].network_ip
}
EOF
```

### Step 5 — Create Dev Environment

```bash
cat > ${PROJECT_ROOT}/environments/dev/main.tf << 'EOF'
module "vpc" {
  source       = "../../modules/vpc"
  project_id   = var.project_id
  region       = var.region
  network_name = "${var.environment}-vpc"
  subnet_name  = "${var.environment}-subnet"
  subnet_cidr  = "10.0.1.0/24"
}

module "web_server" {
  source         = "../../modules/compute"
  project_id     = var.project_id
  zone           = var.zone
  instance_name  = "${var.environment}-web-ew2-001"
  machine_type   = "e2-micro"
  subnet_id      = module.vpc.subnet_id
  external_ip    = true
  tags           = ["ssh", "http-server"]
  labels = {
    env  = var.environment
    team = "platform"
    role = "web"
  }
}
EOF

cat > ${PROJECT_ROOT}/environments/dev/variables.tf << 'EOF'
variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "europe-west2"
}

variable "zone" {
  description = "GCP zone"
  type        = string
  default     = "europe-west2-a"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}
EOF

cat > ${PROJECT_ROOT}/environments/dev/backend.tf << 'EOF'
terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  # Uncomment for remote state:
  # backend "gcs" {
  #   bucket = "PROJECT-tf-state"
  #   prefix = "dev"
  # }
}

provider "google" {
  project = var.project_id
  region  = var.region
}
EOF

cat > ${PROJECT_ROOT}/environments/dev/outputs.tf << 'EOF'
output "vpc_name" {
  value = module.vpc.network_name
}

output "web_server_name" {
  value = module.web_server.instance_name
}

output "web_server_ip" {
  value = module.web_server.internal_ip
}
EOF

cat > ${PROJECT_ROOT}/environments/dev/terraform.tfvars.example << 'EOF'
project_id  = "your-project-id"
region      = "europe-west2"
zone        = "europe-west2-a"
environment = "dev"
EOF
```

### Step 6 — Create Root README

```bash
cat > ${PROJECT_ROOT}/README.md << 'EOF'
# GCP Infrastructure Portfolio

Infrastructure as Code for GCP environments using Terraform.

## Architecture

```
environments/dev  → Dev VPC + Web Server (e2-micro)
environments/prod → Prod VPC + Web Server (e2-small) + Backups
```

## Structure

```
├── modules/           # Reusable Terraform modules
│   ├── vpc/           # VPC + subnets + firewall
│   ├── compute/       # Compute instances
│   └── storage/       # GCS buckets
├── environments/      # Per-environment configurations
│   ├── dev/           # Development environment
│   └── prod/          # Production environment
└── scripts/           # Helper scripts
```

## Quick Start

```bash
# 1. Navigate to environment
cd environments/dev

# 2. Copy and fill in variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your project ID

# 3. Initialize and apply
terraform init
terraform plan
terraform apply
```

## Modules

| Module | Description |
|---|---|
| [vpc](modules/vpc/) | VPC, subnet, firewall rules (SSH via IAP, HTTP) |
| [compute](modules/compute/) | Compute Engine instance with configurable params |
| [storage](modules/storage/) | GCS bucket with lifecycle and versioning |

## Environments

| Environment | Purpose | Machine Types |
|---|---|---|
| dev | Development/testing | e2-micro |
| prod | Production workloads | e2-small+ |

## Region: europe-west2 (London)
EOF

echo ""
echo "=== Final structure ==="
find ${PROJECT_ROOT} -type f | sort
```

### Step 7 — Initialize Git (Optional)

```bash
cd ${PROJECT_ROOT}

# Initialize git repo
git init
git add .
git status

echo ""
echo "=== Files tracked by git ==="
git ls-files

echo ""
echo "=== Files ignored by git ==="
# Any .tfstate or .terraform would be ignored
```

### Cleanup

```bash
rm -rf /tmp/gcp-infra-portfolio
```

---

## Part 3 — Revision (15 min)

### Key Concepts

- **Standard file layout:** `main.tf`, `variables.tf`, `outputs.tf`, `backend.tf` per directory
- **Modules** = reusable blocks; call from environments with different variables
- **Environments** = separate directories or workspaces; each has own state
- **`.gitignore`** must exclude: `.tfstate`, `.terraform/`, `.tfvars`, `*.pem`
- **Never commit state files** — they contain secrets (passwords, IPs, keys)
- **README per module** — essential for team repos and portfolios

### File Conventions

```
modules/MODULE_NAME/
  ├── main.tf          # Resources
  ├── variables.tf     # Inputs
  ├── outputs.tf       # Outputs
  └── README.md        # Usage docs

environments/ENV_NAME/
  ├── main.tf          # Module calls
  ├── variables.tf     # Env-specific variables
  ├── terraform.tfvars # Values (gitignored)
  ├── backend.tf       # Provider + remote state
  └── outputs.tf       # Env outputs
```

---

## Part 4 — Quiz (15 min)

<details>
<summary><strong>Q1: A colleague commits terraform.tfstate to Git. What risks does this create, and how do you fix it?</strong></summary>

**Answer:**

**Risks:**
1. **Secrets exposed** — state files contain resource attributes including passwords, private IPs, service account keys, and database connection strings in **plaintext**
2. **State corruption** — if two people pull, modify, and push state, the merge creates an invalid state file
3. **Git history** — even after removing the file, the secrets remain in Git history

**Fix:**
1. **Immediately:** Remove from Git tracking: `git rm --cached terraform.tfstate terraform.tfstate.backup`
2. **Add to .gitignore:** `*.tfstate` and `*.tfstate.*`
3. **Rotate secrets** — any credential in the committed state file should be considered compromised
4. **Remove from history** (if pushed): `git filter-branch` or BFG Repo Cleaner
5. **Use remote state:** Configure GCS backend so state is stored in a bucket, not locally:
   ```hcl
   backend "gcs" {
     bucket = "project-tf-state"
     prefix = "dev"
   }
   ```
</details>

<details>
<summary><strong>Q2: Why use modules instead of putting everything in one big main.tf?</strong></summary>

**Answer:**

| Single main.tf | Modular Structure |
|---|---|
| 500+ lines, hard to navigate | Each module ~50-100 lines |
| Copy-paste between environments | Reuse same module with different vars |
| Change one thing, risk breaking another | Isolated changes per module |
| Can't test components independently | Test each module separately |
| One person's code style | Standardised module interface |

**Practical benefit for your portfolio:** When an interviewer asks about your VPC setup, you can point to `modules/vpc/` — clean, self-contained, documented. Much more impressive than "it's all in this 400-line file somewhere."
</details>

<details>
<summary><strong>Q3: What's the difference between `terraform.tfvars` and `variables.tf`?</strong></summary>

**Answer:**

| File | Purpose | Git? |
|---|---|---|
| `variables.tf` | **Declares** variables (name, type, description, default) | Yes — always commit |
| `terraform.tfvars` | **Assigns** values to those variables | No — contains env-specific/secret values |
| `*.example.tfvars` | **Template** showing required variables | Yes — helps others set up |

**Example:**
```hcl
# variables.tf (committed)
variable "project_id" {
  description = "GCP project ID"
  type        = string
}

# terraform.tfvars (NOT committed)
project_id = "my-actual-project-123"

# terraform.tfvars.example (committed)
project_id = "your-project-id-here"
```
</details>

<details>
<summary><strong>Q4: You have dev and prod environments using the same modules. Dev needs e2-micro VMs and prod needs e2-standard-2. How do you handle this without duplicating code?</strong></summary>

**Answer:** The module accepts `machine_type` as a variable. Each environment passes a different value:

```hcl
# modules/compute/variables.tf
variable "machine_type" {
  type    = string
  default = "e2-small"
}

# environments/dev/main.tf
module "web_server" {
  source       = "../../modules/compute"
  machine_type = "e2-micro"
  # ... other vars
}

# environments/prod/main.tf
module "web_server" {
  source       = "../../modules/compute"
  machine_type = "e2-standard-2"
  # ... other vars
}
```

**Zero duplication** — the module code is written once. Environments only differ in their `.tfvars` or module call parameters. This is the core value of the module pattern.
</details>
