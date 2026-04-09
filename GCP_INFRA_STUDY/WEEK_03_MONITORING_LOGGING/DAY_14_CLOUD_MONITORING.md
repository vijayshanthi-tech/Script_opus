# Day 14 — Cloud Monitoring: Metrics, Dashboards & Uptime Checks

> **Week 3 · Monitoring & Logging** | Region: `europe-west2` | Study time: 2 hours

---

## Part 1 — Concept (30 min)

### 1.1 What Is Cloud Monitoring?

Cloud Monitoring is GCP's centralised metrics and observability platform — think **Prometheus + Grafana as a managed service**. Every GCP resource automatically emits metrics; Monitoring collects, stores, visualises, and alerts on them.

| Linux Analogy | GCP Equivalent |
|---|---|
| `top` / `htop` | Metrics Explorer (real-time) |
| Grafana dashboards | Cloud Monitoring dashboards |
| Nagios/Zabbix checks | Uptime checks |
| `/proc/stat`, `/proc/meminfo` | GCE auto-collected metrics |
| collectd / Prometheus | Ops Agent + custom metrics |

### 1.2 Metrics Architecture

```
┌──────────────────────────────────────────────────────────┐
│                   CLOUD MONITORING                        │
│                                                          │
│  ┌──────────┐   ┌──────────┐   ┌──────────────────┐     │
│  │ GCE VMs  │   │ GCS      │   │ Cloud SQL        │     │
│  │ (auto)   │   │ (auto)   │   │ (auto)           │     │
│  └────┬─────┘   └────┬─────┘   └────────┬─────────┘     │
│       │              │                   │               │
│       ▼              ▼                   ▼               │
│  ┌─────────────────────────────────────────────┐         │
│  │           METRICS TIME-SERIES DB            │         │
│  │  (automatic ingestion, 24-month retention)  │         │
│  └──────────┬──────────┬──────────┬────────────┘         │
│             │          │          │                       │
│     ┌───────▼──┐ ┌─────▼────┐ ┌──▼──────────┐           │
│     │Dashboards│ │ Alerting │ │Uptime Checks│           │
│     │ & Charts │ │ Policies │ │             │           │
│     └──────────┘ └──────────┘ └─────────────┘           │
└──────────────────────────────────────────────────────────┘
```

### 1.3 Metric Types

| Metric Domain | Example Metric | Description |
|---|---|---|
| `compute.googleapis.com/` | `instance/cpu/utilization` | CPU usage 0.0–1.0 |
| `compute.googleapis.com/` | `instance/disk/read_bytes_count` | Disk read bytes |
| `compute.googleapis.com/` | `instance/network/received_bytes_count` | Network in |
| `compute.googleapis.com/` | `instance/uptime` | VM uptime seconds |
| `agent.googleapis.com/` | `memory/percent_used` | Ops Agent memory % |
| `custom.googleapis.com/` | `myapp/request_count` | User-defined metric |

### 1.4 Metric Anatomy

Every metric is a **time series** defined by:

```
┌─────────────────────────────────────────────────────────┐
│  METRIC TIME SERIES                                      │
│                                                          │
│  metric.type  = compute.googleapis.com/instance/cpu/     │
│                 utilization                               │
│                                                          │
│  resource.type = gce_instance                            │
│  resource.labels:                                        │
│    project_id  = my-project                              │
│    instance_id = 1234567890                              │
│    zone        = europe-west2-b                          │
│                                                          │
│  Points:                                                 │
│    [10:00] 0.15  ─┐                                      │
│    [10:01] 0.22   │  ← data points at 60s intervals     │
│    [10:02] 0.45   │     (alignment period)               │
│    [10:03] 0.38  ─┘                                      │
└─────────────────────────────────────────────────────────┘
```

| Concept | Description | Linux Analogy |
|---|---|---|
| Metric type | What is measured | metric name in Prometheus |
| Resource type | What emits it | `hostname` / `job` label |
| Labels | Filter dimensions | Prometheus labels |
| Alignment period | Sampling interval | polling interval |
| Aggregation | How points are combined (mean, sum, max) | `awk` averaging |

### 1.5 Dashboards & Charts

Dashboards are collections of **widgets** (charts, scorecards, text, alerts).

