# Day 30 — PROJECT: Reusable Network Module

> **Week 5 · Terraform Networking** | 2 hours | europe-west2  
> **Pre-reqs:** Days 25–29 complete — VPC, subnets, firewall, routes, naming modules all built

---

## Part 1 — Concept (30 min)

### 1.1 Project Goal

Combine **all of Week 5's work** into a single, production-ready **network module** that creates a complete VPC networking stack with one module call.

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│  module "network" {                                             │
│    source = "../../modules/network"                             │
│                                                                 │
│    project_id   = "my-project"                                  │
│    project_name = "tap"                                         │
│    env          = "prod"                                        │
│    region       = "europe-west2"                                │
│    subnets      = { ... }                                       │
│    firewall_rules = { ... }                                     │
│    custom_routes  = { ... }                                     │
│  }                                                              │
│                                                                 │
│  Creates:                                                       │
│  ├── VPC (custom mode, REGIONAL routing)                        │
│  ├── Subnets (for_each, dynamic secondary ranges)               │
│  ├── Firewall rules (for_each, deny-all-egress + allow rules)   │
│  ├── Custom routes (for_each, PGA routes)                       │
│  └── Consistent naming (project-env-resource-purpose)           │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 1.2 Architecture Diagram

```
                        ┌──────────────────────────────────────┐
                        │         GCP Project                   │
                        │         (your-gcp-project-id)         │
                        └──────────────┬───────────────────────┘
                                       │
                        ┌──────────────▼───────────────────────┐
                        │      tap-prod-vpc                     │
                        │      routing_mode: REGIONAL           │
                        │      auto_create_subnetworks: false   │
                        └──────────────┬───────────────────────┘
                                       │
            ┌──────────────────────────┼──────────────────────────┐
            │                          │                          │
  ┌─────────▼─────────┐    ┌──────────▼────────┐    ┌───────────▼───────┐
  │ tap-prod-web      │    │ tap-prod-app      │    │ tap-prod-db       │
  │ 10.0.1.0/24       │    │ 10.0.2.0/24       │    │ 10.0.3.0/24       │
  │ europe-west2      │    │ europe-west2      │    │ europe-west2      │
  │ PGA: true         │    │ PGA: true         │    │ PGA: true         │
  │                   │    │ Secondary:        │    │ Flow logs: on     │
  │                   │    │  gke-pods /16     │    │                   │
  │                   │    │  gke-svc  /20     │    │                   │
  └───────────────────┘    └───────────────────┘    └───────────────────┘

  Firewall Rules:
  ┌─────────────────────────────────────────────────────────────────────┐
  │ ✖ deny-all-egress      │ EGRESS │ 0.0.0.0/0    │ pri 1000 │ DENY │
  │ ✔ allow-egress-internal│ EGRESS │ 10.0.0.0/8   │ pri 900  │ ALLOW│
  │ ✔ allow-egress-gapis   │ EGRESS │ 199.36.x.x/30│ pri 900  │ ALLOW│
  │ ✔ allow-iap-ssh        │ INGRESS│ 35.235.x.x/20│ pri 1000 │ ALLOW│
  │ ✔ allow-health-checks  │ INGRESS│ 35.191.x.x/16│ pri 1000 │ ALLOW│
  │ ✔ allow-internal        │ INGRESS│ 10.0.0.0/8   │ pri 1000 │ ALLOW│
  └─────────────────────────────────────────────────────────────────────┘

  Custom Routes:
  ┌─────────────────────────────────────────────────────────────────────┐
  │ restricted-google-apis │ 199.36.153.4/30  │ → default-internet-gw │
  │ private-google-apis    │ 199.36.153.8/30  │ → default-internet-gw │
  └─────────────────────────────────────────────────────────────────────┘
```

### 1.3 Final Directory Structure

