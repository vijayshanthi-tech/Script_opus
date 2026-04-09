# Day 28 — Managing Routes in Terraform

> **Week 5 · Terraform Networking** | 2 hours | europe-west2  
> **Pre-reqs:** Day 25–27 complete (VPC, subnets, firewall modules), understanding of IP routing basics

---

## Part 1 — Concept (30 min)

### 1.1 GCP Route Types

```
┌────────────────────────────────────────────────────────────┐
│                    GCP ROUTE TABLE                         │
│                                                            │
│  System Routes (auto-created, cannot delete via Terraform) │
│  ├── Subnet routes: 10.0.1.0/24 → dev-vpc-web            │
│  ├── Subnet routes: 10.0.2.0/24 → dev-vpc-app            │
│  └── Subnet routes: 10.0.3.0/24 → dev-vpc-db             │
│                                                            │
│  Default Route (auto-created, CAN delete)                  │
│  └── 0.0.0.0/0 → default-internet-gateway                 │
│                                                            │
│  Custom Routes (YOU create via Terraform)                  │
│  ├── 192.168.0.0/16 → VPN tunnel (on-prem)               │
│  ├── 0.0.0.0/0 → NAT gateway instance (override default) │
│  └── 10.100.0.0/16 → VPC peering next-hop                │
│                                                            │
│  Peering Routes (auto-exchanged with peered VPCs)          │
│  └── 172.16.0.0/16 → peer-vpc-connection                 │
└────────────────────────────────────────────────────────────┘
```

### 1.2 Route Priority

Routes are selected by **most specific match** (longest prefix), then by **priority** (lowest number wins):

```
Packet destination: 10.0.2.50

Route Table:
  10.0.0.0/8    → VPN tunnel       priority 1000   ← /8  match
  10.0.2.0/24   → subnet (auto)    priority 0      ← /24 match ← SELECTED (most specific)
  0.0.0.0/0     → internet-gw      priority 1000   ← /0  match

Winner: 10.0.2.0/24 (longest prefix match)
```

When two routes have the **same prefix length**:

```
Packet destination: 192.168.1.50

Route Table:
  192.168.0.0/16 → VPN-tunnel-1    priority 100    ← SELECTED (lower priority)
  192.168.0.0/16 → VPN-tunnel-2    priority 200
```

### 1.3 The `google_compute_route` Resource

```
┌──────────────────────────────────────────────────────┐
│            google_compute_route                      │
│                                                      │
│  name ────────────────────► Route name               │
│  network ─────────────────► VPC self_link            │
│  dest_range ──────────────► CIDR to match            │
│  priority ────────────────► 0–65535 (default 1000)   │
│                                                      │
│  Next hop (exactly ONE of):                          │
│  ├── next_hop_gateway ────► default-internet-gateway │
│  ├── next_hop_instance ──► VM instance (NAT box)     │
│  ├── next_hop_ip ─────────► Internal IP of next hop  │
│  ├── next_hop_vpn_tunnel ► VPN tunnel resource       │
│  └── next_hop_ilb ───────► Internal Load Balancer    │
│                                                      │
│  tags ────────────────────► Apply route to tagged VMs│
│  (empty = applies to all VMs in the VPC)             │
└──────────────────────────────────────────────────────┘
```

### 1.4 Common Route Patterns

| Pattern | dest_range | next_hop | Use Case |
|---------|-----------|----------|----------|
| Internet route | `0.0.0.0/0` | `default-internet-gateway` | Default internet access |
| On-prem route | `192.168.0.0/16` | `next_hop_vpn_tunnel` | Hybrid connectivity |
| NAT instance | `0.0.0.0/0` | `next_hop_instance` (NAT VM) | Legacy NAT (pre-Cloud NAT) |
| ILB as next hop | `10.100.0.0/16` | `next_hop_ilb` | Traffic through appliance |
| Blackhole | `10.99.0.0/16` | (none — route with no instances) | Drop traffic |
| Restricted API | `199.36.153.4/30` | `default-internet-gateway` | Private Google Access |

### 1.5 Route Tags — Selective Routing

