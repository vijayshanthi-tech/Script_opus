# Day 29 — Naming Conventions, Labels, and Network Tags

> **Week 5 · Terraform Networking** | 2 hours | europe-west2  
> **Pre-reqs:** Days 25–28 complete, understanding of Terraform locals and expressions

---

## Part 1 — Concept (30 min)

### 1.1 Why Naming Conventions Matter

```
BAD naming                          GOOD naming
──────────                          ───────────
vpc1                                tap-prod-vpc
subnet-a                            tap-prod-web-euw2
fw-rule-1                           tap-prod-allow-iap-ssh
my-route                            tap-prod-route-onprem-dc1
test-vm                             tap-prod-web-vm-001

Problems with bad naming:           Benefits of good naming:
• Can't tell env from name          • Environment obvious at a glance
• No ownership info                 • Team/project clear
• Hard to filter in Console         • gcloud --filter works well
• Billing confusion                 • Cost attribution easy
• Incident response slower          • Faster troubleshooting
```

### 1.2 Naming Convention Pattern

Recommended pattern: `{project}-{env}-{resource}-{purpose}[-{region_short}][-{index}]`

```
┌────────┬──────┬──────────┬─────────┬────────┬───────┐
│project │ env  │ resource │ purpose │ region │ index │
├────────┼──────┼──────────┼─────────┼────────┼───────┤
│ tap    │ prod │ vpc      │         │        │       │
│ tap    │ dev  │ subnet   │ web     │ euw2   │       │
│ tap    │ stg  │ fw       │ iap-ssh │        │       │
│ tap    │ prod │ route    │ onprem  │        │       │
│ tap    │ prod │ vm       │ web     │ euw2a  │ 001   │
└────────┴──────┴──────────┴─────────┴────────┴───────┘
```

### 1.3 Region Short Codes

| Region | Short Code | Example |
|--------|-----------|---------|
| `europe-west2` | `euw2` | `tap-prod-subnet-web-euw2` |
| `europe-west1` | `euw1` | `tap-prod-subnet-app-euw1` |
| `us-central1` | `usc1` | `tap-prod-subnet-data-usc1` |
| `us-east1` | `use1` | `tap-dev-subnet-test-use1` |

### 1.4 Labels Strategy

Labels are key-value pairs attached to GCP resources for **organisation, filtering, and billing**.

```
┌────────────────────────────────────────────────────────┐
│                    LABELS                              │
│                                                        │
│  ┌──────────────────┬────────────────────────────┐    │
│  │ Key              │ Example Values             │    │
│  ├──────────────────┼────────────────────────────┤    │
│  │ env              │ dev, staging, prod          │    │
│  │ team             │ platform, data, security   │    │
│  │ cost-center      │ cc-1234, cc-5678           │    │
│  │ managed-by       │ terraform                  │    │
│  │ project          │ tap                        │    │
│  │ owner            │ infra-team                 │    │
│  │ data-class       │ public, internal, pii      │    │
│  │ created-by       │ ci-pipeline                │    │
│  └──────────────────┴────────────────────────────┘    │
│                                                        │
│  Rules:                                                │
│  • Max 64 labels per resource                          │
│  • Key: max 63 chars, lowercase, [a-z0-9_-]          │
│  • Value: max 63 chars, lowercase, [a-z0-9_-]        │
│  • Keys must start with a lowercase letter             │
│  • Empty values are allowed                            │
└────────────────────────────────────────────────────────┘
```

### 1.5 Network Tags vs Labels

```
┌──────────────────────────┬────────────────────────────────┐
│      Network Tags        │          Labels                │
├──────────────────────────┼────────────────────────────────┤
│ Strings (no key-value)   │ Key-value pairs                │
│ VM instances only        │ Most GCP resources             │
│ Used by firewall rules   │ Used for billing/organisation  │
│   and routes             │                                │
│ target_tags = ["web"]    │ labels = { env = "prod" }      │
│ Not visible in billing   │ Visible in billing exports     │
│ Mutable via VM edit      │ Mutable via resource edit      │
│                          │                                │
│ Example: "allow-iap"     │ Example: team = "platform"     │
│          "use-nat"       │          env  = "production"   │
│          "web-server"    │          cost-center = "cc-42" │
└──────────────────────────┴────────────────────────────────┘
```

