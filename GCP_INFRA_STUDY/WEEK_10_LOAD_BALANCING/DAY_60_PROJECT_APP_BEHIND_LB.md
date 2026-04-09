# Day 60 — PROJECT: App Behind Load Balancer

> **Week 10 · Load Balancing — Capstone Project**
> Estimated time: 2 hours | Region: `europe-west2` (London)
> Prerequisites: Days 55-59 completed

---

## Part 1 — Concept & Architecture (30 min)

### Project Overview

Deploy a multi-instance web application behind a Global HTTP(S) Load Balancer with health checks, access logging, monitoring alerts, and full Terraform automation.

### Architecture Diagram

```
┌──────────────────────────────────────────────────────────────────────┐
│                PROJECT: APP BEHIND LOAD BALANCER                      │
│                                                                       │
│  Internet                                                             │
│      │                                                                │
│      ▼                                                                │
│  ┌──────────────────────────────┐                                    │
│  │  Global Forwarding Rule      │  ← Public IP :80                   │
│  │  34.xx.xx.xx:80              │                                    │
│  └──────────────┬───────────────┘                                    │
│                 │                                                     │
│                 ▼                                                     │
│  ┌──────────────────────────────┐                                    │
│  │  Target HTTP Proxy           │                                    │
│  └──────────────┬───────────────┘                                    │
│                 │                                                     │
│                 ▼                                                     │
│  ┌──────────────────────────────┐                                    │
│  │  URL Map                     │                                    │
│  │  /*  → web-backend-svc       │                                    │
│  └──────────────┬───────────────┘                                    │
│                 │                                                     │
│                 ▼                                                     │
│  ┌──────────────────────────────┐                                    │
│  │  Backend Service             │  ← Logging enabled (100%)          │
│  │  (UTILIZATION mode, max 80%) │  ← Timeout: 30s                   │
│  └──────────────┬───────────────┘                                    │
│                 │                                                     │
│  ┌──────────────┴───────────────────────────────────────┐            │
│  │         Regional MIG: app-prod-mig                    │            │
│  │         min=2, max=6, CPU target=60%                  │            │
│  │                                                       │            │
│  │  ┌───────────┐  ┌───────────┐  ┌───────────┐        │            │
│  │  │ zone-a    │  │ zone-b    │  │ zone-c    │        │            │
│  │  │ ┌───────┐ │  │ ┌───────┐ │  │ ┌───────┐ │        │            │
│  │  │ │ nginx │ │  │ │ nginx │ │  │ │ nginx │ │        │            │
│  │  │ │ :80   │ │  │ │ :80   │ │  │ │ :80   │ │        │            │
│  │  │ └───────┘ │  │ └───────┘ │  │ └───────┘ │        │            │
│  │  └───────────┘  └───────────┘  └───────────┘        │            │
│  └──────────────────────────────────────────────────────┘            │
│                 │                                                     │
│  ┌──────────────┴───────────────────────────────────────┐            │
│  │  Health Check: HTTP :80 /health every 10s            │            │
│  │  Healthy: 2 success | Unhealthy: 3 failures          │            │
│  └──────────────────────────────────────────────────────┘            │
│                                                                       │
│  ┌──────────────────────────────────────┐                            │
│  │  Firewall Rules                      │                            │
│  │  ✓ 130.211.0.0/22 → :80 (HC+LB)    │                            │
│  │  ✓ 35.191.0.0/16  → :80 (HC+LB)    │                            │
│  │  ✓ 35.235.240.0/20 → :22 (IAP SSH) │                            │
│  └──────────────────────────────────────┘                            │
└──────────────────────────────────────────────────────────────────────┘
```

### Deployment Checklist

