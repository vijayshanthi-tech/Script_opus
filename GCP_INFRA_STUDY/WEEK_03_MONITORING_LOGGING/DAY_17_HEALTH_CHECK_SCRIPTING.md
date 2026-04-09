# Day 17 — Health Check Scripting: Bash, Cron & Custom Metrics

> **Week 3 · Monitoring & Logging** | Region: `europe-west2` | Study time: 2 hours

---

## Part 1 — Concept (30 min)

### 1.1 Why Health Check Scripts?

Cloud Monitoring covers standard metrics, but real infra needs **custom checks** — is a specific process running? Is a port responding? Is disk usage on a particular mount above threshold? Health check scripts are the glue between OS-level reality and monitoring.

| Linux Tool | Health Check Use |
|---|---|
| `df -h` | Disk space check |
| `free -m` | Memory check |
| `top` / `mpstat` | CPU check |
| `ps aux` / `pgrep` | Process running check |
| `ss` / `netstat` | Port listening check |
| `curl` / `nc` | Service reachability check |
| `crontab -e` | Schedule recurring checks |

### 1.2 Health Check Script Architecture

```
┌───────────────────────────────────────────────────────────┐
│                      VM INSTANCE                           │
│                                                           │
│  ┌─────────────────────────────────────────────────────┐  │
│  │            /opt/scripts/health_check.sh             │  │
│  │                                                     │  │
│  │  ┌──────────┐  ┌──────────┐  ┌───────────────┐     │  │
│  │  │ Disk     │  │ Memory   │  │ Process       │     │  │
│  │  │ Check    │  │ Check    │  │ Check         │     │  │
│  │  │ df -h    │  │ free -m  │  │ pgrep nginx   │     │  │
│  │  └────┬─────┘  └────┬─────┘  └──────┬────────┘     │  │
│  │       │              │               │              │  │
│  │       ▼              ▼               ▼              │  │
│  │  ┌────────────────────────────────────────────┐     │  │
│  │  │        Results → Log File + stdout         │     │  │
│  │  │    /var/log/health_check/results.log       │     │  │
│  │  └───────────────┬────────────────────────────┘     │  │
│  │                  │                                  │  │
│  │       ┌──────────┼──────────────┐                   │  │
│  │       ▼          ▼              ▼                   │  │
│  │   Ops Agent   Exit Code    Custom Metric            │  │
│  │   tails log   for cron     to Cloud Mon.            │  │
│  └─────────────────────────────────────────────────────┘  │
│                                                           │
│  ┌─────────────────┐                                      │
│  │    CRON JOB     │  */5 * * * * /opt/scripts/...       │
│  └─────────────────┘                                      │
└───────────────────────────────────────────────────────────┘
```

### 1.3 Check Types & Commands

| Check | Command | Warning | Critical |
|---|---|---|---|
| Disk space | `df -h /` | >80% | >95% |
| Memory | `free -m` | >80% used | >95% used |
| CPU (1-min avg) | `uptime` / `mpstat` | load > num_cpus | load > 2×num_cpus |
| Process alive | `pgrep -c PROCESS` | — | count = 0 |
| Port listening | `ss -tlnp \| grep :PORT` | — | not listening |
| Service reachable | `curl -s http://localhost:PORT/health` | timeout | non-200 |
| Swap usage | `free -m` (swap line) | >50% | >80% |
| File age | `find FILE -mmin +N` | file too old | file very old |

### 1.4 Exit Codes Convention

Following Nagios/monitoring convention:

| Exit Code | Status | Meaning |
|---|---|---|
| 0 | OK | All checks passed |
| 1 | WARNING | Non-critical issue |
| 2 | CRITICAL | Service-affecting issue |
| 3 | UNKNOWN | Check itself failed |

### 1.5 Cron Scheduling

```
# ┌───────────── minute (0-59)
# │ ┌───────────── hour (0-23)
# │ │ ┌───────────── day of month (1-31)
# │ │ │ ┌───────────── month (1-12)
# │ │ │ │ ┌───────────── day of week (0-7, Sun=0 or 7)
# │ │ │ │ │
# * * * * * command
  */5 * * * * /opt/scripts/health_check.sh >> /var/log/health_check/cron.log 2>&1
```

| Schedule | Cron Expression |
|---|---|
| Every 5 minutes | `*/5 * * * *` |
| Every hour | `0 * * * *` |
| Every day at midnight | `0 0 * * *` |
| Every Monday at 9am | `0 9 * * 1` |