### 1.6 The `locals` Block — DRY Naming

```
┌─────────────────────────────────────────────────────────────┐
│  locals {                                                   │
│    project_prefix = "${var.project}-${var.env}"             │
│    # Result: "tap-dev"                                      │
│                                                             │
│    region_short = {                                         │
│      "europe-west2" = "euw2"                               │
│      "europe-west1" = "euw1"                               │
│      "us-central1"  = "usc1"                               │
│    }                                                        │
│                                                             │
│    common_labels = {                                        │
│      project     = var.project                              │
│      env         = var.env                                  │
│      team        = var.team                                 │
│      managed-by  = "terraform"                              │
│      cost-center = var.cost_center                          │
│    }                                                        │
│  }                                                          │
│                                                             │
│  Usage:                                                     │
│    name   = "${local.project_prefix}-vpc"                   │
│    labels = local.common_labels                             │
│                                                             │
│  Benefits:                                                  │
│  ✓ Single source of truth for naming                        │
│  ✓ Change in one place → propagates everywhere              │
│  ✓ Consistent labels across all resources                   │
│  ✓ Easy to extend (add a label → all resources get it)     │
└─────────────────────────────────────────────────────────────┘
```

### 1.7 Which Resources Support Labels?

| Resource | Labels? | Network Tags? |
|----------|---------|--------------|
| `google_compute_network` (VPC) | ❌ No | ❌ No |
| `google_compute_subnetwork` | ❌ No | ❌ No |
| `google_compute_firewall` | ❌ No | ✅ target_tags |
| `google_compute_route` | ❌ No | ✅ tags |
| `google_compute_instance` (VM) | ✅ Yes | ✅ Yes |
| `google_compute_disk` | ✅ Yes | ❌ No |
| `google_compute_address` | ✅ Yes | ❌ No |
| `google_compute_forwarding_rule` | ✅ Yes | ❌ No |
| `google_storage_bucket` | ✅ Yes | ❌ No |

> Note: VPC, subnets, firewall rules, and routes do not support labels. Use naming conventions for these.

---

## Part 2 — Hands-On Lab (60 min)

### Lab Objective

Implement a consistent naming convention using `locals`, apply labels to all supported resources, and use network tags consistently.

### Step 1 — Create a Naming Module

```bash
mkdir -p ~/tf-networking/modules/naming
```

**`modules/naming/variables.tf`**

```hcl
variable "project" {
  description = "Project short name (e.g., tap)"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,9}$", var.project))
    error_message = "Project must be lowercase alphanumeric, 2-10 characters."
  }
}

variable "env" {
  description = "Environment (dev, staging, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.env)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "region" {
  description = "GCP region"
  type        = string
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
```

**`modules/naming/main.tf`**

```hcl
locals {
  # Region short code lookup
  region_short_map = {
    "europe-west1" = "euw1"
    "europe-west2" = "euw2"
    "europe-west3" = "euw3"
    "us-central1"  = "usc1"
    "us-east1"     = "use1"
    "us-west1"     = "usw1"
  }

  region_short = lookup(local.region_short_map, var.region, replace(var.region, "-", ""))

  # Base prefix: project-env
  prefix = "${var.project}-${var.env}"

  # Full prefix with region: project-env-region
  prefix_regional = "${local.prefix}-${local.region_short}"
}
```

**`modules/naming/outputs.tf`**

```hcl
output "prefix" {
  description = "Base naming prefix (project-env)"
  value       = local.prefix
}

output "prefix_regional" {
  description = "Regional naming prefix (project-env-region)"
  value       = local.prefix_regional
}

output "region_short" {
  description = "Short code for the region"
  value       = local.region_short
}

output "common_labels" {
  description = "Common labels to apply to all resources that support labels"
  value = {
    project     = var.project
    env         = var.env
    team        = var.team
    managed-by  = "terraform"
    cost-center = var.cost_center
  }
}

output "network_tags" {
  description = "Standard network tags"
  value = {
    allow_iap    = "${local.prefix}-allow-iap"
    allow_hc     = "${local.prefix}-allow-hc"
    web_server   = "${local.prefix}-web"
    app_server   = "${local.prefix}-app"
    db_server    = "${local.prefix}-db"
    use_nat      = "${local.prefix}-use-nat"
  }
}
```