```
tf-networking/
├── modules/
│   ├── network/                 ◄── NEW: Composite module
│   │   ├── README.md
│   │   ├── variables.tf
│   │   ├── main.tf
│   │   ├── outputs.tf
│   │   └── versions.tf
│   ├── vpc/                     ◄── Existing from Day 25-26
│   │   ├── variables.tf
│   │   ├── main.tf
│   │   └── outputs.tf
│   ├── firewall/                ◄── Existing from Day 27
│   │   ├── variables.tf
│   │   ├── main.tf
│   │   └── outputs.tf
│   ├── routes/                  ◄── Existing from Day 28
│   │   ├── variables.tf
│   │   ├── main.tf
│   │   └── outputs.tf
│   └── naming/                  ◄── Existing from Day 29
│       ├── variables.tf
│       ├── main.tf
│       └── outputs.tf
└── environments/
    ├── dev/
    │   ├── main.tf
    │   ├── variables.tf
    │   ├── outputs.tf
    │   └── terraform.tfvars
    ├── staging/
    │   ├── main.tf
    │   ├── variables.tf
    │   ├── outputs.tf
    │   └── terraform.tfvars
    └── prod/
        ├── main.tf
        ├── variables.tf
        ├── outputs.tf
        └── terraform.tfvars
```

### 1.4 Composite Module Pattern

```
                          Composite Module
                      ┌────────────────────────┐
                      │    modules/network/     │
                      │                        │
  Caller passes ─────►│  ┌─── module "naming" │
  project, env,       │  │    (naming/*)       │
  subnets, rules      │  │                     │
                      │  ├─── module "vpc"     │
                      │  │    (vpc/*)          │
                      │  │                     │
                      │  ├─── module "firewall"│
                      │  │    (firewall/*)     │
                      │  │                     │
                      │  └─── module "routes"  │
                      │       (routes/*)       │
                      │                        │
  Caller reads  ◄─────│  outputs.tf            │
  vpc_name, subnets,  │  (aggregated outputs)  │
  firewall IDs, etc.  │                        │
                      └────────────────────────┘

  Benefits:
  • ONE module call creates entire networking stack
  • Internal wiring (naming → vpc → firewall → routes) is hidden
  • Caller only provides business-level inputs
  • Child modules can be used independently if needed
```

### 1.5 Design Decisions Checklist

| Decision | Choice | Rationale |
|----------|--------|-----------|
| VPC mode | Custom (`auto_create_subnetworks = false`) | Full CIDR control |
| Routing mode | REGIONAL | Single-region deployment |
| Egress strategy | Deny-all + allow specific | Least privilege |
| IAP access | Allow from `35.235.240.0/20` | Secure SSH without external IPs |
| Health checks | Allow from GCP ranges | Required for load balancing |
| Private Google Access | Enabled on all subnets | VMs don't need external IPs |
| Naming | `project-env-resource-purpose` | Consistent, filterable |
| Labels | On all supporting resources | Billing and org |
| Network tags | Centralised via naming module | No tag mismatches |
| PGA routes | `199.36.153.4/30` + `199.36.153.8/30` | Both restricted and private endpoints |

---

## Part 2 — Hands-On Lab (60 min)

### Lab Objective

Build the composite `network` module and deploy a complete networking stack for the `prod` environment.

### Step 1 — Create the Composite Network Module

```bash
mkdir -p ~/tf-networking/modules/network
```

**`modules/network/versions.tf`**

```hcl
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0.0"
    }
  }
}
```

**`modules/network/variables.tf`**

