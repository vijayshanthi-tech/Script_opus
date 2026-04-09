# Week 18, Day 106 (Thu) — Log-Based Metrics

## Today's Objective

Create custom metrics from Cloud Logging entries, understand counter vs distribution metrics, use log-based metrics in dashboards and alerts, and build practical examples like error rate from logs and SSH login counting.

**Source:** [Cloud Logging: Log-Based Metrics](https://cloud.google.com/logging/docs/logs-based-metrics) | [Creating User-Defined Metrics](https://cloud.google.com/logging/docs/logs-based-metrics/create)

**Deliverable:** Two custom log-based metrics (error counter + SSH login counter) with corresponding alerts

---

## Part 1: Concept (30 minutes)

### 1.1 Why Log-Based Metrics?

```
Linux analogy:

grep -c "ERROR" /var/log/syslog         ──►    Counter metric from logs
awk '{print $NF}' access.log | avg      ──►    Distribution metric from logs
watch -n60 'wc -l /var/log/auth.log'    ──►    Log-based metric in dashboard
cron + grep + mail                       ──►    Log-based alert
```

Cloud Monitoring has built-in metrics for CPU, memory, network. But what about:
- Application error rates buried in log messages?
- SSH logins per hour?
- Specific HTTP status codes from nginx logs?
- Custom application events?

**Log-based metrics** bridge the gap between logs and monitoring.

### 1.2 Architecture

```
┌──────────────────┐     ┌──────────────────┐     ┌──────────────────┐
│  Application     │     │  Cloud Logging   │     │  Cloud Monitoring│
│                  │     │                  │     │                  │
│  Writes logs     │────►│  Stores entries  │────►│  Log-based       │
│  - stdout/stderr │     │  - Filters       │     │  metrics:        │
│  - syslog        │     │  - Queries       │     │  - Dashboards    │
│  - /var/log/*    │     │  - Exports       │     │  - Alerts        │
│                  │     │                  │     │  - SLIs          │
└──────────────────┘     └──────────────────┘     └──────────────────┘
```

### 1.3 Counter vs Distribution Metrics

| Type | What It Measures | Example | Query Result |
|---|---|---|---|
| **Counter** | Number of matching log entries | "How many errors?" | 42 errors/min |
| **Distribution** | Numeric field distribution | "How long are requests?" | p50=120ms, p95=500ms |

```
Counter metric:
  Filter: severity >= ERROR
  Each matching entry increments count by 1
  
  Time ──► [1] [3] [0] [2] [5] [1]   (errors per minute)

Distribution metric:
  Filter: httpRequest.latency exists  
  Each entry contributes its latency value to the distribution
  
  Time ──► [p50=120 p95=400] [p50=130 p95=450]  (latency percentiles)
```

### 1.4 Log Filter Syntax

| Filter | Matches |
|---|---|
| `severity >= ERROR` | All ERROR and CRITICAL logs |
| `textPayload =~ "Connection refused"` | Logs containing regex match |
| `resource.type = "gce_instance"` | Only from Compute Engine |
| `resource.labels.instance_id = "123"` | Specific instance |
| `protoPayload.methodName = "google.iam.admin.v1.SetIAMPolicy"` | IAM changes |
| `logName = "projects/P/logs/syslog"` | Specific log name |

### 1.5 Label Extractors

Add dimensions to your metrics using label extractors:

```
Log entry: "User admin logged in from 10.0.0.5"

Metric: ssh_login_count
Labels:
  user:      EXTRACT(textPayload, "User (\w+)")
  source_ip: EXTRACT(textPayload, "from ([\d.]+)")

Result: Time series per user+IP combination
  {user="admin", source_ip="10.0.0.5"} = 5
  {user="deploy", source_ip="10.0.0.10"} = 12
```

### 1.6 System vs User-Defined Metrics

| Aspect | System Metrics | User-Defined (Log-Based) |
|---|---|---|
| Created by | GCP automatically | You |
| Prefix | `logging.googleapis.com/` | `logging.googleapis.com/user/` |
| Cost | Free (included) | Charged per metric ingested |
| Examples | Log bytes received | Custom error counts |
| Limit | N/A | 500 per project |

---

## Part 2: Hands-On Lab (60 minutes)

### Step 1: Create a VM That Generates Logs (10 min)

```bash
export PROJECT_ID=$(gcloud config get-value project)

gcloud compute instances create logmetric-lab-vm \
  --zone=europe-west2-a \
  --machine-type=e2-micro \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --scopes=logging-write,monitoring-write \
  --metadata=startup-script='#!/bin/bash
apt-get update && apt-get install -y nginx
systemctl start nginx

# Install Ops Agent for better log collection
curl -sSO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh
bash add-google-cloud-ops-agent-repo.sh --also-install

# Generate some log entries
for i in $(seq 1 10); do
  logger -t myapp "INFO: Processing batch $i"
  if [ $((i % 3)) -eq 0 ]; then
    logger -t myapp "ERROR: Failed to process batch $i - connection timeout"
  fi
done
'
```

### Step 2: Create a Counter Metric — Error Count (10 min)

```bash
# Create a log-based metric that counts ERROR entries from our app
gcloud logging metrics create app-error-count \
  --description="Count of application errors from myapp" \
  --log-filter='resource.type="gce_instance" AND textPayload=~"ERROR.*myapp"'

# Verify
gcloud logging metrics list \
  --format="table(name, filter, description)"

# The metric is now available as:
#   logging.googleapis.com/user/app-error-count
```

### Step 3: Create a Counter Metric — SSH Logins (10 min)

```bash
# Create a metric for SSH login events
gcloud logging metrics create ssh-login-count \
  --description="Count of SSH login events" \
  --log-filter='resource.type="gce_instance" AND textPayload=~"Accepted publickey|Accepted password|session opened for user"'

# Generate some SSH login log entries
gcloud compute ssh logmetric-lab-vm --zone=europe-west2-a --command="
  echo 'SSH login successful - generating log entry'
  logger -t sshd 'Accepted publickey for testuser from 10.0.0.1 port 22 ssh2'
  exit
"

# Verify metric exists
gcloud logging metrics describe ssh-login-count
```

### Step 4: Create a Distribution Metric — Log Entry Size (5 min)

```bash
# Create a distribution metric based on log entry size
gcloud logging metrics create log-entry-size \
  --description="Distribution of log entry sizes" \
  --log-filter='resource.type="gce_instance"' \
  --field-name="textPayload" \
  --type=distribution \
  --bucket-type=LINEAR \
  --bucket-min=0 \
  --bucket-max=1000 \
  --bucket-count=10
```

### Step 5: Create Alert on Error Count (15 min)

```bash
mkdir -p tf-logmetric-alert && cd tf-logmetric-alert

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

# Alert when error count exceeds 5 in 5 minutes
resource "google_monitoring_alert_policy" "error_count_alert" {
  display_name = "Log Metric - App Error Rate High"
  combiner     = "OR"

  conditions {
    display_name = "Error count > 5 in 5 min"

    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/app-error-count\" AND resource.type=\"gce_instance\""
      comparison      = "COMPARISON_GT"
      threshold_value = 5
      duration        = "300s"

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }

      trigger {
        count = 1
      }
    }
  }

  documentation {
    content   = <<-DOC
    ## Application Error Rate Alert

    **Metric:** `logging.googleapis.com/user/app-error-count`
    **Threshold:** More than 5 errors in 5 minutes

    ### Investigation Steps
    1. Query logs: `gcloud logging read 'textPayload=~"ERROR.*myapp"' --limit=20 --format="table(timestamp, textPayload)"`
    2. SSH to VM: `gcloud compute ssh logmetric-lab-vm --zone=europe-west2-a`
    3. Check app status: `systemctl status myapp`
    4. Check connectivity: `curl -v upstream-service:8080/health`
    DOC
    mime_type = "text/markdown"
  }

  alert_strategy {
    auto_close = "1800s"
    notification_rate_limit {
      period = "600s"
    }
  }
}

# Alert on SSH logins (security monitoring)
resource "google_monitoring_alert_policy" "ssh_login_alert" {
  display_name = "Log Metric - SSH Login Detected"
  combiner     = "OR"

  conditions {
    display_name = "SSH login detected"

    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/ssh-login-count\" AND resource.type=\"gce_instance\""
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
    content   = "SSH login detected on a GCE instance. Verify the login is authorised."
    mime_type = "text/markdown"
  }
}

output "error_alert" {
  value = google_monitoring_alert_policy.error_count_alert.display_name
}

output "ssh_alert" {
  value = google_monitoring_alert_policy.ssh_login_alert.display_name
}
EOF

echo "project_id = \"${PROJECT_ID}\"" > terraform.tfvars

terraform init
terraform apply -auto-approve
```

### Step 6: Query Log-Based Metrics (5 min)

```bash
# Generate more errors to see metric data
gcloud compute ssh logmetric-lab-vm --zone=europe-west2-a --command="
  for i in \$(seq 1 20); do
    logger -t myapp \"ERROR: Database connection failed - attempt \$i\"
  done
  echo 'Generated 20 error log entries'
"

# Wait a minute, then check the metric
echo "Check metric data at:"
echo "https://console.cloud.google.com/monitoring/metrics-explorer?project=${PROJECT_ID}"
echo ""
echo "Search for: logging.googleapis.com/user/app-error-count"
```

### Step 7: Clean Up

```bash
cd tf-logmetric-alert
terraform destroy -auto-approve
cd ~
rm -rf tf-logmetric-alert

gcloud logging metrics delete app-error-count --quiet
gcloud logging metrics delete ssh-login-count --quiet
gcloud logging metrics delete log-entry-size --quiet
gcloud compute instances delete logmetric-lab-vm --zone=europe-west2-a --quiet
```

---

## Part 3: Revision (15 minutes)

- **Log-based metrics** bridge Cloud Logging and Cloud Monitoring
- **Counter** = count of matching log entries; **Distribution** = spread of a numeric field
- **Filter syntax** — `severity >= ERROR`, `textPayload =~ "regex"`, `resource.type = "gce_instance"`
- **Label extractors** add dimensions (user, IP, status code) to metrics
- **User-defined metric prefix** — `logging.googleapis.com/user/METRIC_NAME`
- **Limit** — 500 user-defined metrics per project
- **Use cases** — error rates, security events (SSH), application-specific KPIs

### Key Commands
```bash
gcloud logging metrics create NAME --log-filter="FILTER"
gcloud logging metrics list
gcloud logging metrics describe NAME
gcloud logging metrics delete NAME
gcloud logging read "FILTER" --limit=20
```

---

## Part 4: Quiz (15 minutes)

**Q1:** When would you use a log-based metric instead of a built-in Cloud Monitoring metric?
<details><summary>Answer</summary>When the data you need <b>only exists in logs</b>, not as a standard metric. Examples: application-specific error counts, SSH login events, custom business events (orders processed, payments failed). Built-in metrics cover infrastructure (CPU, memory, network) but not application-level signals. Log-based metrics let you promote log patterns into first-class monitoring metrics. Like using <code>grep -c "ERROR" /var/log/app.log</code> and graphing the result.</details>

**Q2:** What's the difference between `ALIGN_RATE` and `ALIGN_COUNT` when aggregating a counter metric?
<details><summary>Answer</summary><code>ALIGN_RATE</code> gives you the <b>rate of change per second</b> (e.g., 5 errors/sec). <code>ALIGN_COUNT</code> gives the <b>total count in the alignment period</b> (e.g., 300 errors in 60s). Use <code>ALIGN_RATE</code> for dashboards (smoothed rate view) and <code>ALIGN_COUNT</code> for alerts where you want "more than N events in this window".</details>

**Q3:** You create a log-based metric for SSH logins but see no data. What could be wrong?
<details><summary>Answer</summary>
1. <b>Filter mismatch</b> — the log entry text doesn't match your regex (check with <code>gcloud logging read</code>)<br>
2. <b>Not enough time</b> — metrics may take 1-2 minutes to appear after log ingestion<br>
3. <b>Ops Agent not installed</b> — system logs (auth.log) might not be reaching Cloud Logging<br>
4. <b>Wrong resource.type</b> — filter says <code>gce_instance</code> but logs come in as <code>global</code><br>
Debug: first verify logs exist with <code>gcloud logging read "your filter"</code>, then check the metric definition.
</details>

**Q4:** Why add label extractors to a log-based metric?
<details><summary>Answer</summary>Label extractors add <b>dimensions</b> to the metric, allowing you to filter and group in dashboards and alerts. Without labels, you get a single total count. With labels (e.g., user, status_code, source_ip), you can see "errors per user" or "logins per IP". This is like the difference between a flat counter and a multi-dimensional metric in Prometheus. Be careful: each unique label combination creates a separate time series, which affects cost and cardinality.</details>
