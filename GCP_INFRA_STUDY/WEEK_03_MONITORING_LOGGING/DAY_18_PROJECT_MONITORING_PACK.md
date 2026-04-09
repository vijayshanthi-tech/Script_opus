# Day 18 — PROJECT: Complete Monitoring Pack

> **Week 3 · Monitoring & Logging** | Region: `europe-west2` | Study time: 2 hours

---

## Project Overview

Build a **production-ready monitoring pack** for a VM running a web service. This project combines everything from Week 3: Cloud Logging, Cloud Monitoring, alerting policies, Ops Agent, and health check scripting.

### What You Will Build

```
┌─────────────────────────────────────────────────────────────────────┐
│                    COMPLETE MONITORING PACK                          │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │                     VM: web-server-vm                       │    │
│  │                     (nginx + Ops Agent)                     │    │
│  │                                                             │    │
│  │  ┌─────────────┐  ┌──────────────┐  ┌──────────────────┐   │    │
│  │  │ Ops Agent   │  │ Health Check │  │ nginx            │   │    │
│  │  │ metrics +   │  │ Script       │  │ web server       │   │    │
│  │  │ logging     │  │ (cron 5min)  │  │ port 80          │   │    │
│  │  └──────┬──────┘  └──────┬───────┘  └──────────────────┘   │    │
│  │         │                │                                  │    │
│  └─────────┼────────────────┼──────────────────────────────────┘    │
│            │                │                                       │
│  ┌─────────▼────────────────▼──────────────────────────────────┐    │
│  │              CLOUD MONITORING                                │    │
│  │                                                              │    │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐   │    │
│  │  │  Dashboard   │  │  Alert       │  │  Uptime Check    │   │    │
│  │  │  CPU/Mem/    │  │  Policies    │  │  HTTP :80        │   │    │
│  │  │  Disk/Net    │  │  CPU>80%     │  │                  │   │    │
│  │  │              │  │  Disk>85%    │  │                  │   │    │
│  │  └──────────────┘  └──────────────┘  └──────────────────┘   │    │
│  │                                                              │    │
│  └──────────────────────────────────────────────────────────────┘    │
│                                                                     │
│  ┌──────────────────────────────────────────────────────────────┐    │
│  │              CLOUD LOGGING                                    │    │
│  │                                                              │    │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐   │    │
│  │  │ Log Queries  │  │  Log Sink    │  │  Saved Queries   │   │    │
│  │  │ syslog       │  │  errors →    │  │  health check    │   │    │
│  │  │ nginx access │  │  GCS bucket  │  │  nginx errors    │   │    │
│  │  │ health check │  │              │  │                  │   │    │
│  │  └──────────────┘  └──────────────┘  └──────────────────┘   │    │
│  │                                                              │    │
│  └──────────────────────────────────────────────────────────────┘    │
│                                                                     │
│  ┌──────────────────────────────────────────────────────────────┐    │
│  │              NOTIFICATION                                     │    │
│  │  ┌──────────────┐                                            │    │
│  │  │ Email Channel│── receives alerts                          │    │
│  │  └──────────────┘                                            │    │
│  └──────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────┘
```

### Checklist

Use this to track your progress:

```
[ ] 1.  Create VM with nginx + firewall rule
[ ] 2.  Install and configure Ops Agent
[ ] 3.  Deploy health check script + cron
[ ] 4.  Create notification channel (email)
[ ] 5.  Create CPU alert policy (>80%)
[ ] 6.  Create disk alert policy (>85%)
[ ] 7.  Create uptime check (HTTP :80)
[ ] 8.  Create a monitoring dashboard
[ ] 9.  Create a GCS log sink for errors
[ ] 10. Test: trigger CPU alert
[ ] 11. Test: trigger uptime check failure
[ ] 12. Verify logs flow in Logs Explorer
[ ] 13. Cleanup all resources
```

---

## Part 1 — Concept Review (30 min)