### 1.6 Custom Metrics

You can push custom metric data to Cloud Monitoring for alerting:

```
  Health Script ──> gcloud monitoring time-series create
                         │
                         ▼
                  Custom Metric in Cloud Monitoring
                  custom.googleapis.com/health/disk_used_percent
                         │
                         ▼
                  Alert Policy → Notification
```

### 1.7 Best Practices

| Practice | Why |
|---|---|
| Use functions per check | Maintainable, testable |
| Log every run with timestamp | Audit trail |
| Use exit codes consistently | Integration with monitoring |
| Don't hardcode thresholds | Use variables at top of script |
| Test on your workstation first | Catch syntax errors |
| Use `set -euo pipefail` | Fail fast on errors |
| Redirect cron output to log | Debug when things go wrong |

---

## Part 2 — Hands-On Lab (60 min)

### Lab Goal

Write a comprehensive health check script, deploy it to a VM, set up cron, and optionally push a custom metric.

### Prerequisites

```bash
gcloud config set project YOUR_PROJECT_ID
gcloud config set compute/region europe-west2
gcloud config set compute/zone europe-west2-b
```

### Step 1 — Create a Test VM

```bash
gcloud compute instances create health-check-vm \
    --zone=europe-west2-b \
    --machine-type=e2-small \
    --image-family=debian-12 \
    --image-project=debian-cloud \
    --scopes=monitoring,logging-write \
    --metadata=startup-script='#!/bin/bash
apt-get update && apt-get install -y stress-ng nginx sysstat bc
systemctl start nginx'
```

### Step 2 — SSH and Create the Health Check Script

```bash
gcloud compute ssh health-check-vm --zone=europe-west2-b
```

**Inside the VM — create the script:**

