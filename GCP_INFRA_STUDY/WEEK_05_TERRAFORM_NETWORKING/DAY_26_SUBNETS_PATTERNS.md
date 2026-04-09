# Day 26 — Multi-Subnet Patterns with for_each and Dynamic Blocks

> **Week 5 · Terraform Networking** | 2 hours | europe-west2  
> **Pre-reqs:** Day 25 VPC module complete, familiarity with Terraform maps and loops

---

## Part 1 — Concept (30 min)

### 1.1 Subnet Planning — Why It Matters

```
                    10.0.0.0/16 (VPC supernet)
                           │
          ┌────────────────┼────────────────┐
          │                │                │
   10.0.1.0/24      10.0.2.0/24      10.0.3.0/24
   web-subnet       app-subnet       db-subnet
   europe-west2     europe-west2     europe-west2
          │                │                │
    ┌─────┴─────┐    ┌────┴────┐     ┌────┴────┐
    │ Secondary │    │Secondary│     │  No     │
    │ ranges    │    │ranges   │     │secondary│
    │ (GKE)     │    │(GKE)    │     │         │
    └───────────┘    └─────────┘     └─────────┘
```

### 1.2 Subnet CIDR Planning Table

| Subnet | CIDR | Usable IPs | Purpose | Secondary Ranges |
|--------|------|-----------|---------|-----------------|
| web | `10.0.1.0/24` | 251 | Public-facing load balancers | None |
| app | `10.0.2.0/24` | 251 | Application tier | pods: `10.1.0.0/16`, services: `10.2.0.0/20` |
| db | `10.0.3.0/24` | 251 | Databases (no external access) | None |
| gke-nodes | `10.0.4.0/22` | 1019 | GKE node pool | pods: `10.4.0.0/14`, services: `10.8.0.0/20` |

> **Rule of thumb:** Reserve `/14` for pods (~250K IPs) and `/20` for services (~4K IPs) per GKE cluster.

### 1.3 The `google_compute_subnetwork` Resource

```
┌──────────────────────────────────────────────────┐
│         google_compute_subnetwork                │
│                                                  │
│  name ───────────────────► Subnet name           │
│  network ────────────────► VPC self_link          │
│  ip_cidr_range ──────────► Primary CIDR           │
│  region ─────────────────► e.g. europe-west2      │
│  private_ip_google_access ► true = PGA enabled    │
│                                                  │
│  secondary_ip_range {      ◄── Repeatable block  │
│    range_name              │                     │
│    ip_cidr_range           │                     │
│  }                         │                     │
│                                                  │
│  log_config {              ◄── VPC Flow Logs     │
│    aggregation_interval    │                     │
│    flow_sampling           │                     │
│  }                         │                     │
└──────────────────────────────────────────────────┘
```

### 1.4 for_each vs count

| Feature | `count` | `for_each` |
|---------|---------|------------|
| Index type | Numeric (`count.index`) | String key (`each.key`) |
| Resource address | `resource[0]`, `resource[1]` | `resource["web"]`, `resource["app"]` |
| Delete middle item | **Shifts** all indices → recreation | Removes **only** that key |
| Best for | Identical copies | Named, distinct resources |

```
count (fragile)                     for_each (stable)
───────────────                     ──────────────────
subnets[0] = "web"                  subnets["web"]  = { cidr = "10.0.1.0/24" }
subnets[1] = "app"   ← delete      subnets["app"]  = { cidr = "10.0.2.0/24" }
subnets[2] = "db"    ← becomes [1] subnets["db"]   = { cidr = "10.0.3.0/24" }
                      ↑ RECREATED!                    ↑ Only "app" destroyed
```

### 1.5 Dynamic Blocks for Secondary Ranges

When a subnet may or may not have secondary ranges, use a `dynamic` block:

```
┌───────────────────────────────────────────────────────┐
│  dynamic "secondary_ip_range" {                       │
│    for_each = lookup(each.value, "secondary_ranges",  │
│                      [])                              │
│    content {                                          │
│      range_name    = secondary_ip_range.value.name    │
│      ip_cidr_range = secondary_ip_range.value.cidr    │
│    }                                                  │
│  }                                                    │
│                                                       │
│  If secondary_ranges = [] → block is omitted          │
│  If secondary_ranges has items → one block per item   │
└───────────────────────────────────────────────────────┘
```