```
                    VPC: dev-vpc
┌──────────────────────────────────────────────────┐
│                                                  │
│  Route: 0.0.0.0/0 → internet-gw (no tags)       │
│  Applies to: ALL VMs                             │
│                                                  │
│  Route: 0.0.0.0/0 → NAT-instance                │
│  tags = ["use-nat"]                              │
│  Applies to: ONLY VMs with tag "use-nat"         │
│                                                  │
│  ┌─────────┐     ┌─────────┐     ┌─────────┐   │
│  │ web-vm  │     │ app-vm  │     │ db-vm   │   │
│  │ (no tag)│     │ use-nat │     │ use-nat │   │
│  │ → inet  │     │ → NAT   │     │ → NAT   │   │
│  └─────────┘     └─────────┘     └─────────┘   │
└──────────────────────────────────────────────────┘
```

### 1.6 Routes and Cloud NAT Interaction

```
Cloud NAT (modern approach)         NAT Instance (legacy)
───────────────────────             ─────────────────────
• Managed service                   • You manage a VM
• No routes needed                  • Custom route 0.0.0.0/0 → instance
• Scales automatically              • Single point of failure
• Region-specific                   • Manual HA setup
• Preferred for new projects        • Still in use at some orgs

Cloud NAT works at the VPC level and does NOT create routes.
It NATs packets at the Google edge, not inside your VPC.
```

---

## Part 2 — Hands-On Lab (60 min)

### Lab Objective

Create custom routes via Terraform, including a route to simulate on-prem connectivity and a restricted Google API route.

### Step 1 — Create the Routes Module

```bash
mkdir -p ~/tf-networking/modules/routes
```

**`modules/routes/variables.tf`**

```hcl
variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "network_name" {
  description = "Name of the VPC network"
  type        = string
}

variable "routes" {
  description = "Map of custom routes to create"
  type = map(object({
    description            = optional(string, "Managed by Terraform")
    dest_range             = string
    priority               = optional(number, 1000)
    tags                   = optional(list(string), [])
    next_hop_gateway       = optional(string, null)
    next_hop_ip            = optional(string, null)
    next_hop_instance      = optional(string, null)
    next_hop_instance_zone = optional(string, null)
    next_hop_vpn_tunnel    = optional(string, null)
    next_hop_ilb           = optional(string, null)
  }))
  default = {}
}
```

**`modules/routes/main.tf`**

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

resource "google_compute_route" "routes" {
  for_each = var.routes

  name        = "${var.network_name}-${each.key}"
  project     = var.project_id
  network     = var.network_name
  description = each.value.description
  dest_range  = each.value.dest_range
  priority    = each.value.priority
  tags        = length(each.value.tags) > 0 ? each.value.tags : null

  # Exactly one next_hop must be provided
  next_hop_gateway    = each.value.next_hop_gateway
  next_hop_ip         = each.value.next_hop_ip
  next_hop_instance   = each.value.next_hop_instance
  next_hop_vpn_tunnel = each.value.next_hop_vpn_tunnel
  next_hop_ilb        = each.value.next_hop_ilb

  # next_hop_instance_zone is required when next_hop_instance is used
  dynamic "timeouts" {
    for_each = []
    content {}
  }
}
```

**`modules/routes/outputs.tf`**

```hcl
output "route_ids" {
  description = "Map of route name to route ID"
  value = {
    for k, v in google_compute_route.routes : k => v.id
  }
}

output "route_self_links" {
  description = "Map of route name to self_link"
  value = {
    for k, v in google_compute_route.routes : k => v.self_link
  }
}

output "route_next_hops" {
  description = "Map of route name to next hop gateway"
  value = {
    for k, v in google_compute_route.routes : k => v.next_hop_network
  }
}
```

### Step 2 — Call the Routes Module from Root

Add routes to **`environments/dev/main.tf`** (after the existing VPC and firewall modules):

```hcl
# ──────────────────────────────────────
# Custom Routes
# ──────────────────────────────────────
module "routes" {
  source = "../../modules/routes"

  project_id   = var.project_id
  network_name = module.vpc.network_name

