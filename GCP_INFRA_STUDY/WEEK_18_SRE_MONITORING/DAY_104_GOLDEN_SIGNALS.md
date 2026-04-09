# Week 18, Day 104 (Tue) — Dashboards: Golden Signals

## Today's Objective

Build monitoring dashboards around the four golden signals (latency, traffic, errors, saturation) from the Google SRE book. Understand the RED and USE methods and when to apply each.

**Source:** [Google SRE: Monitoring Distributed Systems](https://sre.google/sre-book/monitoring-distributed-systems/) | [Cloud Monitoring Dashboards](https://cloud.google.com/monitoring/dashboards)

**Deliverable:** A Cloud Monitoring dashboard with golden signal widgets for a sample service

---

## Part 1: Concept (30 minutes)

### 1.1 The Four Golden Signals

```
Linux analogy:

Latency     ──► ping response time / curl -w "%{time_total}"
Traffic     ──► netstat connections / ss -s
Errors      ──► grep ERROR /var/log/syslog | wc -l
Saturation  ──► vmstat (CPU wait, swap usage, disk queue)
```

```
┌──────────────────────────────────────────────────────────┐
│              THE FOUR GOLDEN SIGNALS                      │
│                                                           │
│  ┌─────────────┐   ┌─────────────┐                       │
│  │  LATENCY    │   │  TRAFFIC    │                       │
│  │             │   │             │                       │
│  │ How long    │   │ How much    │                       │
│  │ requests    │   │ demand on   │                       │
│  │ take        │   │ the system  │                       │
│  │             │   │             │                       │
│  │ p50, p95,   │   │ req/sec,    │                       │
│  │ p99         │   │ bytes/sec   │                       │
│  └─────────────┘   └─────────────┘                       │
│                                                           │
│  ┌─────────────┐   ┌─────────────┐                       │
│  │  ERRORS     │   │ SATURATION  │                       │
│  │             │   │             │                       │
│  │ Rate of     │   │ How "full"  │                       │
│  │ failed      │   │ the system  │                       │
│  │ requests    │   │ is          │                       │
│  │             │   │             │                       │
│  │ 5xx rate,   │   │ CPU%, mem%, │                       │
│  │ error ratio │   │ disk queue  │                       │
│  └─────────────┘   └─────────────┘                       │
└──────────────────────────────────────────────────────────┘
```

### 1.2 Golden Signals for GCP Services

| Signal | Compute Engine | Cloud Run | Cloud SQL |
|---|---|---|---|
| **Latency** | N/A (infra) | request_latencies | query time |
| **Traffic** | Network bytes in/out | request_count | connections |
| **Errors** | Instance status checks | 5xx count | error count |
| **Saturation** | CPU util, memory | container CPU | CPU util, connections |

### 1.3 RED Method (Request-Focused)

For **services** — anything that handles requests:

| Signal | Metric |
|---|---|
| **R**ate | Requests per second |
| **E**rrors | Error rate (failed requests / total) |
| **D**uration | Latency distribution (p50, p95, p99) |

### 1.4 USE Method (Resource-Focused)

For **resources** — hardware/infrastructure:

| Signal | CPU | Memory | Disk | Network |
|---|---|---|---|---|
| **U**tilization | CPU % | Memory % | Disk % | Bandwidth % |
| **S**aturation | Run queue | Swap usage | IO queue | Packet drops |
| **E**rrors | — | ECC errors | Disk errors | CRC errors |

### 1.5 When to Use Which Method

```
┌───────────────────────────────────────────────────┐
│                                                    │
│   Request comes in                                 │
│        │                                           │
│        ▼                                           │
│   ┌──────────┐        ┌──────────────────┐        │
│   │ Service  │───────►│ Infrastructure   │        │
│   │ (RED)    │        │ (USE)            │        │
│   │          │        │                  │        │
│   │ Rate     │        │ Utilization      │        │
│   │ Errors   │        │ Saturation       │        │
│   │ Duration │        │ Errors           │        │
│   └──────────┘        └──────────────────┘        │
│                                                    │
│   "Is the user happy?"  "Is the box healthy?"     │
│   SLI-oriented          Capacity-oriented          │
└───────────────────────────────────────────────────┘
```

### 1.6 Dashboard Layout Best Practice

```
┌──────────────────────────────────────────────────────┐
│  SERVICE: Web API  |  Environment: PROD  |  SLO: 99.9% │
├──────────────────────────────────────────────────────┤
│                                                       │
│  Row 1: SLO Status                                    │
│  ┌────────────┐ ┌────────────┐ ┌────────────────────┐ │
│  │ Error      │ │ Budget     │ │ Burn Rate          │ │
│  │ Budget: 73%│ │ Remaining  │ │ [Graph over time]  │ │
│  │ remaining  │ │ 31 min     │ │                    │ │
│  └────────────┘ └────────────┘ └────────────────────┘ │
│                                                       │
│  Row 2: Golden Signals                                │
│  ┌─────────────────────┐ ┌──────────────────────────┐ │
│  │ Latency (p50/p95)   │ │ Traffic (req/sec)        │ │
│  │  [Time series]      │ │  [Time series]           │ │
│  └─────────────────────┘ └──────────────────────────┘ │
│  ┌─────────────────────┐ ┌──────────────────────────┐ │
│  │ Error Rate (%)      │ │ Saturation (CPU/Mem)     │ │
│  │  [Time series]      │ │  [Time series]           │ │
│  └─────────────────────┘ └──────────────────────────┘ │
│                                                       │
│  Row 3: Infrastructure (USE)                          │
│  ┌────────┐ ┌────────┐ ┌────────┐ ┌────────────────┐ │
│  │CPU Util│ │Mem Util│ │Disk IO │ │Network Bytes   │ │
│  └────────┘ └────────┘ └────────┘ └────────────────┘ │
└──────────────────────────────────────────────────────┘
```

---

## Part 2: Hands-On Lab (60 minutes)

### Step 1: Create a Monitored Service (10 min)

```bash
export PROJECT_ID=$(gcloud config get-value project)

# Create a VM running nginx
gcloud compute instances create golden-signal-vm \
  --zone=europe-west2-a \
  --machine-type=e2-small \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --tags=http-server \
  --metadata=startup-script='#!/bin/bash
apt-get update && apt-get install -y nginx stress-ng
echo "OK" > /var/www/html/health
systemctl start nginx'

# Allow HTTP
gcloud compute firewall-rules create golden-allow-http \
  --direction=INGRESS --action=ALLOW --rules=tcp:80 \
  --source-ranges=0.0.0.0/0 --target-tags=http-server \
  --quiet 2>/dev/null || true
```

### Step 2: Create a Dashboard via Terraform (25 min)

```bash
mkdir -p tf-dashboard-lab && cd tf-dashboard-lab

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

resource "google_monitoring_dashboard" "golden_signals" {
  dashboard_json = jsonencode({
    displayName = "Golden Signals Dashboard - Lab"
    gridLayout = {
      columns = 2
      widgets = [
        # --- Row 1: Traffic ---
        {
          title = "Traffic: Network Bytes In (per instance)"
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
            timeshiftDuration = "0s"
          }
        },
        {
          title = "Traffic: Network Bytes Out (per instance)"
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
            timeshiftDuration = "0s"
          }
        },
        # --- Row 2: Saturation ---
        {
          title = "Saturation: CPU Utilization (%)"
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
            timeshiftDuration = "0s"
          }
        },
        {
          title = "Saturation: Disk Read/Write Ops"
          xyChart = {
            dataSets = [
              {
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "metric.type=\"compute.googleapis.com/instance/disk/read_ops_count\" AND resource.type=\"gce_instance\""
                    aggregation = {
                      alignmentPeriod  = "60s"
                      perSeriesAligner = "ALIGN_RATE"
                    }
                  }
                }
              },
              {
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "metric.type=\"compute.googleapis.com/instance/disk/write_ops_count\" AND resource.type=\"gce_instance\""
                    aggregation = {
                      alignmentPeriod  = "60s"
                      perSeriesAligner = "ALIGN_RATE"
                    }
                  }
                }
              }
            ]
            timeshiftDuration = "0s"
          }
        },
        # --- Row 3: Errors ---
        {
          title = "Errors: Uptime Check Status"
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" AND resource.type=\"uptime_url\""
                  aggregation = {
                    alignmentPeriod  = "60s"
                    perSeriesAligner = "ALIGN_FRACTION_TRUE"
                  }
                }
              }
            }]
            timeshiftDuration = "0s"
          }
        },
        {
          title = "Instance: Uptime (seconds)"
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "metric.type=\"compute.googleapis.com/instance/uptime\" AND resource.type=\"gce_instance\""
                  aggregation = {
                    alignmentPeriod  = "60s"
                    perSeriesAligner = "ALIGN_RATE"
                  }
                }
              }
            }]
            timeshiftDuration = "0s"
          }
        }
      ]
    }
  })
}

output "dashboard_name" {
  value = google_monitoring_dashboard.golden_signals.id
}
EOF

echo "project_id = \"${PROJECT_ID}\"" > terraform.tfvars

terraform init
terraform apply -auto-approve
```

### Step 3: Generate Traffic and Saturation (10 min)

```bash
# Get VM IP
VM_IP=$(gcloud compute instances describe golden-signal-vm \
  --zone=europe-west2-a \
  --format='get(networkInterfaces[0].accessConfigs[0].natIP)')

# Generate some HTTP traffic
for i in $(seq 1 50); do
  curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" http://${VM_IP}/
done

# SSH in and generate CPU load
gcloud compute ssh golden-signal-vm --zone=europe-west2-a --command="
  stress-ng --cpu 1 --timeout 120 &
  echo 'Stress test running for 120 seconds...'
"
```

### Step 4: Explore the Dashboard (10 min)

```bash
echo "View your dashboard at:"
echo "https://console.cloud.google.com/monitoring/dashboards?project=${PROJECT_ID}"

echo ""
echo "=== What to look for ==="
echo "1. Traffic graphs: network bytes should show the curl burst"
echo "2. CPU Utilization: should spike from stress-ng"
echo "3. Disk ops: baseline activity"
echo "4. Uptime check: should be passing (green)"
```

### Step 5: Query Metrics via gcloud (5 min)

```bash
# Query CPU utilization for the last 30 minutes
gcloud monitoring metrics list \
  --filter="metric.type = starts_with(\"compute.googleapis.com/instance/cpu\")" \
  --format="table(type, displayName)"

# Read recent CPU data
gcloud monitoring time-series list \
  --filter="metric.type=\"compute.googleapis.com/instance/cpu/utilization\"" \
  --interval-start-time="$(date -u -d '30 minutes ago' +%Y-%m-%dT%H:%M:%SZ)" \
  --format="table(metric.labels.instance_name, points.interval.endTime, points.value.doubleValue)" \
  --limit=10
```

### Step 6: Clean Up

```bash
cd tf-dashboard-lab
terraform destroy -auto-approve
cd ~
rm -rf tf-dashboard-lab

gcloud compute instances delete golden-signal-vm --zone=europe-west2-a --quiet
gcloud compute firewall-rules delete golden-allow-http --quiet 2>/dev/null
```

---

## Part 3: Revision (15 minutes)

- **4 Golden Signals** — Latency, Traffic, Errors, Saturation (Google SRE)
- **RED method** — Rate, Errors, Duration (for services / request-oriented)
- **USE method** — Utilization, Saturation, Errors (for resources / infrastructure)
- **Dashboard layout** — SLO status on top, golden signals in middle, infrastructure at bottom
- **GCP metrics** — `compute.googleapis.com/instance/cpu/utilization`, `network/received_bytes_count`
- **Aggregate properly** — use `ALIGN_RATE` for counters, `ALIGN_MEAN` for gauges

### Key Commands
```bash
gcloud monitoring metrics list --filter="metric.type = starts_with(\"compute\")"
gcloud monitoring time-series list --filter="metric.type=..." --interval-start-time=...
gcloud monitoring dashboards list
# Dashboard management is best done via Terraform (JSON spec)
```

---

## Part 4: Quiz (15 minutes)

**Q1:** Name the four golden signals and give a GCP metric example for each.
<details><summary>Answer</summary>
<b>Latency</b>: <code>loadbalancing.googleapis.com/https/total_latencies</code><br>
<b>Traffic</b>: <code>compute.googleapis.com/instance/network/received_bytes_count</code><br>
<b>Errors</b>: <code>monitoring.googleapis.com/uptime_check/check_passed</code> (inverse)<br>
<b>Saturation</b>: <code>compute.googleapis.com/instance/cpu/utilization</code>
</details>

**Q2:** When would you use the USE method instead of the RED method?
<details><summary>Answer</summary>Use <b>RED</b> when monitoring <b>services</b> (APIs, web apps) — it tells you if users are happy. Use <b>USE</b> when monitoring <b>resources</b> (VMs, disks, network) — it tells you if infrastructure is healthy. Typically, you use both: RED for the service-facing view (SLI-oriented) and USE for the infrastructure troubleshooting view (capacity-oriented). Like monitoring <code>nginx</code> response codes (RED) alongside <code>vmstat</code> (USE).</details>

**Q3:** Why use `ALIGN_RATE` for counter metrics but `ALIGN_MEAN` for gauge metrics?
<details><summary>Answer</summary><b>Counters</b> are cumulative (total bytes ever sent). <code>ALIGN_RATE</code> converts them to a rate (bytes/sec) which is meaningful for dashboards. <b>Gauges</b> are point-in-time values (CPU %). <code>ALIGN_MEAN</code> averages them over the alignment period. Using the wrong aligner gives misleading data — e.g., <code>ALIGN_MEAN</code> on a counter shows ever-increasing values instead of rates.</details>

**Q4:** Your dashboard shows CPU at 90% but the SLO error budget is healthy. Should you alert?
<details><summary>Answer</summary><b>No — do not page.</b> If the SLO is healthy, users aren't impacted despite high CPU. This could be a batch job, a JIT compilation spike, or normal peak-hour load. The high CPU should be an <b>informational signal</b> for capacity planning (USE method saturation), not a paging event. Only page when error budget is burning. Create a low-priority ticket to investigate capacity if the pattern persists.</details>
