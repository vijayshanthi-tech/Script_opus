# Day 21 — Terraform VPC & Firewall: Networking as Code

> **Week 4 · Terraform Basics** | Region: `europe-west2` | Study time: 2 hours

---

## Part 1 — Concept (30 min)

### 1.1 Why Terraform for Networking?

In Week 2 you created VPCs, subnets, and firewalls with `gcloud` commands. The problem: **those commands are imperative and stateless** — run them twice and you get errors or duplicates. Terraform tracks state so your network config is **declarative, repeatable, and version-controlled**.

| Week 2 (gcloud) | Week 4 (Terraform) |
|---|---|
| `gcloud compute networks create ...` | `resource "google_compute_network"` |
| `gcloud compute networks subnets create ...` | `resource "google_compute_subnetwork"` |
| `gcloud compute firewall-rules create ...` | `resource "google_compute_firewall"` |
| Manual cleanup with `delete` commands | `terraform destroy` removes everything |
| No dependency tracking | Terraform knows subnet depends on VPC |

### 1.2 GCP Networking Resources in Terraform

```
┌──────────────────────────────────────────────────────────────┐
│              TERRAFORM GCP NETWORKING RESOURCES               │
│                                                              │
│  ┌──────────────────────────────────────────────────┐        │
│  │  google_compute_network                          │        │
│  │  (VPC — the container)                           │        │
│  │                                                  │        │
│  │  ┌────────────────────┐  ┌────────────────────┐  │        │
│  │  │ google_compute_    │  │ google_compute_    │  │        │
│  │  │ subnetwork         │  │ subnetwork         │  │        │
│  │  │ (subnet-a)         │  │ (subnet-b)         │  │        │
│  │  │ 10.0.1.0/24        │  │ 10.0.2.0/24        │  │        │
│  │  │ europe-west2       │  │ europe-west2       │  │        │
│  │  └────────────────────┘  └────────────────────┘  │        │
│  │                                                  │        │
│  └──────────────────────────────────────────────────┘        │
│                                                              │
│  ┌──────────────────────────────────────────────────┐        │
│  │  google_compute_firewall (rules applied to VPC)  │        │
│  │                                                  │        │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────────┐   │        │
│  │  │ allow-ssh│  │allow-http│  │ allow-icmp   │   │        │
│  │  │ tcp:22   │  │ tcp:80   │  │ icmp         │   │        │
│  │  │ tag:ssh  │  │ tag:http │  │ all targets  │   │        │
│  │  └──────────┘  └──────────┘  └──────────────┘   │        │
│  └──────────────────────────────────────────────────┘        │
└──────────────────────────────────────────────────────────────┘
```

### 1.3 Resource: google_compute_network

```hcl
resource "google_compute_network" "vpc" {
  name                    = "tf-lab-vpc"
  auto_create_subnetworks = false   # Custom mode (we create subnets manually)
  routing_mode            = "REGIONAL"
  description             = "Lab VPC created by Terraform"
}
```

| Argument | Description | Linux Analogy |
|---|---|---|
| `name` | VPC name (unique per project) | Network namespace name |
| `auto_create_subnetworks` | `false` = custom mode (recommended) | Manual vs auto IP assignment |
| `routing_mode` | `REGIONAL` or `GLOBAL` | Routing scope |

> **Key:** Always use `auto_create_subnetworks = false` for production. Auto-mode creates subnets in every region — wasteful and uncontrolled.

### 1.4 Resource: google_compute_subnetwork

```hcl
resource "google_compute_subnetwork" "main" {
  name          = "tf-subnet-main"
  ip_cidr_range = "10.0.1.0/24"
  region        = "europe-west2"
  network       = google_compute_network.vpc.id   # Reference!

  private_ip_google_access = true
  
  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}
```

| Argument | Description |
|---|---|
| `ip_cidr_range` | Subnet CIDR (like `10.0.1.0/24`) |
| `region` | Region for the subnet |
| `network` | **Reference** to the VPC resource (Terraform handles dependency) |
| `private_ip_google_access` | Allow VMs without external IP to reach Google APIs |
| `log_config` | Enable VPC Flow Logs (Week 3 monitoring tie-in) |

### 1.5 Resource: google_compute_firewall

```hcl
resource "google_compute_firewall" "allow_ssh" {
  name    = "tf-allow-ssh"
  network = google_compute_network.vpc.id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]    # Who can reach
  target_tags   = ["ssh-allowed"]   # Which VMs this applies to

  direction = "INGRESS"
  priority  = 1000

  description = "Allow SSH from anywhere to tagged VMs"
}
```

