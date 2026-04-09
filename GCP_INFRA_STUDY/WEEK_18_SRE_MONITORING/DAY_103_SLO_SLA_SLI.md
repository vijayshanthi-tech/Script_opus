# Week 18, Day 103 (Mon) — SLO, SLA & SLI

## Today's Objective

Understand Service Level Objectives (SLOs), Service Level Agreements (SLAs), and Service Level Indicators (SLIs). Learn error budgets, SLO-based alerting vs threshold alerting, and the cultural shift that SRE brings to infrastructure operations.

**Source:** [Google SRE Book: SLIs, SLOs, SLAs](https://sre.google/sre-book/service-level-objectives/) | [Cloud Monitoring SLO](https://cloud.google.com/monitoring/slo/overview)

**Deliverable:** An SLO definition for a sample service with SLIs, error budget calculation, and monitoring alerts

---

## Part 1: Concept (30 minutes)

### 1.1 The SRE Triangle

```
Linux analogy:

uptime(1)                  ──►    SLI (measurement)
/etc/cron.d/health-check   ──►    Monitoring
SLA in hosting contract    ──►    SLA (business agreement)
"99.9% uptime target"      ──►    SLO (internal target)
Downtime budget per month  ──►    Error budget
```

### 1.2 SLI → SLO → SLA Relationship

```
┌──────────────────────────────────────────────────────────┐
│                                                           │
│   SLI (Service Level Indicator)                           │
│   ─────────────────────────────                           │
│   "What we measure"                                       │
│   • Availability: successful requests / total requests    │
│   • Latency: % of requests < 300ms                        │
│   • Throughput: requests per second                        │
│                    │                                      │
│                    ▼                                      │
│   SLO (Service Level Objective)                           │
│   ─────────────────────────────                           │
│   "What we aim for" (internal target)                     │
│   • 99.9% availability over 30 days                       │
│   • 95% of requests < 300ms                               │
│   • Error budget = 100% - 99.9% = 0.1%                   │
│                    │                                      │
│                    ▼                                      │
│   SLA (Service Level Agreement)                           │
│   ─────────────────────────────                           │
│   "What we promise" (external contract)                   │
│   • 99.5% availability (looser than SLO!)                 │
│   • Penalty: credit if breached                           │
│   • Always set SLO stricter than SLA                      │
│                                                           │
└──────────────────────────────────────────────────────────┘
```

### 1.3 Error Budget

| SLO | Error Budget (30 days) | Allowed Downtime |
|---|---|---|
| 99.0% | 1.0% | 7 hours 18 min |
| 99.5% | 0.5% | 3 hours 39 min |
| 99.9% | 0.1% | 43 min 50 sec |
| 99.95% | 0.05% | 21 min 55 sec |
| 99.99% | 0.01% | 4 min 23 sec |

```
Error Budget = 100% - SLO

Example: SLO = 99.9% availability
  Error Budget = 0.1%
  Monthly budget = 30 days × 24h × 60min × 0.001 = 43.2 minutes

If you've used 30 minutes already:
  Remaining budget = 13.2 minutes
  Action: freeze deployments, focus on reliability
```

### 1.4 SLO-Based Alerting vs Threshold Alerting

| Approach | Trigger | Problem |
|---|---|---|
| **Threshold** | CPU > 80% for 5 min | May not affect users; noisy |
| **SLO-based** | Error budget burn rate > 14x | Directly tied to user impact |

```
Threshold alerting:
  CPU > 80%  ──► ALERT!
  But users are fine...  ──► False alarm, alert fatigue

SLO-based alerting:
  Error budget burning at 14x normal rate
  ──► At this rate, budget exhausted in 1 hour
  ──► ALERT! (Users ARE affected)
```

### 1.5 Burn Rate

```
Burn rate = actual error rate / allowed error rate

Example:
  SLO = 99.9% (allowed error rate = 0.1%)
  Current error rate = 1.4% (14× normal)
  
  Burn rate = 1.4% / 0.1% = 14

  At burn rate 14:
    30-day budget consumed in ~2.14 days
    ──► CRITICAL: page the on-call
```

| Burn Rate | Budget Exhaustion | Severity |
|---|---|---|
| 1× | 30 days | Normal |
| 2× | 15 days | Watch |
| 6× | 5 days | Warning |
| 14× | ~2 days | Critical (page) |
| 36× | ~20 hours | Emergency |

### 1.6 SRE Culture Shift

| Traditional Ops | SRE Approach |
|---|---|
| "Keep everything up always" | "Budget errors, ship features" |
| Alert on every metric spike | Alert on user-impacting issues |
| Blame the last deployer | Blameless post-mortems |
| Manual scaling, manual deploys | Automate toil away |
| "We need more 9s!" | "What's the right SLO for this?" |

---

## Part 2: Hands-On Lab (60 minutes)

### Step 1: Enable Required APIs (5 min)

```bash
export PROJECT_ID=$(gcloud config get-value project)

gcloud services enable monitoring.googleapis.com \
  compute.googleapis.com \
  logging.googleapis.com
```

### Step 2: Create a Sample Service (10 min)

```bash
# Create a simple web server VM to monitor
gcloud compute instances create slo-lab-vm \
  --zone=europe-west2-a \
  --machine-type=e2-micro \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --tags=http-server \
  --metadata=startup-script='#!/bin/bash
apt-get update && apt-get install -y nginx
# Create a health endpoint
echo "OK" > /var/www/html/health
systemctl enable nginx && systemctl start nginx'

# Allow HTTP traffic
gcloud compute firewall-rules create slo-lab-allow-http \
  --direction=INGRESS \
  --action=ALLOW \
  --rules=tcp:80 \
  --source-ranges=130.211.0.0/22,35.191.0.0/16 \
  --target-tags=http-server \
  --quiet 2>/dev/null || true
```

### Step 3: Define SLIs with gcloud (15 min)

```bash
# Get the VM's external IP
VM_IP=$(gcloud compute instances describe slo-lab-vm \
  --zone=europe-west2-a \
  --format='get(networkInterfaces[0].accessConfigs[0].natIP)')

echo "VM IP: $VM_IP"

# Create an uptime check (this becomes our availability SLI)
gcloud monitoring uptime create slo-lab-availability \
  --resource-type=uptime-url \
  --monitored-resource="host=${VM_IP}" \
  --http-path="/health" \
  --period=60 \
  --timeout=10 \
  --regions=europe-west1,us-east4,asia-southeast1

# List uptime checks
gcloud monitoring uptime list-configs \
  --format="table(name.basename(), displayName, monitoredResource.labels.host)"
```

### Step 4: Create an SLO via Terraform (20 min)

```bash
mkdir -p tf-slo-lab && cd tf-slo-lab

cat > main.tf <<'EOF'
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
  region  = "europe-west2"
}

variable "project_id" {
  type = string
}

# Create a custom monitoring service
resource "google_monitoring_custom_service" "web_app" {
  service_id   = "slo-lab-web-app"
  display_name = "SLO Lab Web Application"
}

# Define availability SLO: 99.5% over 30 days
resource "google_monitoring_slo" "availability" {
  service      = google_monitoring_custom_service.web_app.service_id
  slo_id       = "availability-slo"
  display_name = "99.5% Availability (30d rolling)"

  goal                = 0.995
  rolling_period_days = 30

  windows_based_sli {
    window_period = "300s"
    good_total_ratio_threshold {
      threshold = 0.995
      performance {
        good_total_ratio {
          good_service_filter = join(" AND ", [
            "metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\"",
            "resource.type=\"uptime_url\"",
          ])
          total_service_filter = join(" AND ", [
            "metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\"",
            "resource.type=\"uptime_url\"",
          ])
        }
      }
    }
  }
}

# Burn-rate alert: fires when consuming budget 14x faster than normal
resource "google_monitoring_alert_policy" "slo_burn_rate" {
  display_name = "SLO Burn Rate Alert - Availability"
  combiner     = "OR"

  conditions {
    display_name = "High burn rate (14x)"

    condition_threshold {
      filter          = "select_slo_burn_rate(\"${google_monitoring_slo.availability.id}\", \"3600s\")"
      comparison      = "COMPARISON_GT"
      threshold_value = 14
      duration        = "0s"

      trigger {
        count = 1
      }

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_NEXT_OLDER"
      }
    }
  }

  notification_channels = []

  documentation {
    content   = "Availability SLO burn rate exceeds 14x. Error budget will be exhausted in ~2 days at this rate. Investigate immediately."
    mime_type = "text/markdown"
  }
}

output "slo_id" {
  value = google_monitoring_slo.availability.id
}

output "alert_policy_name" {
  value = google_monitoring_alert_policy.slo_burn_rate.display_name
}
EOF

echo "project_id = \"${PROJECT_ID}\"" > terraform.tfvars

terraform init
terraform plan
terraform apply -auto-approve
```

### Step 5: View SLO in Console (5 min)

```bash
echo "View your SLO at:"
echo "https://console.cloud.google.com/monitoring/services/custom:slo-lab-web-app?project=${PROJECT_ID}"
```

### Step 6: Calculate Error Budget Manually (5 min)

```bash
cat <<'CALC'
=== Error Budget Calculation ===

SLO:            99.5% availability (30-day rolling)
Error budget:   0.5% = 30 days × 24h × 60min × 0.005 = 216 minutes

Current state:  Check Cloud Monitoring console

If 50 minutes used:
  Remaining:  166 minutes (76.9% remaining)
  Status:     Healthy — can deploy new features

If 200 minutes used:
  Remaining:  16 minutes (7.4% remaining)
  Status:     CRITICAL — freeze deployments, fix reliability
CALC
```

### Step 7: Clean Up

```bash
cd tf-slo-lab
terraform destroy -auto-approve
cd ~
rm -rf tf-slo-lab

gcloud compute instances delete slo-lab-vm --zone=europe-west2-a --quiet
gcloud compute firewall-rules delete slo-lab-allow-http --quiet 2>/dev/null
gcloud monitoring uptime delete slo-lab-availability --quiet 2>/dev/null
```

---

## Part 3: Revision (15 minutes)

- **SLI** = what you measure (availability ratio, latency percentile)
- **SLO** = what you target internally (99.9% over 30 days)
- **SLA** = what you promise externally (always looser than SLO)
- **Error budget** = 100% − SLO; the "budget" of allowed failures
- **Burn rate** = how fast you're consuming error budget (14× = page immediately)
- **SLO-based alerting** > threshold alerting — alerts correlate to user impact
- Set SLO first, then design monitoring around it — not the other way around

### Key Commands
```bash
gcloud monitoring uptime create NAME --resource-type=uptime-url
gcloud monitoring uptime list-configs
# SLOs are best managed via Terraform or Console
# Burn rate alerts use: select_slo_burn_rate("SLO_ID", "WINDOW")
```

---

## Part 4: Quiz (15 minutes)

**Q1:** Your SLO is 99.9% availability (30 days). How much downtime can you afford per month?
<details><summary>Answer</summary>Error budget = 0.1%. Monthly downtime = 30 × 24 × 60 × 0.001 = <b>43.2 minutes</b>. If a single incident lasts 30 minutes, you've consumed 69% of the monthly budget. Two such incidents would breach the SLO.</details>

**Q2:** Why should the SLA be looser than the SLO?
<details><summary>Answer</summary>The SLO is your <b>internal target</b> — it triggers alerts and freezes before users notice. The SLA is the <b>external contract</b> with financial penalties. By setting the SLO stricter (e.g., 99.9% vs SLA of 99.5%), you have a buffer before breaching the SLA. You'll get alerted and fix issues before the customer notices or triggers a penalty.</details>

**Q3:** A threshold alert fires: "CPU > 80% for 5 minutes". Should the on-call engineer drop everything?
<details><summary>Answer</summary>Not necessarily. A CPU spike doesn't automatically mean users are affected. With SLO-based alerting, the key question is: <b>"Is the error budget burning?"</b> If availability and latency SLIs are fine, the CPU spike may be normal (e.g., a batch job). SRE practice: correlate resource metrics with SLIs before escalating. Threshold alerts should inform; SLO alerts should page.</details>

**Q4:** Your error budget is 80% consumed with 10 days left in the window. What actions should you take?
<details><summary>Answer</summary>
1. <b>Freeze non-critical deployments</b> — new releases carry risk<br>
2. <b>Review recent incidents</b> — find the top error budget consumers<br>
3. <b>Focus engineering on reliability</b> — fix the root causes<br>
4. <b>Communicate with stakeholders</b> — explain the freeze<br>
5. If budget exhausted, only <b>reliability-improving changes</b> should be deployed<br>
The error budget is a negotiation tool: SRE says "no more releases" when budget is low; dev says "let us release" when budget is healthy.
</details>
