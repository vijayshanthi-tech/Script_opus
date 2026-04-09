# Day 25 — Building a Reusable VPC Module

> **Week 5 · Terraform Networking** | 2 hours | europe-west2  
> **Pre-reqs:** Weeks 1–4 complete, Terraform ≥ 1.5, `gcloud` authenticated, ACE-level networking knowledge

---

## Part 1 — Concept (30 min)

### 1.1 Why Modules?

Modules are the **primary mechanism for code reuse** in Terraform. Instead of copying VPC blocks across environments, you write one module and call it with different variables.

```
Without Modules                    With Modules
─────────────────                  ──────────────────
dev/main.tf   ─┐                   modules/vpc/
  google_compute_network           ├── variables.tf
  google_compute_subnetwork        ├── main.tf
staging/main.tf ─┤  DUPLICATED     └── outputs.tf
  google_compute_network                  │
  google_compute_subnetwork        environments/
prod/main.tf  ─┘                   ├── dev/main.tf     ──► module "vpc" { source = "../../modules/vpc" }
  google_compute_network           ├── staging/main.tf  ──► module "vpc" { source = "../../modules/vpc" }
  google_compute_subnetwork        └── prod/main.tf     ──► module "vpc" { source = "../../modules/vpc" }
```

### 1.2 Module File Structure

Every well-structured Terraform module follows a **three-file convention**:

```
modules/vpc/
├── variables.tf    ← Inputs: what the caller provides
├── main.tf         ← Resources: what Terraform creates
└── outputs.tf      ← Outputs: what the caller can reference
```

| File | Purpose | Analogy |
|------|---------|---------|
| `variables.tf` | Declares input parameters with types, defaults, descriptions | Function parameters |
| `main.tf` | Contains the `google_compute_network` resource and logic | Function body |
| `outputs.tf` | Exposes resource attributes for use by the caller | Return values |

### 1.3 The `google_compute_network` Resource

```
┌─────────────────────────────────────────────────┐
│           google_compute_network                │
│                                                 │
│  name ──────────────────► VPC display name      │
│  auto_create_subnetworks ► true = auto mode     │
│                            false = custom mode  │
│  routing_mode ──────────► REGIONAL or GLOBAL    │
│  project ───────────────► GCP project ID        │
│  delete_default_routes_on_create ► bool         │
│                                                 │
│  Output attributes:                             │
│    .id          .self_link      .name           │
│    .gateway_ipv4                                │
└─────────────────────────────────────────────────┘
```

### 1.4 Key Design Decisions

| Decision | Recommendation | Why |
|----------|---------------|-----|
| `auto_create_subnetworks` | `false` | Custom mode gives you full control over CIDR ranges |
| `routing_mode` | `REGIONAL` (default) | Use `GLOBAL` only when you need cross-region dynamic routing |
| `delete_default_routes_on_create` | `false` initially | Deleting the default internet route locks you out; add later when you have Cloud NAT |

### 1.5 Module Input Variable Best Practices

```
┌──────────────────────────────────────────────────────────┐
│  Variable Design Checklist                               │
│                                                          │
│  ✓  Always add `description` — self-documenting          │
│  ✓  Use `type` constraints — catches errors early        │
│  ✓  Provide sensible `default` where possible            │
│  ✓  Use `validation` blocks for business rules           │
│  ✓  Mark sensitive vars with `sensitive = true`          │
│  ✗  Never hardcode project/region inside the module      │
└──────────────────────────────────────────────────────────┘
```

### 1.6 Module Call Flow

```
root/main.tf                        modules/vpc/main.tf
┌──────────────────────┐             ┌──────────────────────────┐
│ module "vpc" {       │             │ resource                 │
│   source = "../..."  │──creates──► │  "google_compute_network"│
│   vpc_name = "dev"   │             │  "vpc" {                 │
│   routing_mode = ... │             │   name = var.vpc_name    │
│ }                    │             │   ...                    │
│                      │             │ }                        │
│ # Access output:     │◄──returns── │                          │
│ module.vpc.network_id│             │ output "network_id" {    │
└──────────────────────┘             │   value = ...self_link   │
                                     └──────────────────────────┘
```

---