### 1.6 Private Google Access (PGA)

```
  VM (no external IP)                  Google APIs
  ┌─────────┐                         ┌──────────┐
  │ 10.0.2.5│───── PGA enabled ──────►│ GCS, BQ  │
  │         │     (internal route)     │ Pub/Sub  │
  │         │                          │ etc.     │
  └─────────┘                         └──────────┘

  Without PGA: VM needs a NAT or external IP to reach Google APIs
  With PGA:    Traffic stays on Google's internal network
```

**Best practice:** Enable PGA on every subnet (`private_ip_google_access = true`).

---

## Part 2 — Hands-On Lab (60 min)

### Lab Objective

Extend the Day 25 VPC module to accept a map of subnets and create them using `for_each` with dynamic secondary ranges.

### Step 1 — Update Module Variables

**`modules/vpc/variables.tf`** — Add the subnets variable:

```hcl
variable "vpc_name" {
  description = "Name of the VPC network"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,61}[a-z0-9]$", var.vpc_name))
    error_message = "VPC name must be lowercase, start with a letter, and be 3-63 characters."
  }
}

variable "routing_mode" {
  description = "The network routing mode (REGIONAL or GLOBAL)"
  type        = string
  default     = "REGIONAL"
}

variable "auto_create_subnetworks" {
  description = "If true, creates subnets automatically in auto mode"
  type        = bool
  default     = false
}

variable "delete_default_routes" {
  description = "If true, delete default routes on VPC creation"
  type        = bool
  default     = false
}

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "description" {
  description = "Description for the VPC network"
  type        = string
  default     = "Managed by Terraform"
}

variable "subnets" {
  description = "Map of subnets to create. Key = subnet name suffix."
  type = map(object({
    cidr                    = string
    region                  = string
    private_google_access   = optional(bool, true)
    enable_flow_logs        = optional(bool, false)
    secondary_ranges        = optional(list(object({
      name = string
      cidr = string
    })), [])
  }))
  default = {}
}
```

### Step 2 — Update Module Main

**`modules/vpc/main.tf`** — Add the subnet resource:

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

# ──────────────────────────────────────
# VPC Network
# ──────────────────────────────────────
resource "google_compute_network" "vpc" {
  name                            = var.vpc_name
  project                         = var.project_id
  auto_create_subnetworks         = var.auto_create_subnetworks
  routing_mode                    = var.routing_mode
  delete_default_routes_on_create = var.delete_default_routes
  description                     = var.description
}

# ──────────────────────────────────────
# Subnets (for_each over map)
# ──────────────────────────────────────
resource "google_compute_subnetwork" "subnets" {
  for_each = var.subnets

  name                     = "${var.vpc_name}-${each.key}"
  project                  = var.project_id
  network                  = google_compute_network.vpc.self_link
  ip_cidr_range            = each.value.cidr
  region                   = each.value.region
  private_ip_google_access = each.value.private_google_access

  # Dynamic secondary ranges — only created if the list is non-empty
  dynamic "secondary_ip_range" {
    for_each = each.value.secondary_ranges
    content {
      range_name    = secondary_ip_range.value.name
      ip_cidr_range = secondary_ip_range.value.cidr
    }
  }

  # Optional VPC Flow Logs
  dynamic "log_config" {
    for_each = each.value.enable_flow_logs ? [1] : []
    content {
      aggregation_interval = "INTERVAL_5_SEC"
      flow_sampling        = 0.5
      metadata             = "INCLUDE_ALL_METADATA"
    }
  }
}
```

### Step 3 — Update Module Outputs

**`modules/vpc/outputs.tf`**:

```hcl
output "network_name" {
  description = "The name of the VPC network"
  value       = google_compute_network.vpc.name
}

output "network_id" {
  description = "The ID of the VPC network"
  value       = google_compute_network.vpc.id
}

output "network_self_link" {
  description = "The self_link of the VPC network"
  value       = google_compute_network.vpc.self_link
}

output "subnet_ids" {
  description = "Map of subnet name to subnet ID"
  value = {
    for k, v in google_compute_subnetwork.subnets : k => v.id
  }
}

