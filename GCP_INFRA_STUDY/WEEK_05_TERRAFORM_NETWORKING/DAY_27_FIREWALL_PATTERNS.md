# Day 27 — Firewall Rule Patterns (Least Privilege)

> **Week 5 · Terraform Networking** | 2 hours | europe-west2  
> **Pre-reqs:** Day 25–26 complete (VPC + subnets module), ACE-level firewall knowledge

---

## Part 1 — Concept (30 min)

### 1.1 Firewall Rule Evaluation Order

GCP evaluates firewall rules by **priority** (lowest number = highest priority):

```
Priority 0      ← Highest priority (most urgent)
   │
   ▼
Priority 1000   ← Default allow rules
   │
   ▼
Priority 65534  ← Implied allow egress (0.0.0.0/0)
   │
   ▼
Priority 65535  ← Implied deny ingress (all)
                ← Lowest priority (fallback)

Evaluation: First matching rule wins. If no rule matches → implied rules apply.
```

### 1.2 Least Privilege Firewall Strategy

```
┌──────────────────────────────────────────────────────────────┐
│                  FIREWALL STRATEGY                           │
│                                                              │
│  Layer 1: DENY all egress            (priority 1000)         │
│           ↓                                                  │
│  Layer 2: ALLOW specific egress      (priority 900)          │
│           • Google APIs (199.36.153.8/30)                    │
│           • Internal subnets                                 │
│           • Required external services                       │
│           ↓                                                  │
│  Layer 3: ALLOW specific ingress     (priority 1000)         │
│           • IAP (35.235.240.0/20) → SSH                      │
│           • Health checks (35.191.0.0/16, 130.211.0.0/22)   │
│           • Internal subnet-to-subnet                        │
│           ↓                                                  │
│  Layer 4: Implied DENY all ingress   (priority 65535)        │
│           (built-in, cannot be deleted)                      │
└──────────────────────────────────────────────────────────────┘
```

### 1.3 Common Firewall Rule Patterns

| Rule Name | Direction | Source/Dest | Targets | Ports | Priority |
|-----------|-----------|-------------|---------|-------|----------|
| allow-iap-ssh | INGRESS | `35.235.240.0/20` | tag: `allow-iap` | TCP 22 | 1000 |
| allow-iap-rdp | INGRESS | `35.235.240.0/20` | tag: `allow-iap` | TCP 3389 | 1000 |
| allow-health-checks | INGRESS | `35.191.0.0/16`, `130.211.0.0/22` | tag: `allow-hc` | TCP (configurable) | 1000 |
| allow-internal | INGRESS | `10.0.0.0/8` | all instances | all | 1000 |
| deny-all-egress | EGRESS | `0.0.0.0/0` | all instances | all | 1000 |
| allow-egress-google-apis | EGRESS | `199.36.153.8/30` | all instances | TCP 443 | 900 |
| allow-egress-internal | EGRESS | `10.0.0.0/8` | all instances | all | 900 |

### 1.4 Network Tags vs Service Accounts

```
┌─────────────────────────────────┬──────────────────────────────────┐
│         Network Tags            │        Service Accounts          │
├─────────────────────────────────┼──────────────────────────────────┤
│ Applied to VM instances         │ Identity-based targeting         │
│ Mutable (anyone with VM edit)   │ IAM-controlled (more secure)    │
│ String-based matching           │ Email-based matching             │
│ Easy to use, quick to set up    │ Better for production security  │
│ target_tags = ["web"]           │ target_service_accounts = [...]  │
│                                 │                                  │
│ Best for: dev, quick prototyping│ Best for: production workloads  │
└─────────────────────────────────┴──────────────────────────────────┘
```

### 1.5 The `google_compute_firewall` Resource