### Step 2 — Update Root Configuration

**`environments/dev/variables.tf`**:

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

variable "project_name" {
  description = "Short project name for naming"
  type        = string
  default     = "tap"
}

variable "env" {
  description = "Environment"
  type        = string
  default     = "dev"
}

variable "team" {
  description = "Team name"
  type        = string
  default     = "platform"
}

variable "cost_center" {
  description = "Cost center for billing"
  type        = string
  default     = "cc-1234"
}
```

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

# ──────────────────────────────────────
# Naming Convention
# ──────────────────────────────────────
module "naming" {
  source = "../../modules/naming"

  project     = var.project_name
  env         = var.env
  region      = var.region
  team        = var.team
  cost_center = var.cost_center
}

# ──────────────────────────────────────
# Locals — Central naming and labels
# ──────────────────────────────────────
locals {
  prefix        = module.naming.prefix          # "tap-dev"
  prefix_reg    = module.naming.prefix_regional  # "tap-dev-euw2"
  common_labels = module.naming.common_labels
  tags          = module.naming.network_tags
}

# ──────────────────────────────────────
# VPC + Subnets (using naming convention)
# ──────────────────────────────────────
module "vpc" {
  source = "../../modules/vpc"

  vpc_name     = "${local.prefix}-vpc"
  project_id   = var.project_id
  routing_mode = "REGIONAL"
  description  = "${local.prefix} VPC - managed by Terraform"

  subnets = {
    web = {
      cidr   = "10.0.1.0/24"
      region = var.region
    }
    app = {
      cidr   = "10.0.2.0/24"
      region = var.region
      secondary_ranges = [
        { name = "gke-pods",     cidr = "10.1.0.0/16" },
        { name = "gke-services", cidr = "10.2.0.0/20" }
      ]
    }
    db = {
      cidr             = "10.0.3.0/24"
      region           = var.region
      enable_flow_logs = true
    }
  }
}

# ──────────────────────────────────────
# Firewall Rules (using naming convention tags)
# ──────────────────────────────────────
module "firewall" {
  source = "../../modules/firewall"

  project_id        = var.project_id
  network_name      = module.vpc.network_name
  network_self_link = module.vpc.network_self_link

  firewall_rules = {
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
      description   = "Allow SSH from IAP"
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
  }
}

# ──────────────────────────────────────
# Custom Routes (using naming convention)
# ──────────────────────────────────────
module "routes" {
  source = "../../modules/routes"

  project_id   = var.project_id
  network_name = module.vpc.network_name

  routes = {
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
  }
}

# ──────────────────────────────────────
# Example VM (demonstrating labels + tags)
# ──────────────────────────────────────
resource "google_compute_instance" "web" {
  name         = "${local.prefix_reg}-web-vm-001"
  machine_type = "e2-micro"
  zone         = "${var.region}-a"
  project      = var.project_id

  tags = [
    local.tags.allow_iap,
    local.tags.allow_hc,
    local.tags.web_server
  ]

  labels = merge(local.common_labels, {
    role = "web-server"
  })

  boot_disk {
    initialize_params {
      image  = "debian-cloud/debian-12"
      size   = 10
      labels = local.common_labels
    }
  }

  network_interface {
    subnetwork = module.vpc.subnet_self_links["web"]
    # No external IP — use IAP for SSH
  }

  metadata = {
    enable-oslogin = "TRUE"
  }
}
```

**`environments/dev/outputs.tf`**:

```hcl
output "naming_prefix" {
  value = local.prefix
}

output "naming_prefix_regional" {
  value = local.prefix_reg
}

output "common_labels" {
  value = local.common_labels
}

output "network_tags" {
  value = local.tags
}

output "vpc_name" {
  value = module.vpc.network_name
}

output "subnet_cidrs" {
  value = module.vpc.subnet_cidrs
}

output "web_vm_name" {
  value = google_compute_instance.web.name
}

output "web_vm_labels" {
  value = google_compute_instance.web.labels
}

output "web_vm_tags" {
  value = google_compute_instance.web.tags
}
```