```bash
sudo mkdir -p /opt/scripts /var/log/health_check

sudo tee /opt/scripts/health_check.sh > /dev/null << 'SCRIPT'
#!/bin/bash
# ============================================================
# health_check.sh — Comprehensive VM Health Check
# Day 17 Lab — GCP Infrastructure Study
# ============================================================
set -uo pipefail

# --- Configuration (edit thresholds here) ---
DISK_WARN=80
DISK_CRIT=95
MEM_WARN=80
MEM_CRIT=95
SWAP_WARN=50
SWAP_CRIT=80
LOAD_WARN_MULTIPLIER=1    # warn if load > N * num_cpus
LOAD_CRIT_MULTIPLIER=2    # crit if load > 2N * num_cpus
CHECK_PROCESSES=("nginx" "sshd")
CHECK_PORTS=(80 22)
LOG_FILE="/var/log/health_check/results.log"

# --- State tracking ---
OVERALL_STATUS=0  # 0=OK, 1=WARN, 2=CRIT

update_status() {
    local new_status=$1
    if [ "$new_status" -gt "$OVERALL_STATUS" ]; then
        OVERALL_STATUS=$new_status
    fi
}

log() {
    local level=$1
    shift
    local msg="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $msg" | tee -a "$LOG_FILE"
}

# --- Check 1: Disk Space ---
check_disk() {
    log "INFO" "=== Disk Space Check ==="
    while IFS= read -r line; do
        local mount used_pct
        mount=$(echo "$line" | awk '{print $6}')
        used_pct=$(echo "$line" | awk '{print $5}' | tr -d '%')

        if [ "$used_pct" -ge "$DISK_CRIT" ]; then
            log "CRITICAL" "Disk $mount at ${used_pct}% (threshold: ${DISK_CRIT}%)"
            update_status 2
        elif [ "$used_pct" -ge "$DISK_WARN" ]; then
            log "WARNING" "Disk $mount at ${used_pct}% (threshold: ${DISK_WARN}%)"
            update_status 1
        else
            log "OK" "Disk $mount at ${used_pct}%"
        fi
    done < <(df -h --output=source,size,used,avail,pcent,target -x tmpfs -x devtmpfs | tail -n +2)
}

# --- Check 2: Memory Usage ---
check_memory() {
    log "INFO" "=== Memory Check ==="
    local total used pct
    total=$(free -m | awk '/^Mem:/ {print $2}')
    used=$(free -m | awk '/^Mem:/ {print $3}')
    pct=$((used * 100 / total))

    if [ "$pct" -ge "$MEM_CRIT" ]; then
        log "CRITICAL" "Memory at ${pct}% (${used}MB / ${total}MB)"
        update_status 2
    elif [ "$pct" -ge "$MEM_WARN" ]; then
        log "WARNING" "Memory at ${pct}% (${used}MB / ${total}MB)"
        update_status 1
    else
        log "OK" "Memory at ${pct}% (${used}MB / ${total}MB)"
    fi
}

# --- Check 3: Swap Usage ---
check_swap() {
    log "INFO" "=== Swap Check ==="
    local total used pct
    total=$(free -m | awk '/^Swap:/ {print $2}')
    used=$(free -m | awk '/^Swap:/ {print $3}')

    if [ "$total" -eq 0 ]; then
        log "OK" "No swap configured"
        return
    fi

    pct=$((used * 100 / total))

    if [ "$pct" -ge "$SWAP_CRIT" ]; then
        log "CRITICAL" "Swap at ${pct}% (${used}MB / ${total}MB)"
        update_status 2
    elif [ "$pct" -ge "$SWAP_WARN" ]; then
        log "WARNING" "Swap at ${pct}% (${used}MB / ${total}MB)"
        update_status 1
    else
        log "OK" "Swap at ${pct}% (${used}MB / ${total}MB)"
    fi
}

# --- Check 4: CPU Load Average ---
check_cpu_load() {
    log "INFO" "=== CPU Load Check ==="
    local load1 num_cpus warn_threshold crit_threshold
    load1=$(awk '{print $1}' /proc/loadavg)
    num_cpus=$(nproc)
    warn_threshold=$((num_cpus * LOAD_WARN_MULTIPLIER))
    crit_threshold=$((num_cpus * LOAD_CRIT_MULTIPLIER))

    # Use bc for float comparison
    if echo "$load1 >= $crit_threshold" | bc -l | grep -q 1; then
        log "CRITICAL" "Load avg ${load1} (cpus: ${num_cpus}, crit: ${crit_threshold})"
        update_status 2
    elif echo "$load1 >= $warn_threshold" | bc -l | grep -q 1; then
        log "WARNING" "Load avg ${load1} (cpus: ${num_cpus}, warn: ${warn_threshold})"
        update_status 1
    else
        log "OK" "Load avg ${load1} (cpus: ${num_cpus})"
    fi
}

# --- Check 5: Process Checks ---
check_processes() {
    log "INFO" "=== Process Checks ==="
    for proc in "${CHECK_PROCESSES[@]}"; do
        local count
        count=$(pgrep -c "$proc" 2>/dev/null || true)
        if [ "$count" -eq 0 ]; then
            log "CRITICAL" "Process '$proc' is NOT running"
            update_status 2
        else
            log "OK" "Process '$proc' running (${count} instances)"
        fi
    done
}

# --- Check 6: Port Checks ---
check_ports() {
    log "INFO" "=== Port Checks ==="
    for port in "${CHECK_PORTS[@]}"; do
        if ss -tlnp | grep -q ":${port} "; then
            log "OK" "Port ${port} is listening"
        else
            log "CRITICAL" "Port ${port} is NOT listening"
            update_status 2
        fi
    done
}

# --- Main ---
main() {
    log "INFO" "=========================================="
    log "INFO" "Health check started on $(hostname)"
    log "INFO" "=========================================="

    check_disk
    check_memory
    check_swap
    check_cpu_load
    check_processes
    check_ports

    log "INFO" "=========================================="
    case $OVERALL_STATUS in
        0) log "OK" "Overall status: OK" ;;
        1) log "WARNING" "Overall status: WARNING" ;;
        2) log "CRITICAL" "Overall status: CRITICAL" ;;
    esac
    log "INFO" "=========================================="

    exit $OVERALL_STATUS
}

main "$@"
SCRIPT

sudo chmod +x /opt/scripts/health_check.sh
```

### Step 3 — Run the Health Check Manually

```bash
# Run it
sudo /opt/scripts/health_check.sh

# Check exit code
echo "Exit code: $?"

# View the log
cat /var/log/health_check/results.log
```

### Step 4 — Trigger Warning/Critical Conditions

```bash
# Fill up disk to trigger warning (create a big file)
# Be careful — only fill to ~82%, not 100%
dd if=/dev/zero of=/tmp/disk_fill bs=1M count=500 2>/dev/null
sudo /opt/scripts/health_check.sh
echo "Exit code after disk fill: $?"

# Clean up
rm -f /tmp/disk_fill

# Stop nginx to trigger critical
sudo systemctl stop nginx
sudo /opt/scripts/health_check.sh
echo "Exit code after nginx stop: $?"

# Restart nginx
sudo systemctl start nginx
```