```hcl
# ──────────────────────────────────────
# Project & Environment
# ──────────────────────────────────────
variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "project_name" {
  description = "Short project name for naming (e.g., tap)"
  type        = string
}

variable "env" {
  description = "Environment: dev, staging, or prod"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.env)
    error_message = "env must be dev, staging, or prod."
  }
}

variable "region" {
  description = "Primary GCP region"
  type        = string
  default     = "europe-west2"
}

variable "team" {
  description = "Team owning the resources"
  type        = string
  default     = "platform"
}

variable "cost_center" {
  description = "Cost center code for billing"
  type        = string
  default     = "cc-0000"
}

# ──────────────────────────────────────
# VPC Configuration
# ──────────────────────────────────────
variable "routing_mode" {
  description = "VPC routing mode: REGIONAL or GLOBAL"
  type        = string
  default     = "REGIONAL"
}

variable "delete_default_routes" {
  description = "Delete default internet route on VPC creation"
  type        = bool
  default     = false
}

# ──────────────────────────────────────
# Subnets
# ──────────────────────────────────────
variable "subnets" {
  description = "Map of subnets to create"
  type = map(object({
    cidr                  = string
    region                = string
    private_google_access = optional(bool, true)
    enable_flow_logs      = optional(bool, false)
    secondary_ranges = optional(list(object({
      name = string
      cidr = string
    })), [])
  }))
}

# ──────────────────────────────────────
# Firewall Rules
# ──────────────────────────────────────
variable "extra_firewall_rules" {
  description = "Additional firewall rules beyond the baseline set"
  type = map(object({
    description        = optional(string, "Managed by Terraform")
    direction          = string
    priority           = optional(number, 1000)
    source_ranges      = optional(list(string), [])
    destination_ranges = optional(list(string), [])
    target_tags        = optional(list(string), [])
    source_tags        = optional(list(string), [])
    action             = string
    rules = list(object({
      protocol = string
      ports    = optional(list(string), [])
    }))
    enable_logging = optional(bool, false)
  }))
  default = {}
}

variable "enable_baseline_firewall" {
  description = "Create baseline firewall rules (deny-egress, allow-iap, allow-hc, allow-internal)"
  type        = bool
  default     = true
}

# ──────────────────────────────────────
# Routes
# ──────────────────────────────────────
variable "custom_routes" {
  description = "Additional custom routes"
  type = map(object({
    description      = optional(string, "Managed by Terraform")
    dest_range       = string
    priority         = optional(number, 1000)
    tags             = optional(list(string), [])
    next_hop_gateway = optional(string, null)
    next_hop_ip      = optional(string, null)
  }))
  default = {}
}

variable "enable_pga_routes" {
  description = "Create routes for Private Google Access"
  type        = bool
  default     = true
}
```

**`modules/network/main.tf`**

```hcl
# ══════════════════════════════════════════════════════════
# COMPOSITE NETWORK MODULE
# Creates: Naming + VPC + Subnets + Firewall + Routes
# ══════════════════════════════════════════════════════════

# ──────────────────────────────────────
# 1. Naming Convention
# ──────────────────────────────────────
module "naming" {
  source = "../naming"

  project     = var.project_name
  env         = var.env
  region      = var.region
  team        = var.team
  cost_center = var.cost_center
}

locals {
  prefix = module.naming.prefix
  tags   = module.naming.network_tags
  labels = module.naming.common_labels
}

# ──────────────────────────────────────
# 2. VPC + Subnets
# ──────────────────────────────────────
module "vpc" {
  source = "../vpc"

  vpc_name              = "${local.prefix}-vpc"
  project_id            = var.project_id
  routing_mode          = var.routing_mode
  auto_create_subnetworks = false
  delete_default_routes = var.delete_default_routes
  description           = "${local.prefix} VPC - managed by Terraform"
  subnets               = var.subnets
}

# ──────────────────────────────────────
# 3. Baseline Firewall Rules
# ──────────────────────────────────────
locals {
  baseline_firewall_rules = var.enable_baseline_firewall ? {
    deny-all-egress = {
      description        = "Deny all egress by default"
      direction          = "EGRESS"
      priority           = 1000
      action             = "deny"
      destination_ranges = ["0.0.0.0/0"]
      rules              = [{ protocol = "all" }]
      enable_logging     = true
    }

    allow-egress-internal = {
      description        = "Allow egress to internal subnets"
      direction          = "EGRESS"
      priority           = 900
      action             = "allow"
      destination_ranges = ["10.0.0.0/8"]
      rules              = [{ protocol = "all" }]
    }

    allow-egress-google-apis = {
      description        = "Allow egress to Google APIs (PGA)"
      direction          = "EGRESS"
      priority           = 900
      action             = "allow"
      destination_ranges = ["199.36.153.8/30"]
      rules              = [{ protocol = "tcp", ports = ["443"] }]
    }

    allow-iap-ssh = {
      description   = "Allow SSH from Identity-Aware Proxy"
      direction     = "INGRESS"
      action        = "allow"
      source_ranges = ["35.235.240.0/20"]
      target_tags   = [local.tags.allow_iap]
      rules         = [{ protocol = "tcp", ports = ["22"] }]
    }

    allow-health-checks = {
      description   = "Allow Google health check probes"
      direction     = "INGRESS"
      action        = "allow"
      source_ranges = ["35.191.0.0/16", "130.211.0.0/22"]
      target_tags   = [local.tags.allow_hc]
      rules         = [{ protocol = "tcp", ports = ["80", "443", "8080"] }]
    }

    allow-internal = {
      description   = "Allow all internal traffic"
      direction     = "INGRESS"
      action        = "allow"
      source_ranges = ["10.0.0.0/8"]
      rules = [
        { protocol = "tcp" },
        { protocol = "udp" },
        { protocol = "icmp" }
      ]
    }
  } : {}

  # Merge baseline + extra rules
  all_firewall_rules = merge(local.baseline_firewall_rules, var.extra_firewall_rules)
}

module "firewall" {
  source = "../firewall"

  project_id        = var.project_id
  network_name      = module.vpc.network_name
  network_self_link = module.vpc.network_self_link
  firewall_rules    = local.all_firewall_rules
}

# ──────────────────────────────────────
# 4. Routes (PGA + custom)
# ──────────────────────────────────────
locals {
  pga_routes = var.enable_pga_routes ? {
    restricted-google-apis = {
      description      = "Route to restricted.googleapis.com"
      dest_range       = "199.36.153.4/30"
      priority         = 900
      next_hop_gateway = "default-internet-gateway"
    }
    private-google-apis = {
      description      = "Route to private.googleapis.com"
      dest_range       = "199.36.153.8/30"
      priority         = 900
      next_hop_gateway = "default-internet-gateway"
    }
  } : {}

  all_routes = merge(local.pga_routes, var.custom_routes)
}

module "routes" {
  source = "../routes"

  project_id   = var.project_id
  network_name = module.vpc.network_name
  routes       = local.all_routes
}
```

