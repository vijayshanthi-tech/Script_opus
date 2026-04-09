# Day 51 — Terraform MIG

> **Week 9 · MIG & Autoscaling**
> Estimated time: 2 hours | Region: `europe-west2` (London)
> Prerequisites: Day 50 completed, Terraform basics (Weeks 4-5)

---

## Part 1 — Concept (30 min)

### Terraform MIG Resource Map

```
Terraform Resource                         GCP Equivalent
──────────────────────────────────────────────────────────
google_compute_instance_template      →    Instance Template
google_compute_instance_group_manager →    Managed Instance Group (zonal)
google_compute_region_instance_group_manager → MIG (regional)
google_compute_autoscaler             →    Zonal Autoscaler
google_compute_region_autoscaler      →    Regional Autoscaler
google_compute_health_check           →    Health Check
```

### Dependency Chain

```
┌──────────────────────────┐
│   google_compute_        │
│   instance_template      │   ← "Blueprint" — defines VM spec
│   (machine type, image,  │
│    startup script, SA)   │
└────────────┬─────────────┘
             │ depends on
             ▼
┌──────────────────────────┐
│   google_compute_        │
│   instance_group_manager │   ← Creates N VMs from template
│   (target_size, zone,    │
│    named_port, versions) │
└────────────┬─────────────┘
             │ depends on
             ▼
┌──────────────────────────┐     ┌─────────────────────┐
│   google_compute_        │     │ google_compute_     │
│   autoscaler             │     │ health_check        │
│   (min, max, target,     │     │ (http/tcp/ssl)      │
│    cooldown, policy)     │     │                     │
└──────────────────────────┘     └─────────────────────┘
```

### Key Terraform Arguments

| Resource                       | Key Arguments                                              |
|--------------------------------|------------------------------------------------------------|
| `instance_template`            | `machine_type`, `disk {}`, `network_interface {}`, `metadata` |
| `instance_group_manager`       | `base_instance_name`, `target_size`, `version {}`, `zone`  |
| `autoscaler`                   | `target`, `autoscaling_policy {}`, `min_replicas`, `max_replicas` |
| `health_check`                 | `http_health_check {}` or `tcp_health_check {}`, `check_interval_sec` |

### Linux Analogy: Terraform MIG vs systemd Unit Files

```
systemd unit file                     Terraform HCL
──────────────────────────────────────────────────────
[Service]                             resource "google_compute_instance_template"
ExecStart=/usr/bin/nginx              ← startup_script
User=www-data                         ← service_account
Restart=always                        ← auto_healing_policies

[Install]                             resource "google_compute_instance_group_manager"
WantedBy=multi-user.target            ← base_instance_name, target_size

systemctl enable/start                terraform apply
systemctl status                      terraform show
journalctl -u nginx                   gcloud logging read
```

### Template Versioning Strategy

```
┌─────────────────────────────────────────────┐
│  Template Versioning (name_prefix approach) │
│                                              │
│  web-tpl-20260401   ← old                   │
│  web-tpl-20260408   ← current (100%)        │
│  web-tpl-20260415   ← canary  (20%)         │
│                                              │
│  lifecycle {                                 │
│    create_before_destroy = true              │
│  }                                           │
│  ↑ Creates new template before destroying   │
│    old one — prevents downtime               │
└─────────────────────────────────────────────┘
```

---

## Part 2 — Hands-On Lab (60 min)

### Lab Objective

Build a complete MIG with autoscaling using Terraform — instance template, MIG, health check, and autoscaler.

### Step 1 — Create Project Structure

```bash
mkdir -p ~/tf-mig-lab && cd ~/tf-mig-lab
```

### Step 2 — Create `variables.tf`

```hcl
# variables.tf
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
  default     = "europe-west2-a"
}

variable "min_replicas" {
  description = "Minimum number of instances"
  type        = number
  default     = 2
}

variable "max_replicas" {
  description = "Maximum number of instances"
  type        = number
  default     = 6
}

variable "target_cpu" {
  description = "Target CPU utilization for autoscaling"
  type        = number
  default     = 0.6
}
```

### Step 3 — Create `main.tf`

