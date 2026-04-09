# Week 17, Day 102 (Sat) — PROJECT: Production-Grade Terraform Repo

## Today's Objective

Build a complete production-grade Terraform repository combining everything from this week: envs/modules pattern, remote state in GCS, linting with tflint, security scanning with checkov, variable hygiene, and reusable versioned modules.

**Source:** [Google Cloud Terraform Best Practices](https://cloud.google.com/docs/terraform/best-practices) | [Terraform Style Guide](https://developer.hashicorp.com/terraform/language/style)

**Deliverable:** A fully functional Terraform repo with 3 environments, shared modules, remote state, and automated quality checks

---

## Part 1: Concept (30 minutes)

### 1.1 Project Architecture

```
prod-terraform-repo/
│
├── modules/                          ← Shared reusable modules
│   ├── vpc/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── versions.tf
│   ├── compute/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── versions.tf
│   └── firewall/
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       └── versions.tf
│
├── envs/                             ← Per-environment configs
│   ├── dev/
│   │   ├── main.tf                   ← Calls modules
│   │   ├── backend.tf                ← GCS state (dev bucket)
│   │   ├── variables.tf
│   │   ├── terraform.tfvars          ← Git-ignored
│   │   └── outputs.tf
│   ├── staging/
│   │   └── ... (same structure)
│   └── prod/
│       └── ... (same structure)
│
├── scripts/
│   ├── lint.sh                       ← Run all quality checks
│   └── init-backend.sh               ← Create state buckets
│
├── .tflint.hcl                       ← tflint configuration
├── .pre-commit-config.yaml           ← Pre-commit hooks
├── .gitignore                        ← Protect secrets
├── example.tfvars                    ← Template for new envs
└── README.md
```

### 1.2 Environment Comparison

| Aspect | Dev | Staging | Prod |
|---|---|---|---|
| VPC CIDR | 10.10.0.0/24 | 10.20.0.0/24 | 10.30.0.0/24 |
| Machine type | e2-micro | e2-small | e2-medium |
| Flow logs | Off | On | On |
| Instance count | 1 | 1 | 2 |
| State bucket | proj-tf-dev | proj-tf-staging | proj-tf-prod |

### 1.3 Quality Gate Pipeline

```
Developer commit
       │
       ▼
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│  pre-commit  │────►│  CI Pipeline │────►│   Review     │
│              │     │              │     │              │
│ • tf fmt     │     │ • tf init    │     │ • Plan diff  │
│ • tf validate│     │ • tf plan    │     │ • Security   │
│ • tflint     │     │ • checkov    │     │   findings   │
│              │     │ • Plan output│     │ • Approval   │
└──────────────┘     └──────────────┘     └──────────────┘
                                                │
                                                ▼
                                         terraform apply
                                         (automated or manual)
```

---

## Part 2: Hands-On Lab (60 minutes)

### Step 1: Create Repository Structure (5 min)

```bash
export PROJECT_ID=$(gcloud config get-value project)

mkdir -p prod-tf-repo/{modules/{vpc,compute,firewall},envs/{dev,staging,prod},scripts}
cd prod-tf-repo
git init
```

### Step 2: Build the VPC Module (10 min)

```bash
cat > modules/vpc/versions.tf <<'EOF'
terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}
EOF

cat > modules/vpc/variables.tf <<'EOF'
variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "network_name" {
  type        = string
  description = "VPC network name"
}

variable "region" {
  type        = string
  description = "GCP region"
  default     = "europe-west2"
}

variable "subnet_cidr" {
  type        = string
  description = "Primary subnet CIDR"
}

variable "enable_flow_logs" {
  type        = bool
  description = "Enable VPC flow logs"
  default     = false
}
EOF

cat > modules/vpc/main.tf <<'EOF'
resource "google_compute_network" "vpc" {
  name                    = var.network_name
  project                 = var.project_id
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnet" {
  name          = "${var.network_name}-subnet"
  project       = var.project_id
  region        = var.region
  network       = google_compute_network.vpc.id
  ip_cidr_range = var.subnet_cidr

  dynamic "log_config" {
    for_each = var.enable_flow_logs ? [1] : []
    content {
      aggregation_interval = "INTERVAL_5_SEC"
      flow_sampling        = 0.5
      metadata             = "INCLUDE_ALL_METADATA"
    }
  }
}

resource "google_compute_router" "router" {
  name    = "${var.network_name}-router"
  project = var.project_id
  region  = var.region
  network = google_compute_network.vpc.id
}

resource "google_compute_router_nat" "nat" {
  name                               = "${var.network_name}-nat"
  project                            = var.project_id
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}
EOF

cat > modules/vpc/outputs.tf <<'EOF'
output "network_id" {
  description = "VPC network self-link"
  value       = google_compute_network.vpc.id
}

output "network_name" {
  description = "VPC network name"
  value       = google_compute_network.vpc.name
}

output "subnet_id" {
  description = "Subnet self-link"
  value       = google_compute_subnetwork.subnet.id
}
EOF
```

### Step 3: Build the Firewall Module (5 min)

```bash
cat > modules/firewall/versions.tf <<'EOF'
terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}
EOF

cat > modules/firewall/variables.tf <<'EOF'
variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "network_name" {
  type        = string
  description = "VPC network name"
}

variable "environment" {
  type        = string
  description = "Environment label"
}
EOF

cat > modules/firewall/main.tf <<'EOF'
resource "google_compute_firewall" "allow_iap_ssh" {
  name    = "${var.network_name}-allow-iap-ssh"
  network = var.network_name
  project = var.project_id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["ssh-allowed"]
}

resource "google_compute_firewall" "allow_health_check" {
  name    = "${var.network_name}-allow-hc"
  network = var.network_name
  project = var.project_id

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  target_tags   = ["http-server"]
}
EOF

cat > modules/firewall/outputs.tf <<'EOF'
output "ssh_firewall_name" {
  description = "SSH firewall rule name"
  value       = google_compute_firewall.allow_iap_ssh.name
}

output "hc_firewall_name" {
  description = "Health check firewall rule name"
  value       = google_compute_firewall.allow_health_check.name
}
EOF
```

### Step 4: Build the Compute Module (5 min)

```bash
cat > modules/compute/versions.tf <<'EOF'
terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}
EOF

cat > modules/compute/variables.tf <<'EOF'
variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "zone" {
  type        = string
  description = "GCP zone"
  default     = "europe-west2-a"
}

variable "instance_name" {
  type        = string
  description = "VM instance name prefix"
}

variable "machine_type" {
  type        = string
  description = "Machine type"
  default     = "e2-micro"
}

variable "subnet_id" {
  type        = string
  description = "Subnet self-link"
}

variable "instance_count" {
  type        = number
  description = "Number of instances"
  default     = 1
}

variable "labels" {
  type        = map(string)
  description = "Resource labels"
  default     = {}
}
EOF

cat > modules/compute/main.tf <<'EOF'
resource "google_compute_instance" "vm" {
  count        = var.instance_count
  name         = "${var.instance_name}-${count.index}"
  machine_type = var.machine_type
  zone         = var.zone
  project      = var.project_id

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 10
      type  = "pd-balanced"
    }
  }

  network_interface {
    subnetwork = var.subnet_id
  }

  tags   = ["ssh-allowed", "http-server"]
  labels = var.labels

  metadata = {
    enable-oslogin = "TRUE"
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }
}
EOF

cat > modules/compute/outputs.tf <<'EOF'
output "instance_names" {
  description = "VM instance names"
  value       = google_compute_instance.vm[*].name
}

output "internal_ips" {
  description = "VM internal IPs"
  value       = google_compute_instance.vm[*].network_interface[0].network_ip
}
EOF
```

### Step 5: Wire Up Dev Environment (10 min)

```bash
cat > envs/dev/backend.tf <<'EOF'
terraform {
  backend "gcs" {
    # Partial config — supply via -backend-config or .tfbackend
  }
}
EOF

cat > envs/dev/variables.tf <<'EOF'
variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "region" {
  type        = string
  description = "GCP region"
  default     = "europe-west2"
}
EOF

cat > envs/dev/main.tf <<'EOF'
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
  source           = "../../modules/vpc"
  project_id       = var.project_id
  network_name     = "prod-repo-dev"
  region           = var.region
  subnet_cidr      = "10.10.0.0/24"
  enable_flow_logs = false
}

module "firewall" {
  source       = "../../modules/firewall"
  project_id   = var.project_id
  network_name = module.vpc.network_name
  environment  = "dev"
}

module "compute" {
  source         = "../../modules/compute"
  project_id     = var.project_id
  instance_name  = "prod-repo-dev-vm"
  machine_type   = "e2-micro"
  subnet_id      = module.vpc.subnet_id
  instance_count = 1
  labels         = { env = "dev", managed_by = "terraform", week = "17" }
}
EOF

cat > envs/dev/outputs.tf <<'EOF'
output "vpc_name" {
  value = module.vpc.network_name
}

output "instance_names" {
  value = module.compute.instance_names
}

output "internal_ips" {
  value = module.compute.internal_ips
}
EOF

cat > envs/dev/terraform.tfvars <<EOF
project_id = "${PROJECT_ID}"
region     = "europe-west2"
EOF
```

### Step 6: Create Linting Config & Scripts (5 min)

```bash
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

cat > scripts/lint.sh <<'SCRIPT'
#!/bin/bash
set -euo pipefail

echo "========================================="
echo "  Production Terraform Quality Checks"
echo "========================================="

echo ""
echo "[1/4] terraform fmt -check"
terraform fmt -check -recursive . || { echo "FAIL: Run 'terraform fmt -recursive .'"; exit 1; }
echo "PASS"

echo ""
echo "[2/4] terraform validate (all envs)"
for env in envs/*/; do
  echo "  Validating ${env}..."
  (cd "$env" && terraform init -backend=false -input=false -no-color > /dev/null 2>&1 && terraform validate -no-color)
done
echo "PASS"

echo ""
echo "[3/4] tflint"
tflint --init --config=.tflint.hcl > /dev/null 2>&1
tflint --config=.tflint.hcl .
echo "PASS"

echo ""
echo "[4/4] checkov security scan"
checkov -d . --compact --quiet --skip-check CKV_GCP_38
echo "PASS"

echo ""
echo "========================================="
echo "  All quality checks passed! ✓"
echo "========================================="
SCRIPT
chmod +x scripts/lint.sh

cat > .gitignore <<'EOF'
*.tfstate
*.tfstate.*
.terraform/
.terraform.lock.hcl
*.tfvars
!example.tfvars
crash.log
crash.*.log
override.tf
override.tf.json
*_override.tf
*_override.tf.json
.terraformrc
terraform.rc
.DS_Store
EOF

cat > example.tfvars <<'EOF'
# Copy this file to terraform.tfvars and fill in values
# cp example.tfvars envs/dev/terraform.tfvars

project_id = "REPLACE_WITH_YOUR_PROJECT_ID"
region     = "europe-west2"
EOF
```

### Step 7: Validate Everything (5 min)

```bash
cd envs/dev
terraform init -backend=false
terraform validate

echo ""
echo "Format check:"
terraform fmt -check -recursive ../../
echo "All checks passed!"
```

### Step 8: Clean Up

```bash
cd ~
rm -rf prod-tf-repo
```

---

## Part 3: Revision (15 minutes)

- **envs/modules pattern** — modules are reusable, envs call modules with specific values
- **One backend per env** — separate state isolation, different access controls
- **Partial backend config** — keep bucket names out of committed code
- **Quality pipeline** — fmt → validate → tflint → checkov → plan → review → apply
- **Shielded VMs + OS Login** — security defaults enforced at module level
- **Labels everywhere** — `env`, `managed_by`, `week` for cost tracking and filtering
- **`.gitignore`** protects state and tfvars; `example.tfvars` guides new contributors

### Key Commands
```bash
# Quality checks
terraform fmt -check -recursive .
terraform validate
tflint --init && tflint .
checkov -d . --compact

# Environment workflow
cd envs/dev && terraform init -backend-config="bucket=BUCKET"
terraform plan -out=plan.out
terraform apply plan.out
```

---

## Part 4: Quiz (15 minutes)

**Q1:** In the production repo pattern, why does each module have its own `versions.tf`?
<details><summary>Answer</summary>Each module declares its own <b>provider and Terraform version constraints</b>. This ensures the module works independently — if someone uses it in a different repo with a different provider version, they'll get a clear error instead of mysterious failures. It's like declaring <code>Requires: nginx >= 1.24</code> in an RPM spec — the dependency is explicit.</details>

**Q2:** Why use `count` in the compute module instead of separate resources per environment?
<details><summary>Answer</summary><code>count</code> makes the module reusable — dev sets <code>instance_count = 1</code>, prod sets <code>instance_count = 2</code>. Without it, you'd need separate modules or duplicated resource blocks for different instance counts. The trade-off: <code>count</code> uses index-based addressing (<code>[0]</code>, <code>[1]</code>), which can cause ordering issues when removing instances from the middle. For production, consider <code>for_each</code> with named keys instead.</details>

**Q3:** The lint script skips `CKV_GCP_38`. When is it acceptable to skip checkov checks?
<details><summary>Answer</summary>Skip a check only when you have a <b>documented reason</b> — e.g., the check doesn't apply to your architecture, or you have a compensating control. Always <b>document the skip</b> in the script or a README. Never skip checks just to make the pipeline pass. In this case, CKV_GCP_38 may be a false positive for the specific resource configuration.</details>

**Q4:** A new team member needs to add a `staging` environment. Walk through the steps.
<details><summary>Answer</summary>
1. <code>cp -r envs/dev envs/staging</code><br>
2. Edit <code>envs/staging/main.tf</code> — change network names, set <code>subnet_cidr = "10.20.0.0/24"</code>, adjust machine type and instance count<br>
3. Edit <code>envs/staging/backend.tf</code> — point to staging state bucket<br>
4. Create <code>envs/staging/terraform.tfvars</code> from <code>example.tfvars</code><br>
5. <code>cd envs/staging && terraform init -backend-config="bucket=proj-tf-staging"</code><br>
6. <code>terraform plan</code> and review<br>
7. Run <code>scripts/lint.sh</code> to verify quality checks pass<br>
The structure is designed so that adding environments is a copy-and-customise operation.
</details>