**`modules/network/outputs.tf`**

```hcl
# ──────────────────────────────────────
# Naming
# ──────────────────────────────────────
output "prefix" {
  description = "Naming prefix (project-env)"
  value       = local.prefix
}

output "common_labels" {
  description = "Common labels for all resources"
  value       = local.labels
}

output "network_tags" {
  description = "Standardised network tags"
  value       = local.tags
}

# ──────────────────────────────────────
# VPC
# ──────────────────────────────────────
output "network_name" {
  description = "VPC network name"
  value       = module.vpc.network_name
}

output "network_id" {
  description = "VPC network ID"
  value       = module.vpc.network_id
}

output "network_self_link" {
  description = "VPC network self_link"
  value       = module.vpc.network_self_link
}

# ──────────────────────────────────────
# Subnets
# ──────────────────────────────────────
output "subnet_ids" {
  description = "Map of subnet name to ID"
  value       = module.vpc.subnet_ids
}

output "subnet_self_links" {
  description = "Map of subnet name to self_link"
  value       = module.vpc.subnet_self_links
}

output "subnet_cidrs" {
  description = "Map of subnet name to CIDR"
  value       = module.vpc.subnet_cidrs
}

output "subnet_regions" {
  description = "Map of subnet name to region"
  value       = module.vpc.subnet_regions
}

# ──────────────────────────────────────
# Firewall
# ──────────────────────────────────────
output "firewall_allow_rule_ids" {
  description = "Map of allow rule name to ID"
  value       = module.firewall.allow_rule_ids
}

output "firewall_deny_rule_ids" {
  description = "Map of deny rule name to ID"
  value       = module.firewall.deny_rule_ids
}

# ──────────────────────────────────────
# Routes
# ──────────────────────────────────────
output "route_ids" {
  description = "Map of route name to ID"
  value       = module.routes.route_ids
}
```

### Step 2 — Create the Module README

**`modules/network/README.md`**