| Argument | Description | Linux Analogy |
|---|---|---|
| `allow { protocol, ports }` | Traffic to permit | `iptables -A INPUT -p tcp --dport 22 -j ACCEPT` |
| `source_ranges` | Source CIDR(s) | `-s 0.0.0.0/0` |
| `target_tags` | Only VMs with these network tags | Interface-specific rules |
| `direction` | `INGRESS` or `EGRESS` | `INPUT` vs `OUTPUT` chain |
| `priority` | 0 (highest) to 65535 (lowest) | Rule ordering |

### 1.6 Implicit Dependencies

Terraform automatically understands that a **subnet depends on its VPC** because you reference `google_compute_network.vpc.id`:

```
┌───────────────────┐
│  google_compute_  │
│  network.vpc      │ ◄── Created first
└────────┬──────────┘
         │  .id referenced by
         ▼
┌───────────────────┐
│  google_compute_  │
│  subnetwork.main  │ ◄── Created second (waits for VPC)
└────────┬──────────┘
         │  .id referenced by
         ▼
┌───────────────────┐
│  google_compute_  │
│  firewall.rules   │ ◄── Created third (waits for VPC)
└───────────────────┘
```

> **Linux analogy:** It's like Makefile dependencies — `app: lib.o utils.o` means `lib.o` and `utils.o` are built before `app`.

---

## Part 2 — Hands-On Lab (60 min)

### Lab Goal

Create a complete VPC with two subnets, three firewall rules, and a VM in the custom VPC — all via Terraform.

### Prerequisites

```bash
gcloud config set project YOUR_PROJECT_ID
gcloud config set compute/region europe-west2
gcloud config set compute/zone europe-west2-b
```

### Step 1 — Create Project Directory

```bash
mkdir -p ~/tf-day21 && cd ~/tf-day21
```

### Step 2 — Write providers.tf

```bash
cat > providers.tf << 'EOF'
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
EOF
```

### Step 3 — Write variables.tf

```bash
cat > variables.tf << 'EOF'
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
  default     = "europe-west2-b"
}

variable "vpc_name" {
  description = "Name of the VPC"
  type        = string
  default     = "tf-lab-vpc"
}

variable "subnet_cidr_web" {
  description = "CIDR for the web subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "subnet_cidr_app" {
  description = "CIDR for the app subnet"
  type        = string
  default     = "10.0.2.0/24"
}

variable "allowed_ssh_cidrs" {
  description = "CIDRs allowed to SSH"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}
EOF
```

### Step 4 — Write main.tf (VPC + Subnets)

```bash
cat > main.tf << 'EOF'
# ──────────────────────────────────────────────
# VPC
# ──────────────────────────────────────────────

resource "google_compute_network" "vpc" {
  name                    = var.vpc_name
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
  description             = "Day 21 lab VPC"
}

# ──────────────────────────────────────────────
# Subnets
# ──────────────────────────────────────────────

resource "google_compute_subnetwork" "web" {
  name          = "${var.vpc_name}-web"
  ip_cidr_range = var.subnet_cidr_web
  region        = var.region
  network       = google_compute_network.vpc.id

  private_ip_google_access = true

  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

resource "google_compute_subnetwork" "app" {
  name          = "${var.vpc_name}-app"
  ip_cidr_range = var.subnet_cidr_app
  region        = var.region
  network       = google_compute_network.vpc.id

  private_ip_google_access = true
}

# ──────────────────────────────────────────────
# Firewall Rules
# ──────────────────────────────────────────────

resource "google_compute_firewall" "allow_ssh" {
  name    = "${var.vpc_name}-allow-ssh"
  network = google_compute_network.vpc.id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = var.allowed_ssh_cidrs
  target_tags   = ["ssh-allowed"]
  direction     = "INGRESS"
  priority      = 1000
  description   = "Allow SSH to tagged VMs"
}

resource "google_compute_firewall" "allow_http" {
  name    = "${var.vpc_name}-allow-http"
  network = google_compute_network.vpc.id

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["http-server"]
  direction     = "INGRESS"
  priority      = 1000
  description   = "Allow HTTP/HTTPS to tagged VMs"
}

resource "google_compute_firewall" "allow_internal" {
  name    = "${var.vpc_name}-allow-internal"
  network = google_compute_network.vpc.id

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "icmp"
  }

  # Allow all traffic between the two subnets
  source_ranges = [var.subnet_cidr_web, var.subnet_cidr_app]
  direction     = "INGRESS"
  priority      = 900
  description   = "Allow all internal traffic between subnets"
}

# ──────────────────────────────────────────────
# Test VM (in the web subnet)
# ──────────────────────────────────────────────

resource "google_compute_instance" "web_vm" {
  name         = "tf-web-vm"
  machine_type = "e2-micro"
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 10
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.web.id

    access_config {}  # External IP
  }

  tags = ["ssh-allowed", "http-server"]

  labels = {
    env     = "lab"
    week    = "4"
    day     = "21"
    managed = "terraform"
  }

  metadata = {
    enable-oslogin = "TRUE"
  }

  metadata_startup_script = <<-SCRIPT
    #!/bin/bash
    apt-get update && apt-get install -y nginx
    echo "<h1>Day 21 — Terraform VPC Lab</h1><p>VM: $(hostname)</p>" > /var/www/html/index.html
    systemctl enable nginx && systemctl start nginx
  SCRIPT
}
EOF
```