```
┌──────────────────────────────────────────────────────┐
│           google_compute_firewall                    │
│                                                      │
│  name ────────────────► Rule name                    │
│  network ─────────────► VPC self_link                │
│  direction ───────────► INGRESS or EGRESS            │
│  priority ────────────► 0–65535 (default 1000)       │
│  source_ranges ───────► CIDRs (ingress only)         │
│  destination_ranges ──► CIDRs (egress only)          │
│  target_tags ─────────► Network tags on target VMs   │
│  source_tags ─────────► Tags on source VMs           │
│                                                      │
│  allow {               ◄── Repeatable block          │
│    protocol = "tcp"    │                             │
│    ports    = ["22"]   │                             │
│  }                     │                             │
│                                                      │
│  deny {                ◄── Mutually exclusive w/allow│
│    protocol = "all"    │                             │
│  }                     │                             │
│                                                      │
│  log_config {          ◄── Optional logging          │
│    metadata = "INCLUDE_ALL_METADATA"                 │
│  }                     │                             │
└──────────────────────────────────────────────────────┘
```

### 1.6 Dynamic Blocks for Allow/Deny

When a firewall rule allows multiple protocols/port combinations:

```
┌─────────────────────────────────────────────────────────┐
│  variable "rules" {                                     │
│    type = list(object({                                 │
│      protocol = string                                  │
│      ports    = optional(list(string), [])              │
│    }))                                                  │
│  }                                                      │
│                                                         │
│  dynamic "allow" {                                      │
│    for_each = var.rules                                 │
│    content {                                            │
│      protocol = allow.value.protocol                    │
│      ports    = allow.value.ports                       │
│    }                                                    │
│  }                                                      │
│                                                         │
│  rules = [                                              │
│    { protocol = "tcp", ports = ["22", "443"] },         │
│    { protocol = "icmp" }                   ← no ports   │
│  ]                                                      │
│  Generates TWO allow blocks automatically               │
└─────────────────────────────────────────────────────────┘
```

---

## Part 2 — Hands-On Lab (60 min)

### Lab Objective

Create a reusable firewall module using `for_each` over a list of rule objects, implementing the least-privilege pattern.

### Step 1 — Create the Firewall Module Directory

```bash
mkdir -p ~/tf-networking/modules/firewall
```

### Step 2 — Write the Firewall Module

**`modules/firewall/variables.tf`**

```hcl
variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "network_name" {
  description = "Name of the VPC network"
  type        = string
}

variable "network_self_link" {
  description = "Self-link of the VPC network"
  type        = string
}

variable "firewall_rules" {
  description = "Map of firewall rules to create"
  type = map(object({
    description        = optional(string, "Managed by Terraform")
    direction          = string
    priority           = optional(number, 1000)
    source_ranges      = optional(list(string), [])
    destination_ranges = optional(list(string), [])
    target_tags        = optional(list(string), [])
    source_tags        = optional(list(string), [])
    action             = string  # "allow" or "deny"
    rules = list(object({
      protocol = string
      ports    = optional(list(string), [])
    }))
    enable_logging = optional(bool, false)
  }))
  default = {}
}
```

**`modules/firewall/main.tf`**

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
# Firewall Rules — ALLOW type
# ──────────────────────────────────────
resource "google_compute_firewall" "allow_rules" {
  for_each = {
    for k, v in var.firewall_rules : k => v if v.action == "allow"
  }

  name        = "${var.network_name}-${each.key}"
  project     = var.project_id
  network     = var.network_self_link
  description = each.value.description
  direction   = each.value.direction
  priority    = each.value.priority

  source_ranges      = each.value.direction == "INGRESS" ? each.value.source_ranges : null
  destination_ranges = each.value.direction == "EGRESS" ? each.value.destination_ranges : null
  target_tags        = length(each.value.target_tags) > 0 ? each.value.target_tags : null
  source_tags        = length(each.value.source_tags) > 0 ? each.value.source_tags : null

  dynamic "allow" {
    for_each = each.value.rules
    content {
      protocol = allow.value.protocol
      ports    = length(allow.value.ports) > 0 ? allow.value.ports : null
    }
  }

  dynamic "log_config" {
    for_each = each.value.enable_logging ? [1] : []
    content {
      metadata = "INCLUDE_ALL_METADATA"
    }
  }
}