```markdown
# Network Module

Production-ready composite module that creates a complete GCP networking
stack: VPC, subnets, firewall rules, and routes with consistent naming
and labelling.

## Usage

```hcl
module "network" {
  source = "../../modules/network"

  project_id   = "my-gcp-project"
  project_name = "tap"
  env          = "prod"
  region       = "europe-west2"
  team         = "platform"
  cost_center  = "cc-5678"

  subnets = {
    web = {
      cidr   = "10.0.1.0/24"
      region = "europe-west2"
    }
    app = {
      cidr   = "10.0.2.0/24"
      region = "europe-west2"
      secondary_ranges = [
        { name = "gke-pods",     cidr = "10.1.0.0/16" },
        { name = "gke-services", cidr = "10.2.0.0/20" }
      ]
    }
  }
}
```

## What It Creates

| Resource | Count | Description |
|----------|-------|-------------|
| VPC | 1 | Custom-mode VPC |
| Subnets | N (for_each) | One per map entry |
| Firewall rules | 6 baseline + N extra | Least-privilege defaults |
| Routes | 2 PGA + N custom | Private Google Access routes |

## Inputs

| Name | Type | Default | Required |
|------|------|---------|----------|
| project_id | string | | yes |
| project_name | string | | yes |
| env | string | | yes |
| region | string | europe-west2 | no |
| subnets | map(object) | | yes |
| extra_firewall_rules | map(object) | {} | no |
| custom_routes | map(object) | {} | no |
| enable_baseline_firewall | bool | true | no |
| enable_pga_routes | bool | true | no |

## Outputs

| Name | Description |
|------|-------------|
| network_name | VPC name |
| network_self_link | VPC self_link |
| subnet_ids | Map of subnet name → ID |
| subnet_self_links | Map of subnet name → self_link |
| common_labels | Labels to apply to other resources |
| network_tags | Standardised network tags |
```

### Step 3 — Create the Production Environment

```bash
mkdir -p ~/tf-networking/environments/prod
```

**`environments/prod/variables.tf`**

```hcl
variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "europe-west2"
}
```

**`environments/prod/main.tf`**

```hcl
terraform {
  required_version = ">= 1.5.0"

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

# ══════════════════════════════════════
# PRODUCTION NETWORK — Single module call
# ══════════════════════════════════════
module "network" {
  source = "../../modules/network"

  # Identity
  project_id   = var.project_id
  project_name = "tap"
  env          = "prod"
  region       = var.region
  team         = "platform"
  cost_center  = "cc-5678"

  # VPC
  routing_mode          = "REGIONAL"
  delete_default_routes = false

  # Subnets
  subnets = {
    web = {
      cidr                  = "10.0.1.0/24"
      region                = var.region
      private_google_access = true
      enable_flow_logs      = true
    }

    app = {
      cidr                  = "10.0.2.0/24"
      region                = var.region
      private_google_access = true
      enable_flow_logs      = true
      secondary_ranges = [
        { name = "gke-pods",      cidr = "10.1.0.0/16" },
        { name = "gke-services",  cidr = "10.2.0.0/20" }
      ]
    }

    db = {
      cidr                  = "10.0.3.0/24"
      region                = var.region
      private_google_access = true
      enable_flow_logs      = true
    }

    mgmt = {
      cidr                  = "10.0.10.0/24"
      region                = var.region
      private_google_access = true
      enable_flow_logs      = true
    }
  }

  # Baseline firewall (deny-egress, allow-iap, allow-hc, allow-internal)
  enable_baseline_firewall = true

  # Additional firewall rules for production
  extra_firewall_rules = {
    allow-web-lb = {
      description   = "Allow HTTP/HTTPS from load balancer to web tier"
      direction     = "INGRESS"
      action        = "allow"
      source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
      target_tags   = ["tap-prod-web"]
      rules = [
        { protocol = "tcp", ports = ["80", "443"] }
      ]
    }

    allow-app-from-web = {
      description = "Allow web tier to reach app tier on port 8080"
      direction   = "INGRESS"
      action      = "allow"
      source_tags = ["tap-prod-web"]
      target_tags = ["tap-prod-app"]
      rules = [
        { protocol = "tcp", ports = ["8080"] }
      ]
    }

    allow-db-from-app = {
      description = "Allow app tier to reach db tier on port 5432"
      direction   = "INGRESS"
      action      = "allow"
      source_tags = ["tap-prod-app"]
      target_tags = ["tap-prod-db"]
      rules = [
        { protocol = "tcp", ports = ["5432"] }
      ]
    }
  }

  # PGA routes (default enabled)
  enable_pga_routes = true

  # Additional custom routes
  custom_routes = {
    onprem-datacenter = {
      description = "Route to on-prem datacenter via VPN"
      dest_range  = "192.168.0.0/16"
      priority    = 800
      next_hop_ip = "10.0.10.10"
    }
  }
}
```