### Step 5 — Set Up Cron Job

```bash
# Create a cron job to run every 5 minutes
sudo tee /etc/cron.d/health_check > /dev/null << 'EOF'
# Health check every 5 minutes
*/5 * * * * root /opt/scripts/health_check.sh >> /var/log/health_check/cron.log 2>&1
EOF

# Verify cron is running
sudo systemctl status cron

# List cron jobs
sudo ls -la /etc/cron.d/health_check
cat /etc/cron.d/health_check

# Set up log rotation for the health check log
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

echo "Cron job set. Check /var/log/health_check/cron.log after 5 minutes."
```

### Step 6 — Configure Ops Agent to Collect Health Check Logs

```bash
# Install Ops Agent (if not already installed)
curl -sSO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh
sudo bash add-google-cloud-ops-agent-repo.sh --also-install

# Configure agent to tail the health check log
sudo tee /etc/google-cloud-ops-agent/config.yaml > /dev/null << 'EOF'
logging:
  receivers:
    syslog:
      type: files
      include_paths:
        - /var/log/messages
        - /var/log/syslog
    health_check:
      type: files
      include_paths:
        - /var/log/health_check/results.log
  service:
    pipelines:
      default_pipeline:
        receivers: [syslog]
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
```

### Step 7 — Push a Custom Metric (Optional Advanced)

```bash
# Create a wrapper that pushes disk usage as a custom metric
sudo tee /opt/scripts/push_disk_metric.sh > /dev/null << 'METRIC_SCRIPT'
#!/bin/bash
# Push root disk usage percentage as a custom metric
DISK_PCT=$(df / | tail -1 | awk '{print $5}' | tr -d '%')
PROJECT_ID=$(curl -sH "Metadata-Flavor: Google" \
    http://metadata.google.internal/computeMetadata/v1/project/project-id)
INSTANCE_ID=$(curl -sH "Metadata-Flavor: Google" \
    http://metadata.google.internal/computeMetadata/v1/instance/id)
ZONE=$(curl -sH "Metadata-Flavor: Google" \
    http://metadata.google.internal/computeMetadata/v1/instance/zone | awk -F/ '{print $NF}')

# Create the time series data
NOW=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

cat > /tmp/ts_data.json << JSONEOF
{
  "timeSeries": [
    {
      "metric": {
        "type": "custom.googleapis.com/health/disk_root_percent"
      },
      "resource": {
        "type": "gce_instance",
        "labels": {
          "instance_id": "$INSTANCE_ID",
          "zone": "$ZONE",
          "project_id": "$PROJECT_ID"
        }
      },
      "points": [
        {
          "interval": { "endTime": "$NOW" },
          "value": { "doubleValue": $DISK_PCT }
        }
      ]
    }
  ]
}
JSONEOF

# Push via REST API using instance metadata token
TOKEN=$(curl -sH "Metadata-Flavor: Google" \
    http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token | \
    python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

curl -s -X POST \
    "https://monitoring.googleapis.com/v3/projects/$PROJECT_ID/timeSeries" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d @/tmp/ts_data.json

echo "Pushed disk_root_percent=$DISK_PCT to custom metric"
METRIC_SCRIPT

sudo chmod +x /opt/scripts/push_disk_metric.sh

# Run it
sudo /opt/scripts/push_disk_metric.sh

exit
```

### Step 8 — Verify in Cloud Logging & Monitoring

```bash
# Back on your local machine — check health check logs in Cloud Logging
INSTANCE_ID=$(gcloud compute instances describe health-check-vm \
    --zone=europe-west2-b --format="value(id)")

gcloud logging read \
    "resource.type=\"gce_instance\" AND resource.labels.instance_id=\"$INSTANCE_ID\" AND logName:\"health_check\"" \
    --limit=20 \
    --format="table(timestamp,textPayload)"

# Check the custom metric (if you did Step 7)
gcloud monitoring time-series list \
    --filter="metric.type=\"custom.googleapis.com/health/disk_root_percent\" AND resource.labels.instance_id=\"$INSTANCE_ID\"" \
    --interval-start-time=$(date -u -d '30 minutes ago' '+%Y-%m-%dT%H:%M:%SZ') \
    --limit=5
```

### Cleanup

```bash
# Delete the VM
gcloud compute instances delete health-check-vm --zone=europe-west2-b --quiet
```

---

## Part 3 — Revision (15 min)