```hcl
# main.tf
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

# ─── Instance Template ───────────────────────────────────
resource "google_compute_instance_template" "web" {
  name_prefix  = "web-tpl-"
  machine_type = "e2-micro"
  region       = var.region
  tags         = ["http-server", "allow-ssh"]

  disk {
    source_image = "debian-cloud/debian-12"
    auto_delete  = true
    boot         = true
    disk_size_gb = 10
    disk_type    = "pd-standard"
  }

  network_interface {
    network = "default"
    access_config {} # Ephemeral public IP
  }

  metadata = {
    startup-script = <<-EOT
      #!/bin/bash
      apt-get update && apt-get install -y nginx stress-ng
      HOSTNAME=$(hostname)
      echo "<h1>Hello from $HOSTNAME</h1><p>Managed by Terraform MIG</p>" \
        > /var/www/html/index.html
      systemctl enable nginx && systemctl start nginx
    EOT
  }

  # Create new template before destroying old one
  lifecycle {
    create_before_destroy = true
  }
}

# ─── Health Check ─────────────────────────────────────────
resource "google_compute_health_check" "http" {
  name                = "http-health-check"
  check_interval_sec  = 10
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 3

  http_health_check {
    port         = 80
    request_path = "/"
  }
}

# ─── Managed Instance Group ──────────────────────────────
resource "google_compute_instance_group_manager" "web" {
  name               = "web-mig"
  base_instance_name = "web"
  zone               = var.zone
  target_size        = var.min_replicas

  version {
    instance_template = google_compute_instance_template.web.id
    name              = "primary"
  }

  named_port {
    name = "http"
    port = 80
  }

  auto_healing_policies {
    health_check      = google_compute_health_check.http.id
    initial_delay_sec = 120
  }

  update_policy {
    type                         = "PROACTIVE"
    minimal_action               = "REPLACE"
    most_disruptive_allowed_action = "REPLACE"
    max_surge_fixed              = 1
    max_unavailable_fixed        = 0
    replacement_method           = "SUBSTITUTE"
  }
}

# ─── Autoscaler ──────────────────────────────────────────
resource "google_compute_autoscaler" "web" {
  name   = "web-autoscaler"
  zone   = var.zone
  target = google_compute_instance_group_manager.web.id

  autoscaling_policy {
    min_replicas    = var.min_replicas
    max_replicas    = var.max_replicas
    cooldown_period = 60

    cpu_utilization {
      target = var.target_cpu
    }

    scale_in_control {
      max_scaled_in_replicas {
        fixed = 1
      }
      time_window_sec = 300
    }
  }
}

# ─── Firewall: Allow Health Checks ──────────────────────
resource "google_compute_firewall" "allow_health_check" {
  name    = "allow-health-check-mig"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  target_tags   = ["http-server"]
}
```

### Step 4 — Create `outputs.tf`

```hcl
# outputs.tf
output "instance_template" {
  description = "Instance template self-link"
  value       = google_compute_instance_template.web.self_link
}

output "mig_name" {
  description = "MIG name"
  value       = google_compute_instance_group_manager.web.name
}

output "mig_instance_group" {
  description = "MIG instance group URL"
  value       = google_compute_instance_group_manager.web.instance_group
}

output "autoscaler_name" {
  description = "Autoscaler name"
  value       = google_compute_autoscaler.web.name
}
```

### Step 5 — Create `terraform.tfvars`

```hcl
# terraform.tfvars
project_id   = "YOUR_PROJECT_ID"
region       = "europe-west2"
zone         = "europe-west2-a"
min_replicas = 2
max_replicas = 6
target_cpu   = 0.6
```

### Step 6 — Deploy

```bash
terraform init
terraform plan
terraform apply -auto-approve
```

### Step 7 — Verify

```bash
# Check MIG instances
gcloud compute instance-groups managed list-instances web-mig \
    --zone=europe-west2-a \
    --format="table(instance.basename(), status, currentAction)"

# Check autoscaler
gcloud compute instance-groups managed describe web-mig \
    --zone=europe-west2-a \
    --format="yaml(autoscaler)"

# Verify health check
gcloud compute health-checks describe http-health-check
```

### Step 8 — Test Template Update (Rolling Update)

```bash
# Modify the startup script in main.tf (change the HTML message)
# Then apply — Terraform creates new template, MIG does rolling update
terraform apply -auto-approve

# Watch the rolling update
watch -n 10 "gcloud compute instance-groups managed list-instances web-mig \
    --zone=europe-west2-a --format='table(instance.basename(), status, currentAction)'"
```

