# Week 18, Day 108 (Sat) — PROJECT: SRE Monitoring Pack v2

## Today's Objective

Build a complete SRE monitoring setup combining everything from this week: SLO tracking with error budgets, golden signal dashboards, multi-window burn-rate alerts, log-based metrics, and a monitoring strategy document — all deployed via Terraform.

**Source:** [Google SRE Workbook](https://sre.google/workbook/) | [Cloud Monitoring SLOs](https://cloud.google.com/monitoring/slo/overview)

**Deliverable:** Production-ready monitoring pack with SLO service, dashboards, burn-rate alerts, log metrics, and documentation

---

## Part 1: Concept (30 minutes)

### 1.1 Project Architecture

```
sre-monitoring-pack/
│
├── terraform/
│   ├── main.tf              ← Provider config
│   ├── variables.tf         ← Project-level vars
│   ├── slo.tf               ← Custom service + SLO definitions
│   ├── dashboards.tf        ← Golden signal + executive dashboards
│   ├── alerts.tf            ← Burn-rate + threshold alerts
│   ├── log_metrics.tf       ← Log-based metric definitions
│   ├── notifications.tf     ← Notification channels
│   ├── outputs.tf           ← Dashboard URLs, alert IDs
│   └── terraform.tfvars     ← Project-specific values
│
├── docs/
│   ├── MONITORING_STRATEGY.md
│   ├── RUNBOOKS.md
│   └── ON_CALL_PROCEDURES.md
│
└── README.md
```

### 1.2 Component Map

```
┌──────────────────────────────────────────────────────────┐
│                  SRE MONITORING PACK v2                    │
│                                                           │
│  ┌─────────────┐  ┌─────────────┐  ┌──────────────────┐  │
│  │   SLOs      │  │ Dashboards  │  │  Alerts          │  │
│  │             │  │             │  │                  │  │
│  │ Availability│  │ Executive   │  │ Burn-rate (P1)   │  │
│  │ 99.9% (30d) │  │ Golden Sigs │  │ Threshold (P2)   │  │
│  │ Error budget│  │ Infra/USE   │  │ Security (P3)    │  │
│  └─────────────┘  └─────────────┘  └──────────────────┘  │
│                                                           │
│  ┌─────────────┐  ┌─────────────┐  ┌──────────────────┐  │
│  │ Log Metrics │  │ Notif.      │  │ Documentation    │  │
│  │             │  │ Channels    │  │                  │  │
│  │ Error count │  │ Email       │  │ Strategy doc     │  │
│  │ SSH logins  │  │ (Slack,PD   │  │ Runbooks         │  │
│  │ IAM changes │  │  concepts)  │  │ On-call procs    │  │
│  └─────────────┘  └─────────────┘  └──────────────────┘  │
└──────────────────────────────────────────────────────────┘
```

### 1.3 SLO Summary

| Service | SLI | SLO Target | Error Budget (30d) | Alert Strategy |
|---|---|---|---|---|
| Web Service | Uptime check pass rate | 99.9% | 43.2 min | Multi-window burn rate |
| Compute | VM availability | 99.5% | 3h 39min | Threshold |

---

## Part 2: Hands-On Lab (60 minutes)

### Step 1: Create Monitored Infrastructure (10 min)

```bash
export PROJECT_ID=$(gcloud config get-value project)

# Create a web server VM
gcloud compute instances create sre-pack-web \
  --zone=europe-west2-a \
  --machine-type=e2-small \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --tags=http-server \
  --labels=env=prod,tier=1,service=web-api \
  --metadata=startup-script='#!/bin/bash
apt-get update && apt-get install -y nginx stress-ng
echo "OK" > /var/www/html/health
echo "{\"status\":\"healthy\",\"service\":\"web-api\"}" > /var/www/html/api/health
mkdir -p /var/www/html/api
echo "{\"status\":\"healthy\"}" > /var/www/html/api/health
systemctl start nginx'

# Firewall for health checks
gcloud compute firewall-rules create sre-pack-allow-hc \
  --direction=INGRESS --action=ALLOW --rules=tcp:80 \
  --source-ranges=130.211.0.0/22,35.191.0.0/16,35.235.240.0/20 \
  --target-tags=http-server \
  --quiet 2>/dev/null || true
```

### Step 2: Build the Terraform Monitoring Pack (35 min)

```bash
mkdir -p sre-pack/terraform sre-pack/docs && cd sre-pack/terraform

# --- main.tf ---
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
EOF

# --- variables.tf ---
cat > variables.tf <<'EOF'
variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "region" {
  type        = string
  description = "GCP region"
  default     = "europe-west2"
}

variable "availability_slo_target" {
  type        = number
  description = "Availability SLO target (0-1)"
  default     = 0.999
}
EOF

# --- slo.tf ---
cat > slo.tf <<'EOF'
# Custom monitoring service
resource "google_monitoring_custom_service" "web_api" {
  service_id   = "sre-pack-web-api"
  display_name = "Web API Service (Tier 1)"
}

# Availability SLO
resource "google_monitoring_slo" "availability" {
  service      = google_monitoring_custom_service.web_api.service_id
  slo_id       = "availability-slo-30d"
  display_name = "${var.availability_slo_target * 100}% Availability (30d rolling)"

  goal                = var.availability_slo_target
  rolling_period_days = 30

  windows_based_sli {
    window_period = "300s"
    good_total_ratio_threshold {
      threshold = 0.99
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
EOF

# --- log_metrics.tf ---
cat > log_metrics.tf <<'EOF'
# Error count from application logs
resource "google_logging_metric" "app_errors" {
  name        = "sre-pack-app-errors"
  filter      = "resource.type=\"gce_instance\" AND severity >= ERROR"
  description = "Count of ERROR+ severity log entries from GCE instances"

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
  }
}

# SSH login detection
resource "google_logging_metric" "ssh_logins" {
  name        = "sre-pack-ssh-logins"
  filter      = "resource.type=\"gce_instance\" AND textPayload=~\"Accepted publickey|Accepted password|session opened\""
  description = "Count of SSH login events"

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
  }
}

# IAM policy changes
resource "google_logging_metric" "iam_changes" {
  name        = "sre-pack-iam-changes"
  filter      = "protoPayload.methodName=\"SetIamPolicy\""
  description = "Count of IAM policy modifications"

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
  }
}
EOF

# --- alerts.tf ---
cat > alerts.tf <<'EOF'
# --- Burn Rate Alert: Fast burn (page) ---
resource "google_monitoring_alert_policy" "burn_rate_fast" {
  display_name = "SRE Pack: SLO Burn Rate CRITICAL (14x)"
  combiner     = "AND"

  conditions {
    display_name = "1h burn rate > 14x"

    condition_threshold {
      filter          = "select_slo_burn_rate(\"${google_monitoring_slo.availability.id}\", \"3600s\")"
      comparison      = "COMPARISON_GT"
      threshold_value = 14
      duration        = "0s"

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_NEXT_OLDER"
      }

      trigger {
        count = 1
      }
    }
  }

  documentation {
    content   = <<-DOC
    ## CRITICAL: SLO Burn Rate > 14x

    Error budget is being consumed 14× faster than normal.
    At this rate, the entire 30-day budget will be exhausted in ~2 days.

    ### Immediate Actions
    1. Check uptime status: `gcloud monitoring uptime list-configs`
    2. Check instance: `gcloud compute instances describe sre-pack-web --zone=europe-west2-a`
    3. SSH and check nginx: `systemctl status nginx`
    4. Check recent deployments
    5. Roll back if deployment-related
    DOC
    mime_type = "text/markdown"
  }

  alert_strategy {
    notification_rate_limit {
      period = "600s"
    }
  }
}

# --- Burn Rate Alert: Slow burn (ticket) ---
resource "google_monitoring_alert_policy" "burn_rate_slow" {
  display_name = "SRE Pack: SLO Burn Rate WARNING (6x)"
  combiner     = "AND"

  conditions {
    display_name = "6h burn rate > 6x"

    condition_threshold {
      filter          = "select_slo_burn_rate(\"${google_monitoring_slo.availability.id}\", \"21600s\")"
      comparison      = "COMPARISON_GT"
      threshold_value = 6
      duration        = "0s"

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_NEXT_OLDER"
      }

      trigger {
        count = 1
      }
    }
  }

  documentation {
    content   = "SLO burn rate > 6x over 6h. Error budget at risk. Create a ticket and investigate."
    mime_type = "text/markdown"
  }

  alert_strategy {
    notification_rate_limit {
      period = "1800s"
    }
  }
}

# --- Infrastructure: CPU saturation ---
resource "google_monitoring_alert_policy" "cpu_saturation" {
  display_name = "SRE Pack: CPU Saturation > 90%"
  combiner     = "OR"

  conditions {
    display_name = "CPU > 90% for 10 min"

    condition_threshold {
      filter          = "metric.type=\"compute.googleapis.com/instance/cpu/utilization\" AND resource.type=\"gce_instance\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0.9
      duration        = "600s"

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }

      trigger {
        count = 1
      }
    }
  }

  documentation {
    content   = "CPU utilization > 90% for 10+ minutes. Check `top` and consider scaling."
    mime_type = "text/markdown"
  }

  alert_strategy {
    auto_close = "1800s"
    notification_rate_limit {
      period = "900s"
    }
  }
}

# --- Security: SSH login ---
resource "google_monitoring_alert_policy" "ssh_login" {
  display_name = "SRE Pack: SSH Login Detected"
  combiner     = "OR"

  conditions {
    display_name = "SSH login event"

    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.ssh_logins.name}\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      duration        = "0s"

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_COUNT"
      }

      trigger {
        count = 1
      }
    }
  }

  documentation {
    content   = "SSH login detected on a production instance. Verify this was an authorised action."
    mime_type = "text/markdown"
  }
}

# --- Security: IAM change ---
resource "google_monitoring_alert_policy" "iam_change" {
  display_name = "SRE Pack: IAM Policy Changed"
  combiner     = "OR"

  conditions {
    display_name = "IAM policy modification"

    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.iam_changes.name}\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      duration        = "0s"

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_COUNT"
      }

      trigger {
        count = 1
      }
    }
  }

  documentation {
    content   = "IAM policy was modified. Review audit logs to confirm authorisation."
    mime_type = "text/markdown"
  }
}
EOF

# --- dashboards.tf ---
cat > dashboards.tf <<'EOF'
resource "google_monitoring_dashboard" "golden_signals" {
  dashboard_json = jsonencode({
    displayName = "SRE Pack: Golden Signals"
    gridLayout = {
      columns = 2
      widgets = [
        {
          title = "Traffic: Network Bytes In"
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "metric.type=\"compute.googleapis.com/instance/network/received_bytes_count\" AND resource.type=\"gce_instance\""
                  aggregation = {
                    alignmentPeriod  = "60s"
                    perSeriesAligner = "ALIGN_RATE"
                  }
                }
              }
            }]
          }
        },
        {
          title = "Traffic: Network Bytes Out"
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "metric.type=\"compute.googleapis.com/instance/network/sent_bytes_count\" AND resource.type=\"gce_instance\""
                  aggregation = {
                    alignmentPeriod  = "60s"
                    perSeriesAligner = "ALIGN_RATE"
                  }
                }
              }
            }]
          }
        },
        {
          title = "Saturation: CPU Utilization"
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "metric.type=\"compute.googleapis.com/instance/cpu/utilization\" AND resource.type=\"gce_instance\""
                  aggregation = {
                    alignmentPeriod  = "60s"
                    perSeriesAligner = "ALIGN_MEAN"
                  }
                }
              }
            }]
          }
        },
        {
          title = "Saturation: Disk I/O"
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "metric.type=\"compute.googleapis.com/instance/disk/write_ops_count\" AND resource.type=\"gce_instance\""
                  aggregation = {
                    alignmentPeriod  = "60s"
                    perSeriesAligner = "ALIGN_RATE"
                  }
                }
              }
            }]
          }
        }
      ]
    }
  })
}
EOF

# --- outputs.tf ---
cat > outputs.tf <<'EOF'
output "slo_id" {
  description = "Availability SLO ID"
  value       = google_monitoring_slo.availability.id
}

output "dashboard_id" {
  description = "Golden Signals Dashboard ID"
  value       = google_monitoring_dashboard.golden_signals.id
}

output "alert_policies" {
  description = "Alert policy names"
  value = [
    google_monitoring_alert_policy.burn_rate_fast.display_name,
    google_monitoring_alert_policy.burn_rate_slow.display_name,
    google_monitoring_alert_policy.cpu_saturation.display_name,
    google_monitoring_alert_policy.ssh_login.display_name,
    google_monitoring_alert_policy.iam_change.display_name,
  ]
}

output "log_metrics" {
  description = "Log-based metric names"
  value = [
    google_logging_metric.app_errors.name,
    google_logging_metric.ssh_logins.name,
    google_logging_metric.iam_changes.name,
  ]
}
EOF

# --- Apply ---
echo "project_id = \"${PROJECT_ID}\"" > terraform.tfvars
terraform init
terraform plan
terraform apply -auto-approve
```

### Step 3: Validate the Pack (10 min)

```bash
echo "=== SRE Monitoring Pack v2 — Deployment Summary ==="
echo ""
terraform output
echo ""
echo "=== Console Links ==="
echo "Dashboards: https://console.cloud.google.com/monitoring/dashboards?project=${PROJECT_ID}"
echo "Alerts:     https://console.cloud.google.com/monitoring/alerting?project=${PROJECT_ID}"
echo "SLOs:       https://console.cloud.google.com/monitoring/services?project=${PROJECT_ID}"
echo "Logs:       https://console.cloud.google.com/logs?project=${PROJECT_ID}"
```

### Step 4: Clean Up (5 min)

```bash
cd sre-pack/terraform
terraform destroy -auto-approve
cd ~
rm -rf sre-pack

gcloud compute instances delete sre-pack-web --zone=europe-west2-a --quiet
gcloud compute firewall-rules delete sre-pack-allow-hc --quiet 2>/dev/null
```

---

## Part 3: Revision (15 minutes)

- **SLO service** — `google_monitoring_custom_service` + `google_monitoring_slo` for tracking
- **Multi-window burn rate** — 1h/14× for critical (page), 6h/6× for warning (ticket)
- **Golden signal dashboard** — traffic, saturation (CPU/disk) as time series charts
- **Log-based metrics** — error count, SSH logins, IAM changes → all alertable
- **Notification rate limiting** — prevents alert storms (600s for critical, 1800s for warnings)
- **Embedded runbooks** — every alert has investigation steps in `documentation` block
- **Everything in Terraform** — SLOs, dashboards, alerts, log metrics are version-controlled

### Key Commands
```bash
terraform output                                    # See all deployed resources
gcloud monitoring policies list                     # List alert policies
gcloud monitoring dashboards list                   # List dashboards
gcloud logging metrics list                         # List custom metrics
```

---

## Part 4: Quiz (15 minutes)

**Q1:** The SRE pack has 5 alert policies. Classify each by severity (P1/P2/P3) and justify.
<details><summary>Answer</summary>
<b>P1 (Page):</b> Burn rate CRITICAL (14×) — users are currently impacted, budget draining fast<br>
<b>P2 (Ticket):</b> Burn rate WARNING (6×) — slow degradation, needs attention within hours. CPU saturation — capacity issue, may escalate<br>
<b>P3 (Email):</b> SSH login — informational security signal. IAM change — audit event, needs review<br>
P1 = immediate user impact. P2 = will impact users soon. P3 = informational/security.
</details>

**Q2:** Why are log-based metrics managed in Terraform alongside infrastructure?
<details><summary>Answer</summary>Log-based metrics are <b>monitoring infrastructure</b> — they should be version-controlled, reviewed in PRs, and deployed consistently. If a metric filter is wrong, it affects alerting reliability. Terraform ensures: 1) metrics exist before alerts reference them, 2) changes are tracked in git, 3) consistent deployment across environments, 4) cleanup happens automatically on destroy. Like managing Nagios check configs in Puppet/Ansible.</details>