**`environments/prod/outputs.tf`**

```hcl
# ──────────────────────────────────────
# Network Outputs
# ──────────────────────────────────────
output "vpc_name" {
  value = module.network.network_name
}

output "vpc_self_link" {
  value = module.network.network_self_link
}

output "subnet_ids" {
  value = module.network.subnet_ids
}

output "subnet_cidrs" {
  value = module.network.subnet_cidrs
}

output "common_labels" {
  value = module.network.common_labels
}

output "network_tags" {
  value = module.network.network_tags
}

output "firewall_allow_rules" {
  value = module.network.firewall_allow_rule_ids
}

output "firewall_deny_rules" {
  value = module.network.firewall_deny_rule_ids
}

output "route_ids" {
  value = module.network.route_ids
}
```

**`environments/prod/terraform.tfvars`**

```hcl
project_id = "your-gcp-project-id"
region     = "europe-west2"
```

### Step 4 — Deploy the Production Network

```bash
cd ~/tf-networking/environments/prod

# Initialise — discovers all nested modules
terraform init

# Validate configuration
terraform validate

# Plan — review carefully!
terraform plan

# Expected resource count:
#   1 VPC
#   4 subnets (web, app, db, mgmt)
#   9 firewall rules (6 baseline + 3 extra)
#   3 routes (2 PGA + 1 custom)
# ─────────
#   17 resources total

# Apply
terraform apply
```

### Step 5 — Comprehensive Verification

```bash
PROJECT="your-gcp-project-id"

echo "=== VPC ==="
gcloud compute networks describe tap-prod-vpc \
  --project=$PROJECT \
  --format="table(name, routingConfig.routingMode, autoCreateSubnetworks)"

echo "=== Subnets ==="
gcloud compute networks subnets list \
  --network=tap-prod-vpc \
  --project=$PROJECT \
  --format="table(name, region, ipCidrRange, privateIpGoogleAccess)"

echo "=== Firewall Rules ==="
gcloud compute firewall-rules list \
  --filter="network:tap-prod-vpc" \
  --project=$PROJECT \
  --sort-by=priority \
  --format="table(name, direction, priority, sourceRanges.list():label=SRC, allowed[].map().firewall_rule().list():label=ALLOW, denied[].map().firewall_rule().list():label=DENY)"

echo "=== Custom Routes ==="
gcloud compute routes list \
  --filter="network:tap-prod-vpc AND name~tap-prod" \
  --project=$PROJECT \
  --format="table(name, destRange, priority, nextHopGateway.basename(), nextHopIp)"

echo "=== Terraform Outputs ==="
terraform output
```

### Step 6 — Verify Module Reusability (Staging)

Create a minimal staging environment to prove the module works for another env:

```bash
mkdir -p ~/tf-networking/environments/staging
```

**`environments/staging/main.tf`** (minimal example):

```hcl
terraform {
  required_version = ">= 1.5.0"
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

module "network" {
  source = "../../modules/network"

  project_id   = var.project_id
  project_name = "tap"
  env          = "staging"
  region       = "europe-west2"
  team         = "platform"
  cost_center  = "cc-9999"

  subnets = {
    web = { cidr = "10.10.1.0/24", region = "europe-west2" }
    app = { cidr = "10.10.2.0/24", region = "europe-west2" }
    db  = { cidr = "10.10.3.0/24", region = "europe-west2" }
  }
}

output "vpc_name"    { value = module.network.network_name }
output "subnet_cidrs" { value = module.network.subnet_cidrs }
```