## Part 2 — Hands-On Lab (60 min)

### Lab Objective

Create a reusable VPC module in `modules/vpc/` and call it from a root configuration.

### Step 1 — Project Directory Structure

```bash
mkdir -p ~/tf-networking/modules/vpc
mkdir -p ~/tf-networking/environments/dev
cd ~/tf-networking
```

Target structure:

```
tf-networking/
├── modules/
│   └── vpc/
│       ├── variables.tf
│       ├── main.tf
│       └── outputs.tf
└── environments/
    └── dev/
        ├── main.tf
        ├── variables.tf
        ├── outputs.tf
        └── terraform.tfvars
```

### Step 2 — Write the VPC Module

**`modules/vpc/variables.tf`**

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

  validation {
    condition     = contains(["REGIONAL", "GLOBAL"], var.routing_mode)
    error_message = "routing_mode must be REGIONAL or GLOBAL."
  }
}

variable "auto_create_subnetworks" {
  description = "If true, subnets are created automatically (auto mode). Use false for custom mode."
  type        = bool
  default     = false
}

variable "delete_default_routes" {
  description = "If true, delete default routes on VPC creation. Use with caution."
  type        = bool
  default     = false
}

variable "project_id" {
  description = "GCP project ID where the VPC will be created"
  type        = string
}

variable "description" {
  description = "Description for the VPC network"
  type        = string
  default     = "Managed by Terraform"
}
```

**`modules/vpc/main.tf`**

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

resource "google_compute_network" "vpc" {
  name                            = var.vpc_name
  project                         = var.project_id
  auto_create_subnetworks         = var.auto_create_subnetworks
  routing_mode                    = var.routing_mode
  delete_default_routes_on_create = var.delete_default_routes
  description                     = var.description
}
```

**`modules/vpc/outputs.tf`**

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

output "network_gateway_ipv4" {
  description = "The IPv4 gateway address of the VPC"
  value       = google_compute_network.vpc.gateway_ipv4
}
```

### Step 3 — Call the Module from Root

**`environments/dev/variables.tf`**

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

**`environments/dev/main.tf`**

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

  # Custom mode — we control subnets explicitly
  auto_create_subnetworks = false
  delete_default_routes   = false
  description             = "Development VPC - managed by Terraform"
}
```

**`environments/dev/outputs.tf`**

```hcl
output "vpc_name" {
  description = "Name of the created VPC"
  value       = module.vpc.network_name
}

output "vpc_self_link" {
  description = "Self-link of the created VPC"
  value       = module.vpc.network_self_link
}

output "vpc_id" {
  description = "ID of the created VPC"
  value       = module.vpc.network_id
}
```

**`environments/dev/terraform.tfvars`**

```hcl
project_id = "your-gcp-project-id"
region     = "europe-west2"
```

### Step 4 — Deploy and Validate

```bash
cd ~/tf-networking/environments/dev

# Initialise — downloads provider + discovers module
terraform init

# Validate the configuration
terraform validate

# Preview the plan
terraform plan

# Apply (type 'yes' when prompted)
terraform apply
```

### Step 5 — Verify the VPC

```bash
# Confirm VPC exists via gcloud
gcloud compute networks describe dev-vpc \
  --project=your-gcp-project-id \
  --format="table(name, routingConfig.routingMode, autoCreateSubnetworks)"

# Verify Terraform state
terraform state list

# Show details
terraform state show module.vpc.google_compute_network.vpc

# Check outputs
terraform output
```

### Step 6 — Experiment

```bash
# Change routing_mode to GLOBAL in terraform.tfvars or main.tf
# Run terraform plan to see the diff
terraform plan

# Revert and re-apply
terraform apply
```

### Step 7 — Cleanup

```bash
terraform destroy
# Type 'yes' to confirm
```

---

## Part 3 — Revision (15 min)

### Key Concepts