### Step 5 — Write outputs.tf

```bash
cat > outputs.tf << 'EOF'
output "vpc_name" {
  description = "VPC name"
  value       = google_compute_network.vpc.name
}

output "vpc_self_link" {
  description = "VPC self-link"
  value       = google_compute_network.vpc.self_link
}

output "web_subnet_cidr" {
  description = "Web subnet CIDR"
  value       = google_compute_subnetwork.web.ip_cidr_range
}

output "app_subnet_cidr" {
  description = "App subnet CIDR"
  value       = google_compute_subnetwork.app.ip_cidr_range
}

output "firewall_rules" {
  description = "Firewall rule names"
  value = [
    google_compute_firewall.allow_ssh.name,
    google_compute_firewall.allow_http.name,
    google_compute_firewall.allow_internal.name,
  ]
}

output "web_vm_name" {
  description = "Web VM name"
  value       = google_compute_instance.web_vm.name
}

output "web_vm_external_ip" {
  description = "Web VM external IP"
  value       = google_compute_instance.web_vm.network_interface[0].access_config[0].nat_ip
}

output "web_vm_internal_ip" {
  description = "Web VM internal IP (in web subnet)"
  value       = google_compute_instance.web_vm.network_interface[0].network_ip
}

output "web_url" {
  description = "URL to test the web server"
  value       = "http://${google_compute_instance.web_vm.network_interface[0].access_config[0].nat_ip}"
}
EOF
```

### Step 6 — Write terraform.tfvars

```bash
cat > terraform.tfvars << 'EOF'
project_id      = "YOUR_PROJECT_ID"
region          = "europe-west2"
zone            = "europe-west2-b"
vpc_name        = "tf-lab-vpc"
subnet_cidr_web = "10.0.1.0/24"
subnet_cidr_app = "10.0.2.0/24"
EOF
```

### Step 7 — Init, Plan, Apply

```bash
terraform init
terraform fmt
terraform validate

# Plan — review the dependency graph
terraform plan

# Apply
terraform apply
```

**Expected plan output:**

```
Plan: 6 to add, 0 to change, 0 to destroy.

  # google_compute_network.vpc
  # google_compute_subnetwork.web
  # google_compute_subnetwork.app
  # google_compute_firewall.allow_ssh
  # google_compute_firewall.allow_http
  # google_compute_firewall.allow_internal
  # google_compute_instance.web_vm  (7 with VM)
```

### Step 8 — Verify with gcloud

```bash
# List VPCs
gcloud compute networks list --filter="name=tf-lab-vpc"

# List subnets
gcloud compute networks subnets list --filter="network~tf-lab-vpc" \
    --format="table(name,region,ipCidrRange)"

# List firewall rules
gcloud compute firewall-rules list --filter="network~tf-lab-vpc" \
    --format="table(name,direction,allowed,sourceRanges,targetTags)"

# Check the VM
gcloud compute instances list --filter="name=tf-web-vm"

# Test the web server
WEB_IP=$(terraform output -raw web_vm_external_ip)
curl -s "http://$WEB_IP"
```

### Step 9 — SSH and Verify Networking

```bash
# SSH to the web VM
gcloud compute ssh tf-web-vm --zone=europe-west2-b

# --- Inside the VM ---

# Check which subnet we're on
ip addr show ens4
# Should show 10.0.1.x (web subnet)

# Verify nginx is running
curl -s localhost
# Should show "Day 21 — Terraform VPC Lab"

# Check routing table
ip route

exit
```

### Step 10 — Inspect Terraform Internals

```bash
# View the dependency graph (requires graphviz for visual)
terraform graph

# List all resources in state
terraform state list

# Show detailed state for the VPC
terraform state show google_compute_network.vpc

# Show detailed state for a firewall rule
terraform state show google_compute_firewall.allow_ssh
```

### Cleanup

```bash
# Destroy all resources in reverse dependency order
terraform destroy

# Verify nothing remains
gcloud compute instances list --filter="labels.day=21"
gcloud compute networks list --filter="name=tf-lab-vpc"
gcloud compute firewall-rules list --filter="network~tf-lab-vpc"

# Clean up directory
cd ~ && rm -rf ~/tf-day21
```

---

## Part 3 — Revision (15 min)

### Key Concepts