| Chart Type | Best For | Example |
|---|---|---|
| Line chart | Trends over time | CPU utilization last 6h |
| Stacked area | Composition | Network in vs out |
| Heatmap | Distribution | Latency distribution |
| Scorecard | Single current value | Uptime percentage |
| Table | Tabular comparison | Top 5 VMs by CPU |

### 1.6 Uptime Checks

Uptime checks probe your endpoints from multiple global locations — like **external Nagios HTTP checks**.

```
  ┌──────────┐  ┌──────────┐  ┌──────────┐
  │ Virginia │  │ Oregon   │  │ Belgium  │  ← check locations
  └────┬─────┘  └────┬─────┘  └────┬─────┘
       │              │              │
       ▼              ▼              ▼
  ┌─────────────────────────────────────────┐
  │   Your VM / Load Balancer / URL         │
  │   GET /health  → expect HTTP 200       │
  └─────────────────────────────────────────┘
       │
       ▼
  Alert if fails from ≥ 2 regions
```

| Uptime Check Type | Target |
|---|---|
| HTTP/HTTPS | URL endpoint |
| TCP | Port reachability |
| ICMP (internal) | Internal VM ping (via private check) |

### 1.7 Free vs Paid

| Feature | Free Tier |
|---|---|
| GCP metrics (auto) | Free ingestion & 24-month retention |
| Uptime checks | Free (up to limits) |
| Custom metrics | First 150 MiB/month free |
| Dashboards | Free |
| Alerting | Free |

---

## Part 2 — Hands-On Lab (60 min)

### Lab Goal

Create a VM, generate CPU load, build a custom dashboard, and set up an uptime check.

### Prerequisites

```bash
gcloud config set project YOUR_PROJECT_ID
gcloud config set compute/region europe-west2
gcloud config set compute/zone europe-west2-b
```

### Step 1 — Create a Test VM with HTTP Server

```bash
# Create VM with startup script that runs a simple HTTP server
gcloud compute instances create mon-test-vm \
    --zone=europe-west2-b \
    --machine-type=e2-small \
    --image-family=debian-12 \
    --image-project=debian-cloud \
    --tags=http-server \
    --metadata=startup-script='#!/bin/bash
apt-get update && apt-get install -y stress-ng python3
# Simple health endpoint
nohup python3 -c "
from http.server import HTTPServer, BaseHTTPRequestHandler
class H(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b\"OK\")
    def log_message(self, *a): pass
HTTPServer((\"0.0.0.0\", 80), H).serve_forever()
" &'

# Allow HTTP traffic
gcloud compute firewall-rules create allow-http-monitoring \
    --allow=tcp:80 \
    --target-tags=http-server \
    --source-ranges=0.0.0.0/0 \
    --description="Allow HTTP for uptime check"
```

### Step 2 — Explore Metrics via CLI

```bash
# List available metric types for GCE (like discovering /proc files)
gcloud monitoring metrics-descriptors list \
    --filter='metric.type = starts_with("compute.googleapis.com/instance/cpu")' \
    --format="table(type,description)" \
    --limit=10

# Read current CPU utilization for our VM
INSTANCE_ID=$(gcloud compute instances describe mon-test-vm \
    --zone=europe-west2-b --format="value(id)")

gcloud monitoring time-series list \
    --filter="metric.type=\"compute.googleapis.com/instance/cpu/utilization\" AND resource.labels.instance_id=\"$INSTANCE_ID\"" \
    --interval-start-time=$(date -u -d '10 minutes ago' '+%Y-%m-%dT%H:%M:%SZ') \
    --format="table(points.interval.endTime,points.value.doubleValue)"
```

### Step 3 — Generate CPU Load

```bash
# SSH and produce CPU spike (like stress-testing a Linux server)
gcloud compute ssh mon-test-vm --zone=europe-west2-b \
    --command="nohup stress-ng --cpu 2 --timeout 300 > /dev/null 2>&1 &"

echo "CPU stress running for 5 minutes on mon-test-vm"
```

### Step 4 — Create a Custom Dashboard (Console)

**Console → Monitoring → Dashboards → + Create Dashboard**

Name it: `Day-14-Lab-Dashboard`

Add these widgets:

**Widget 1 — CPU Line Chart:**
- Type: Line chart
- Metric: `compute.googleapis.com/instance/cpu/utilization`
- Filter: `instance_name = mon-test-vm`
- Period: 1 minute

**Widget 2 — Network Received:**
- Type: Stacked area
- Metric: `compute.googleapis.com/instance/network/received_bytes_count`
- Filter: `instance_name = mon-test-vm`