output "subnet_self_links" {
  description = "Map of subnet name to self_link"
  value = {
    for k, v in google_compute_subnetwork.subnets : k => v.self_link
  }
}

output "subnet_cidrs" {
  description = "Map of subnet name to CIDR"
  value = {
    for k, v in google_compute_subnetwork.subnets : k => v.ip_cidr_range
  }
}

output "subnet_regions" {
  description = "Map of subnet name to region"
  value = {
    for k, v in google_compute_subnetwork.subnets : k => v.region
  }
}
```

### Step 4 — Call the Module with Subnets

**`environments/dev/main.tf`**:

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

module "vpc" {
  source = "../../modules/vpc"

  vpc_name     = "dev-vpc"
  project_id   = var.project_id
  routing_mode = "REGIONAL"

  auto_create_subnetworks = false
  delete_default_routes   = false
  description             = "Development VPC - managed by Terraform"

  subnets = {
    web = {
      cidr                  = "10.0.1.0/24"
      region                = var.region
      private_google_access = true
      enable_flow_logs      = false
    }

    app = {
      cidr                  = "10.0.2.0/24"
      region                = var.region
      private_google_access = true
      enable_flow_logs      = true
      secondary_ranges = [
        {
          name = "gke-pods"
          cidr = "10.1.0.0/16"
        },
        {
          name = "gke-services"
          cidr = "10.2.0.0/20"
        }
      ]
    }

    db = {
      cidr                  = "10.0.3.0/24"
      region                = var.region
      private_google_access = true
      enable_flow_logs      = true
    }
  }
}
```

**`environments/dev/outputs.tf`**:

```hcl
output "vpc_name" {
  value = module.vpc.network_name
}

output "vpc_self_link" {
  value = module.vpc.network_self_link
}

output "subnet_ids" {
  value = module.vpc.subnet_ids
}

output "subnet_cidrs" {
  value = module.vpc.subnet_cidrs
}
```

### Step 5 — Deploy and Validate

```bash
cd ~/tf-networking/environments/dev

terraform init -upgrade
terraform validate
terraform plan

# Review the plan — you should see:
#   + google_compute_network.vpc
#   + google_compute_subnetwork.subnets["web"]
#   + google_compute_subnetwork.subnets["app"]
#   + google_compute_subnetwork.subnets["db"]

terraform apply
```

### Step 6 — Verify Subnets

```bash
# List subnets in the VPC
gcloud compute networks subnets list \
  --network=dev-vpc \
  --project=your-gcp-project-id \
  --format="table(name, region, ipCidrRange, privateIpGoogleAccess)"

# Check secondary ranges on the app subnet
gcloud compute networks subnets describe dev-vpc-app \
  --region=europe-west2 \
  --project=your-gcp-project-id \
  --format="yaml(secondaryIpRanges)"

# Terraform outputs
terraform output subnet_cidrs
terraform output subnet_ids
```

### Step 7 — Experiment: Remove a Subnet

```bash
# Comment out the "web" subnet in main.tf, then:
terraform plan
# Observe: only subnets["web"] is marked for destruction — app and db are untouched
# This is the power of for_each over count!

# Revert the change to restore "web"
terraform apply
```

### Step 8 — Cleanup

```bash
terraform destroy
```

---

## Part 3 — Revision (15 min)

### Key Concepts

- Use `for_each` (not `count`) when creating named resources — deletion of one item doesn't shift others
- `google_compute_subnetwork` requires: `name`, `network`, `ip_cidr_range`, `region`
- `private_ip_google_access = true` lets VMs without external IPs reach Google APIs
- `dynamic` blocks conditionally generate repeated nested blocks (secondary_ip_range, log_config)
- Secondary ranges are needed for GKE: one for pods, one for services
- Plan CIDRs carefully — once a subnet is in use, resizing is destructive
- Reserve `/14` for pods (~250K IPs) and `/20` for services (~4K) per GKE cluster
- VPC Flow Logs (`log_config`) capture network telemetry — enable on sensitive subnets
- `optional()` type constraint (Terraform 1.3+) lets you provide defaults for object attributes
- Module outputs use `for` expressions to create maps from `for_each` resources

### Essential Commands