- **`google_compute_network`** = VPC; always use `auto_create_subnetworks = false` (custom mode)
- **`google_compute_subnetwork`** = subnet inside a VPC; specify `ip_cidr_range` and `region`
- **`google_compute_firewall`** = firewall rule attached to a VPC; uses `allow {}` blocks
- **Implicit dependencies**: referencing `google_compute_network.vpc.id` in a subnet tells Terraform to create the VPC first
- Firewall `source_ranges` = who can send traffic; `target_tags` = which VMs receive it
- `priority` ranges 0–65535; lower number = higher priority
- VPC Flow Logs enabled via `log_config {}` in subnet — useful for monitoring (Week 3)
- `private_ip_google_access = true` lets VMs without external IPs reach Google APIs
- String interpolation: `"${var.vpc_name}-web"` for dynamic naming
- Terraform destroys in reverse dependency order (VM → firewall → subnet → VPC)

### Essential Commands

```bash
# Terraform networking resources
resource "google_compute_network" "name" { ... }
resource "google_compute_subnetwork" "name" { ... }
resource "google_compute_firewall" "name" { ... }

# Verify with gcloud
gcloud compute networks list
gcloud compute networks subnets list --filter="network~VPC_NAME"
gcloud compute firewall-rules list --filter="network~VPC_NAME"

# Terraform inspection
terraform graph                         # Dependency graph (DOT format)
terraform state list                    # All tracked resources
terraform state show RESOURCE_ADDRESS   # Details of one resource
```

---

## Part 4 — Quiz (15 min)

**Question 1: You set `auto_create_subnetworks = true` in your VPC resource. What happens, and why is this generally not recommended?**

<details>
<summary>Show Answer</summary>

With `auto_create_subnetworks = true`, GCP automatically creates **one subnet in every region** with predefined CIDR ranges (from the `10.128.0.0/9` range). This is called **auto mode**.

It's not recommended because:
- You can't control CIDR ranges (they may overlap with on-prem or other VPCs)
- Subnets are created in regions you don't use (wasteful)
- Hard to peer with other VPCs due to CIDR overlap risk
- Not suitable for production network design

Always use `auto_create_subnetworks = false` (custom mode) and explicitly declare subnets with your own CIDR ranges.

</details>

---

**Question 2: You apply your config and the VM is created. Then you change the subnet CIDR from `10.0.1.0/24` to `10.0.1.0/20` in your `.tf` file. What happens when you run `terraform plan`?**

<details>
<summary>Show Answer</summary>

Terraform will show the subnet needs to be **destroyed and recreated** (`-/+` force replacement). Changing `ip_cidr_range` on a `google_compute_subnetwork` is a **destructive change** — GCP doesn't allow in-place CIDR modification.

Since the **VM depends on the subnet**, Terraform will also plan to **destroy and recreate the VM**. The cascade looks like:

```
-/+ google_compute_subnetwork.web (forces replacement)
-/+ google_compute_instance.web_vm (forces replacement, depends on subnet)
```

This highlights why CIDR planning matters upfront — changing it later causes downtime.

> Note: GCP does allow **expanding** a subnet CIDR (e.g., /24 → /20) via `gcloud compute networks subnets expand-ip-range`, but Terraform treats `ip_cidr_range` changes as replace by default.

</details>

---

**Question 3: Your firewall rule has `target_tags = ["http-server"]` but your VM doesn't have the tag `http-server`. Does the firewall rule apply to that VM?**

<details>
<summary>Show Answer</summary>

**No.** Firewall rules with `target_tags` only apply to VMs that have the matching network tag. If your VM has `tags = ["ssh-allowed"]` but not `"http-server"`, the HTTP firewall rule is ignored for that VM.

This is the same behaviour as Week 2:
- `target_tags` = whitelist of VMs the rule affects
- If `target_tags` is omitted, the rule applies to **all VMs** in the VPC
- Tags are set on VMs, not on subnets

In Terraform, ensure your `google_compute_instance` resource includes all required tags: `tags = ["ssh-allowed", "http-server"]`.

</details>

---

**Question 4: You delete the `google_compute_firewall.allow_ssh` resource block from your `.tf` file but keep everything else. What happens on next `terraform apply`?**

<details>
<summary>Show Answer</summary>

Terraform will **destroy the SSH firewall rule** because it's no longer in the config but still exists in state.

```
Plan: 0 to add, 0 to change, 1 to destroy.

  # google_compute_firewall.allow_ssh will be destroyed
  - resource "google_compute_firewall" "allow_ssh" { ... }
```

After apply, the SSH firewall rule is deleted from GCP. If you're SSH'd into the VM, your existing session may continue (TCP connections are stateful), but **new SSH connections will be blocked** because there's no firewall rule allowing port 22.

This is an important difference from `gcloud`: deleting a `.tf` block triggers destruction. With `gcloud`, you'd need an explicit `gcloud compute firewall-rules delete` command.

</details>

---

*End of Day 21 — Tomorrow: Terraform state, drift detection, and state recovery.*