**Q3:** The burn rate alert fires but resolves in 2 minutes. Is the alert configuration correct?
<details><summary>Answer</summary>A 2-minute spike shouldn't trigger a burn rate alert if configured correctly. Check: 1) Is the <code>duration</code> set to <code>0s</code>? Should it require sustained burn (e.g., 300s)? 2) Is it a multi-window alert? A single short window can false-fire on blips. The fix: add a <b>long window confirmation</b> — alert only when BOTH short (1h) AND long (6h) windows show elevated burn. This eliminates one-off spikes.</details>

**Q4:** Walk through the complete monitoring lifecycle for a new service being onboarded.
<details><summary>Answer</summary>
1. <b>Classify tier</b> — determine business impact (Tier 1/2/3)<br>
2. <b>Define SLIs</b> — availability, latency, error rate for the service<br>
3. <b>Set SLOs</b> — based on tier (99.95% for T1, 99.9% for T2)<br>
4. <b>Create log-based metrics</b> — for app-specific signals<br>
5. <b>Deploy monitoring via Terraform</b> — SLO, dashboards, alerts<br>
6. <b>Add to strategy doc</b> — update service catalogue and tier table<br>
7. <b>Write runbooks</b> — embed in alert documentation<br>
8. <b>Add to on-call rotation</b> — update escalation matrix<br>
9. <b>Review after 30 days</b> — tune SLOs and alerts based on real data
</details>