  routes = {
    # Route to restricted Google APIs (Private Google Access)
    restricted-google-apis = {
      description      = "Route to restricted.googleapis.com for PGA"
      dest_range       = "199.36.153.4/30"
      priority         = 900
      next_hop_gateway = "default-internet-gateway"
    }

    # Route to private Google APIs
    private-google-apis = {
      description      = "Route to private.googleapis.com for PGA"
      dest_range       = "199.36.153.8/30"
      priority         = 900
      next_hop_gateway = "default-internet-gateway"
    }

    # Simulated on-prem route (via next_hop_ip — in production this would be a VPN tunnel)
    onprem-datacenter = {
      description = "Route to simulated on-prem datacenter"
      dest_range  = "192.168.0.0/16"
      priority    = 800
      next_hop_ip = "10.0.2.10"  # In production: next_hop_vpn_tunnel
    }

    # Force specific VMs through a "NAT" path using tags
    nat-tagged-only = {
      description      = "Internet via tagged route (NAT simulation)"
      dest_range       = "0.0.0.0/0"
      priority         = 800
      tags             = ["use-nat"]
      next_hop_gateway = "default-internet-gateway"
    }
  }
}
```

### Step 3 — Add Route Outputs

Add to **`environments/dev/outputs.tf`**:

```hcl
output "route_ids" {
  value = module.routes.route_ids
}
```

### Step 4 — Deploy and Validate

```bash
cd ~/tf-networking/environments/dev

terraform init -upgrade
terraform validate
terraform plan

# You should see 4 routes being created
terraform apply
```

### Step 5 — Verify Routes

```bash
# List all routes for the VPC
gcloud compute routes list \
  --filter="network:dev-vpc" \
  --project=your-gcp-project-id \
  --format="table(name, destRange, priority, nextHopGateway.basename(), nextHopIp, tags.list())"

# Describe a specific route
gcloud compute routes describe dev-vpc-restricted-google-apis \
  --project=your-gcp-project-id

# Show the full routing table (system + custom routes)
gcloud compute routes list \
  --filter="network:dev-vpc" \
  --project=your-gcp-project-id \
  --sort-by=priority \
  --format="table(name, destRange, priority, nextHopGateway.basename(), nextHopIp, nextHopInstance.basename())"
```

### Step 6 — Verify Route Selection

```bash
# Check what route a specific destination would match
# (This is a conceptual exercise — GCP doesn't have a "route lookup" CLI command)
# Instead, use connectivity tests:

gcloud network-management connectivity-tests create test-route-google \
  --source-instance=projects/your-gcp-project-id/zones/europe-west2-a/instances/test-vm \
  --destination-ip-address=199.36.153.4 \
  --protocol=TCP \
  --destination-port=443 \
  --project=your-gcp-project-id

# View test results
gcloud network-management connectivity-tests describe test-route-google \
  --project=your-gcp-project-id

# Cleanup connectivity test
gcloud network-management connectivity-tests delete test-route-google \
  --project=your-gcp-project-id --quiet
```

### Step 7 — Experiment: Change Route Priority

```bash
# In environments/dev/main.tf, change the onprem-datacenter priority from 800 to 500
# Run terraform plan to see route updated in-place (not recreated)
terraform plan

# Apply the change
terraform apply

# Verify priority changed
gcloud compute routes describe dev-vpc-onprem-datacenter \
  --project=your-gcp-project-id --format="value(priority)"
```

### Step 8 — Cleanup

```bash
terraform destroy
```

---

## Part 3 — Revision (15 min)

### Key Concepts

- GCP routes: system (subnet), default (internet), custom (you create), peering (auto-exchanged)
- Routing uses **longest prefix match** first, then **lowest priority number** as tiebreaker
- Each `google_compute_route` must have exactly **one** `next_hop_*` attribute
- `default-internet-gateway` is a special next-hop that routes to the internet
- `tags` on a route restrict it to VMs with matching network tags — empty = all VMs
- Cloud NAT does NOT create routes — it operates at the Google edge
- `delete_default_routes_on_create = true` on VPC removes `0.0.0.0/0 → internet-gw`
- Private Google Access routes: `199.36.153.4/30` (restricted) and `199.36.153.8/30` (private)
- Routes are global within a VPC (even with REGIONAL routing mode, custom routes are global)
- You cannot create a route to a destination that overlaps with a subnet route

### Essential Commands

```bash
# List routes for a VPC
gcloud compute routes list --filter="network:VPC_NAME"

# Sort by priority
gcloud compute routes list --filter="network:VPC_NAME" --sort-by=priority

# Describe a route
gcloud compute routes describe ROUTE_NAME

# Network connectivity test
gcloud network-management connectivity-tests create TEST_NAME \
  --source-instance=INSTANCE_URI \
  --destination-ip-address=IP \
  --protocol=TCP --destination-port=PORT

# Terraform state for a specific route
terraform state show 'module.routes.google_compute_route.routes["restricted-google-apis"]'
```

### Route Selection Decision Tree

```
Packet arrives → destination IP = X.X.X.X
     │
     ▼