### Week 3 Recap — Components & How They Connect

| Day | Component | Role in This Project |
|---|---|---|
| Day 13 | Cloud Logging | Collect syslog, nginx logs, health check logs; sink errors to GCS |
| Day 14 | Cloud Monitoring | Dashboard with CPU/memory/disk/network charts |
| Day 15 | Alerting Policies | CPU >80% alert, disk >85% alert with email notification |
| Day 16 | Ops Agent | Collect memory/disk metrics + custom log paths from VM |
| Day 17 | Health Check Script | Bash script checking disk/memory/processes/ports via cron |

### Architecture Flow

```
  User Request ──> nginx (port 80)
                      │
                      │ access.log + error.log
                      ▼
                   Ops Agent ──────────────────> Cloud Logging
                      │                              │
                      │ metrics                      │ sink (errors)
                      ▼                              ▼
                 Cloud Monitoring              GCS Bucket (archive)
                      │
            ┌─────────┼──────────┐
            ▼         ▼          ▼
        Dashboard  Alerts    Uptime Check
                      │
                      ▼
                 Email Notification
```

### Linux Commands You'll Use

| Command | Purpose |
|---|---|
| `systemctl start/status nginx` | Manage web server |
| `systemctl status google-cloud-ops-agent` | Check agent |
| `logger` | Generate syslog entries |
| `stress-ng` | Generate CPU load for alert testing |
| `df -h`, `free -m`, `pgrep`, `ss` | Health check commands |
| `crontab -l`, `/etc/cron.d/` | Scheduled health checks |

---

## Part 2 — Hands-On Build (60 min)

### Prerequisites

```bash
gcloud config set project YOUR_PROJECT_ID
gcloud config set compute/region europe-west2
gcloud config set compute/zone europe-west2-b

PROJECT_ID=$(gcloud config get-value project)
```

### Step 1 — Create the VM and Firewall Rule

```bash
# Create the web server VM
gcloud compute instances create web-server-vm \
    --zone=europe-west2-b \
    --machine-type=e2-small \
    --image-family=debian-12 \
    --image-project=debian-cloud \
    --scopes=monitoring,logging-write \
    --tags=http-server,web \
    --labels=env=lab,week=3,project=monitoring-pack \
    --metadata=startup-script='#!/bin/bash
apt-get update
apt-get install -y nginx stress-ng bc
systemctl enable nginx
systemctl start nginx
echo "<h1>Day 18 Monitoring Pack - $(hostname)</h1>" > /var/www/html/index.html'

# Create firewall rule for HTTP
gcloud compute firewall-rules create allow-http-web \
    --allow=tcp:80 \
    --target-tags=http-server \
    --source-ranges=0.0.0.0/0 \
    --description="Allow HTTP for monitoring pack project"

# Get the external IP
EXTERNAL_IP=$(gcloud compute instances describe web-server-vm \
    --zone=europe-west2-b \
    --format="value(networkInterfaces[0].accessConfigs[0].natIP)")
echo "Web server: http://$EXTERNAL_IP"
```

**Checkpoint:** Visit `http://$EXTERNAL_IP` in a browser — you should see the nginx page.

### Step 2 — Install and Configure the Ops Agent

```bash
gcloud compute ssh web-server-vm --zone=europe-west2-b
```

**Inside the VM:**