# ──────────────────────────────────────
# Firewall Rules — DENY type
# ──────────────────────────────────────
resource "google_compute_firewall" "deny_rules" {
  for_each = {
    for k, v in var.firewall_rules : k => v if v.action == "deny"
  }

  name        = "${var.network_name}-${each.key}"
  project     = var.project_id
  network     = var.network_self_link
  description = each.value.description
  direction   = each.value.direction
  priority    = each.value.priority

  source_ranges      = each.value.direction == "INGRESS" ? each.value.source_ranges : null
  destination_ranges = each.value.direction == "EGRESS" ? each.value.destination_ranges : null
  target_tags        = length(each.value.target_tags) > 0 ? each.value.target_tags : null

  dynamic "deny" {
    for_each = each.value.rules
    content {
      protocol = deny.value.protocol
      ports    = length(deny.value.ports) > 0 ? deny.value.ports : null
    }
  }

  dynamic "log_config" {
    for_each = each.value.enable_logging ? [1] : []
    content {
      metadata = "INCLUDE_ALL_METADATA"
    }
  }
}
```

**`modules/firewall/outputs.tf`**

```hcl
output "allow_rule_ids" {
  description = "Map of allow rule name to rule ID"
  value = {
    for k, v in google_compute_firewall.allow_rules : k => v.id
  }
}

output "deny_rule_ids" {
  description = "Map of deny rule name to rule ID"
  value = {
    for k, v in google_compute_firewall.deny_rules : k => v.id
  }
}

output "allow_rule_self_links" {
  description = "Map of allow rule name to self_link"
  value = {
    for k, v in google_compute_firewall.allow_rules : k => v.self_link
  }
}

output "deny_rule_self_links" {
  description = "Map of deny rule name to self_link"
  value = {
    for k, v in google_compute_firewall.deny_rules : k => v.self_link
  }
}
```

### Step 3 — Call Both Modules from Root

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
# VPC + Subnets
# ──────────────────────────────────────
module "vpc" {
  source = "../../modules/vpc"

  vpc_name     = "dev-vpc"
  project_id   = var.project_id
  routing_mode = "REGIONAL"

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
# Firewall Rules (least-privilege)
# ──────────────────────────────────────
module "firewall" {
  source = "../../modules/firewall"

  project_id        = var.project_id
  network_name      = module.vpc.network_name
  network_self_link = module.vpc.network_self_link

  firewall_rules = {
    # ── Deny all egress first ──
    deny-all-egress = {
      description        = "Deny all egress by default"
      direction          = "EGRESS"
      priority           = 1000
      action             = "deny"
      destination_ranges = ["0.0.0.0/0"]
      rules              = [{ protocol = "all" }]
      enable_logging     = true
    }

    # ── Allow specific egress ──
    allow-egress-internal = {
      description        = "Allow egress to internal subnets"
      direction          = "EGRESS"
      priority           = 900
      action             = "allow"
      destination_ranges = ["10.0.0.0/8"]
      rules              = [{ protocol = "all" }]
    }

    allow-egress-google-apis = {
      description        = "Allow egress to Google APIs (Private Google Access)"
      direction          = "EGRESS"
      priority           = 900
      action             = "allow"
      destination_ranges = ["199.36.153.8/30"]
      rules              = [{ protocol = "tcp", ports = ["443"] }]
    }

    # ── Allow specific ingress ──
    allow-iap-ssh = {
      description   = "Allow SSH from IAP"
      direction     = "INGRESS"
      action        = "allow"
      source_ranges = ["35.235.240.0/20"]
      target_tags   = ["allow-iap"]
      rules         = [{ protocol = "tcp", ports = ["22"] }]
    }

    allow-health-checks = {
      description   = "Allow Google health check probes"
      direction     = "INGRESS"
      action        = "allow"
      source_ranges = ["35.191.0.0/16", "130.211.0.0/22"]
      target_tags   = ["allow-hc"]
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
```