**`environments/dev/terraform.tfvars`**:

```hcl
project_id   = "your-gcp-project-id"
region       = "europe-west2"
project_name = "tap"
env          = "dev"
team         = "platform"
cost_center  = "cc-1234"
```

### Step 3 — Deploy and Validate

```bash
cd ~/tf-networking/environments/dev

terraform init -upgrade
terraform validate
terraform plan
terraform apply
```

### Step 4 — Verify Naming and Labels

```bash
# Check VM name and tags
gcloud compute instances describe tap-dev-euw2-web-vm-001 \
  --zone=europe-west2-a \
  --project=your-gcp-project-id \
  --format="yaml(name, tags.items, labels)"

# Filter VMs by label
gcloud compute instances list \
  --filter="labels.env=dev AND labels.team=platform" \
  --project=your-gcp-project-id \
  --format="table(name, zone, labels)"

# Filter by managed-by label
gcloud compute instances list \
  --filter="labels.managed-by=terraform" \
  --project=your-gcp-project-id

# Check all resources with a specific cost center
gcloud asset search-all-resources \
  --query="labels.cost-center:cc-1234" \
  --project=your-gcp-project-id

# Verify naming on all networking resources
gcloud compute networks list --project=your-gcp-project-id --filter="name~tap-dev"
gcloud compute networks subnets list --project=your-gcp-project-id --filter="name~tap-dev"
gcloud compute firewall-rules list --project=your-gcp-project-id --filter="name~tap-dev"
gcloud compute routes list --project=your-gcp-project-id --filter="name~tap-dev"

# Terraform outputs
terraform output naming_prefix
terraform output common_labels
terraform output network_tags
terraform output web_vm_labels
```

### Step 5 — Experiment: Add a New Label

```bash
# Add "data-class" to common_labels in modules/naming/outputs.tf
# Run terraform plan — observe all labeled resources update
terraform plan

# This demonstrates how locals centralise changes
```

### Step 6 — Cleanup

```bash
terraform destroy
```

---

## Part 3 — Revision (15 min)

### Key Concepts

- Naming pattern: `{project}-{env}-{resource}-{purpose}[-{region}][-{index}]`
- Use `locals` block to define naming prefix once, reference everywhere
- Labels are key-value pairs for billing, filtering, and organisation
- Label constraints: lowercase, [a-z0-9_-], max 63 chars, max 64 per resource
- Network tags are strings for firewall and route targeting — VM instances only
- NOT all resources support labels (VPC, subnets, firewalls, routes do not)
- `merge()` function combines label maps: `merge(local.common_labels, { role = "web" })`
- `lookup()` for safe map access with default: `lookup(local.region_map, var.region, "unknown")`
- Consistent naming makes `gcloud --filter` and Console search effective
- The naming module is a zero-resource module — it only produces computed outputs

### Essential Commands

```bash
# Filter by label
gcloud compute instances list --filter="labels.env=dev"

# Filter by name pattern
gcloud compute instances list --filter="name~tap-dev"

# List labels on a resource
gcloud compute instances describe VM --format="yaml(labels)"

# Add a label to existing resource
gcloud compute instances add-labels VM --labels="new-key=value"

# Remove a label
gcloud compute instances remove-labels VM --labels="old-key"

# Terraform console — test locals
terraform console
> local.prefix
> local.common_labels
> merge(local.common_labels, { role = "test" })
```

### Label Decision Matrix

| Label Key | Required? | Who Sets It | Used By |
|-----------|----------|------------|---------|
| `env` | Yes | Terraform var | Billing, filtering |
| `team` | Yes | Terraform var | Ownership, billing |
| `managed-by` | Yes | Hardcoded `terraform` | Drift detection |
| `cost-center` | Yes | Terraform var | Finance/billing |
| `project` | Yes | Terraform var | Multi-project filtering |
| `data-class` | Optional | Terraform var | Security/compliance |
| `owner` | Optional | Terraform var | Incident response |