```bash
# Install Ops Agent
curl -sSO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh
sudo bash add-google-cloud-ops-agent-repo.sh --also-install

# Configure: collect nginx logs + health check logs + system metrics
sudo tee /etc/google-cloud-ops-agent/config.yaml > /dev/null << 'EOF'
logging:
  receivers:
    syslog:
      type: files
      include_paths:
        - /var/log/messages
        - /var/log/syslog
    nginx_access:
      type: files
      include_paths:
        - /var/log/nginx/access.log
    nginx_error:
      type: files
      include_paths:
        - /var/log/nginx/error.log
    health_check:
      type: files
      include_paths:
        - /var/log/health_check/results.log
  service:
    pipelines:
      default_pipeline:
        receivers: [syslog]
      nginx_access_pipeline:
        receivers: [nginx_access]
      nginx_error_pipeline:
        receivers: [nginx_error]
      health_pipeline:
        receivers: [health_check]

metrics:
  receivers:
    hostmetrics:
      type: hostmetrics
      collection_interval: 60s
  service:
    pipelines:
      default_pipeline:
        receivers: [hostmetrics]
EOF

sudo systemctl restart google-cloud-ops-agent

# Verify all three sub-services
sudo systemctl is-active google-cloud-ops-agent
sudo systemctl is-active google-cloud-ops-agent-opentelemetry-collector
sudo systemctl is-active google-cloud-ops-agent-fluent-bit

echo "Ops Agent installed and configured."
```

### Step 3 — Deploy the Health Check Script

```bash
# Still inside the VM

sudo mkdir -p /opt/scripts /var/log/health_check

sudo tee /opt/scripts/health_check.sh > /dev/null << 'SCRIPT'
#!/bin/bash
set -uo pipefail

DISK_WARN=80
DISK_CRIT=95
MEM_WARN=80
MEM_CRIT=95
CHECK_PROCESSES=("nginx" "sshd" "google_cloud_ops_agent")
CHECK_PORTS=(80 22)
LOG_FILE="/var/log/health_check/results.log"
OVERALL_STATUS=0

update_status() { [ "$1" -gt "$OVERALL_STATUS" ] && OVERALL_STATUS=$1; }

log() {
    local ts level msg
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    level=$1; shift; msg="$*"
    echo "[$ts] [$level] $msg" | tee -a "$LOG_FILE"
}

check_disk() {
    log "INFO" "--- Disk Check ---"
    while IFS= read -r line; do
        local mount pct
        mount=$(echo "$line" | awk '{print $6}')
        pct=$(echo "$line" | awk '{print $5}' | tr -d '%')
        if [ "$pct" -ge "$DISK_CRIT" ]; then
            log "CRITICAL" "Disk $mount at ${pct}%"; update_status 2
        elif [ "$pct" -ge "$DISK_WARN" ]; then
            log "WARNING" "Disk $mount at ${pct}%"; update_status 1
        else
            log "OK" "Disk $mount at ${pct}%"
        fi
    done < <(df -h --output=source,size,used,avail,pcent,target -x tmpfs -x devtmpfs | tail -n +2)
}

check_memory() {
    log "INFO" "--- Memory Check ---"
    local total used pct
    total=$(free -m | awk '/^Mem:/ {print $2}')
    used=$(free -m | awk '/^Mem:/ {print $3}')
    pct=$((used * 100 / total))
    if [ "$pct" -ge "$MEM_CRIT" ]; then
        log "CRITICAL" "Memory at ${pct}%"; update_status 2
    elif [ "$pct" -ge "$MEM_WARN" ]; then
        log "WARNING" "Memory at ${pct}%"; update_status 1
    else
        log "OK" "Memory at ${pct}%"
    fi
}

check_processes() {
    log "INFO" "--- Process Checks ---"
    for proc in "${CHECK_PROCESSES[@]}"; do
        local count
        count=$(pgrep -c "$proc" 2>/dev/null || true)
        if [ "$count" -eq 0 ]; then
            log "CRITICAL" "Process '$proc' NOT running"; update_status 2
        else
            log "OK" "Process '$proc' running ($count)"
        fi
    done
}

check_ports() {
    log "INFO" "--- Port Checks ---"
    for port in "${CHECK_PORTS[@]}"; do
        if ss -tlnp | grep -q ":${port} "; then
            log "OK" "Port ${port} listening"
        else
            log "CRITICAL" "Port ${port} NOT listening"; update_status 2
        fi
    done
}

main() {
    log "INFO" "===== Health Check: $(hostname) ====="
    check_disk
    check_memory
    check_processes
    check_ports
    case $OVERALL_STATUS in
        0) log "OK" "OVERALL: OK" ;;
        1) log "WARNING" "OVERALL: WARNING" ;;
        2) log "CRITICAL" "OVERALL: CRITICAL" ;;
    esac
    log "INFO" "====================================="
    exit $OVERALL_STATUS
}

main "$@"
SCRIPT

sudo chmod +x /opt/scripts/health_check.sh

# Run a test
sudo /opt/scripts/health_check.sh
echo "Exit code: $?"

# Set up cron — every 5 minutes
sudo tee /etc/cron.d/health_check > /dev/null << 'EOF'
*/5 * * * * root /opt/scripts/health_check.sh >> /var/log/health_check/cron.log 2>&1
EOF

# Log rotation
sudo tee /etc/logrotate.d/health_check > /dev/null << 'EOF'
/var/log/health_check/*.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 0644 root root
}
EOF

echo "Health check deployed. Cron running every 5 minutes."
exit
```

