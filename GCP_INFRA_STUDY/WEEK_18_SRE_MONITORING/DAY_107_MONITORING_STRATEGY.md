# Week 18, Day 107 (Fri) — Monitoring Strategy Document

## Today's Objective

Build a comprehensive monitoring strategy template: decide what to monitor per service tier, design an alert escalation matrix, organise dashboards, and create a living document that guides all monitoring decisions for a production environment.

**Source:** [Google SRE Workbook: Monitoring](https://sre.google/workbook/monitoring/) | [Cloud Monitoring Best Practices](https://cloud.google.com/monitoring/docs/best-practices)

**Deliverable:** A complete monitoring strategy document template applicable to any GCP project

---

## Part 1: Concept (30 minutes)

### 1.1 Why a Monitoring Strategy Document?

```
Linux analogy:

/etc/nagios/nagios.cfg         ──►    Monitoring strategy doc
  "What hosts do we monitor?"          "What services do we monitor?"
  "What checks per host?"              "What SLIs per service?"
  "Who gets paged?"                    "What's the escalation matrix?"
  "How often do we check?"             "What are our SLO windows?"
```

Without a strategy, monitoring grows organically: critical services lack alerts while unimportant services generate noise.

### 1.2 Service Tier Model

```
┌────────────────────────────────────────────────────────┐
│                    SERVICE TIERS                         │
│                                                         │
│  TIER 1: Revenue-Critical                               │
│  ┌─────────────────────────────────────────────┐        │
│  │ Payment API, Auth Service, Main Website      │        │
│  │ SLO: 99.95%  |  Alerts: Page (P1)           │        │
│  │ Response: 5 min  |  Dashboards: Dedicated    │        │
│  └─────────────────────────────────────────────┘        │
│                                                         │
│  TIER 2: Business-Important                             │
│  ┌─────────────────────────────────────────────┐        │
│  │ Reporting, Email Service, Search             │        │
│  │ SLO: 99.9%   |  Alerts: Ticket (P2)         │        │
│  │ Response: 30 min  |  Dashboards: Shared      │        │
│  └─────────────────────────────────────────────┘        │
│                                                         │
│  TIER 3: Internal/Non-Critical                          │
│  ┌─────────────────────────────────────────────┐        │
│  │ Dev environments, Internal tools, Batch jobs │        │
│  │ SLO: 99.5%   |  Alerts: Email (P3)          │        │
│  │ Response: Next business day                  │        │
│  └─────────────────────────────────────────────┘        │
│                                                         │
└────────────────────────────────────────────────────────┘
```

| Tier | SLO | Alerting | Response Time | On-Call |
|---|---|---|---|---|
| **Tier 1** | 99.95% | Page (P1) | 5 min | 24/7 |
| **Tier 2** | 99.9% | Ticket (P2) | 30 min | Business hours |
| **Tier 3** | 99.5% | Email (P3) | Next day | Best effort |

### 1.3 What to Monitor Per Service

```
Per Service Monitoring Checklist:

□ Availability SLI      (uptime checks, health endpoints)
□ Latency SLI           (p50, p95, p99)
□ Error rate SLI        (5xx / total requests)
□ Saturation metrics    (CPU, memory, disk, connections)
□ Dependency health     (upstream/downstream status)
□ Business metrics      (orders/min, logins/hour)
□ Security signals      (auth failures, permission denials)
□ Log-based metrics     (application-specific errors)
```

### 1.4 Alert Escalation Matrix

```
INCIDENT ──► P1: Page ──► If no ACK in 15 min ──► Escalate to secondary
                             │
                             ▼ If no ACK in 30 min
                          Escalate to team lead
                             │
                             ▼ If no resolution in 2h
                          Escalate to management + war room

INCIDENT ──► P2: Ticket ──► Assigned within 1h ──► Resolved within 4h
                             │
                             ▼ If no resolution in 4h
                          Escalate to P1

INCIDENT ──► P3: Email ──► Reviewed next business day
                             │
                             ▼ If recurring 3+ times
                          Promote to P2
```

### 1.5 Dashboard Organisation

| Dashboard | Audience | Content |
|---|---|---|
| **Executive Overview** | Leadership | SLO status, error budgets, availability trends |
| **Service Health** | On-call engineers | Golden signals per service, active incidents |
| **Infrastructure** | Platform team | USE metrics, capacity, cost |
| **Security** | SecOps | Auth failures, IAM changes, network anomalies |
| **Per-Service Detail** | Service owners | Deep-dive into specific service metrics |

### 1.6 Monitoring Strategy Template Structure

```
MONITORING STRATEGY DOCUMENT
│
├── 1. Overview & Scope
│   ├── Services covered
│   ├── Environments (dev/staging/prod)
│   └── Revision history
│
├── 2. Service Tiers & SLOs
│   ├── Tier definitions
│   ├── SLO per service
│   └── Error budget policies
│
├── 3. Metrics & SLIs
│   ├── Golden signals per service
│   ├── Infrastructure metrics
│   └── Log-based metrics
│
├── 4. Alerting
│   ├── Alert policies
│   ├── Escalation matrix
│   └── Notification channels
│
├── 5. Dashboards
│   ├── Dashboard catalogue
│   ├── Layout standards
│   └── Access control
│
├── 6. On-Call
│   ├── Rotation schedule
│   ├── Handoff procedures
│   └── Post-incident review process
│
└── 7. Review & Maintenance
    ├── Quarterly SLO review
    ├── Alert tuning cadence
    └── Dashboard refresh
```

---

## Part 2: Hands-On Lab (60 minutes)

### Step 1: Write the Monitoring Strategy for a Sample Service (20 min)

```bash
export PROJECT_ID=$(gcloud config get-value project)
mkdir -p monitoring-strategy && cd monitoring-strategy

cat > MONITORING_STRATEGY.md <<'STRATEGY'
# Monitoring Strategy — Web Application Platform

**Version:** 1.0
**Date:** $(date +%Y-%m-%d)
**Owner:** Platform Engineering
**Review Cycle:** Quarterly

---

## 1. Overview & Scope

### Services Covered
| Service | Type | Environment | Owner |
|---|---|---|---|
| Web API | Cloud Run | prod, staging | Backend Team |
| Auth Service | GKE | prod, staging | Security Team |
| Worker Queue | Compute Engine | prod | Data Team |
| Admin Portal | App Engine | prod | Frontend Team |

### Environments Monitored
- **Production:** Full monitoring with on-call
- **Staging:** Alerting during business hours only
- **Development:** Metrics collection only (no alerts)

---

## 2. Service Tiers & SLOs

| Service | Tier | Availability SLO | Latency SLO (p99) | Error Budget (30d) |
|---|---|---|---|---|
| Web API | 1 | 99.95% | < 500ms | 21.9 min |
| Auth Service | 1 | 99.99% | < 200ms | 4.3 min |
| Worker Queue | 2 | 99.9% | N/A | 43.2 min |
| Admin Portal | 3 | 99.5% | < 2s | 3h 39min |

### Error Budget Policy
- **Budget > 50%:** Normal releases allowed
- **Budget 20-50%:** Only reliability-improving changes
- **Budget < 20%:** Deployment freeze, all hands on reliability
- **Budget exhausted:** War room, post-mortem required

---

## 3. Metrics & SLIs

### Golden Signals per Service

| Service | Latency SLI | Traffic SLI | Error SLI | Saturation SLI |
|---|---|---|---|---|
| Web API | request_latencies p99 | request_count/min | 5xx_count/total | CPU%, Memory% |
| Auth Service | auth_latency p99 | auth_attempts/min | auth_failures/total | Connection pool% |
| Worker Queue | job_duration p95 | jobs_processed/min | failed_jobs/total | Queue depth |
| Admin Portal | page_load p95 | active_sessions | error_pages/total | CPU% |

### Infrastructure Metrics (USE Method)

| Resource | Utilization | Saturation | Errors |
|---|---|---|---|
| Compute Engine | CPU%, Memory% | Run queue, Swap | Disk errors |
| Cloud SQL | CPU%, Storage% | Connection count | Replication lag |
| GCS | Request count | Bucket size | 4xx/5xx errors |
| Network | Bandwidth% | Packet drops | Firewall denies |

### Log-Based Metrics

| Metric Name | Filter | Type | Alert? |
|---|---|---|---|
| app-error-count | severity >= ERROR | Counter | Yes (> 10/min) |
| ssh-login-count | textPayload =~ "Accepted" | Counter | Yes (any) |
| iam-policy-change | protoPayload.methodName = "SetIamPolicy" | Counter | Yes (any) |

---

## 4. Alerting

### Alert Policies

| Alert Name | Condition | Severity | Channel |
|---|---|---|---|
| SLO Burn Rate Critical | 1h burn > 14x AND 6h burn > 6x | P1 | PagerDuty |
| SLO Burn Rate Warning | 6h burn > 6x AND 3d burn > 1x | P2 | Slack + Ticket |
| Infra: CPU Saturation | CPU > 90% for 10 min (Tier 1) | P2 | Slack |
| Security: SSH Login | Any SSH login to prod | P3 | Email |
| Security: IAM Change | Any IAM policy change | P2 | Slack |

### Escalation Matrix

| Time | P1 Action | P2 Action | P3 Action |
|---|---|---|---|
| 0 min | Page primary on-call | Create ticket | Send email |
| 15 min | Page secondary | Assign owner | — |
| 30 min | Page team lead | — | — |
| 1 hour | Notify management | Escalate to P1 | — |
| 4 hours | War room | — | Review in standup |

---

## 5. Dashboards

| Dashboard | URL | Audience | Refresh |
|---|---|---|---|
| Executive SLO Overview | /monitoring/dashboards/exec | Leadership | Weekly review |
| Service: Web API | /monitoring/dashboards/web-api | Backend Team | Real-time |
| Infrastructure Health | /monitoring/dashboards/infra | Platform Team | Real-time |
| Security Overview | /monitoring/dashboards/security | SecOps | Daily review |
| Cost & Capacity | /monitoring/dashboards/cost | FinOps | Weekly |

---

## 6. On-Call

### Rotation
- **Schedule:** Weekly rotation, handoff Monday 09:00 UTC
- **Primary + Secondary:** Always two engineers on-call
- **Max pages/shift:** 2 per 12h (if exceeded, tune alerts)

### Handoff Checklist
- [ ] Review active incidents
- [ ] Check error budget status
- [ ] Review recent deployments
- [ ] Verify notification channels working

---

## 7. Review & Maintenance

| Activity | Frequency | Owner |
|---|---|---|
| SLO review | Quarterly | Service owners |
| Alert tuning | Monthly | On-call rotation |
| Dashboard refresh | Quarterly | Platform team |
| Strategy document update | Bi-annual | Platform lead |
| Post-incident reviews | After every P1 | Incident commander |
STRATEGY
```

### Step 2: Implement Tier 1 Service Monitoring via Terraform (25 min)

```bash
mkdir -p tf-strategy && cd tf-strategy

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

# --- Tier 1: Custom monitoring service ---
resource "google_monitoring_custom_service" "web_api" {
  service_id   = "web-api-prod"
  display_name = "Web API (Production) — Tier 1"
}

# --- Executive Overview Dashboard ---
resource "google_monitoring_dashboard" "exec_overview" {
  dashboard_json = jsonencode({
    displayName = "Executive SLO Overview"
    gridLayout = {
      columns = 2
      widgets = [
        {
          title = "VM CPU Utilization (All Instances)"
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "metric.type=\"compute.googleapis.com/instance/cpu/utilization\" AND resource.type=\"gce_instance\""
                  aggregation = {
                    alignmentPeriod  = "300s"
                    perSeriesAligner = "ALIGN_MEAN"
                  }
                }
              }
            }]
          }
        },
        {
          title = "Network Traffic (All Instances)"
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "metric.type=\"compute.googleapis.com/instance/network/received_bytes_count\" AND resource.type=\"gce_instance\""
                  aggregation = {
                    alignmentPeriod  = "300s"
                    perSeriesAligner = "ALIGN_RATE"
                  }
                }
              }
            }]
          }
        },
        {
          title = "Disk Utilization"
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "metric.type=\"compute.googleapis.com/instance/disk/read_ops_count\" AND resource.type=\"gce_instance\""
                  aggregation = {
                    alignmentPeriod  = "300s"
                    perSeriesAligner = "ALIGN_RATE"
                  }
                }
              }
            }]
          }
        },
        {
          title = "Instance Count by Status"
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "metric.type=\"compute.googleapis.com/instance/uptime\" AND resource.type=\"gce_instance\""
                  aggregation = {
                    alignmentPeriod  = "300s"
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

# --- IAM Change Detection ---
resource "google_logging_metric" "iam_changes" {
  name        = "iam-policy-changes"
  filter      = "protoPayload.methodName=\"SetIamPolicy\" OR protoPayload.methodName=\"SetOrgPolicy\""
  description = "Counts IAM and Org policy changes"

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
  }
}

resource "google_monitoring_alert_policy" "iam_change_alert" {
  display_name = "Security: IAM Policy Change Detected"
  combiner     = "OR"

  conditions {
    display_name = "IAM policy changed"

    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/iam-policy-changes\""
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
    content   = "An IAM policy change was detected. Review the audit log to verify the change was authorised."
    mime_type = "text/markdown"
  }
}

output "dashboard_id" {
  value = google_monitoring_dashboard.exec_overview.id
}

output "iam_alert" {
  value = google_monitoring_alert_policy.iam_change_alert.display_name
}
EOF

echo "project_id = \"${PROJECT_ID}\"" > terraform.tfvars
terraform init
terraform plan
terraform apply -auto-approve
```

### Step 3: Validate the Strategy (10 min)

```bash
echo "=== Strategy Validation Checklist ==="
echo ""
echo "[✓] Monitoring strategy document written"
echo "[✓] Service tiers defined with SLOs"
echo "[✓] Alerting policies created"
echo "[✓] Dashboard deployed"
echo "[✓] Log-based metric for IAM changes"
echo "[✓] Escalation matrix documented"
echo ""
echo "View dashboard: https://console.cloud.google.com/monitoring/dashboards?project=${PROJECT_ID}"
echo "View alerts: https://console.cloud.google.com/monitoring/alerting?project=${PROJECT_ID}"
```

### Step 4: Clean Up

```bash
cd tf-strategy
terraform destroy -auto-approve
cd ~
rm -rf monitoring-strategy tf-strategy
```

---

## Part 3: Revision (15 minutes)

- **Service tiers** — classify by business impact; Tier 1 gets 24/7 on-call, Tier 3 gets best-effort
- **Monitor per service** — golden signals + dependencies + business metrics + security signals
- **Escalation matrix** — time-based escalation from primary → secondary → lead → management
- **Dashboard hierarchy** — executive overview → service health → infrastructure → security
- **Error budget policy** — defines freeze/release decisions based on remaining budget
- **Review cadence** — SLOs quarterly, alerts monthly, dashboards quarterly, strategy bi-annually
- **Living document** — the strategy doc must be updated after every significant incident

### Key Commands
```bash
gcloud monitoring dashboards list
gcloud monitoring policies list
gcloud logging metrics list
gcloud monitoring channels list
```

---

## Part 4: Quiz (15 minutes)

**Q1:** A new microservice is being deployed. How do you decide its monitoring tier?
<details><summary>Answer</summary>Evaluate <b>business impact</b>: How many users/revenue does it affect if it goes down? <b>Tier 1</b> = revenue-critical (payment, auth). <b>Tier 2</b> = business-important but not immediately revenue-impacting (reporting, search). <b>Tier 3</b> = internal/non-critical. Also consider <b>dependencies</b> — if Tier 1 services depend on it, it may need to be classified higher than its own direct impact suggests.</details>

**Q2:** Your monitoring strategy says "max 2 pages per 12h shift". You're getting 8. What do you do?
<details><summary>Answer</summary>This indicates <b>alert tuning is needed</b>. Steps: 1) Review each alert that fired — was it actionable? 2) Remove non-actionable alerts or demote to tickets. 3) Add <code>duration</code> requirements (don't alert on brief spikes). 4) Implement notification rate limiting. 5) Add multi-condition logic (AND) to reduce false positives. 6) Consider burn-rate alerting instead of threshold alerting. The goal is signal-to-noise: every page should require human action.</details>

**Q3:** Why have separate dashboards for different audiences instead of one big dashboard?
<details><summary>Answer</summary>Different audiences need different information at different levels of detail. <b>Executives</b> need SLO status and trends — a 50-widget infra dashboard wastes their time. <b>On-call engineers</b> need golden signals and active incidents — cost data isn't relevant at 3am. <b>Security</b> needs auth failures and IAM changes. Information overload is as bad as no information. Like different log levels: management reads the summary, engineers read the debug output.</details>

**Q4:** The monitoring strategy calls for quarterly SLO reviews. What should be reviewed?
<details><summary>Answer</summary>
1. <b>Were SLOs met?</b> Check actual availability vs target over the quarter<br>
2. <b>Were SLOs too tight?</b> If frequently breached, the target may be unrealistic<br>
3. <b>Were SLOs too loose?</b> If never consumed >10% budget, tighten them and ship faster<br>
4. <b>New services added?</b> Assign tiers and SLOs<br>
5. <b>Incident patterns?</b> Do SLIs capture the failure modes that occurred?<br>
6. <b>Error budget policy working?</b> Were freezes respected? Were they effective?<br>
The review is a negotiation between reliability and velocity.
</details>