| #  | Task                                           | Status |
|----|------------------------------------------------|--------|
| 1  | Write Terraform config (`main.tf`)             | ☐      |
| 2  | Create instance template with startup          | ☐      |
| 3  | Create regional MIG with auto-healing          | ☐      |
| 4  | Create health check (HTTP /health)             | ☐      |
| 5  | Create backend service with logging            | ☐      |
| 6  | Create URL map + proxy + forwarding rule       | ☐      |
| 7  | Create firewall rules (HC + IAP)               | ☐      |
| 8  | Configure autoscaler (CPU 60%, min 2, max 6)   | ☐      |
| 9  | Deploy with `terraform apply`                  | ☐      |
| 10 | Verify LB endpoint serves traffic              | ☐      |
| 11 | Verify multi-zone distribution                 | ☐      |
| 12 | Test auto-healing (stop nginx on one VM)       | ☐      |
| 13 | Query LB access logs                           | ☐      |
| 14 | Clean up with `terraform destroy`              | ☐      |

---

## Part 2 — Hands-On Lab (60 min)

### Step 1 — Create Terraform Project

```bash
mkdir -p ~/tf-app-lb-project && cd ~/tf-app-lb-project
```

### Step 2 — Write `main.tf`

```hcl
# main.tf — Complete App Behind LB
terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

variable "project_id" { type = string }
variable "region" { type = string; default = "europe-west2" }

provider "google" {
  project = var.project_id
  region  = var.region
}

# ─── Instance Template ────────────────────────────────────
resource "google_compute_instance_template" "app" {
  name_prefix  = "app-prod-tpl-"
  machine_type = "e2-small"
  region       = var.region
  tags         = ["app-prod"]

  disk {
    source_image = "debian-cloud/debian-12"
    auto_delete  = true
    boot         = true
    disk_size_gb = 10
  }

  network_interface {
    network = "default"
    access_config {}
  }

  metadata = {
    startup-script = <<-EOT
      #!/bin/bash
      set -e
      apt-get update && apt-get install -y nginx stress-ng
      HOSTNAME=$(hostname)
      ZONE=$(curl -sf -H "Metadata-Flavor: Google" \
          http://metadata.google.internal/computeMetadata/v1/instance/zone | cut -d/ -f4)
      cat > /var/www/html/index.html <<EOF
      <!DOCTYPE html>
      <html><body>
      <h1>Production App</h1>
      <table>
      <tr><td>Hostname</td><td>$HOSTNAME</td></tr>
      <tr><td>Zone</td><td>$ZONE</td></tr>
      <tr><td>Deployed</td><td>$(date -u)</td></tr>
      </table>
      </body></html>
      EOF
      echo "OK" > /var/www/html/health
      systemctl enable nginx && systemctl start nginx
    EOT
  }

  lifecycle { create_before_destroy = true }
}

# ─── Health Check ──────────────────────────────────────────
resource "google_compute_health_check" "app" {
  name                = "app-prod-hc"
  check_interval_sec  = 10
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 3

  http_health_check {
    port         = 80
    request_path = "/health"
  }
}

# ─── Regional MIG ─────────────────────────────────────────
resource "google_compute_region_instance_group_manager" "app" {
  name               = "app-prod-mig"
  region             = var.region
  base_instance_name = "app-prod"
  target_size        = 2

  version {
    instance_template = google_compute_instance_template.app.id
    name              = "primary"
  }

  named_port {
    name = "http"
    port = 80
  }

  auto_healing_policies {
    health_check      = google_compute_health_check.app.id
    initial_delay_sec = 120
  }

  update_policy {
    type                           = "PROACTIVE"
    minimal_action                 = "REPLACE"
    most_disruptive_allowed_action = "REPLACE"
    max_surge_fixed                = 1
    max_unavailable_fixed          = 0
    replacement_method             = "SUBSTITUTE"
  }
}

# ─── Autoscaler ───────────────────────────────────────────
resource "google_compute_region_autoscaler" "app" {
  name   = "app-prod-autoscaler"
  region = var.region
  target = google_compute_region_instance_group_manager.app.id

  autoscaling_policy {
    min_replicas    = 2
    max_replicas    = 6
    cooldown_period = 120

    cpu_utilization {
      target = 0.6
    }

    scale_in_control {
      max_scaled_in_replicas {
        fixed = 1
      }
      time_window_sec = 300
    }
  }
}

# ─── Backend Service ──────────────────────────────────────
resource "google_compute_backend_service" "app" {
  name                  = "app-prod-backend"
  protocol              = "HTTP"
  port_name             = "http"
  health_checks         = [google_compute_health_check.app.id]
  load_balancing_scheme = "EXTERNAL"
  timeout_sec           = 30

  backend {
    group           = google_compute_region_instance_group_manager.app.instance_group
    balancing_mode  = "UTILIZATION"
    max_utilization = 0.8
  }

  log_config {
    enable      = true
    sample_rate = 1.0
  }
}

# ─── URL Map ──────────────────────────────────────────────
resource "google_compute_url_map" "app" {
  name            = "app-prod-urlmap"
  default_service = google_compute_backend_service.app.id
}

# ─── Target HTTP Proxy ────────────────────────────────────
resource "google_compute_target_http_proxy" "app" {
  name    = "app-prod-http-proxy"
  url_map = google_compute_url_map.app.id
}

# ─── Global Forwarding Rule ───────────────────────────────
resource "google_compute_global_forwarding_rule" "app" {
  name                  = "app-prod-fwd"
  target                = google_compute_target_http_proxy.app.id
  port_range            = "80"
  load_balancing_scheme = "EXTERNAL"
}

# ─── Firewall: Health Checks + LB Traffic ─────────────────
resource "google_compute_firewall" "allow_hc_lb" {
  name    = "app-prod-allow-hc-lb"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  target_tags   = ["app-prod"]
}

# ─── Firewall: IAP SSH ────────────────────────────────────
resource "google_compute_firewall" "allow_iap" {
  name    = "app-prod-allow-iap"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["app-prod"]
}

# ─── Outputs ──────────────────────────────────────────────
output "lb_ip" {
  value = google_compute_global_forwarding_rule.app.ip_address
}

output "lb_url" {
  value = "http://${google_compute_global_forwarding_rule.app.ip_address}"
}
```