### Step 4 — Create Notification Channel

```bash
# Back on local machine

cat > /tmp/email-channel.json << 'EOF'
{
  "type": "email",
  "displayName": "Day18-Project-Email",
  "labels": {
    "email_address": "YOUR_EMAIL@example.com"
  }
}
EOF

gcloud monitoring channels create --channel-content-from-file=/tmp/email-channel.json

CHANNEL_ID=$(gcloud monitoring channels list \
    --filter="displayName='Day18-Project-Email'" \
    --format="value(name)")

echo "Channel: $CHANNEL_ID"
```

### Step 5 — Create Alert Policies

```bash
INSTANCE_ID=$(gcloud compute instances describe web-server-vm \
    --zone=europe-west2-b --format="value(id)")

# --- CPU Alert Policy (>80% for 3 minutes) ---
cat > /tmp/cpu-alert.json << EOF
{
  "displayName": "Day18-CPU-High",
  "documentation": {
    "content": "CPU > 80% on web-server-vm. Run 'top' to identify the process. Consider scaling up or optimizing.",
    "mimeType": "text/markdown"
  },
  "conditions": [{
    "displayName": "CPU > 80% for 3 min",
    "conditionThreshold": {
      "filter": "metric.type=\"compute.googleapis.com/instance/cpu/utilization\" AND resource.type=\"gce_instance\" AND resource.labels.instance_id=\"$INSTANCE_ID\"",
      "comparison": "COMPARISON_GT",
      "thresholdValue": 0.80,
      "duration": "180s",
      "aggregations": [{
        "alignmentPeriod": "60s",
        "perSeriesAligner": "ALIGN_MEAN"
      }],
      "trigger": { "count": 1 }
    }
  }],
  "combiner": "OR",
  "notificationChannels": ["$CHANNEL_ID"],
  "alertStrategy": { "autoClose": "1800s" }
}
EOF

gcloud monitoring policies create --policy-from-file=/tmp/cpu-alert.json

# --- Disk Alert Policy (>85%) ---
cat > /tmp/disk-alert.json << EOF
{
  "displayName": "Day18-Disk-High",
  "documentation": {
    "content": "Disk usage > 85% on web-server-vm. Run 'df -h' and 'du -sh /*' to find large files.",
    "mimeType": "text/markdown"
  },
  "conditions": [{
    "displayName": "Disk > 85% for 5 min",
    "conditionThreshold": {
      "filter": "metric.type=\"agent.googleapis.com/disk/percent_used\" AND resource.type=\"gce_instance\" AND resource.labels.instance_id=\"$INSTANCE_ID\"",
      "comparison": "COMPARISON_GT",
      "thresholdValue": 85,
      "duration": "300s",
      "aggregations": [{
        "alignmentPeriod": "60s",
        "perSeriesAligner": "ALIGN_MEAN"
      }],
      "trigger": { "count": 1 }
    }
  }],
  "combiner": "OR",
  "notificationChannels": ["$CHANNEL_ID"],
  "alertStrategy": { "autoClose": "1800s" }
}
EOF

gcloud monitoring policies create --policy-from-file=/tmp/disk-alert.json

# List policies
gcloud monitoring policies list \
    --filter="displayName:'Day18'" \
    --format="table(displayName,enabled)"
```