Find all routes where dest_range contains X.X.X.X
     │
     ▼
Select routes with LONGEST prefix match (/24 beats /16)
     │
     ▼
Among those, select route with LOWEST priority number
     │
     ▼
If tied: ECMP (equal-cost multi-path) — traffic is split
     │
     ▼
Route applied → packet forwarded to next_hop
```

---

## Part 4 — Quiz (15 min)

**Question 1:** A VPC has these routes for destination `10.0.2.50`: (a) `10.0.0.0/8 → VPN, priority 100`, (b) `10.0.2.0/24 → subnet auto-route, priority 0`, (c) `0.0.0.0/0 → internet-gw, priority 1000`. Which route is selected and why?

<details>
<summary>Show Answer</summary>

**Route (b)** `10.0.2.0/24 → subnet auto-route` is selected.

Routing uses **longest prefix match first**, regardless of priority:

| Route | Prefix Length | Matches `10.0.2.50`? | Priority |
|-------|-------------|----------------------|----------|
| `10.0.2.0/24` | /24 | Yes | 0 |
| `10.0.0.0/8` | /8 | Yes | 100 |
| `0.0.0.0/0` | /0 | Yes | 1000 |

The `/24` is the most specific match. Even though the VPN route has a very low priority number (100), the subnet route wins because `/24 > /8 > /0`.

Priority only breaks ties when multiple routes have the **same** prefix length for the same destination.

</details>

---

**Question 2:** What happens if you set `delete_default_routes_on_create = true` on a VPC and forget to create a Cloud NAT or custom internet route?

<details>
<summary>Show Answer</summary>

**All egress traffic to the internet will be blackholed.** VMs in the VPC will:

- ❌ Cannot reach the internet (no `0.0.0.0/0` route exists)
- ❌ Cannot reach Google APIs (unless you add PGA routes to `199.36.153.x/30`)
- ❌ Cannot pull apt/yum packages
- ❌ Cannot resolve external DNS (unless using Cloud DNS with private zones)
- ✅ Can still communicate within the VPC (subnet routes still exist)

**Fix:** Either add Cloud NAT (doesn't need routes) or create explicit routes:

```hcl
google_compute_route "internet" {
  dest_range       = "0.0.0.0/0"
  next_hop_gateway = "default-internet-gateway"
}
```

**Best practice:** Don't use `delete_default_routes_on_create = true` unless you've already planned your routing strategy.

</details>

---

**Question 3:** How do route `tags` differ from firewall `target_tags`? Can you use both together?

<details>
<summary>Show Answer</summary>

| Feature | Route Tags | Firewall target_tags |
|---------|-----------|---------------------|
| Applied to | VMs (network tags) | VMs (network tags) |
| Effect | Route only applies to tagged VMs | Firewall rule only targets tagged VMs |
| Empty value | Route applies to **all** VMs | Rule applies to **all** VMs |
| Scope | Routing decision (where to send) | Access control (allow/deny) |

**Yes, you can use both together** and they work independently:

1. A route with `tags = ["use-nat"]` means only VMs with that tag use the route
2. A firewall with `target_tags = ["use-nat"]` means only those VMs are affected by the rule
3. A packet first matches a route (routing decision), then the firewall rule is evaluated

**Example:** Tag a VM with `use-nat`. The route sends its traffic through a NAT gateway, and the firewall allow rule permits that egress.

</details>

---

**Question 4:** Your Terraform creates a route `onprem-datacenter` with `next_hop_ip = "10.0.2.10"` but the IP doesn't belong to any running instance. What happens to packets matching this route?

<details>
<summary>Show Answer</summary>

**GCP drops the packets** (blackhole). When a route's `next_hop_ip` points to an IP that:

1. Doesn't exist in the VPC → packets are dropped silently
2. Belongs to a stopped VM → packets are dropped
3. Belongs to a running VM without IP forwarding → packets are dropped at the VM

Terraform will **not** validate that the IP exists — this is a runtime behaviour.

**How to diagnose:**

```bash
# Check if the IP is in use
gcloud compute addresses list --filter="address=10.0.2.10"

# Check if the VM has ip_forwarding enabled
gcloud compute instances describe VM_NAME --format="value(canIpForward)"
```

**Best practice:** In production, use `next_hop_vpn_tunnel` or `next_hop_ilb` instead of `next_hop_ip` — they are more robust and support health checking.

</details>
