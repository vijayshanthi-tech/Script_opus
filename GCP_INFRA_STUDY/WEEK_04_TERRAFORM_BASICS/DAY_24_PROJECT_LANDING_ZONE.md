# Day 24 — PROJECT: Terraform Landing Zone Lite

> **Week 4 · Terraform Basics** | Region: `europe-west2` | Study time: 2 hours

---

## Project Overview

Build a **Terraform Landing Zone Lite** — a complete, modular infrastructure deployment combining everything from Week 4: lifecycle, variables, VPC/firewall, state management, and modules.

### What You Will Build

```
┌───────────────────────────────────────────────────────────────────────┐
│                   TERRAFORM LANDING ZONE LITE                         │
│                                                                       │
│  ┌─────────────────────────────────────────────────────────────────┐  │
│  │                         VPC MODULE                              │  │
│  │                                                                 │  │
│  │   ┌───────────────────────────────┐                             │  │
│  │   │  google_compute_network       │                             │  │
│  │   │  "lz-vpc" (custom mode)       │                             │  │
│  │   └────────────────┬──────────────┘                             │  │
│  │                    │                                            │  │
│  │   ┌────────────────┴──────────────┐                             │  │
│  │   │                               │                             │  │
│  │   ▼                               ▼                             │  │
│  │  ┌──────────────────┐  ┌──────────────────┐                     │  │
│  │  │ Subnet: web      │  │ Subnet: app      │                     │  │
│  │  │ 10.10.1.0/24     │  │ 10.10.2.0/24     │                     │  │
│  │  │ europe-west2     │  │ europe-west2     │                     │  │
│  │  └──────────────────┘  └──────────────────┘                     │  │
│  │                                                                 │  │
│  │  ┌──────────┐  ┌──────────┐  ┌────────────┐  ┌──────────────┐  │  │
│  │  │allow-ssh │  │allow-http│  │allow-icmp  │  │allow-internal│  │  │
│  │  │tcp:22    │  │tcp:80,443│  │icmp        │  │all internal  │  │  │
│  │  └──────────┘  └──────────┘  └────────────┘  └──────────────┘  │  │
│  └─────────────────────────────────────────────────────────────────┘  │
│                                                                       │
│  ┌─────────────────────────────────────────────────────────────────┐  │
│  │                          VM MODULE                              │  │
│  │                                                                 │  │
│  │  ┌──────────────────────┐    ┌──────────────────────┐           │  │
│  │  │ web-server           │    │ app-server           │           │  │
│  │  │ e2-small             │    │ e2-micro             │           │  │
│  │  │ web subnet           │    │ app subnet           │           │  │
│  │  │ external IP: yes     │    │ external IP: no      │           │  │
│  │  │ nginx installed      │    │ internal only        │           │  │
│  │  └──────────────────────┘    └──────────────────────┘           │  │
│  └─────────────────────────────────────────────────────────────────┘  │
│                                                                       │
│  Outputs: VPC name, subnet CIDRs, VM IPs, SSH commands, web URL      │
└───────────────────────────────────────────────────────────────────────┘
```

### Checklist

```
[ ] 1.  Create directory structure with modules/vpc/ and modules/vm/
[ ] 2.  Write VPC module (VPC + subnets + firewall rules)
[ ] 3.  Write VM module (reusable compute instance)
[ ] 4.  Write root module calling both modules
[ ] 5.  Write variables.tf with all configurable parameters
[ ] 6.  Write outputs.tf exposing all useful values
[ ] 7.  Write terraform.tfvars with lab values
[ ] 8.  terraform init
[ ] 9.  terraform fmt && terraform validate
[ ] 10. terraform plan — review the full plan
[ ] 11. terraform apply
[ ] 12. Verify: gcloud, curl, SSH
[ ] 13. Test: modify a variable and re-apply
[ ] 14. Cleanup: terraform destroy
```

---

## Part 1 — Concept Review (30 min)