### Step 6 — Create the Uptime Check

```bash
EXTERNAL_IP=$(gcloud compute instances describe web-server-vm \
    --zone=europe-west2-b \
    --format="value(networkInterfaces[0].accessConfigs[0].natIP)")

gcloud monitoring uptime create day18-web-uptime \
    --resource-type=uptime-url \
    --monitored-resource-host="$EXTERNAL_IP" \
    --protocol=http \
    --port=80 \
    --path="/" \
    --period=5 \
    --timeout=10

gcloud monitoring uptime list-configs \
    --format="table(displayName,httpCheck.port,period)"
```

### Step 7 — Create the Monitoring Dashboard

```bash
cat > /tmp/dashboard.json << 'EOF'
{
  "displayName": "Day18-Web-Server-Dashboard",
  "mosaicLayout": {
    "tiles": [
      {
        "width": 6, "height": 4,
        "widget": {
          "title": "CPU Utilization",
          "xyChart": {
            "dataSets": [{
              "timeSeriesQuery": {
                "timeSeriesFilter": {
                  "filter": "metric.type=\"compute.googleapis.com/instance/cpu/utilization\" resource.type=\"gce_instance\"",
                  "aggregation": { "alignmentPeriod": "60s", "perSeriesAligner": "ALIGN_MEAN" }
                }
              },
              "plotType": "LINE"
            }]
          }
        }
      },
      {
        "xPos": 6, "width": 6, "height": 4,
        "widget": {
          "title": "Memory Used %",
          "xyChart": {
            "dataSets": [{
              "timeSeriesQuery": {
                "timeSeriesFilter": {
                  "filter": "metric.type=\"agent.googleapis.com/memory/percent_used\" resource.type=\"gce_instance\"",
                  "aggregation": { "alignmentPeriod": "60s", "perSeriesAligner": "ALIGN_MEAN" }
                }
              },
              "plotType": "LINE"
            }]
          }
        }
      },
      {
        "yPos": 4, "width": 6, "height": 4,
        "widget": {
          "title": "Disk Used %",
          "xyChart": {
            "dataSets": [{
              "timeSeriesQuery": {
                "timeSeriesFilter": {
                  "filter": "metric.type=\"agent.googleapis.com/disk/percent_used\" resource.type=\"gce_instance\"",
                  "aggregation": { "alignmentPeriod": "60s", "perSeriesAligner": "ALIGN_MEAN" }
                }
              },
              "plotType": "LINE"
            }]
          }
        }
      },
      {
        "xPos": 6, "yPos": 4, "width": 6, "height": 4,
        "widget": {
          "title": "Network Bytes (In/Out)",
          "xyChart": {
            "dataSets": [{
              "timeSeriesQuery": {
                "timeSeriesFilter": {
                  "filter": "metric.type=\"compute.googleapis.com/instance/network/received_bytes_count\" resource.type=\"gce_instance\"",
                  "aggregation": { "alignmentPeriod": "60s", "perSeriesAligner": "ALIGN_RATE" }
                }
              },
              "plotType": "STACKED_AREA"
            }]
          }
        }
      }
    ]
  }
}
EOF

gcloud monitoring dashboards create --config-from-file=/tmp/dashboard.json

gcloud monitoring dashboards list --format="table(displayName,name)"
```

### Step 8 — Create a Log Sink for Errors