---

## Part 4 — Quiz (15 min)

**Question 1:** Why do we use a `locals` block for naming instead of just putting the prefix directly in each resource's `name` attribute?

<details>
<summary>Show Answer</summary>

**DRY (Don't Repeat Yourself) principle.** Using `locals`:

1. **Single source of truth** — Change the naming pattern in one place, all resources update
2. **Consistency** — Impossible to have typos in one resource but not another
3. **Computed values** — Can use functions like `lookup()` for region short codes
4. **Testable** — `terraform console` lets you verify the prefix before applying
5. **Refactoring** — Easy to change from `project-env` to `project-env-region` across everything

Without `locals`, every resource repeats `"${var.project}-${var.env}"`, and a typo in one resource creates an inconsistency that's hard to find.

```hcl
# BAD — repeated, error-prone
resource "a" { name = "${var.project}-${var.env}-vpc" }
resource "b" { name = "${var.project}-${var.envv}-subnet" }  # typo!

# GOOD — centralised
locals { prefix = "${var.project}-${var.env}" }
resource "a" { name = "${local.prefix}-vpc" }
resource "b" { name = "${local.prefix}-subnet" }  # consistent
```

</details>

---

**Question 2:** VPCs and subnets don't support labels. How do you still achieve cost attribution and organisation for networking resources?

<details>
<summary>Show Answer</summary>

Three strategies:

1. **Naming convention** — Embed project, env, and purpose in the resource name:
   ```
   tap-prod-vpc
   tap-prod-subnet-web-euw2
   ```
   This makes filtering via `gcloud --filter="name~tap-prod"` effective.

2. **Project-level labels** — Apply labels at the GCP project level. All resources within the project inherit project-level billing attribution.

3. **Description field** — Use the `description` attribute (supported on VPC, subnets, firewalls) to add metadata:
   ```hcl
   description = "tap-prod web subnet | team:platform | cc:1234"
   ```

4. **Resource hierarchy** — Use folders and projects in your org hierarchy for cost boundaries. Networking resources inherit the project's billing account.

The best approach is combining all four: consistent naming + project labels + descriptions + org hierarchy.

</details>

---

**Question 3:** What is the difference between `merge(local.common_labels, { role = "web" })` and putting all labels directly? When would merge fail?

<details>
<summary>Show Answer</summary>

`merge()` combines two or more maps. Later maps override earlier ones for duplicate keys:

```hcl
merge(
  { env = "dev", team = "platform" },   # common
  { role = "web", env = "staging" }      # specific — overrides env!
)
# Result: { env = "staging", team = "platform", role = "web" }
```

**Advantage over direct labels:**
- Common labels defined once, extended per resource
- Adding a label to `common_labels` automatically propagates to all resources
- Resource-specific labels (like `role`) stay close to the resource definition

**When merge can cause issues:**
- If the second map accidentally **overrides** a common label (as shown with `env` above)
- If you exceed the 64-label limit per resource
- If values contain invalid characters (uppercase, spaces)

**Best practice:** Use specific key names for resource-level labels that don't collide with common labels.

</details>

---

**Question 4:** A colleague creates a firewall rule with `target_tags = ["web-server"]` and a VM with `tags = ["Web-Server"]`. Will the rule apply to the VM?

<details>
<summary>Show Answer</summary>

**No.** Network tags are **case-sensitive**. `"web-server"` ≠ `"Web-Server"`.

GCP network tags must be lowercase and match exactly. The `tags` field on `google_compute_instance` accepts strings that:

- Are lowercase
- Contain only letters, numbers, and hyphens
- Start with a letter

The VM tag `"Web-Server"` is actually invalid — GCP will reject it at creation time.

**Fix:** Use the naming module's standardised tags and reference them via `local.tags.web_server`:

```hcl
# Firewall
target_tags = [local.tags.web_server]  # "tap-dev-web"

# VM
tags = [local.tags.web_server]  # same: "tap-dev-web"
```

By centralising tag definitions, you eliminate case mismatches and typos entirely.

</details>