### Week 4 Recap — Components & How They Connect

| Day | Topic | Role in This Project |
|---|---|---|
| Day 19 | Lifecycle | `init` → `plan` → `apply` → `destroy` for the entire landing zone |
| Day 20 | Variables & Outputs | All resources parameterised; outputs for IPs, names, SSH commands |
| Day 21 | VPC & Firewall | VPC module creates network, subnets, firewall rules |
| Day 22 | State & Drift | State tracks all resources; destroy cleans everything |
| Day 23 | Modules | VPC module + VM module composed in root |

### Architecture — Dependency Graph

```
           providers.tf
                │
                ▼
    ┌───────────────────────┐
    │     ROOT MODULE       │
    │     main.tf           │
    └───────┬───────────────┘
            │
    ┌───────┴───────────────┐
    │                       │
    ▼                       ▼
┌─────────────┐     ┌─────────────┐
│ module.vpc  │     │  (depends   │
│             │     │   on VPC)   │
│ VPC         │     │             │
│ Subnets     │     │ module.web  │
│ Firewalls   │     │ module.app  │
└──────┬──────┘     └─────────────┘
       │                    ▲
       │  outputs:          │  inputs:
       │  vpc_id            │  subnetwork
       │  subnet_ids        │
       └────────────────────┘
```

### Complete Directory Structure

```
tf-landing-zone/
├── main.tf                  # Root: calls VPC + VM modules
├── variables.tf             # Root: all input variables
├── outputs.tf               # Root: exposes key values
├── providers.tf             # Provider + version constraints
├── terraform.tfvars         # Lab-specific values
├── README.md                # Documentation
│
└── modules/
    ├── vpc/
    │   ├── main.tf          # VPC + subnets + firewalls
    │   ├── variables.tf     # VPC module inputs
    │   └── outputs.tf       # VPC module outputs
    │
    └── vm/
        ├── main.tf          # Compute instance
        ├── variables.tf     # VM module inputs
        └── outputs.tf       # VM module outputs
```

---

## Part 2 — Hands-On Build (60 min)

### Prerequisites

```bash
gcloud config set project YOUR_PROJECT_ID
gcloud config set compute/region europe-west2
gcloud config set compute/zone europe-west2-b
PROJECT_ID=$(gcloud config get-value project)
```

### Step 1 — Create Directory Structure

```bash
mkdir -p ~/tf-landing-zone/modules/{vpc,vm}
cd ~/tf-landing-zone
```

### Step 2 — VPC Module

**modules/vpc/variables.tf:**

```bash
cat > modules/vpc/variables.tf << 'EOF'
variable "vpc_name" {
  description = "Name of the VPC network"
  type        = string
}

variable "region" {
  description = "GCP region for subnets"
  type        = string
  default     = "europe-west2"
}

variable "subnets" {
  description = "Map of subnets to create"
  type = map(object({
    cidr                     = string
    private_google_access    = optional(bool, true)
    enable_flow_logs         = optional(bool, false)
  }))
}

variable "allowed_ssh_cidrs" {
  description = "CIDRs allowed to SSH"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enable_http" {
  description = "Create HTTP/HTTPS firewall rule"
  type        = bool
  default     = true
}
EOF
```

**modules/vpc/main.tf:**