```bash
cd ~/tf-networking/environments/staging
terraform init
terraform plan -var="project_id=your-gcp-project-id"
# Don't apply — just verify the plan looks correct
```

### Step 7 — Run the Checklist

| # | Check | Command | Expected |
|---|-------|---------|----------|
| 1 | VPC exists | `gcloud compute networks describe tap-prod-vpc` | Custom mode, REGIONAL |
| 2 | 4 subnets | `gcloud compute networks subnets list --network=tap-prod-vpc` | web, app, db, mgmt |
| 3 | PGA enabled | Same as above — check `privateIpGoogleAccess` | `True` on all |
| 4 | Secondary ranges | `describe tap-prod-app --region=europe-west2` | gke-pods, gke-services |
| 5 | Deny-egress | `describe tap-prod-vpc-deny-all-egress` | Priority 1000, deny all |
| 6 | IAP SSH | `describe tap-prod-vpc-allow-iap-ssh` | Source 35.235.240.0/20 |
| 7 | PGA routes | `gcloud compute routes list --filter="name~google-apis"` | 2 routes, priority 900 |
| 8 | Naming prefix | `terraform output` | All names start with `tap-prod` |
| 9 | Labels output | `terraform output common_labels` | env=prod, team=platform |
| 10 | State count | `terraform state list \| wc -l` | ~17 resources |

### Step 8 — Cleanup

```bash
# Destroy production
cd ~/tf-networking/environments/prod
terraform destroy
# Type 'yes'

# Destroy staging (if applied)
cd ~/tf-networking/environments/staging
terraform destroy
# Type 'yes'

# Verify nothing remains
gcloud compute networks list --project=your-gcp-project-id --filter="name~tap"
```

---

## Part 3 — Revision (15 min)

### Key Concepts

- A **composite module** calls child modules to create a complete stack from one call
- The `network` module wires: naming → vpc → firewall → routes internally
- Callers provide business-level inputs (env, subnets, rules); internal wiring is hidden
- `merge()` combines baseline and extra firewall rules: `merge(local.baseline, var.extra)`
- Conditional resources via `var.enable_baseline_firewall ? { ... } : {}`
- `for_each` on every resource type ensures safe add/remove without index shifting
- The same module serves dev, staging, and prod — only variables differ
- `terraform init` must rediscover modules after adding new child module references
- `terraform state list` shows the full resource hierarchy: `module.network.module.vpc.google_compute_network.vpc`

### Final Command Reference

```bash
# Full lifecycle
terraform init                  # Discover modules + providers
terraform validate              # Syntax + type checks
terraform fmt -recursive        # Format all .tf files
terraform plan                  # Preview changes
terraform apply                 # Create resources
terraform output                # Show outputs
terraform state list            # List all managed resources
terraform destroy               # Tear down everything

# Module-specific
terraform init -upgrade         # Upgrade providers + re-discover modules
terraform plan -target='module.network.module.vpc'  # Plan only VPC
terraform state show 'module.network.module.vpc.google_compute_network.vpc'

# gcloud verification
gcloud compute networks describe VPC_NAME
gcloud compute networks subnets list --network=VPC_NAME
gcloud compute firewall-rules list --filter="network:VPC_NAME"
gcloud compute routes list --filter="network:VPC_NAME"
```

### Week 5 Summary

| Day | Topic | Key Outcome |
|-----|-------|-------------|
| 25 | VPC Module | Reusable module with variables, main, outputs |
| 26 | Subnet Patterns | for_each + dynamic blocks for multi-subnet |
| 27 | Firewall Patterns | Least-privilege deny+allow with for_each |
| 28 | Routes | Custom routes via Terraform, PGA routes |
| 29 | Naming/Labels/Tags | Consistent naming via locals, centralised tags |
| 30 | Project | Composite network module — production ready |

---

## Part 4 — Quiz (15 min)

