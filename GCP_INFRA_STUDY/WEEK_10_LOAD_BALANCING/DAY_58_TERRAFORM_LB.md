# Day 58 — Terraform Load Balancer

> **Week 10 · Load Balancing**
> Estimated time: 2 hours | Region: `europe-west2` (London)
> Prerequisites: Day 56-57, Terraform basics (Weeks 4-5)

---

## Part 1 — Concept (30 min)

### Terraform Resource Map for HTTP(S) LB

```
Terraform Resource                              GCP Component
────────────────────────────────────────────────────────────────
google_compute_health_check                →  Health Check
google_compute_instance_template           →  Instance Template
google_compute_region_instance_group_manager → MIG (regional)
google_compute_backend_service             →  Backend Service (global)
google_compute_url_map                     →  URL Map
google_compute_target_http_proxy           →  Target HTTP Proxy
google_compute_global_forwarding_rule      →  Global Forwarding Rule
google_compute_firewall                    →  Firewall Rules
```

### Dependency Graph

```
┌────────────────────────┐   ┌──────────────────────┐
│ google_compute_        │   │ google_compute_      │
│ instance_template      │   │ health_check         │
└──────────┬─────────────┘   └──────────┬───────────┘
           │                            │
           ▼                            │
┌────────────────────────┐              │
│ google_compute_region_ │              │
│ instance_group_manager │              │
└──────────┬─────────────┘              │
           │                            │
           ▼                            ▼
┌─────────────────────────────────────────┐
│ google_compute_backend_service          │
│ (references MIG + health check)         │
└──────────┬──────────────────────────────┘
           │
           ▼
┌─────────────────────────────────────────┐
│ google_compute_url_map                  │
│ (references backend service)            │
└──────────┬──────────────────────────────┘
           │
           ▼
┌─────────────────────────────────────────┐
│ google_compute_target_http_proxy        │
│ (references url map)                    │
└──────────┬──────────────────────────────┘
           │
           ▼
┌─────────────────────────────────────────┐
│ google_compute_global_forwarding_rule   │
│ (references target proxy)               │
└─────────────────────────────────────────┘
```

### Linux Analogy: Terraform LB vs nginx Config

```
nginx.conf                        Terraform HCL
──────────────────────────────────────────────────────
upstream api_pool {               google_compute_backend_service "api"
  server 10.0.0.1:80;            ← instance group
  server 10.0.0.2:80;
}

server {                          google_compute_global_forwarding_rule
  listen 80;                      ← port binding

  location /api {                 google_compute_url_map
    proxy_pass http://api_pool;   ← path_matcher → backend
  }
  location / {
    proxy_pass http://web_pool;
  }
}
```

---

## Part 2 — Hands-On Lab (60 min)

### Lab Objective

Build a complete HTTP(S) Load Balancer with Terraform, including MIG backend, health check, URL map, and global forwarding rule.

### Step 1 — Create Project Structure