**Widget 3 — Disk Read/Write:**
- Type: Line chart
- Metric: `compute.googleapis.com/instance/disk/read_bytes_count`
- Filter: `instance_name = mon-test-vm`

**Widget 4 — Uptime Scorecard:**
- Type: Scorecard
- Metric: `compute.googleapis.com/instance/uptime`
- Filter: `instance_name = mon-test-vm`

### Step 5 — Create Dashboard via gcloud (JSON)

```bash
# Create a dashboard definition file
cat > /tmp/dashboard.json << 'EOF'
{
  "displayName": "Day-14-CLI-Dashboard",
  "mosaicLayout": {
    "tiles": [
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "CPU Utilization",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "metric.type=\"compute.googleapis.com/instance/cpu/utilization\" resource.type=\"gce_instance\"",
                    "aggregation": {
                      "alignmentPeriod": "60s",
                      "perSeriesAligner": "ALIGN_MEAN"
                    }
                  }
                },
                "plotType": "LINE"
              }
            ],
            "timeshiftDuration": "0s"
          }
        }
      },
      {
        "xPos": 6,
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Network Received Bytes",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "metric.type=\"compute.googleapis.com/instance/network/received_bytes_count\" resource.type=\"gce_instance\"",
                    "aggregation": {
                      "alignmentPeriod": "60s",
                      "perSeriesAligner": "ALIGN_RATE"
                    }
                  }
                },
                "plotType": "STACKED_AREA"
              }
            ],
            "timeshiftDuration": "0s"
          }
        }
      }
    ]
  }
}
EOF

# Create the dashboard
gcloud monitoring dashboards create --config-from-file=/tmp/dashboard.json

# List dashboards
gcloud monitoring dashboards list --format="table(displayName,name)"
```

### Step 6 — Create an Uptime Check

```bash
# Get the external IP of our VM
EXTERNAL_IP=$(gcloud compute instances describe mon-test-vm \
    --zone=europe-west2-b \
    --format="value(networkInterfaces[0].accessConfigs[0].natIP)")

echo "VM external IP: $EXTERNAL_IP"

# Create an HTTP uptime check (like a Nagios HTTP check)
gcloud monitoring uptime create day14-http-check \
    --resource-type=uptime-url \
    --monitored-resource-host="$EXTERNAL_IP" \
    --protocol=http \
    --port=80 \
    --path="/" \
    --period=5 \
    --timeout=10

# List uptime checks
gcloud monitoring uptime list-configs --format="table(displayName,httpCheck.port,period)"
```

### Step 7 — Verify Dashboard Shows Load Spike

```bash
# Wait a few minutes, then check CPU metric
gcloud monitoring time-series list \
    --filter="metric.type=\"compute.googleapis.com/instance/cpu/utilization\" AND resource.labels.instance_id=\"$INSTANCE_ID\"" \
    --interval-start-time=$(date -u -d '15 minutes ago' '+%Y-%m-%dT%H:%M:%SZ') \
    --format="table(points.interval.endTime,points.value.doubleValue)"

# Also view in Console: Monitoring → Dashboards → Day-14-Lab-Dashboard
# You should see the CPU spike from the stress test
```

### Step 8 — Test Uptime Check Failure

```bash
# Stop the HTTP server to trigger uptime failure
gcloud compute ssh mon-test-vm --zone=europe-west2-b \
    --command="sudo pkill -f 'python3.*HTTPServer'"

echo "HTTP server stopped — uptime check should fail within 5 minutes"
echo "Check Console → Monitoring → Uptime checks"

# Restart it after verifying the failure
gcloud compute ssh mon-test-vm --zone=europe-west2-b \
    --command="nohup python3 -c \"
from http.server import HTTPServer, BaseHTTPRequestHandler
class H(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b'OK')
    def log_message(self, *a): pass
HTTPServer(('0.0.0.0', 80), H).serve_forever()
\" > /dev/null 2>&1 &"
```

### Cleanup

