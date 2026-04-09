# Week 17, Day 101 (Fri) — Reusable Terraform Templates

## Today's Objective

Build reusable Terraform modules with versioning via git tags, understand module registries, compose modules together, create wrapper modules, and develop starter templates for common GCP infrastructure patterns.

**Source:** [Terraform Module Registry](https://developer.hashicorp.com/terraform/registry/modules) | [Google Terraform Modules](https://github.com/terraform-google-modules) | [Module Composition](https://developer.hashicorp.com/terraform/language/modules/develop/composition)

**Deliverable:** A versioned VPC module called from multiple environments with a wrapper module pattern

---

## Part 1: Concept (30 minutes)

### 1.1 Why Reusable Modules?

```
Linux analogy:

RPM/DEB packages              ──►    Terraform modules
  └── versioned                        └── versioned (git tags)
  └── dependencies declared            └── required_providers
  └── yum repo / apt repo             └── module registry
  └── rpm -i nginx-1.24               └── source = "git::...?ref=v1.2"
  └── /etc/nginx/ (config)            └── variables (inputs)
```

### 1.2 Module Sources

```
┌──────────────────────────────────────────────────────────┐
│                    MODULE SOURCES                          │
│                                                           │
│  ┌─────────────┐  ┌─────────────┐  ┌──────────────────┐  │
│  │   Local     │  │   Git Repo  │  │  Registry        │  │
│  │             │  │             │  │                  │  │
│  │ source =    │  │ source =    │  │ source =         │  │
│  │ "../../     │  │ "git::https │  │ "terraform-      │  │
│  │  modules/   │  │  ://github  │  │  google-modules/ │  │
│  │  vpc"       │  │  .com/org/  │  │  terraform-      │  │
│  │             │  │  mod.git    │  │  google-network" │  │
│  │ Dev/test    │  │  ?ref=v1.2" │  │                  │  │
│  │ workflow    │  │ Production  │  │ Official/public  │  │
│  └─────────────┘  └─────────────┘  └──────────────────┘  │
└──────────────────────────────────────────────────────────┘
```

| Source Type | When to Use | Version Control |
|---|---|---|
| **Local path** | Development, testing | None (uses HEAD) |
| **Git repo** | Internal team modules | `?ref=v1.2.0` (git tags) |
| **Terraform Registry** | Community/official modules | `version = "~> 5.0"` |
| **GCS bucket** | Air-gapped environments | By object path |

### 1.3 Versioning with Git Tags

```
main branch:
  ──●──●──●──●──●──●──●──●──●──►
    │        │           │
    v1.0.0   v1.1.0      v2.0.0
    │        │           │
    Initial  Add flow    Breaking change:
    VPC      logs        new required var

Consumers pin to a version:
  source = "git::https://github.com/org/tf-vpc.git?ref=v1.1.0"

Upgrade path:
  v1.0 → v1.1  (non-breaking, safe)
  v1.1 → v2.0  (breaking, review required)
```

### 1.4 Module Composition Pattern

```
┌─────────────────────────────────────────────────────┐
│                 envs/prod/main.tf                     │
│                                                       │
│  module "network" ──► modules/vpc/                    │
│       │                                               │
│       ▼ outputs                                       │
│  module "compute" ──► modules/compute/                │
│       │ uses network.vpc_id                           │
│       ▼ outputs                                       │
│  module "monitoring" ──► modules/monitoring/           │
│       uses compute.instance_ids                       │
└─────────────────────────────────────────────────────┘
```

### 1.5 Wrapper Module Pattern

A wrapper module combines several lower-level modules into a higher-level abstraction:

```
┌─────────────────────────────────────────────────────┐
│            modules/web-app/  (wrapper)                │
│                                                       │
│  ┌───────────┐  ┌──────────┐  ┌──────────────────┐   │
│  │ module    │  │ module   │  │ module           │   │
│  │ "vpc"     │  │ "compute"│  │ "load_balancer"  │   │
│  │ (low-lvl) │  │(low-lvl) │  │ (low-lvl)        │   │
│  └───────────┘  └──────────┘  └──────────────────┘   │
│                                                       │
│  Input: app_name, env, instance_count                 │
│  Output: lb_ip, vpc_id, instance_ips                  │
└─────────────────────────────────────────────────────┘

Usage:
  module "my_app" {
    source         = "../../modules/web-app"
    app_name       = "orders-api"
    environment    = "prod"
    instance_count = 3
  }
```

### 1.6 Starter Template Catalogue

| Template | Contains | Use When |
|---|---|---|
| **basic-vpc** | VPC + subnet + firewall + NAT | Starting any new project |
| **web-app** | VPC + MIG + LB + SSL | Deploying a web service |
| **data-pipeline** | VPC + GCS + Dataflow + BQ | Building ETL pipelines |
| **gke-cluster** | VPC + GKE + node pools | Running containers |

---

## Part 2: Hands-On Lab (60 minutes)

### Step 1: Create a Versioned Module Repo (15 min)

```bash
mkdir -p tf-module-lab/modules/vpc tf-module-lab/envs/{dev,prod}
cd tf-module-lab

# Initialize git
git init

# Create the VPC module
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

variable "environment" {
  type        = string
  description = "Environment (dev/staging/prod)"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Must be dev, staging, or prod."
  }
}

variable "enable_flow_logs" {
  type        = bool
  description = "Enable VPC flow logs on subnet"
  default     = false
}
EOF

cat > modules/vpc/main.tf <<'EOF'
resource "google_compute_network" "vpc" {
  name                    = var.network_name
  project                 = var.project_id
  auto_create_subnetworks = false
  description             = "${var.environment} VPC managed by Terraform"
}

resource "google_compute_subnetwork" "subnet" {
  name          = "${var.network_name}-${var.region}"
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
  description = "Subnet CIDR range"
  value       = google_compute_subnetwork.subnet.ip_cidr_range
}

output "router_name" {
  description = "Cloud Router name"
  value       = google_compute_router.router.name
}
EOF
```

### Step 2: Tag Version 1.0.0 (5 min)

```bash
git add modules/
git commit -m "feat: VPC module v1.0.0 - network, subnet, router, NAT"
git tag -a v1.0.0 -m "VPC module initial release"

# List tags
git tag -l
```

### Step 3: Create Dev Environment Using Local Module (10 min)

```hcl
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
  region  = "europe-west2"
}

variable "project_id" {
  type        = string
  description = "GCP project ID"
}

# Dev uses local source (for active development)
module "vpc" {
  source           = "../../modules/vpc"
  project_id       = var.project_id
  network_name     = "dev-reusable-lab"
  region           = "europe-west2"
  subnet_cidr      = "10.10.0.0/24"
  environment      = "dev"
  enable_flow_logs = false
}

output "vpc_name" {
  value = module.vpc.network_name
}

output "subnet_cidr" {
  value = module.vpc.subnet_cidr
}
```

### Step 4: Create Prod Environment (Pinned Version Pattern) (10 min)

```hcl
# envs/prod/main.tf
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
  description = "GCP project ID"
}

# Prod would use a git tag in real setup:
#   source = "git::https://github.com/org/tf-modules.git//modules/vpc?ref=v1.0.0"
# For this lab, we use local path
module "vpc" {
  source           = "../../modules/vpc"
  project_id       = var.project_id
  network_name     = "prod-reusable-lab"
  region           = "europe-west2"
  subnet_cidr      = "10.20.0.0/24"
  environment      = "prod"
  enable_flow_logs = true    # Prod enables flow logs
}

output "vpc_name" {
  value = module.vpc.network_name
}

output "subnet_cidr" {
  value = module.vpc.subnet_cidr
}
```

### Step 5: Create a Wrapper Module (10 min)

```bash
mkdir -p modules/web-stack
```

```hcl
# modules/web-stack/variables.tf
variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "app_name" {
  type        = string
  description = "Application name"
}

variable "environment" {
  type        = string
  description = "Environment (dev/staging/prod)"
}

variable "subnet_cidr" {
  type        = string
  description = "Subnet CIDR"
}

# modules/web-stack/main.tf
module "vpc" {
  source           = "../vpc"
  project_id       = var.project_id
  network_name     = "${var.app_name}-${var.environment}"
  subnet_cidr      = var.subnet_cidr
  environment      = var.environment
  enable_flow_logs = var.environment == "prod"
}

resource "google_compute_firewall" "allow_iap_ssh" {
  name    = "${var.app_name}-${var.environment}-allow-iap-ssh"
  network = module.vpc.network_name
  project = var.project_id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]  # IAP range
}

resource "google_compute_firewall" "allow_health_check" {
  name    = "${var.app_name}-${var.environment}-allow-hc"
  network = module.vpc.network_name
  project = var.project_id

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]  # GCP health checks
}

# modules/web-stack/outputs.tf
output "network_name" {
  value = module.vpc.network_name
}

output "subnet_id" {
  value = module.vpc.subnet_id
}
```

### Step 6: Validate All Environments (5 min)

```bash
cd envs/dev
terraform init -backend=false
terraform validate

cd ../prod
terraform init -backend=false
terraform validate

echo "Both environments validated successfully!"
```

### Step 7: Clean Up

```bash
cd ~
rm -rf tf-module-lab
```

---

## Part 3: Revision (15 minutes)

- **Module sources** — local (dev), git+tag (prod), registry (community)
- **Git tags** for versioning — `?ref=v1.2.0`; use semantic versioning
- **Wrapper modules** compose lower-level modules into higher-level abstractions
- **Pin versions** in production — never use `main` branch as a module source
- **`dynamic` blocks** enable conditional configuration (e.g., flow logs only in prod)
- **Validation blocks** catch bad inputs at plan time (not apply time)
- **Standard structure** — every module has `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`

### Key Commands
```bash
git tag -a v1.0.0 -m "description"    # Create version tag
git tag -l                              # List tags
terraform init -upgrade                 # Upgrade module versions
terraform get -update                   # Re-download modules
terraform init -backend=false           # Validate without backend
```

---

## Part 4: Quiz (15 minutes)

**Q1:** Why pin module versions with git tags instead of pointing to `main`?
<details><summary>Answer</summary>Pointing to <code>main</code> means any commit to the module repo could change your infrastructure unexpectedly. A git tag (<code>?ref=v1.2.0</code>) provides <b>immutable references</b> — you know exactly what code you're deploying. Upgrading is explicit: change the ref, review the diff, test in dev first. Like pinning RPM versions with <code>yum versionlock</code>.</details>

**Q2:** What is the difference between a regular module and a wrapper module?
<details><summary>Answer</summary>A <b>regular module</b> manages a single concern (VPC, compute, IAM). A <b>wrapper module</b> composes multiple regular modules into a higher-level abstraction (e.g., "web-stack" = VPC + firewall + compute). Wrapper modules simplify the consumer's interface — instead of wiring 5 modules together, they call one wrapper with simple inputs. Like a shell function that calls multiple commands.</details>

**Q3:** When would you use a local module source vs a git source?
<details><summary>Answer</summary><b>Local source</b> (<code>../../modules/vpc</code>) during active development — changes are picked up immediately without committing/tagging. <b>Git source</b> (<code>git::https://...?ref=v1.0</code>) for production and shared modules — provides version control and immutability. Switch from local to git once the module is stable and tested.</details>

**Q4:** How do `dynamic` blocks help make modules reusable?
<details><summary>Answer</summary><code>dynamic</code> blocks allow conditional resource blocks based on input variables. For example, VPC flow logs can be enabled only for prod by using <code>dynamic "log_config" { for_each = var.enable_flow_logs ? [1] : [] }</code>. Without dynamic blocks, you'd need separate modules for "vpc with logs" and "vpc without logs". Like using <code>if</code> statements in a shell script to conditionally add config sections.</details>