```bash
mkdir -p ~/tf-lb-lab && cd ~/tf-lb-lab
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

# ─── Instance Template ────────────────────────────────────
resource "google_compute_instance_template" "web" {
  name_prefix  = "web-lb-tpl-"
  machine_type = "e2-micro"
  region       = var.region
  tags         = ["http-lb-backend"]

  disk {
    source_image = "debian-cloud/debian-12"
    auto_delete  = true
    boot         = true
  }

  network_interface {
    network = "default"
    access_config {}
  }

  metadata = {
    startup-script = <<-EOT
      #!/bin/bash
      apt-get update && apt-get install -y nginx
      HOSTNAME=$(hostname)
      ZONE=$(curl -sf -H "Metadata-Flavor: Google" \
          http://metadata.google.internal/computeMetadata/v1/instance/zone | cut -d/ -f4)
      cat > /var/www/html/index.html <<EOF
      <h1>Terraform LB Backend</h1>
      <p>Host: $HOSTNAME | Zone: $ZONE</p>
      EOF
      echo "OK" > /var/www/html/health
      systemctl enable nginx && systemctl start nginx
    EOT
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ─── Health Check ──────────────────────────────────────────
resource "google_compute_health_check" "http" {
  name                = "tf-lb-health-check"
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
resource "google_compute_region_instance_group_manager" "web" {
  name               = "tf-lb-mig"
  region             = var.region
  base_instance_name = "web-lb"
  target_size        = 2

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
}

# ─── Backend Service ──────────────────────────────────────
resource "google_compute_backend_service" "web" {
  name                  = "tf-lb-backend-svc"
  protocol              = "HTTP"
  port_name             = "http"
  health_checks         = [google_compute_health_check.http.id]
  load_balancing_scheme = "EXTERNAL"
  timeout_sec           = 30

  backend {
    group           = google_compute_region_instance_group_manager.web.instance_group
    balancing_mode  = "UTILIZATION"
    max_utilization = 0.8
  }

  log_config {
    enable      = true
    sample_rate = 1.0
  }
}

# ─── URL Map ──────────────────────────────────────────────
resource "google_compute_url_map" "web" {
  name            = "tf-lb-url-map"
  default_service = google_compute_backend_service.web.id
}

# ─── Target HTTP Proxy ────────────────────────────────────
resource "google_compute_target_http_proxy" "web" {
  name    = "tf-lb-http-proxy"
  url_map = google_compute_url_map.web.id
}

# ─── Global Forwarding Rule ───────────────────────────────
resource "google_compute_global_forwarding_rule" "web" {
  name                  = "tf-lb-forwarding-rule"
  target                = google_compute_target_http_proxy.web.id
  port_range            = "80"
  load_balancing_scheme = "EXTERNAL"
}

# ─── Firewall: Allow Health Check Probes ──────────────────
resource "google_compute_firewall" "allow_hc" {
  name    = "tf-lb-allow-health-check"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  target_tags   = ["http-lb-backend"]
}
```

### Step 4 — Create `outputs.tf`

```hcl
# outputs.tf
output "lb_ip_address" {
  description = "External IP of the load balancer"
  value       = google_compute_global_forwarding_rule.web.ip_address
}

output "lb_url" {
  description = "URL to access the load balancer"
  value       = "http://${google_compute_global_forwarding_rule.web.ip_address}"
}

output "backend_service" {
  description = "Backend service name"
  value       = google_compute_backend_service.web.name
}

output "mig_instance_group" {
  description = "MIG instance group"
  value       = google_compute_region_instance_group_manager.web.instance_group
}
```

### Step 5 — Create `terraform.tfvars`

```hcl
# terraform.tfvars
project_id = "YOUR_PROJECT_ID"
region     = "europe-west2"
```

### Step 6 — Deploy

```bash
terraform init
terraform plan
terraform apply -auto-approve
```

### Step 7 — Verify

```bash
# Get the LB IP
terraform output lb_ip_address

# Test the LB (wait 3-5 min for propagation)
LB_IP=$(terraform output -raw lb_ip_address)
echo "Testing http://$LB_IP ..."

for i in $(seq 1 30); do
    STATUS=$(curl -s -o /dev/null -w '%{http_code}' http://$LB_IP/ 2>/dev/null)
    [ "$STATUS" = "200" ] && echo "LB active!" && break
    echo "  Attempt $i: HTTP $STATUS"
    sleep 10
done

# Test traffic distribution
for i in $(seq 1 6); do
    curl -s http://$LB_IP/
    echo "---"
done
```

### Step 8 — Check Backend Health via gcloud

```bash
gcloud compute backend-services get-health tf-lb-backend-svc --global
```

### Cleanup

```bash
terraform destroy -auto-approve
rm -rf ~/tf-lb-lab
```

---

## Part 3 — Revision (15 min)

### Key Concepts