```bash
# Delete uptime check
UPTIME_ID=$(gcloud monitoring uptime list-configs \
    --format="value(name)" --filter="displayName='day14-http-check'" | head -1)
gcloud monitoring uptime delete "$UPTIME_ID" --quiet

# Delete dashboards
for DASH in $(gcloud monitoring dashboards list \
    --format="value(name)" \
    --filter="displayName:'Day-14'"); do
    gcloud monitoring dashboards delete "$DASH" --quiet
done

# Delete firewall rule
gcloud compute firewall-rules delete allow-http-monitoring --quiet

# Delete VM
gcloud compute instances delete mon-test-vm --zone=europe-west2-b --quiet

# Clean up temp files
rm -f /tmp/dashboard.json
```

---

## Part 3 — Revision (15 min)

### Key Concepts

- Cloud Monitoring = managed Prometheus + Grafana; auto-collects GCP resource metrics
- **Metrics** are time series with `metric.type` + `resource.type` + labels
- **Alignment period** = sampling interval; **aggregation** = how points combine (mean/sum/max)
- **Dashboards** contain widgets: line charts, area charts, heatmaps, scorecards
- **Uptime checks** probe endpoints from global locations (HTTP, TCP, ICMP)
- Auto-collected GCE metrics: CPU, network, disk (but NOT memory — need Ops Agent)
- Free: all GCP metrics, dashboards, uptime checks, alerting; charged: custom metrics beyond 150 MiB

### Essential Commands

```bash
# List metric descriptors
gcloud monitoring metrics-descriptors list --filter='...' --limit=10

# Read time-series data
gcloud monitoring time-series list --filter='...' --interval-start-time=...

# Dashboard management
gcloud monitoring dashboards create --config-from-file=FILE.json
gcloud monitoring dashboards list
gcloud monitoring dashboards delete DASHBOARD_NAME

# Uptime checks
gcloud monitoring uptime create NAME --resource-type=uptime-url ...
gcloud monitoring uptime list-configs
gcloud monitoring uptime delete UPTIME_ID
```

---

## Part 4 — Quiz (15 min)

**Question 1: A VM is running but Cloud Monitoring shows no memory utilization metric. Why?**

<details>
<summary>Show Answer</summary>

GCE **auto-collected metrics** include CPU, disk, and network — but **NOT memory or disk space percentage**. These require the **Ops Agent** (or legacy Monitoring Agent) to be installed on the VM. The Ops Agent exposes metrics under `agent.googleapis.com/`, including `memory/percent_used`.

This is analogous to how `/proc/meminfo` data isn't sent anywhere unless you install a collector like `collectd` or `node_exporter`.

</details>

---

**Question 2: What is the difference between an alignment period and an aggregation in Cloud Monitoring?**

<details>
<summary>Show Answer</summary>

- **Alignment period**: The time window used to regularise data points (e.g., 60s). Raw data is bucketed into these intervals. Think of it as the sampling resolution.
- **Aggregation** (aligner + reducer): How data points within one alignment window are combined. **Aligner** = per-series (e.g., ALIGN_MEAN averages all points in 60s for one VM). **Reducer** = cross-series (e.g., REDUCE_MEAN averages across multiple VMs).

Linux analogy: alignment period is like choosing 1-minute intervals in `sar`; aggregation is `awk '{sum+=$1} END {print sum/NR}'` over those intervals.

</details>

---

**Question 3: You need to monitor whether an internal service at `10.128.0.5:8080` is reachable. Can you use a standard uptime check?**

<details>
<summary>Show Answer</summary>

Standard uptime checks probe from **external Google locations** — they cannot reach internal IPs. For internal services, use a **private uptime check** which runs from within your VPC.

Steps: Create an internal uptime check, specify the internal IP/port, and ensure a network path exists. The check runs from the Google-managed Cloud Monitoring infrastructure inside your VPC via Private Service Connect or equivalent.

</details>

---

**Question 4: You created a dashboard showing CPU for `mon-test-vm`, but the chart is empty. The VM is running. What should you check?**

<details>
<summary>Show Answer</summary>

Common causes:
1. **Time range** — the chart time window may not include the period when the VM was running. Expand to "Last 1 hour" or "Last 6 hours".
2. **Filter mismatch** — the filter label (`instance_name`, `instance_id`, `zone`) might not match the actual VM.
3. **Metric delay** — GCE metrics have a 1–3 minute ingestion delay. Wait a few minutes after VM creation.
4. **Alignment period too wide** — if set to 1 hour but the VM has only been running for 5 minutes, no complete data point exists yet.

Quick check: use **Metrics Explorer** directly to test the query before adding it to a dashboard.

</details>

---

*End of Day 14 — Tomorrow: Alerting policies and notification channels.*