```bash
# Create a GCS bucket for error logs
gcloud storage buckets create gs://${PROJECT_ID}-error-logs \
    --location=europe-west2 \
    --uniform-bucket-level-access

# Create sink — route ERROR+ logs to GCS
gcloud logging sinks create web-error-sink \
    storage.googleapis.com/${PROJECT_ID}-error-logs \
    --log-filter='resource.type="gce_instance" AND severity>=ERROR'

# Grant the sink's service account write access
SINK_SA=$(gcloud logging sinks describe web-error-sink \
    --format="value(writerIdentity)")

gcloud storage buckets add-iam-policy-binding \
    gs://${PROJECT_ID}-error-logs \
    --member="$SINK_SA" \
    --role="roles/storage.objectCreator"

echo "Error log sink configured: errors → gs://${PROJECT_ID}-error-logs"
```

### Step 9 — Test: Trigger CPU Alert

```bash
# Stress the CPU to trigger the Day18-CPU-High alert
gcloud compute ssh web-server-vm --zone=europe-west2-b \
    --command="nohup stress-ng --cpu 2 --cpu-load 95 --timeout 600 > /dev/null 2>&1 &"

echo "CPU stress running for 10 minutes."
echo "Alert should fire within 4-6 minutes."
echo "Watch: Console → Monitoring → Alerting → Incidents"
```

Wait for the alert, then stop the stress:

```bash
gcloud compute ssh web-server-vm --zone=europe-west2-b \
    --command="sudo pkill stress-ng"
echo "Stress stopped. Incident will auto-close in 30 minutes."
```

### Step 10 — Test: Trigger Uptime Check Failure

```bash
# Stop nginx to make the uptime check fail
gcloud compute ssh web-server-vm --zone=europe-west2-b \
    --command="sudo systemctl stop nginx"

echo "nginx stopped. Uptime check should fail within 5 minutes."
echo "Watch: Console → Monitoring → Uptime checks"

# After verifying failure, restart nginx
gcloud compute ssh web-server-vm --zone=europe-west2-b \
    --command="sudo systemctl start nginx"
echo "nginx restarted."
```

### Step 11 — Verify Logs in Logs Explorer

Run these queries in **Console → Logging → Logs Explorer**:

**Health check logs:**
```
resource.type="gce_instance"
logName:"health_check"
```

**Nginx access logs:**
```
resource.type="gce_instance"
logName:"nginx_access"
```

**Errors only:**
```
resource.type="gce_instance"
severity>=ERROR
```

**CLI verification:**
```bash
INSTANCE_ID=$(gcloud compute instances describe web-server-vm \
    --zone=europe-west2-b --format="value(id)")

# Health check logs
gcloud logging read \
    "resource.type=\"gce_instance\" AND resource.labels.instance_id=\"$INSTANCE_ID\" AND logName:\"health_check\"" \
    --limit=10 --format="table(timestamp,textPayload)"

# nginx access logs
gcloud logging read \
    "resource.type=\"gce_instance\" AND resource.labels.instance_id=\"$INSTANCE_ID\" AND logName:\"nginx_access\"" \
    --limit=5 --format="table(timestamp,textPayload)"
```

---

## Part 3 — Revision (15 min)

### Week 3 Summary

| Topic | What You Built | Key Takeaway |
|---|---|---|
| Cloud Logging | Log queries, GCS sink | Centralised logs; sinks route to storage |
| Cloud Monitoring | Dashboard, uptime check | Auto-metrics for all GCP resources |
| Alerting | CPU + disk alert policies | Conditions + channels + documentation |
| Ops Agent | Installed on VM | Unlocks memory/disk metrics + custom logs |
| Health Scripts | Bash checks + cron | Real-world operational checks on a schedule |

### Production Monitoring Checklist

```
[ ] Ops Agent installed on all VMs
[ ] Dashboard for each service with CPU, memory, disk, network
[ ] CPU alert (>80% for 5 min → email, >95% for 5 min → page)
[ ] Disk alert (>85% → email, >95% → page)
[ ] Memory alert (>90% → email, requires Ops Agent)
[ ] Uptime check on all public endpoints
[ ] Log sink for ERROR+ to GCS for compliance/audit
[ ] Health check script for custom checks (processes, ports)
[ ] Notification channels verified and tested
[ ] Runbook links in all alert documentation
[ ] Log rotation configured for custom log files
[ ] Alert thresholds reviewed quarterly for relevance
```