```bash
cat > modules/vpc/main.tf << 'EOF'
# ──────────────────────────────────────────────
# VPC Network
# ──────────────────────────────────────────────

resource "google_compute_network" "vpc" {
  name                    = var.vpc_name
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
  description             = "Landing Zone VPC: ${var.vpc_name}"
}

# ──────────────────────────────────────────────
# Subnets (created from map variable)
# ──────────────────────────────────────────────

resource "google_compute_subnetwork" "subnets" {
  for_each = var.subnets

  name          = "${var.vpc_name}-${each.key}"
  ip_cidr_range = each.value.cidr
  region        = var.region
  network       = google_compute_network.vpc.id

  private_ip_google_access = each.value.private_google_access

  dynamic "log_config" {
    for_each = each.value.enable_flow_logs ? [1] : []
    content {
      aggregation_interval = "INTERVAL_10_MIN"
      flow_sampling        = 0.5
      metadata             = "INCLUDE_ALL_METADATA"
    }
  }
}

# ──────────────────────────────────────────────
# Firewall Rules
# ──────────────────────────────────────────────

# Allow SSH
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
  description   = "Allow SSH to tagged instances"
}

# Allow HTTP/HTTPS (conditional)
resource "google_compute_firewall" "allow_http" {
  count = var.enable_http ? 1 : 0

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
  description   = "Allow HTTP/HTTPS to tagged instances"
}

# Allow ICMP (ping)
resource "google_compute_firewall" "allow_icmp" {
  name    = "${var.vpc_name}-allow-icmp"
  network = google_compute_network.vpc.id

  allow {
    protocol = "icmp"
  }

  source_ranges = ["0.0.0.0/0"]
  direction     = "INGRESS"
  priority      = 1000
  description   = "Allow ICMP (ping) from anywhere"
}

# Allow all internal traffic between subnets
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

  source_ranges = [for s in var.subnets : s.cidr]
  direction     = "INGRESS"
  priority      = 900
  description   = "Allow all internal traffic between subnets"
}
EOF
```

**modules/vpc/outputs.tf:**

```bash
cat > modules/vpc/outputs.tf << 'EOF'
output "vpc_name" {
  description = "VPC network name"
  value       = google_compute_network.vpc.name
}

output "vpc_id" {
  description = "VPC network ID"
  value       = google_compute_network.vpc.id
}

output "vpc_self_link" {
  description = "VPC self-link"
  value       = google_compute_network.vpc.self_link
}

output "subnet_ids" {
  description = "Map of subnet name to ID"
  value       = { for k, v in google_compute_subnetwork.subnets : k => v.id }
}

output "subnet_self_links" {
  description = "Map of subnet name to self-link"
  value       = { for k, v in google_compute_subnetwork.subnets : k => v.self_link }
}

output "subnet_cidrs" {
  description = "Map of subnet name to CIDR"
  value       = { for k, v in google_compute_subnetwork.subnets : k => v.ip_cidr_range }
}

output "firewall_rules" {
  description = "List of firewall rule names"
  value = compact([
    google_compute_firewall.allow_ssh.name,
    google_compute_firewall.allow_icmp.name,
    google_compute_firewall.allow_internal.name,
    var.enable_http ? google_compute_firewall.allow_http[0].name : "",
  ])
}
EOF
```

### Step 3 — VM Module

**modules/vm/variables.tf:**

```bash
cat > modules/vm/variables.tf << 'EOF'
variable "vm_name" {
  description = "Name of the VM instance"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,62}$", var.vm_name))
    error_message = "vm_name must be lowercase, start with a letter, max 63 chars."
  }
}

variable "machine_type" {
  description = "Machine type"
  type        = string
  default     = "e2-micro"
}

variable "zone" {
  description = "GCP zone"
  type        = string
  default     = "europe-west2-b"
}

variable "image" {
  description = "Boot disk image"
  type        = string
  default     = "debian-cloud/debian-12"
}

variable "disk_size_gb" {
  description = "Boot disk size in GB"
  type        = number
  default     = 10
}

variable "subnetwork" {
  description = "Subnetwork self-link or ID"
  type        = string
}

variable "tags" {
  description = "Network tags"
  type        = list(string)
  default     = []
}

variable "labels" {
  description = "Labels to apply"
  type        = map(string)
  default     = {}
}

variable "enable_external_ip" {
  description = "Whether to assign an external IP"
  type        = bool
  default     = true
}

variable "startup_script" {
  description = "Startup script content (optional)"
  type        = string
  default     = ""
}
EOF
```

**modules/vm/main.tf:**