### Step 3 — Create `terraform.tfvars`

```hcl
project_id = "YOUR_PROJECT_ID"
region     = "europe-west2"
```

### Step 4 — Deploy

```bash
terraform init
terraform plan
terraform apply -auto-approve
```

### Step 5 — Verify Everything

```bash
# Get LB IP
LB_IP=$(terraform output -raw lb_ip)
echo "App URL: http://$LB_IP"

# Wait for LB propagation
for i in $(seq 1 30); do
    STATUS=$(curl -s -o /dev/null -w '%{http_code}' http://$LB_IP/ 2>/dev/null)
    [ "$STATUS" = "200" ] && echo "LB active!" && break
    echo "Attempt $i: HTTP $STATUS"
    sleep 10
done

# Test multi-zone distribution
for i in $(seq 1 8); do
    echo "--- Request $i ---"
    curl -s http://$LB_IP/ | grep -E "(Hostname|Zone)"
done

# Check backend health
gcloud compute backend-services get-health app-prod-backend --global

# Check MIG instances across zones
gcloud compute instance-groups managed list-instances app-prod-mig \
    --region=europe-west2 \
    --format="table(instance.basename(), zone.basename(), status, healthState[0].healthState)"
```

### Step 6 — Test Auto-Healing

```bash
# Pick an instance and break it
INST=$(gcloud compute instance-groups managed list-instances app-prod-mig \
    --region=europe-west2 --format="value(instance)" | head -1)
INST_ZONE=$(gcloud compute instances list \
    --filter="name=$INST" --format="value(zone)")

gcloud compute ssh $INST --zone=$INST_ZONE -- "sudo systemctl stop nginx"

# Observe auto-healing (2-3 min)
watch -n 15 "gcloud compute instance-groups managed list-instances app-prod-mig \
    --region=europe-west2 --format='table(instance.basename(), status, healthState[0].healthState, currentAction)'"
```