### Cleanup

```bash
terraform destroy -auto-approve
rm -rf ~/tf-mig-lab
```

---

## Part 3 — Revision (15 min)

### Key Concepts

- `google_compute_instance_template` — immutable VM blueprint; use `name_prefix` + `create_before_destroy`
- `google_compute_instance_group_manager` — zonal MIG; use `google_compute_region_instance_group_manager` for regional
- `google_compute_autoscaler` — autoscaling policy with min/max/target/cooldown
- `google_compute_health_check` — auto-healing trigger; integrated via `auto_healing_policies`
- `update_policy` block controls rolling update behaviour (surge, unavailable, method)
- `scale_in_control` prevents aggressive scale-in (limits removals per time window)
- Template versioning: `name_prefix` + lifecycle block enables zero-downtime updates

### Essential HCL Patterns

```hcl
# Template with create_before_destroy
resource "google_compute_instance_template" "web" {
  name_prefix = "web-tpl-"
  lifecycle { create_before_destroy = true }
}

# MIG referencing template
resource "google_compute_instance_group_manager" "web" {
  version {
    instance_template = google_compute_instance_template.web.id
  }
}

# Autoscaler targeting MIG
resource "google_compute_autoscaler" "web" {
  target = google_compute_instance_group_manager.web.id
  autoscaling_policy {
    cpu_utilization { target = 0.6 }
  }
}
```

---

## Part 4 — Quiz (15 min)

**Question 1: Why do we use `name_prefix` instead of `name` for instance templates in Terraform?**

<details>
<summary>Show Answer</summary>

Instance templates are **immutable** — you can't update them in place. When you change any property, Terraform must destroy the old template and create a new one. With `name_prefix` + `lifecycle { create_before_destroy = true }`, Terraform:

1. Creates a **new** template with a unique auto-generated suffix
2. Updates the MIG to reference the new template
3. Deletes the old template

Without `name_prefix`, Terraform would try to delete the old template first (which fails because the MIG still references it).

</details>

**Question 2: What does `max_surge_fixed = 1` and `max_unavailable_fixed = 0` mean in the update policy?**

<details>
<summary>Show Answer</summary>

- **`max_surge_fixed = 1`**: During a rolling update, the MIG can create **1 extra instance** above `target_size` temporarily
- **`max_unavailable_fixed = 0`**: **Zero instances** may be unavailable during the update

Together, this creates a **zero-downtime rolling update**: a new instance is created first (surge), verified healthy, then an old instance is removed. This ensures capacity never drops below `target_size`.

</details>

**Question 3: You want to switch from a zonal MIG to a regional MIG in Terraform. What resource changes?**

<details>
<summary>Show Answer</summary>

Replace `google_compute_instance_group_manager` with `google_compute_region_instance_group_manager`, and `google_compute_autoscaler` with `google_compute_region_autoscaler`. Change `zone` to `region` argument:

```hcl
resource "google_compute_region_instance_group_manager" "web" {
  region             = var.region           # was: zone = var.zone
  distribution_policy_zones = ["europe-west2-a", "europe-west2-b", "europe-west2-c"]
  ...
}

resource "google_compute_region_autoscaler" "web" {
  region = var.region
  target = google_compute_region_instance_group_manager.web.id
  ...
}
```

Note: This requires destroying and recreating — you cannot in-place migrate zonal → regional.

</details>

**Question 4: The autoscaler has `cooldown_period = 60` but your app takes 3 minutes to start serving traffic. What happens?**

<details>
<summary>Show Answer</summary>

The autoscaler may **over-provision**. Since the cooldown (60s) is shorter than the app startup (180s), the autoscaler checks metrics before new VMs are ready to serve. It still sees high load, so it adds **more** VMs than needed. Once all VMs finish starting, load drops sharply, and the autoscaler scales in.

**Fix**: Set `cooldown_period = 180` (or longer) to match actual startup time. Also set `initial_delay_sec` in `auto_healing_policies` to avoid false-positive health check failures during startup.

</details>

---

*Next: [Day 52 — Health Checks & Rolling Updates](DAY_52_HEALTH_CHECKS_ROLLING.md)*