- Terraform HTTP LB needs 7 resources: template, MIG, health check, backend service, URL map, proxy, forwarding rule
- Terraform handles dependency ordering automatically based on resource references
- `log_config` block on `google_compute_backend_service` enables access logging
- `google_compute_global_forwarding_rule` exposes the public IP
- `google_compute_backend_service` with `backend` block connects MIG to LB
- Use `google_compute_region_instance_group_manager` for HA across zones
- `lifecycle { create_before_destroy = true }` on templates prevents downtime

### Essential HCL Patterns

```hcl
# Backend service with logging
resource "google_compute_backend_service" "web" {
  health_checks = [google_compute_health_check.http.id]
  backend {
    group = google_compute_region_instance_group_manager.web.instance_group
  }
  log_config { enable = true; sample_rate = 1.0 }
}

# URL map → proxy → forwarding rule chain
resource "google_compute_url_map" "web" {
  default_service = google_compute_backend_service.web.id
}
resource "google_compute_target_http_proxy" "web" {
  url_map = google_compute_url_map.web.id
}
resource "google_compute_global_forwarding_rule" "web" {
  target     = google_compute_target_http_proxy.web.id
  port_range = "80"
}
```

---

## Part 4 — Quiz (15 min)

**Question 1: In Terraform, you add a second backend service for `/api/*` routes. What else needs to change?**

<details>
<summary>Show Answer</summary>

The **URL map** needs a `host_rule` and `path_matcher`:

```hcl
resource "google_compute_url_map" "web" {
  name            = "my-url-map"
  default_service = google_compute_backend_service.web.id

  host_rule {
    hosts        = ["*"]
    path_matcher = "allpaths"
  }

  path_matcher {
    name            = "allpaths"
    default_service = google_compute_backend_service.web.id

    path_rule {
      paths   = ["/api/*"]
      service = google_compute_backend_service.api.id
    }
  }
}
```

You also need the new backend service resource with its own health check and backend MIG.

</details>

**Question 2: `terraform apply` fails with "The resource 'xxx' is already being used by 'yyy'." when updating the instance template. How do you fix this?**

<details>
<summary>Show Answer</summary>

Add to the instance template:
```hcl
lifecycle {
  create_before_destroy = true
}
```
And use `name_prefix` instead of `name`:
```hcl
name_prefix = "web-tpl-"
```

Without these, Terraform tries to delete the old template before creating the new one, but the MIG still references it. With `create_before_destroy`, Terraform creates the new template first, updates the MIG reference, then deletes the old template.

</details>

**Question 3: How do you add HTTPS (SSL) to this Terraform LB?**

<details>
<summary>Show Answer</summary>

Three changes:

1. **Add SSL certificate** (managed or self-managed):
```hcl
resource "google_compute_managed_ssl_certificate" "web" {
  name = "web-ssl-cert"
  managed { domains = ["example.com"] }
}
```

2. **Replace** `google_compute_target_http_proxy` with `google_compute_target_https_proxy`:
```hcl
resource "google_compute_target_https_proxy" "web" {
  name             = "web-https-proxy"
  url_map          = google_compute_url_map.web.id
  ssl_certificates = [google_compute_managed_ssl_certificate.web.id]
}
```

3. **Update forwarding rule** port to 443:
```hcl
port_range = "443"
target     = google_compute_target_https_proxy.web.id
```

</details>

**Question 4: You want to destroy only the LB (not the backend VMs). How?**

<details>
<summary>Show Answer</summary>

Use **targeted destroy**:
```bash
terraform destroy \
  -target=google_compute_global_forwarding_rule.web \
  -target=google_compute_target_http_proxy.web \
  -target=google_compute_url_map.web \
  -target=google_compute_backend_service.web
```

This destroys only the LB components (top-down), leaving the MIG, instance template, and health check intact. Note: `-target` affects dependent resources too, so ordering matters.

Alternatively, remove the LB resources from your `.tf` files and run `terraform apply` — Terraform will destroy only the removed resources.

</details>

---

*Next: [Day 59 — LB Troubleshooting](DAY_59_LB_TROUBLESHOOTING.md)*