**Question 1:** The composite network module calls 4 child modules. If `module "naming"` changes an output value, which other modules are potentially affected? How does Terraform handle this?

<details>
<summary>Show Answer</summary>

**All other modules are potentially affected:**

```
module "naming"
  ├── local.prefix → module "vpc" (vpc_name)
  ├── local.tags   → module "firewall" (target_tags in baseline rules)
  └── local.labels → outputs (common_labels)
```

**How Terraform handles it:**

1. Terraform builds a **dependency graph** from references
2. If `module.naming` output changes, Terraform detects that `local.prefix` changed
3. All resources using `local.prefix` in their `name` attribute are marked for **update** or **replacement**
4. Naming changes in GCP resources usually require **replacement** (destroy + create) because `name` is a ForceNew field

**This is why naming conventions should be decided early** — changing them on existing infrastructure triggers mass resource recreation.

</details>

---

**Question 2:** A new team member wants to add a firewall rule allowing HTTPS from a partner IP `203.0.113.50/32`. Using the composite module, where would they add this and what would the code look like?

<details>
<summary>Show Answer</summary>

They would add it to the `extra_firewall_rules` variable in the environment's `main.tf`:

```hcl
module "network" {
  source = "../../modules/network"
  # ... existing config ...

  extra_firewall_rules = {
    # ... existing extra rules ...

    allow-partner-https = {
      description   = "Allow HTTPS from partner network"
      direction     = "INGRESS"
      action        = "allow"
      priority      = 1000
      source_ranges = ["203.0.113.50/32"]
      target_tags   = ["tap-prod-web"]
      rules = [
        { protocol = "tcp", ports = ["443"] }
      ]
      enable_logging = true
    }
  }
}
```

The rule gets merged with the baseline rules via `merge()` in the composite module's `main.tf`. No changes needed to any module code — just the calling configuration.

</details>

---

**Question 3:** You run `terraform plan` on the production environment and see `17 to add, 0 to change, 0 to destroy`. But `terraform state list` after apply shows 17 resources. If you then run `terraform plan` again, what should you see?

<details>
<summary>Show Answer</summary>

**You should see: `No changes. Your infrastructure matches the configuration.`**

This is called **idempotency** — running `terraform apply` again with no config changes produces no changes. Terraform:

1. Reads the state file (lists all 17 resources)
2. Reads the GCP API (actual state of those resources)
3. Compares desired config vs actual state
4. Finds no differences → no changes needed

If you see changes on the second run, it indicates:

- **Drift** — someone changed a resource outside Terraform
- **Non-deterministic values** — using `timestamp()` or random values
- **Provider bug** — the provider reports a diff that doesn't exist
- **API normalisation** — GCP returns a different format than what you wrote

In a well-written module, the second plan should always be clean.

</details>

---

**Question 4:** The staging environment uses `10.10.x.0/24` CIDRs and production uses `10.0.x.0/24`. Both are in the same GCP project. You want to peer these VPCs. What networking constraint must you verify first?

<details>
<summary>Show Answer</summary>

**CIDR ranges must NOT overlap** between peered VPCs.

VPC peering exchanges routes between the two VPCs. If CIDRs overlap, GCP will reject the peering request.

| VPC | Subnets | Status |
|-----|---------|--------|
| tap-prod-vpc | 10.0.1.0/24, 10.0.2.0/24, 10.0.3.0/24 | ✅ |
| tap-staging-vpc | 10.10.1.0/24, 10.10.2.0/24, 10.10.3.0/24 | ✅ |

These don't overlap → peering is possible. ✅

But also check **secondary ranges**:

| VPC | Secondary | Conflict? |
|-----|-----------|-----------|
| tap-prod-vpc | 10.1.0.0/16 (pods) | |
| tap-staging-vpc | 10.1.0.0/16 (pods) | ❌ **OVERLAP!** |

If staging also uses `10.1.0.0/16` for GKE pods, peering will fail or routing will be ambiguous. Each environment needs a **unique CIDR plan** across all subnets and secondary ranges.

**Best practice:** Plan your entire CIDR allocation upfront using a spreadsheet or IPAM tool before creating any infrastructure.

</details>
