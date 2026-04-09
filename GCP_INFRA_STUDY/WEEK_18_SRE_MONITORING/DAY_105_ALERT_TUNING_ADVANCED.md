# Week 18, Day 105 (Wed) — Advanced Alert Tuning

## Today's Objective

Master multi-condition alerts, notification rate limiting, alert grouping, SLO-based burn rate alerts, on-call best practices, and understand integration concepts with PagerDuty/OpsGenie.

**Source:** [Cloud Monitoring Alerting](https://cloud.google.com/monitoring/alerts) | [Google SRE: Alerting on SLOs](https://sre.google/workbook/alerting-on-slos/) | [Multi-window Burn Rate](https://sre.google/workbook/alerting-on-slos/#6-multiwindow-multi-burn-rate-alerts)

**Deliverable:** A tuned alerting configuration with multi-condition policies, burn rate alerts, and documented on-call procedures

---

## Part 1: Concept (30 minutes)

### 1.1 Alert Fatigue — The #1 Problem

```
Linux analogy:

/var/log/messages with ERROR every second   ──►   Alert storms
logrotate + log level tuning                ──►   Alert tuning
/etc/rsyslog.d/rate-limit.conf              ──►   Notification rate limiting
"I just ignore the alerts now"              ──►   Alert fatigue (disaster waiting)
```

```
                    Alert Pipeline
                    
Raw metrics ──► Conditions ──► Policies ──► Channels ──► Human
                                                           │
              Too many?           Too noisy?           FATIGUE
              Simplify            Rate limit           They stop
              conditions          channels             reading
```

### 1.2 Multi-Condition Alerts

```
┌─────────────────────────────────────────────────┐
│           SINGLE CONDITION (noisy)               │
│                                                  │
│   CPU > 80%  ──► ALERT                           │
│   (fires on any spike, even during batch jobs)   │
└─────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────┐
│           MULTI-CONDITION (precise)              │
│                                                  │
│   CPU > 80% for 10 min                           │
│       AND                                        │
│   Error rate > 1%                                │
│       AND                                        │
│   Memory > 90%                                   │
│                                                  │
│   ──► ALERT (all conditions met = real problem)  │
└─────────────────────────────────────────────────┘
```

| Combiner | Meaning | Use When |
|---|---|---|
| `AND` | All conditions must be true | Reduce false positives |
| `OR` | Any condition triggers | Catch multiple failure modes |
| `AND_WITH_MATCHING_RESOURCE` | All conditions on same resource | Per-instance correlation |

### 1.3 Multi-Window Burn Rate Alerts

The gold standard for SLO alerting — uses two windows to catch both fast and slow budget burns:

```
┌──────────────────────────────────────────────────┐
│  SHORT WINDOW (1h)         LONG WINDOW (6h)       │
│                                                   │
│  Burn rate > 14×           Burn rate > 6×          │
│  ──► "Burning fast!"       ──► "Burning slowly"    │
│  ──► Page immediately      ──► Create ticket       │
│                                                   │
│  Combined:                                         │
│  Short(1h) > 14× AND Long(6h) > 6×               │
│  ──► Confirmed fast burn, not just a blip          │
└──────────────────────────────────────────────────┘
```

| Window | Burn Rate | Response | Detection Time |
|---|---|---|---|
| 1h short + 6h long | 14× / 6× | Page (P1) | ~1 hour |
| 6h short + 3d long | 6× / 1× | Ticket (P2) | ~6 hours |
| 3d short + 30d long | 1× / 1× | Review (P3) | ~3 days |

### 1.4 Notification Rate Limiting

```
Without rate limiting:
  Alert fires ──► SMS + Email + Slack every 60 seconds
  ──► 60 notifications in 1 hour
  ──► Engineer mutes phone ──► Misses critical alert later

With rate limiting:
  Alert fires ──► Notify once
  ──► Reminder at 15 min, 30 min, 1 hour
  ──► Resolution notification when cleared
  ──► 4 notifications instead of 60
```

### 1.5 Alert Grouping

| Approach | When | Example |
|---|---|---|
| **Group by service** | Multiple instances failing | "3 of 5 web servers down" vs 3 separate alerts |
| **Group by region** | Regional outage | "europe-west2: 5 alerts" vs 5 individual ones |
| **Inhibition** | Higher-level failure explains lower | If load balancer down, suppress instance alerts |

### 1.6 On-Call Best Practices

| Practice | Why |
|---|---|
| Maximum 2 pages per 12h shift | Prevents burnout |
| Runbook linked in every alert | Reduces MTTR (mean time to resolve) |
| Escalation after 15 min no-ack | Ensures coverage |
| Post-incident review for every page | Continuous improvement |
| Rotate on-call weekly | Fair load distribution |

---

## Part 2: Hands-On Lab (60 minutes)

### Step 1: Create Monitored Resources (10 min)

```bash
export PROJECT_ID=$(gcloud config get-value project)

# Create a VM to monitor
gcloud compute instances create alert-lab-vm \
  --zone=europe-west2-a \
  --machine-type=e2-small \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --labels=env=lab,week=18 \
  --metadata=startup-script='#!/bin/bash
apt-get update && apt-get install -y nginx stress-ng
systemctl start nginx'
```

### Step 2: Create Notification Channel (5 min)

```bash
# Create an email notification channel
gcloud monitoring channels create \
  --type=email \
  --display-name="Lab Alert Channel" \
  --channel-labels=email_address="your-email@example.com"

# List channels and get the channel ID
CHANNEL_ID=$(gcloud monitoring channels list \
  --filter="displayName='Lab Alert Channel'" \
  --format="value(name)" | head -1)

echo "Channel ID: $CHANNEL_ID"
```

### Step 3: Create Multi-Condition Alert via Terraform (20 min)

```bash
mkdir -p tf-alert-lab && cd tf-alert-lab

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

variable "notification_channel_id" {
  type    = string
  default = ""
}

# --- Multi-Condition Alert: CPU + Memory Saturation ---
resource "google_monitoring_alert_policy" "saturation_alert" {
  display_name = "Alert Lab - Saturation (CPU AND Memory)"
  combiner     = "AND"

  conditions {
    display_name = "CPU utilization > 80% for 5 min"

    condition_threshold {
      filter          = "metric.type=\"compute.googleapis.com/instance/cpu/utilization\" AND resource.type=\"gce_instance\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0.8
      duration        = "300s"

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }

      trigger {
        count = 1
      }
    }
  }

  conditions {
    display_name = "Memory usage > 90%"

    condition_threshold {
      filter          = "metric.type=\"agent.googleapis.com/memory/percent_used\" AND resource.type=\"gce_instance\" AND metric.labels.state=\"used\""
      comparison      = "COMPARISON_GT"
      threshold_value = 90
      duration        = "300s"

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }

      trigger {
        count = 1
      }
    }
  }

  notification_channels = var.notification_channel_id != "" ? [var.notification_channel_id] : []

  documentation {
    content   = <<-DOC
    ## Saturation Alert

    **What:** Both CPU (>80%) and memory (>90%) are high simultaneously.
    **Impact:** Service degradation likely. Response times increasing.

    ### Runbook
    1. SSH to the instance: `gcloud compute ssh INSTANCE --zone=europe-west2-a`
    2. Check top processes: `top -bn1 | head -20`
    3. Check memory: `free -h && cat /proc/meminfo | grep -E "MemTotal|MemFree|MemAvailable"`
    4. Check OOM killer: `dmesg | grep -i oom`
    5. If a runaway process: `kill -15 PID`
    6. If persistent: scale up machine type or add instances
    DOC
    mime_type = "text/markdown"
  }

  alert_strategy {
    auto_close = "1800s"  # Auto-close after 30 min of no data

    notification_rate_limit {
      period = "900s"  # Max one notification per 15 minutes
    }
  }
}

# --- Error Rate Alert ---
resource "google_monitoring_alert_policy" "error_rate" {
  display_name = "Alert Lab - High Error Rate"
  combiner     = "OR"

  conditions {
    display_name = "Uptime check failure rate > 20%"

    condition_threshold {
      filter          = "metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" AND resource.type=\"uptime_url\""
      comparison      = "COMPARISON_LT"
      threshold_value = 0.8
      duration        = "300s"

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_FRACTION_TRUE"
      }

      trigger {
        count = 1
      }
    }
  }

  notification_channels = var.notification_channel_id != "" ? [var.notification_channel_id] : []

  documentation {
    content   = <<-DOC
    ## Errors Alert

    **What:** Uptime check success rate dropped below 80%.
    **Impact:** Users are seeing errors. SLO budget burning.

    ### Runbook
    1. Check instance status: `gcloud compute instances describe alert-lab-vm --zone=europe-west2-a --format="value(status)"`
    2. Check nginx: `gcloud compute ssh alert-lab-vm --zone=europe-west2-a --command="systemctl status nginx"`
    3. Check logs: Cloud Logging → filter by instance
    4. Restart if needed: `gcloud compute instances reset alert-lab-vm --zone=europe-west2-a`
    DOC
    mime_type = "text/markdown"
  }

  alert_strategy {
    auto_close = "1800s"

    notification_rate_limit {
      period = "600s"  # Max one notification per 10 minutes
    }
  }
}

output "saturation_alert_name" {
  value = google_monitoring_alert_policy.saturation_alert.display_name
}

output "error_rate_alert_name" {
  value = google_monitoring_alert_policy.error_rate.display_name
}
EOF

echo "project_id = \"${PROJECT_ID}\"" > terraform.tfvars

terraform init
terraform plan
terraform apply -auto-approve
```

### Step 4: Trigger Alerts (Simulation) (10 min)

```bash
# SSH into VM and generate CPU load
gcloud compute ssh alert-lab-vm --zone=europe-west2-a --command="
  echo '=== Generating CPU stress ==='
  stress-ng --cpu 2 --timeout 300 &
  echo 'Stress running for 5 minutes'
  echo 'Check Cloud Monitoring for alert state changes'
"
```

### Step 5: View Alert Incidents (5 min)

```bash
# List alert policies
gcloud monitoring policies list \
  --format="table(displayName, enabled, conditions.displayName)"

# List incidents (if any triggered)
echo ""
echo "View incidents at:"
echo "https://console.cloud.google.com/monitoring/alerting?project=${PROJECT_ID}"
```

### Step 6: Document On-Call Procedures (5 min)

```bash
cat <<'RUNBOOK'
=== On-Call Procedures (Lab Example) ===

Escalation Matrix:
  0-5 min:   Auto-acknowledge via monitoring app
  5-15 min:  Primary on-call investigates
  15-30 min: If unresolved, escalate to secondary
  30-60 min: If unresolved, escalate to team lead

Alert Severity Mapping:
  P1 (Page):   SLO burn rate >14x, service fully down
  P2 (Ticket): SLO burn rate >6x, partial degradation
  P3 (Review): Capacity warnings, non-urgent

Response Checklist:
  [ ] Acknowledge the alert
  [ ] Follow the embedded runbook
  [ ] Communicate in #incidents channel
  [ ] Update status page if user-facing
  [ ] Write post-incident review within 48h
RUNBOOK
```

### Step 7: Clean Up

```bash
cd tf-alert-lab
terraform destroy -auto-approve
cd ~
rm -rf tf-alert-lab

gcloud compute instances delete alert-lab-vm --zone=europe-west2-a --quiet
gcloud monitoring channels delete "$CHANNEL_ID" --quiet 2>/dev/null
```

---

## Part 3: Revision (15 minutes)

- **Multi-condition alerts** — use `AND` to reduce false positives; all conditions must be true
- **Burn rate alerts** — multi-window (short + long) catches fast burns without false positives from blips
- **Notification rate limiting** — `period = "900s"` prevents alert storms (max 1 notification per 15 min)
- **Alert documentation** — embed runbooks directly in alert configs for faster MTTR
- **Auto-close** — automatically close incidents after a quiet period (e.g., 30 min)
- **Escalation matrix** — primary → secondary → team lead; defined timeouts at each level
- **On-call target** — max 2 pages per 12h shift; more than that = alerts need tuning

### Key Commands
```bash
gcloud monitoring policies list
gcloud monitoring policies describe POLICY_ID
gcloud monitoring channels list
gcloud monitoring channels create --type=email --display-name=NAME
```

---

## Part 4: Quiz (15 minutes)

**Q1:** Why use `AND` combiner for the CPU + Memory alert instead of `OR`?
<details><summary>Answer</summary><code>AND</code> means both CPU <b>and</b> memory must be high simultaneously. This reduces false positives: high CPU alone might be a batch job (no user impact), high memory alone might be caching (normal). Both being high together signals genuine resource saturation. <code>OR</code> would fire on either condition, making it noisier. Like requiring both high load average AND swap usage on Linux before paging.</details>

**Q2:** Explain multi-window burn rate alerts. Why two windows?
<details><summary>Answer</summary>A <b>short window</b> (e.g., 1h) detects fast-burning incidents quickly. A <b>long window</b> (e.g., 6h) confirms it's not just a momentary blip. Together: if 1h burn > 14× AND 6h burn > 6×, the incident is both <b>fast and sustained</b> — worth paging. Without the long window, a 2-minute error spike could trigger a false page. Without the short window, a slow-burn incident wouldn't be caught until too late.</details>

**Q3:** An engineer gets 30 alerts in an hour for the same issue. What's wrong and how do you fix it?
<details><summary>Answer</summary><b>Missing notification rate limiting.</b> Fix by adding <code>notification_rate_limit { period = "900s" }</code> to the alert strategy — max 1 notification per 15 minutes. Also check: is the <code>duration</code> too short (condition flapping)? Is auto-close configured? Consider alert grouping so the 30 individual alerts are presented as one grouped incident. Alert fatigue leads to engineers ignoring all alerts — dangerous.</details>

**Q4:** Why embed runbooks directly in alert documentation instead of linking to a wiki?
<details><summary>Answer</summary>
1. <b>Speed</b> — the on-call sees the runbook immediately in the notification (no context-switching)<br>
2. <b>Availability</b> — if the wiki is down during an incident, the runbook is still accessible in the alert<br>
3. <b>Versioning</b> — the runbook is version-controlled with the alert (Terraform), not a separate system<br>
4. <b>Accuracy</b> — the runbook is reviewed alongside the alert configuration in PRs<br>
Trade-off: long runbooks may not fit. Use embedded steps for immediate actions and link to detailed wiki for background.
</details>