```bash
cat > modules/vm/main.tf << 'EOF'
resource "google_compute_instance" "vm" {
  name         = var.vm_name
  machine_type = var.machine_type
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = var.image
      size  = var.disk_size_gb
    }
  }

  network_interface {
    subnetwork = var.subnetwork

    dynamic "access_config" {
      for_each = var.enable_external_ip ? [1] : []
      content {}
    }
  }

  tags = var.tags

  labels = merge(
    { managed = "terraform" },
    var.labels
  )

  metadata = {
    enable-oslogin = "TRUE"
  }

  metadata_startup_script = var.startup_script != "" ? var.startup_script : null
}
EOF
```

**modules/vm/outputs.tf:**

```bash
cat > modules/vm/outputs.tf << 'EOF'
output "name" {
  description = "VM name"
  value       = google_compute_instance.vm.name
}

output "self_link" {
  description = "VM self-link"
  value       = google_compute_instance.vm.self_link
}

output "zone" {
  description = "VM zone"
  value       = google_compute_instance.vm.zone
}

output "internal_ip" {
  description = "Internal IP"
  value       = google_compute_instance.vm.network_interface[0].network_ip
}

output "external_ip" {
  description = "External IP (empty if disabled)"
  value       = var.enable_external_ip ? google_compute_instance.vm.network_interface[0].access_config[0].nat_ip : ""
}

output "instance_id" {
  description = "Instance ID"
  value       = google_compute_instance.vm.instance_id
}
EOF
```

### Step 4 — Root Module

**providers.tf:**

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
  zone    = var.zone
}
EOF
```

**variables.tf (root):**

```bash
cat > variables.tf << 'EOF'
# ── Project ──

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

# ── Naming ──