### Key Concepts

- Health check scripts fill the gap between Cloud Monitoring auto-metrics and real operational checks
- Standard checks: disk (`df`), memory (`free`), CPU load (`/proc/loadavg`), process (`pgrep`), port (`ss`)
- Follow Nagios exit code convention: 0=OK, 1=WARN, 2=CRIT, 3=UNKNOWN
- Use `cron` for scheduling; redirect output to a log file
- Ops Agent can tail health check logs → appear in Cloud Logging → alertable
- Custom metrics: push arbitrary values via `monitoring.googleapis.com/v3` API
- `set -uo pipefail` for robust scripts; use functions for each check
- `logrotate` for health check log management

### Essential Commands

```bash
# Key check commands
df -h --output=source,pcent,target    # disk space
free -m                                # memory/swap
cat /proc/loadavg                      # CPU load
pgrep -c PROCESS                       # process count
ss -tlnp | grep :PORT                  # port check
curl -s -o /dev/null -w '%{http_code}' URL  # HTTP check

# Cron
sudo crontab -e                        # edit user cron
cat /etc/cron.d/JOBNAME               # system cron file
*/5 * * * * /path/to/script.sh        # every 5 min

# Log rotation
cat /etc/logrotate.d/APPNAME
```

---

## Part 4 — Quiz (15 min)

**Question 1: Your health check script reports `CRITICAL` for nginx being down, but the cron log shows the script ran successfully (exit code 0). What is likely wrong?**

<details>
<summary>Show Answer</summary>

The script is likely **not using the exit code from the check functions**. Common mistake: the script logs "CRITICAL" but always exits 0. Ensure the script tracks an overall status variable and `exit $OVERALL_STATUS` at the end.

Also check:
- Is `set -e` causing early exit before reaching the status logic?
- Is the exit code being swallowed by piping (e.g., `script.sh | tee log` — exit code is from `tee`, not the script; use `set -o pipefail`)
- Cron's `>> log 2>&1` redirect may show success if cron itself ran fine, even if the script exited non-zero

</details>

---

**Question 2: You want to check if port 8080 is listening on a VM. Write the `ss` command and explain how to interpret the output.**

<details>
<summary>Show Answer</summary>

```bash
ss -tlnp | grep ':8080 '
```

Flags:
- `-t` — TCP sockets only
- `-l` — listening sockets only
- `-n` — numeric (no DNS resolution)
- `-p` — show process name

If output is non-empty, the port is listening. If empty, nothing is bound to 8080.

Example output:
```
LISTEN  0  128  0.0.0.0:8080  0.0.0.0:*  users:(("java",pid=12345,fd=10))
```

In a script: `if ss -tlnp | grep -q ':8080 '; then echo "OK"; else echo "CRITICAL"; fi`

</details>

---

**Question 3: Why should you use `set -uo pipefail` at the top of a health check script?**

<details>
<summary>Show Answer</summary>

- **`-u`** (nounset): Treat unset variables as errors. Catches typos like `$DIKS_WARN` instead of `$DISK_WARN`.
- **`-o pipefail`**: Return the exit code of the first failed command in a pipeline. Without this, `failing_cmd | grep something` returns grep's exit code, hiding the failure.

Note: **`-e`** (errexit) is intentionally omitted from health check scripts because you *expect* some commands to return non-zero (e.g., `pgrep` returns 1 when no process is found). If `-e` were set, the script would abort on the first "failed" check instead of reporting all results.

</details>

---

**Question 4: You push a custom metric `custom.googleapis.com/health/disk_root_percent` from your script. How do you create an alert policy for it?**

<details>
<summary>Show Answer</summary>

Create an alert policy with a **metric threshold condition** using your custom metric:

```json
{
  "conditions": [{
    "conditionThreshold": {
      "filter": "metric.type=\"custom.googleapis.com/health/disk_root_percent\" AND resource.type=\"gce_instance\"",
      "comparison": "COMPARISON_GT",
      "thresholdValue": 85,
      "duration": "300s",
      "aggregations": [{
        "alignmentPeriod": "300s",
        "perSeriesAligner": "ALIGN_MEAN"
      }]
    }
  }]
}
```

Custom metrics work exactly like built-in metrics for alerting. The key requirement is that the metric must be consistently pushed (every few minutes) for the alert to evaluate properly. A `metric absence` alert alongside it catches cases where the script stops running.

</details>

---

*End of Day 17 — Tomorrow: Capstone project combining all Week 3 topics.*