- A **Terraform module** is a directory containing `.tf` files — every root configuration is itself a module
- The **three-file convention**: `variables.tf` (inputs), `main.tf` (resources), `outputs.tf` (return values)
- `google_compute_network` creates a VPC; set `auto_create_subnetworks = false` for custom mode
- `routing_mode` controls whether dynamic routes propagate within region (`REGIONAL`) or globally (`GLOBAL`)
- `delete_default_routes_on_create = true` removes the `0.0.0.0/0` → internet gateway route — use carefully
- Module `source` can be a local path (`../../modules/vpc`), Git URL, or Terraform registry
- Module outputs are accessed via `module.<name>.<output_name>`
- Always add `description` to variables and outputs — it powers `terraform docs` and IDE hints
- Use `validation` blocks in variables to enforce naming conventions and allowed values

### Essential Commands

```bash
terraform init            # Download providers + discover modules
terraform validate        # Syntax + type check
terraform plan            # Preview changes
terraform apply           # Create/update resources
terraform destroy         # Tear down resources
terraform state list      # List all managed resources
terraform state show <r>  # Show details of one resource
terraform output          # Display root outputs
terraform fmt -recursive  # Format all .tf files
terraform console         # Interactive expression tester
```

### Quick Reference Table

| Attribute | Type | Default | Note |
|-----------|------|---------|------|
| `name` | string | required | Must be unique in project |
| `auto_create_subnetworks` | bool | `true` | Set `false` for custom |
| `routing_mode` | string | `REGIONAL` | `GLOBAL` for cross-region |
| `delete_default_routes_on_create` | bool | `false` | Removes internet route |
| `description` | string | `""` | Free-text description |

---

## Part 4 — Quiz (15 min)

**Question 1:** What are the three conventional files in a Terraform module and what is each file's purpose?

<details>
<summary>Show Answer</summary>

| File | Purpose |
|------|---------|
| `variables.tf` | Declares input parameters (type, default, description, validation) the caller provides |
| `main.tf` | Contains the resource definitions and logic — the "body" of the module |
| `outputs.tf` | Exposes attributes from created resources so the calling module can reference them |

This convention is not enforced by Terraform (you can name files anything) but is universally adopted for readability and tooling support.

</details>

---

**Question 2:** You have a VPC with `auto_create_subnetworks = true`. What happens, and why is `false` preferred in production?

<details>
<summary>Show Answer</summary>

With `auto_create_subnetworks = true` (auto mode), Google automatically creates one subnet per region with a `/20` CIDR from the `10.128.0.0/9` range. This means:

- You **cannot control** CIDR ranges — potential overlap with on-prem networks
- You get subnets in **every** region, even ones you don't use
- Secondary ranges for GKE pods/services must be added manually anyway

Setting `false` (custom mode) gives full control over which regions get subnets, what CIDRs they use, and allows proper CIDR planning for hybrid connectivity.

</details>

---

**Question 3:** What is the difference between `REGIONAL` and `GLOBAL` routing mode? When would you use each?

<details>
<summary>Show Answer</summary>

| Routing Mode | Behaviour | Use Case |
|-------------|-----------|----------|
| `REGIONAL` | Cloud Router advertises routes only within its region | Single-region deployments, simpler setups |
| `GLOBAL` | Cloud Router advertises routes to **all** regions in the VPC | Multi-region with Cloud VPN/Interconnect, cross-region dynamic routing needed |

Use `REGIONAL` (default) for most workloads. Switch to `GLOBAL` when you have Cloud Routers with BGP sessions (VPN, Interconnect) and need routes learned in one region visible in another.

</details>

---

**Question 4:** A colleague calls the VPC module but gets an error: `Module "vpc" has no output named "vpc_id"`. The module's `outputs.tf` defines `network_id`. What's wrong and how do you fix it?

<details>
<summary>Show Answer</summary>

The caller is referencing `module.vpc.vpc_id` but the module output is named `network_id`. Module outputs must be referenced by their **exact declared name**.

**Fix option A** — Change the caller to use the correct name:

```hcl
# In the calling module
output "vpc_id" {
  value = module.vpc.network_id   # ← matches the module's output name
}
```

**Fix option B** — Rename the output in the module (requires `terraform state` migration if already applied):

```hcl
# In modules/vpc/outputs.tf
output "vpc_id" {        # ← renamed from network_id
  value = google_compute_network.vpc.id
}
```

Option A is safer because it doesn't change the module's interface, which other callers may depend on.

</details>