variable "environment" {
  description = "Environment name (lab, dev, staging, prod)"
  type        = string
  default     = "lab"

  validation {
    condition     = contains(["lab", "dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: lab, dev, staging, prod."
  }
}

variable "name_prefix" {
  description = "Prefix for all resource names"
  type        = string
  default     = "lz"
}

# ── VPC ──

variable "vpc_name" {
  description = "VPC name"
  type        = string
  default     = "lz-vpc"
}

variable "web_subnet_cidr" {
  description = "Web tier subnet CIDR"
  type        = string
  default     = "10.10.1.0/24"
}

variable "app_subnet_cidr" {
  description = "App tier subnet CIDR"
  type        = string
  default     = "10.10.2.0/24"
}

# ── Web VM ──

variable "web_machine_type" {
  description = "Machine type for web server"
  type        = string
  default     = "e2-small"
}

# ── App VM ──

variable "app_machine_type" {
  description = "Machine type for app server"
  type        = string
  default     = "e2-micro"
}
EOF
```

**main.tf (root):**

```bash
cat > main.tf << 'EOF'
# ══════════════════════════════════════════════════
# LANDING ZONE — NETWORKING
# ══════════════════════════════════════════════════

module "vpc" {
  source = "./modules/vpc"

  vpc_name = var.vpc_name
  region   = var.region

  subnets = {
    web = {
      cidr              = var.web_subnet_cidr
      enable_flow_logs  = true
    }
    app = {
      cidr              = var.app_subnet_cidr
      enable_flow_logs  = false
    }
  }

  enable_http = true
}

# ══════════════════════════════════════════════════
# LANDING ZONE — COMPUTE
# ══════════════════════════════════════════════════

module "web_vm" {
  source = "./modules/vm"

  vm_name      = "${var.name_prefix}-web-server"
  machine_type = var.web_machine_type
  zone         = var.zone
  subnetwork   = module.vpc.subnet_ids["web"]

  tags = ["ssh-allowed", "http-server"]

  labels = {
    env  = var.environment
    tier = "web"
  }

  enable_external_ip = true

  startup_script = <<-SCRIPT
    #!/bin/bash
    apt-get update && apt-get install -y nginx
    cat > /var/www/html/index.html << 'HTML'
    <!DOCTYPE html>
    <html>
    <head><title>Landing Zone — Web Server</title></head>
    <body>
      <h1>Terraform Landing Zone Lite</h1>
      <p><strong>Host:</strong> HOSTNAME_PLACEHOLDER</p>
      <p><strong>Environment:</strong> ${var.environment}</p>
      <p><strong>Region:</strong> ${var.region}</p>
    </body>
    </html>
    HTML
    sed -i "s/HOSTNAME_PLACEHOLDER/$(hostname)/" /var/www/html/index.html
    systemctl enable nginx && systemctl start nginx
  SCRIPT
}

module "app_vm" {
  source = "./modules/vm"

  vm_name      = "${var.name_prefix}-app-server"
  machine_type = var.app_machine_type
  zone         = var.zone
  subnetwork   = module.vpc.subnet_ids["app"]

  tags = ["ssh-allowed"]

  labels = {
    env  = var.environment
    tier = "app"
  }

  enable_external_ip = false
}
EOF
```

**outputs.tf (root):**

```bash
cat > outputs.tf << 'EOF'
# ── Network Outputs ──

output "vpc_name" {
  description = "VPC name"
  value       = module.vpc.vpc_name
}

output "vpc_self_link" {
  description = "VPC self-link"
  value       = module.vpc.vpc_self_link
}

output "subnet_cidrs" {
  description = "Subnet CIDRs"
  value       = module.vpc.subnet_cidrs
}

output "firewall_rules" {
  description = "Firewall rule names"
  value       = module.vpc.firewall_rules
}

# ── Web Server Outputs ──

output "web_vm_name" {
  description = "Web VM name"
  value       = module.web_vm.name
}

output "web_vm_external_ip" {
  description = "Web VM external IP"
  value       = module.web_vm.external_ip
}

output "web_vm_internal_ip" {
  description = "Web VM internal IP"
  value       = module.web_vm.internal_ip
}

output "web_url" {
  description = "Web server URL"
  value       = "http://${module.web_vm.external_ip}"
}

output "web_ssh_command" {
  description = "SSH command for web server"
  value       = "gcloud compute ssh ${module.web_vm.name} --zone=${var.zone}"
}

# ── App Server Outputs ──

output "app_vm_name" {
  description = "App VM name"
  value       = module.app_vm.name
}

output "app_vm_internal_ip" {
  description = "App VM internal IP"
  value       = module.app_vm.internal_ip
}

output "app_ssh_command" {
  description = "SSH command for app server (via IAP tunnel)"
  value       = "gcloud compute ssh ${module.app_vm.name} --zone=${var.zone} --tunnel-through-iap"
}

# ── Summary ──

output "landing_zone_summary" {
  description = "Quick summary of all resources"
  value = <<-SUMMARY
    ╔══════════════════════════════════════════════════╗
    ║         LANDING ZONE DEPLOYMENT SUMMARY          ║
    ╠══════════════════════════════════════════════════╣
    ║  VPC:         ${module.vpc.vpc_name}
    ║  Web Subnet:  ${module.vpc.subnet_cidrs["web"]}
    ║  App Subnet:  ${module.vpc.subnet_cidrs["app"]}
    ║  Web Server:  ${module.web_vm.name} (${module.web_vm.external_ip})
    ║  App Server:  ${module.app_vm.name} (${module.app_vm.internal_ip})
    ║  Web URL:     http://${module.web_vm.external_ip}
    ╚══════════════════════════════════════════════════╝
  SUMMARY
}
EOF
```

**terraform.tfvars:**

```bash
cat > terraform.tfvars << 'EOF'
# ── Project Settings ──
project_id  = "YOUR_PROJECT_ID"
region      = "europe-west2"
zone        = "europe-west2-b"
environment = "lab"
name_prefix = "lz"

# ── VPC Settings ──
vpc_name        = "lz-vpc"
web_subnet_cidr = "10.10.1.0/24"
app_subnet_cidr = "10.10.2.0/24"

# ── VM Settings ──
web_machine_type = "e2-small"
app_machine_type = "e2-micro"
EOF
```

### Step 5 — Create README.md

```bash
cat > README.md << 'EOF'
# Terraform Landing Zone Lite

A modular Terraform deployment for GCP that creates a VPC with subnets, firewall rules, and compute instances.

## Architecture

- **VPC** with custom-mode subnets (web + app tiers)
- **Firewall rules** for SSH, HTTP/S, ICMP, and internal traffic
- **Web server** with nginx in the web subnet (external IP)
- **App server** in the app subnet (internal only)

## Prerequisites

- Terraform >= 1.5.0
- Google Cloud SDK (`gcloud`)
- GCP project with Compute Engine API enabled
- Authenticated via `gcloud auth application-default login`

## Usage

```bash
# 1. Clone and enter directory
cd tf-landing-zone

# 2. Update terraform.tfvars with your project ID
vim terraform.tfvars

# 3. Deploy
terraform init
terraform plan
terraform apply

# 4. Verify
terraform output web_url
curl $(terraform output -raw web_vm_external_ip)

# 5. Cleanup
terraform destroy
```

## Modules

| Module | Path | Description |
|---|---|---|
| vpc | `modules/vpc/` | VPC, subnets, firewall rules |
| vm | `modules/vm/` | Compute Engine instance |

## Variables

See `variables.tf` for all configurable parameters.

## Cleanup

```bash
terraform destroy -auto-approve
```

This removes all resources created by this configuration.
EOF
```

### Step 6 — Verify Structure

```bash
find ~/tf-landing-zone -name "*.tf" -o -name "*.md" -o -name "*.tfvars" | sort
```

Expected:

```
tf-landing-zone/README.md
tf-landing-zone/main.tf
tf-landing-zone/modules/vm/main.tf
tf-landing-zone/modules/vm/outputs.tf
tf-landing-zone/modules/vm/variables.tf
tf-landing-zone/modules/vpc/main.tf
tf-landing-zone/modules/vpc/outputs.tf
tf-landing-zone/modules/vpc/variables.tf
tf-landing-zone/outputs.tf
tf-landing-zone/providers.tf
tf-landing-zone/terraform.tfvars
tf-landing-zone/variables.tf
```

### Step 7 — Init, Format, Validate

```bash
cd ~/tf-landing-zone

terraform init
terraform fmt -recursive
terraform validate
```

### Step 8 — Plan

```bash
terraform plan
```

**Expected plan (review carefully):**

```
Plan: 8 to add, 0 to change, 0 to destroy.

  # module.vpc.google_compute_network.vpc
  # module.vpc.google_compute_subnetwork.subnets["web"]
  # module.vpc.google_compute_subnetwork.subnets["app"]
  # module.vpc.google_compute_firewall.allow_ssh
  # module.vpc.google_compute_firewall.allow_http[0]
  # module.vpc.google_compute_firewall.allow_icmp
  # module.vpc.google_compute_firewall.allow_internal
  # module.web_vm.google_compute_instance.vm
  # module.app_vm.google_compute_instance.vm

Changes to Outputs:
  + vpc_name           = "lz-vpc"
  + web_vm_external_ip = (known after apply)
  ...
```

### Step 9 — Apply

```bash
terraform apply
```

### Step 10 — Verify Deployment

```bash
# View the summary
terraform output landing_zone_summary

# Verify VPC
gcloud compute networks list --filter="name=lz-vpc"
gcloud compute networks subnets list --filter="network~lz-vpc" \
    --format="table(name,region,ipCidrRange)"

# Verify firewall rules
gcloud compute firewall-rules list --filter="network~lz-vpc" \
    --format="table(name,direction,allowed[],sourceRanges[],targetTags[])"

# Verify VMs
gcloud compute instances list --filter="labels.managed=terraform" \
    --format="table(name,machineType.basename(),status,zone,networkInterfaces[0].networkIP,networkInterfaces[0].accessConfigs[0].natIP)"

# Test the web server
WEB_IP=$(terraform output -raw web_vm_external_ip)
curl -s "http://$WEB_IP"

# SSH to web server
gcloud compute ssh $(terraform output -raw web_vm_name) \
    --zone=$(terraform output -raw web_vm_name | xargs -I{} gcloud compute instances describe {} --zone=europe-west2-b --format="value(zone.basename())")

# or simply:
eval "$(terraform output -raw web_ssh_command)"
```

### Step 11 — Test a Change

Modify a variable and re-apply to see Terraform update in-place:

```bash
# Change web machine type to e2-medium
terraform apply -var="web_machine_type=e2-medium"

# Plan shows:
#   ~ module.web_vm.google_compute_instance.vm
#     ~ machine_type = "e2-small" -> "e2-medium"
```

### Step 12 — Inspect State

```bash
# List everything
terraform state list

# Count resources
terraform state list | wc -l

# Show the VPC
terraform state show module.vpc.google_compute_network.vpc

# Show the web VM
terraform state show module.web_vm.google_compute_instance.vm
```

### Cleanup

```bash
# Destroy all resources
terraform destroy

# Verify everything is removed
gcloud compute instances list --filter="labels.managed=terraform"
gcloud compute firewall-rules list --filter="network~lz-vpc"
gcloud compute networks subnets list --filter="network~lz-vpc"
gcloud compute networks list --filter="name=lz-vpc"

# Clean up working directory
cd ~ && rm -rf ~/tf-landing-zone
```

---

## Part 3 — Revision (15 min)

### Key Concepts — Week 4 Complete

- **Lifecycle**: `init` → `plan` → `apply` → `destroy` — always follow this order
- **Variables**: parameterise everything; use `.tfvars` for environment-specific values
- **Outputs**: expose useful values (IPs, names, URLs, SSH commands)
- **Modules**: package reusable infrastructure; root module composes child modules
- **State**: Terraform's memory; use remote state (GCS) for teams
- **Drift**: manual changes detected by `plan`; `apply` enforces `.tf` config
- **`for_each`** on maps creates multiple instances from a single resource block
- **`count`** for conditional resources (`count = var.enable_http ? 1 : 0`)
- **`dynamic` blocks** for optional nested blocks
- **`merge()`** combines maps (default labels + user labels)
- **`compact()`** removes empty strings from lists
- **Implicit dependencies** via resource references — Terraform handles ordering
- `terraform fmt -recursive` formats all `.tf` files including modules

### Essential Commands — Full Reference

```bash
# Lifecycle
terraform init                      # Download providers + modules
terraform plan                      # Preview changes
terraform apply                     # Execute changes
terraform destroy                   # Tear down everything

# Inspection
terraform show                      # Human-readable state
terraform state list                # All tracked resources
terraform state show ADDR           # Details of one resource
terraform output                    # All outputs
terraform output -raw NAME          # Raw output for scripting
terraform graph                     # Dependency graph (DOT format)

# Housekeeping
terraform fmt -recursive            # Format all .tf files
terraform validate                  # Syntax + type check

# State management
terraform import ADDR ID            # Import existing resource
terraform state rm ADDR             # Unmanage resource (keep infra)
terraform state mv OLD NEW          # Rename in state

# Variable overrides
terraform apply -var="key=value"
terraform apply -var-file="prod.tfvars"
export TF_VAR_key="value"
```

### Files to Remember

| File | Purpose | Commit? |
|---|---|---|
| `*.tf` | All Terraform configuration | Yes |
| `terraform.tfvars` | Variable values | Yes (if no secrets) |
| `.terraform.lock.hcl` | Provider version lock | Yes |
| `.terraform/` | Plugin cache | No |
| `terraform.tfstate` | State file | No (use remote) |

---

## Part 4 — Quiz (15 min)

**Question 1: In the VPC module, the `subnets` variable uses `for_each`. What happens if you add a third subnet to the map in `terraform.tfvars` and run `terraform apply`?**

<details>
<summary>Show Answer</summary>

Terraform will **add only the new subnet** without touching the existing two. This is the key advantage of `for_each` over `count`:

```
Plan: 1 to add, 0 to change, 0 to destroy.

  + module.vpc.google_compute_subnetwork.subnets["new-subnet"]
```

With `for_each`, resources are identified by their **map key** (e.g., `"web"`, `"app"`, `"new-subnet"`), not by index. So existing resources aren't affected when you add or remove entries.

If you had used `count` instead, adding a subnet in the middle would shift indices and cause Terraform to destroy/recreate resources — which is why `for_each` is preferred for maps and sets.

</details>

---

**Question 2: The web VM references `module.vpc.subnet_ids["web"]` for its subnetwork. What would happen if you accidentally typo it as `module.vpc.subnet_ids["wbe"]`?**

<details>
<summary>Show Answer</summary>

Terraform would **fail during `plan`** (before any infrastructure is touched) with an error:

```
Error: Invalid index

  on main.tf line XX:
  xx:   subnetwork = module.vpc.subnet_ids["wbe"]

The given key does not identify an element in this collection value.
```

This is one of the safety benefits of Terraform's type system — it catches typos at plan time, not at apply time. The map only contains keys `"web"` and `"app"` (from your `subnets` variable), so `"wbe"` doesn't exist.

This is like accessing a missing key in a bash associative array — but Terraform catches it before execution.

</details>

---

**Question 3: You want to deploy this same landing zone to a `staging` environment with different CIDRs and machine types. What's the recommended approach?**

<details>
<summary>Show Answer</summary>

Create a **separate `.tfvars` file** for staging:

```bash
# staging.tfvars
project_id       = "staging-project-id"
environment      = "staging"
name_prefix      = "stg"
vpc_name         = "stg-vpc"
web_subnet_cidr  = "10.20.1.0/24"
app_subnet_cidr  = "10.20.2.0/24"
web_machine_type = "e2-medium"
app_machine_type = "e2-small"
```

Deploy with:
```bash
terraform apply -var-file="staging.tfvars"
```

**Important:** Each environment needs its own **state file** (use different GCS prefixes or workspaces):

```hcl
# For remote state, use prefix per environment:
backend "gcs" {
  bucket = "my-tf-state"
  prefix = "landing-zone/staging"
}
```

Or use `terraform workspace`:
```bash
terraform workspace new staging
terraform apply -var-file="staging.tfvars"
```

Never share a state file between environments.

</details>

---

**Question 4: After running `terraform destroy`, are you confident that ALL resources are removed? How would you verify?**

<details>
<summary>Show Answer</summary>

`terraform destroy` removes everything **tracked in state**, but there are edge cases:

1. **Resources removed with `terraform state rm`** are NOT destroyed (Terraform forgot them)
2. **Resources created outside Terraform** (manually) are NOT tracked
3. **Resources in a different Terraform config** are NOT affected

To verify everything is truly gone:

```bash
# Check compute instances
gcloud compute instances list --filter="labels.managed=terraform"

# Check VPCs
gcloud compute networks list --filter="name=lz-vpc"

# Check firewall rules
gcloud compute firewall-rules list --filter="network~lz-vpc"

# Check subnets
gcloud compute networks subnets list --filter="network~lz-vpc"

# Check state is empty
terraform state list
# (should return nothing)
```

Always verify with `gcloud` after `destroy` — especially in shared projects where manual resources may exist alongside Terraform-managed ones.

</details>

---

*End of Day 24 and Week 4 — You now have the foundations to manage GCP infrastructure as code with Terraform. Next steps: remote state backends, Terraform workspaces, and CI/CD pipelines.*