### Step 7 — Query Access Logs

```bash
gcloud logging read \
    'resource.type="http_load_balancer" AND resource.labels.forwarding_rule_name="app-prod-fwd"' \
    --limit=10 \
    --format="table(timestamp, httpRequest.status, httpRequest.latency, httpRequest.remoteIp)"
```

### Cleanup

```bash
terraform destroy -auto-approve
rm -rf ~/tf-app-lb-project
```

---

## Part 3 — Revision (15 min)

### Week 10 Summary

- GCP has **7 LB types** — Global HTTP(S) is most common for web apps
- HTTP LB chain: forwarding rule → proxy → URL map → backend service → MIG → health check
- Create **bottom-up** (health check first), delete **top-down** (forwarding rule first)
- **Named ports** link backend service `port_name` to instance group port number
- **Backend health** command is the #1 debug tool: `get-health`
- Common 502 cause: **firewall missing** for health check probes (`130.211.0.0/22`, `35.191.0.0/16`)
- **LB logging**: per backend service, adjustable sample rate (1.0 = 100%)
- **504**: backend timeout exceeded — increase `timeout_sec`
- LB takes **3-5 minutes** to propagate after creation
- Terraform manages all 7+ resources with automatic dependency ordering

---

## Part 4 — Quiz (15 min)

**Question 1: List the 6 GCP resources needed for a Global External HTTP(S) LB, in creation order.**

<details>
<summary>Show Answer</summary>

1. **Health Check** (`google_compute_health_check`) — no dependencies
2. **Instance Group / MIG** (`google_compute_region_instance_group_manager`) — needs template
3. **Backend Service** (`google_compute_backend_service`) — needs HC + IG
4. **URL Map** (`google_compute_url_map`) — needs backend service
5. **Target HTTP Proxy** (`google_compute_target_http_proxy`) — needs URL map
6. **Global Forwarding Rule** (`google_compute_global_forwarding_rule`) — needs proxy

Plus: Firewall rules (independent, create anytime).

</details>

**Question 2: Your production app gets 502 errors during rolling updates. Why?**

<details>
<summary>Show Answer</summary>

During a rolling update, old instances are being replaced by new ones. If `max_unavailable > 0`, some instances go offline simultaneously. If the remaining instances can't handle the load, or new instances haven't passed health checks yet, the LB can't find healthy backends → 502.

**Fix**: Set `max_surge = 1` and `max_unavailable = 0` in the update policy. This ensures a new instance is created and verified healthy **before** the old one is removed. Zero downtime.

</details>

**Question 3: A developer asks why they can't use a Network LB for path-based routing. Explain.**

<details>
<summary>Show Answer</summary>

A Network LB operates at **Layer 4** (TCP/UDP) — it sees only IP addresses and port numbers, not HTTP content. URL paths (`/api/v1`, `/static`) are **Layer 7** (HTTP) concepts.

To route by URL path, you need an **HTTP(S) Load Balancer** which operates at Layer 7. It reads the HTTP request, inspects the URL, and uses the **URL Map** to route to different backend services.

Linux analogy: `iptables -t nat DNAT` (L4) vs `nginx location /path { proxy_pass }` (L7).

</details>

**Question 4: You need to ensure the LB never routes traffic to a VM that's still starting up. What configuration ensures this?**

<details>
<summary>Show Answer</summary>

Two settings work together:

1. **Health check** with appropriate thresholds — the LB only routes to backends that pass `healthy_threshold` consecutive checks
2. **`initial_delay_sec`** in MIG `auto_healing_policies` — prevents the MIG from marking a new VM as unhealthy during startup

The health check ensures no traffic reaches an unready VM. The initial delay prevents the MIG from immediately destroying a VM that's still booting (which would create an auto-heal loop).

Set `initial_delay_sec >= application_startup_time + buffer`.

</details>

---

*Next: [Week 11 — Security Posture](../WEEK_11_SECURITY_POSTURE/DAY_61_SHARED_RESPONSIBILITY.md)*