### Essential Commands — Full Reference

```bash
# --- Cloud Logging ---
gcloud logging read 'FILTER' --limit=N --format=json
gcloud logging write LOG "message" --severity=INFO
gcloud logging sinks create NAME DESTINATION --log-filter='FILTER'
gcloud logging sinks delete NAME

# --- Cloud Monitoring ---
gcloud monitoring dashboards create --config-from-file=FILE
gcloud monitoring dashboards list
gcloud monitoring dashboards delete DASHBOARD_NAME
gcloud monitoring uptime create NAME --resource-type=uptime-url ...
gcloud monitoring uptime list-configs
gcloud monitoring uptime delete UPTIME_ID

# --- Alerting ---
gcloud monitoring channels create --channel-content-from-file=FILE
gcloud monitoring channels list
gcloud monitoring policies create --policy-from-file=FILE
gcloud monitoring policies list
gcloud monitoring policies delete POLICY_NAME

# --- Ops Agent ---
curl -sSO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh
sudo bash add-google-cloud-ops-agent-repo.sh --also-install
sudo systemctl restart google-cloud-ops-agent
sudo vim /etc/google-cloud-ops-agent/config.yaml

# --- Health Check ---
df -h / | awk 'NR==2 {print $5}'
free -m | awk '/Mem:/ {print int($3/$2*100)}'
pgrep -c nginx
ss -tlnp | grep :80
```

---

## Part 4 — Quiz (15 min)

**Question 1: You've deployed the full monitoring pack but the memory chart on your dashboard shows no data. CPU, disk IO, and network charts all work. What is wrong?**

<details>
<summary>Show Answer</summary>

Memory metrics require the **Ops Agent** to be installed and running. The memory chart uses `agent.googleapis.com/memory/percent_used`, which is only reported by the Ops Agent — not by the hypervisor.

Troubleshooting:
1. Check agent status: `sudo systemctl status google-cloud-ops-agent`
2. Check metrics collector: `sudo systemctl status google-cloud-ops-agent-opentelemetry-collector`
3. Check agent logs: `sudo journalctl -u google-cloud-ops-agent --no-pager -n 20`
4. Verify the chart filter references the correct metric type and instance
5. Wait 2-3 minutes after agent install for metrics to start flowing

</details>

---

**Question 2: Your log sink is configured to send ERROR+ logs to GCS, but the bucket is empty after 1 hour. The sink filter is correct and errors are being generated. What should you check?**

<details>
<summary>Show Answer</summary>

The most likely cause is the **sink writer identity** lacks permissions on the GCS bucket.

Fix:
```bash
SINK_SA=$(gcloud logging sinks describe web-error-sink --format="value(writerIdentity)")
gcloud storage buckets add-iam-policy-binding gs://BUCKET \
    --member="$SINK_SA" --role="roles/storage.objectCreator"
```

Also check:
- Logs matching the filter actually exist: test the filter in Logs Explorer
- The bucket name in the sink destination is correct
- GCS exports are batched — files may take up to 2-3 hours to appear in some cases
- The sink was created at the right scope (project-level, not org-level by mistake)

</details>

---

**Question 3: Your health check script runs fine manually but never produces output when run by cron. What are three things to check?**

<details>
<summary>Show Answer</summary>

1. **PATH environment** — cron runs with a minimal PATH. Commands like `ss`, `bc`, or `pgrep` may not be found. Use full paths (`/usr/bin/ss`) or set PATH at the top of the script.

2. **Permissions** — check that the cron user (root in `/etc/cron.d/`) has execute permission on the script and write permission on the log directory.