### Step 4 — Deploy and Validate

```bash
cd ~/tf-networking/environments/dev

terraform init -upgrade
terraform validate
terraform plan

# You should see 6 firewall rules being created
terraform apply
```

### Step 5 — Verify Firewall Rules

```bash
# List all firewall rules in the VPC
gcloud compute firewall-rules list \
  --filter="network:dev-vpc" \
  --project=your-gcp-project-id \
  --format="table(name, direction, priority, sourceRanges.list():label=SRC, allowed[].map().firewall_rule().list():label=ALLOW, denied[].map().firewall_rule().list():label=DENY)"

# Describe a specific rule
gcloud compute firewall-rules describe dev-vpc-allow-iap-ssh \
  --project=your-gcp-project-id

# Verify deny-all-egress is in place
gcloud compute firewall-rules describe dev-vpc-deny-all-egress \
  --project=your-gcp-project-id
```

### Step 6 — Test a Rule (SSH via IAP)

```bash
# Create a test VM with the allow-iap tag
gcloud compute instances create test-fw-vm \
  --zone=europe-west2-a \
  --machine-type=e2-micro \
  --subnet=dev-vpc-web \
  --no-address \
  --tags=allow-iap \
  --project=your-gcp-project-id

# SSH via IAP (should work because of allow-iap-ssh rule)
gcloud compute ssh test-fw-vm \
  --zone=europe-west2-a \
  --tunnel-through-iap \
  --project=your-gcp-project-id

# Cleanup the test VM
gcloud compute instances delete test-fw-vm \
  --zone=europe-west2-a \
  --project=your-gcp-project-id --quiet
```

### Step 7 — Cleanup

```bash
terraform destroy
```

---

## Part 3 — Revision (15 min)

### Key Concepts

- **Least privilege:** Deny all egress (priority 1000), then allow specific (priority 900)
- Implied rules exist at priority 65535: deny-all-ingress and allow-all-egress — you cannot delete them
- Priority is `0` (highest) to `65535` (lowest); lower number = evaluated first
- `source_ranges` is for INGRESS rules; `destination_ranges` is for EGRESS rules
- `target_tags` apply the rule to VMs with matching network tags
- Use separate resources for `allow` and `deny` — you cannot mix them in one `google_compute_firewall`
- IAP CIDR range: `35.235.240.0/20` — memorise this for the ACE exam
- Health check CIDRs: `35.191.0.0/16` and `130.211.0.0/22`
- Private Google Access routes to `199.36.153.8/30` (restricted) or `199.36.153.4/30` (private)
- `log_config` enables firewall rule logging — costs money, use selectively

### Essential Commands

```bash
# List firewall rules for a network
gcloud compute firewall-rules list --filter="network:VPC_NAME"

# Describe a specific rule
gcloud compute firewall-rules describe RULE_NAME

# Test connectivity via IAP
gcloud compute ssh VM_NAME --tunnel-through-iap --zone=ZONE

# Check what rules apply to a VM
gcloud compute instances describe VM_NAME --zone=ZONE --format="yaml(tags)"

# Terraform — target a specific firewall rule
terraform plan -target='module.firewall.google_compute_firewall.allow_rules["allow-iap-ssh"]'
```

### Priority Guide

| Priority | Purpose |
|----------|---------|
| 100 | Emergency overrides |
| 900 | Specific allow (egress) |
| 1000 | Standard rules (default) |
| 5000 | Low-priority catch-all |
| 65534 | Implied allow egress |
| 65535 | Implied deny ingress |

---

## Part 4 — Quiz (15 min)