```bash
# List subnets in a VPC
gcloud compute networks subnets list --network=NETWORK_NAME

# Describe a specific subnet
gcloud compute networks subnets describe SUBNET_NAME --region=REGION

# Check secondary ranges
gcloud compute networks subnets describe SUBNET --region=REGION --format="yaml(secondaryIpRanges)"

# Terraform state for specific subnet
terraform state show 'module.vpc.google_compute_subnetwork.subnets["app"]'

# Terraform console — test expressions interactively
terraform console
> var.subnets
> { for k, v in var.subnets : k => v.cidr }
```

### for_each Pattern Cheat Sheet

```hcl
# Basic for_each with map
resource "x" "y" {
  for_each = var.my_map
  name     = each.key
  value    = each.value.some_attr
}

# for_each with set of strings
resource "x" "y" {
  for_each = toset(["a", "b", "c"])
  name     = each.value
}

# Output from for_each resource
output "ids" {
  value = { for k, v in x.y : k => v.id }
}
```

---

## Part 4 — Quiz (15 min)

**Question 1:** You have 3 subnets created with `count`. You delete the middle subnet (index 1). What happens to index 2?

<details>
<summary>Show Answer</summary>

With `count`, resources are addressed by numeric index: `[0]`, `[1]`, `[2]`. When you delete index 1:

1. What was `[2]` becomes `[1]`
2. Terraform sees `[1]` (was db) now differs from the old `[1]` (was app)
3. **Terraform destroys and recreates** the shifted resource

This is why `for_each` is preferred — it uses string keys (`["web"]`, `["app"]`, `["db"]`), so deleting `"app"` only affects that one resource. The others remain untouched.

</details>

---

**Question 2:** What does `private_ip_google_access = true` do, and when is it essential?

<details>
<summary>Show Answer</summary>

Private Google Access (PGA) allows VMs with **only internal IP addresses** to reach Google APIs and services (Cloud Storage, BigQuery, Pub/Sub, etc.) via internal routes.

**Essential when:**
- VMs have no external IP (best practice for security)
- You use Cloud NAT for general internet but want Google API traffic to stay on Google's backbone
- GKE nodes need to pull container images from `gcr.io` / `pkg.dev`

**Without PGA:** VMs with no external IP cannot reach `*.googleapis.com` at all — even with Cloud NAT, which handles general internet egress.

**Best practice:** Enable PGA on **every** subnet by default.

</details>

---

**Question 3:** In the dynamic block below, what happens when `each.value.secondary_ranges` is an empty list?

```hcl
dynamic "secondary_ip_range" {
  for_each = each.value.secondary_ranges
  content {
    range_name    = secondary_ip_range.value.name
    ip_cidr_range = secondary_ip_range.value.cidr
  }
}
```

<details>
<summary>Show Answer</summary>

When `each.value.secondary_ranges` is `[]` (empty list):

- The `for_each` iterates over **zero** items
- The `dynamic` block generates **zero** `secondary_ip_range` blocks
- The subnet is created with **no secondary ranges**

This is the power of `dynamic` — it conditionally generates nested blocks. The alternative would be two separate resource definitions (one with, one without secondary ranges), which is verbose and error-prone.

Note: The iterator inside `content` is named after the dynamic block label (`secondary_ip_range`), not `each` — `each` refers to the outer `for_each` on the resource.

</details>

---

**Question 4:** Your team asks for a new `staging` environment that uses the same subnets but with different CIDRs (`10.10.x.0/24`). How would you do this without duplicating the module?

<details>
<summary>Show Answer</summary>

Create a new environment directory and call the same module with different variables:

```
environments/
├── dev/
│   └── main.tf         # subnets with 10.0.x.0/24
└── staging/
    ├── main.tf          # subnets with 10.10.x.0/24
    ├── variables.tf
    └── terraform.tfvars
```

**`environments/staging/main.tf`:**

```hcl
module "vpc" {
  source = "../../modules/vpc"

  vpc_name   = "staging-vpc"
  project_id = var.project_id

  subnets = {
    web = { cidr = "10.10.1.0/24", region = "europe-west2" }
    app = { cidr = "10.10.2.0/24", region = "europe-west2" }
    db  = { cidr = "10.10.3.0/24", region = "europe-west2" }
  }
}
```

The module stays unchanged. Each environment provides its own CIDR plan. This is the core benefit of modules: **write once, parameterise per environment**.

</details>