3. **Output redirection** — ensure cron redirects stdout and stderr to a log file: `>> /var/log/health_check/cron.log 2>&1`. Without this, output goes to mail (which may not be configured).

Bonus checks:
- Verify cron daemon is running: `systemctl status cron`
- Check `/var/log/syslog` for cron execution entries
- Syntax of the cron schedule expression

</details>

---

**Question 4: Your team gets 30 alert emails per day, mostly for brief CPU spikes that resolve in under 2 minutes. How do you reduce noise without missing real incidents?**

<details>
<summary>Show Answer</summary>

This is **alert fatigue** from transient spikes. Solutions:

1. **Increase duration window**: Change from 1 min to 5 min. The condition must hold for 5 continuous minutes before firing. Brief spikes won't trigger alerts.

2. **Increase alignment period**: Use 5-minute averages instead of 1-minute. Smooths out short bursts.

3. **Raise threshold**: If 80% causes too many alerts, try 85% or 90% for the email tier. Keep a higher threshold (95%) for paging.

4. **Tier the alerts**: WARNING (email, non-urgent) at 80%, CRITICAL (page, immediate) at 95%. Only page for truly service-affecting conditions.

5. **Increase auto-close duration**: Prevents rapid open/close/open cycles.

The goal: every alert should be **actionable**. If you routinely ignore alerts, the thresholds are wrong.

</details>

---

## Cleanup — Delete All Project Resources

Run this cleanup section to remove **all resources** created during this project:

```bash
PROJECT_ID=$(gcloud config get-value project)

echo "=== Cleaning up Day 18 Monitoring Pack ==="

# 1. Delete alert policies
for POLICY in $(gcloud monitoring policies list \
    --filter="displayName:'Day18'" \
    --format="value(name)" 2>/dev/null); do
    echo "Deleting alert policy: $POLICY"
    gcloud monitoring policies delete "$POLICY" --quiet
done

# 2. Delete uptime checks
for UPTIME in $(gcloud monitoring uptime list-configs \
    --format="value(name)" \
    --filter="displayName:'day18'" 2>/dev/null); do
    echo "Deleting uptime check: $UPTIME"
    gcloud monitoring uptime delete "$UPTIME" --quiet
done

# 3. Delete dashboards
for DASH in $(gcloud monitoring dashboards list \
    --format="value(name)" \
    --filter="displayName:'Day18'" 2>/dev/null); do
    echo "Deleting dashboard: $DASH"
    gcloud monitoring dashboards delete "$DASH" --quiet
done

# 4. Delete notification channels
for CHAN in $(gcloud monitoring channels list \
    --filter="displayName:'Day18'" \
    --format="value(name)" 2>/dev/null); do
    echo "Deleting notification channel: $CHAN"
    gcloud monitoring channels delete "$CHAN" --quiet --force
done

# 5. Delete log sink
gcloud logging sinks delete web-error-sink --quiet 2>/dev/null && \
    echo "Deleted log sink: web-error-sink"

# 6. Delete GCS bucket
gcloud storage rm -r gs://${PROJECT_ID}-error-logs/ 2>/dev/null
gcloud storage buckets delete gs://${PROJECT_ID}-error-logs 2>/dev/null && \
    echo "Deleted GCS bucket: gs://${PROJECT_ID}-error-logs"

# 7. Delete firewall rule
gcloud compute firewall-rules delete allow-http-web --quiet 2>/dev/null && \
    echo "Deleted firewall rule: allow-http-web"

# 8. Delete VM
gcloud compute instances delete web-server-vm --zone=europe-west2-b --quiet 2>/dev/null && \
    echo "Deleted VM: web-server-vm"

# 9. Clean up temp files
rm -f /tmp/email-channel.json /tmp/cpu-alert.json /tmp/disk-alert.json /tmp/dashboard.json

echo "=== Cleanup complete ==="
```

---

*End of Day 18 & Week 3 — Monitoring & Logging complete. Next week: Identity, IAM & Security.*