**Question 1:** You create a `deny-all-egress` rule at priority 1000 and an `allow-egress-google-apis` rule at priority 900. A VM tries to reach `storage.googleapis.com` (199.36.153.8). Which rule matches?

<details>
<summary>Show Answer</summary>

The **allow-egress-google-apis** rule at priority **900** matches first.

GCP evaluates firewall rules from lowest priority number (highest priority) to highest number. Since 900 < 1000, the allow rule is evaluated first. The destination `199.36.153.8` is within `199.36.153.8/30`, so the allow rule matches and traffic is permitted.

The deny-all-egress rule at priority 1000 would only match if no higher-priority rule matched first. This is exactly the pattern you want: deny everything, then punch specific holes at a higher priority.

</details>

---

**Question 2:** What is the difference between `source_ranges` and `source_tags` in a firewall rule? Can you use both?

<details>
<summary>Show Answer</summary>

| Attribute | Sources Identified By |
|-----------|----------------------|
| `source_ranges` | CIDR blocks (e.g., `10.0.0.0/8`, `35.235.240.0/20`) |
| `source_tags` | Network tags on source VMs (e.g., `["web-server"]`) |

**Yes, you can use both** on the same rule. When both are specified, traffic is allowed from sources matching **either** condition (OR logic, not AND).

**Important caveats:**
- `source_ranges` and `source_tags` are INGRESS-only attributes
- For EGRESS, you use `destination_ranges` (no `destination_tags` exists)
- `source_tags` only work for VM-to-VM traffic within the same VPC
- For traffic from outside GCP, you must use `source_ranges`

</details>

---

**Question 3:** Why does the firewall module use two separate resources (`allow_rules` and `deny_rules`) instead of one?

<details>
<summary>Show Answer</summary>

The `google_compute_firewall` resource requires exactly **one** of `allow {}` or `deny {}` blocks — you cannot have both in the same resource. If you try:

```hcl
resource "google_compute_firewall" "bad" {
  allow { protocol = "tcp" }
  deny  { protocol = "udp" }  # ERROR: cannot have both
}
```

By splitting into two resources filtered by `action`:

```hcl
# Only processes rules where action == "allow"
resource "google_compute_firewall" "allow_rules" {
  for_each = { for k, v in var.firewall_rules : k => v if v.action == "allow" }
  ...
  dynamic "allow" { ... }
}

# Only processes rules where action == "deny"
resource "google_compute_firewall" "deny_rules" {
  for_each = { for k, v in var.firewall_rules : k => v if v.action == "deny" }
  ...
  dynamic "deny" { ... }
}
```

The `for` expression with `if` filter ensures each resource only processes the correct rule type. The caller doesn't need to worry about this — they just pass all rules in one map.

</details>

---

**Question 4:** A VM has no external IP and no network tags. The VPC has: (a) implied deny-all-ingress at 65535, (b) implied allow-all-egress at 65534, (c) your `deny-all-egress` at 1000, (d) `allow-egress-internal` at 900 for `10.0.0.0/8`. Can the VM ping `8.8.8.8`?

<details>
<summary>Show Answer</summary>

**No, the VM cannot ping `8.8.8.8`.**

Step-by-step rule evaluation for the ICMP packet to `8.8.8.8`:

1. **Priority 900** — `allow-egress-internal`: destination `8.8.8.8` is NOT in `10.0.0.0/8` → no match
2. **Priority 1000** — `deny-all-egress`: destination `8.8.8.8` IS in `0.0.0.0/0` → **MATCH, DENY**

The packet is denied at step 2. The implied `allow-all-egress` at priority 65534 is never reached because your explicit deny at 1000 takes precedence.

To allow this VM to ping `8.8.8.8`, you would need an additional allow rule at priority < 1000 with `destination_ranges = ["8.8.8.8/32"]` and `rules = [{ protocol = "icmp" }]`.

</details>
