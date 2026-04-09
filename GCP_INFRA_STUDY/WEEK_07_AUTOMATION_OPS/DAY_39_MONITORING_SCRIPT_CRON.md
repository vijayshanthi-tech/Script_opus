# Day 39 — Monitoring Script & Cron

> **Week 7 — Automation & Ops** | ⏱ 2 hours | Region: `europe-west2`

---

## Part 1 — Concept (30 min)

### Custom Monitoring — Why Go Beyond Cloud Monitoring?

Cloud Monitoring's Ops Agent covers standard metrics (CPU, memory, disk). But infrastructure teams often need **custom checks**: application-specific health, file counts, queue depths, certificate expiry.

**Linux analogy:**

| Linux/Nagios | GCP Equivalent |
|---|---|
| Custom Nagios plugin | Monitoring script + custom metric |
| `/etc/cron.d/` | cron on the VM (or Cloud Scheduler) |
| Nagios NRPE agent | Ops Agent + custom metrics |
| `/var/log/nagios/` | Cloud Logging |
| Email alerts | Cloud Monitoring alert policies |
| `check_disk -w 80 -c 90` | Custom script + uptime check |

### Architecture

```
┌──────────────────────────────────────────────────────────┐
│             Custom Monitoring Architecture                │
│                                                          │
│  ┌─────────────────────────────────────────────────────┐ │
│  │                    VM Instance                       │ │
│  │                                                     │ │
│  │  ┌──────────────────┐    ┌─────────────────────┐    │ │
│  │  │  monitor.sh      │    │  /var/log/           │    │ │
│  │  │  (custom script) │──►│  monitor.log         │    │ │
│  │  │                  │    └─────────────────────┘    │ │
│  │  │  Checks:         │                               │ │
│  │  │  • Disk usage    │    ┌─────────────────────┐    │ │
│  │  │  • Memory        │──►│  Cloud Monitoring    │    │ │
│  │  │  • CPU load      │    │  Custom Metrics     │    │ │
│  │  │  • App health    │    └────────┬────────────┘    │ │
│  │  └──────────────────┘             │                 │ │
│  │           ▲                        │                 │ │
│  │           │ cron (every 5 min)     │                 │ │
│  │  ┌────────┴─────────┐             │                 │ │
│  │  │   /etc/cron.d/   │             │                 │ │
│  │  │   monitoring     │             │                 │ │
│  │  └──────────────────┘             │                 │ │
│  └───────────────────────────────────┼─────────────────┘ │
│                                      │                   │
│                                      ▼                   │
│  ┌─────────────────────────────────────────────────────┐ │
│  │             Cloud Monitoring                         │ │
│  │  ┌──────────┐  ┌──────────────┐  ┌──────────────┐  │ │
│  │  │ Metrics  │  │ Alert Policy │  │ Notification │  │ │
│  │  │ Explorer │  │ (threshold)  │──│ Channel      │  │ │
│  │  └──────────┘  └──────────────┘  └──────────────┘  │ │
│  └─────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────┘
```

### Cron Refresher

```
┌─────────────────────── minute (0-59)
│  ┌──────────────────── hour (0-23)
│  │  ┌───────────────── day of month (1-31)
│  │  │  ┌────────────── month (1-12)
│  │  │  │  ┌─────────── day of week (0-7, 0=Sun)
│  │  │  │  │
*  *  *  *  *  command

# Examples:
*/5  *  *  *  *    # Every 5 minutes
0    */1 *  *  *   # Every hour on the hour
0    2   *  *  *   # Daily at 02:00
0    0   *  *  0   # Every Sunday at midnight
30   6   1  *  *   # 1st of each month at 06:30
```

### Custom Metrics Concepts

Custom metrics let you push **your own data** into Cloud Monitoring:

| Concept | Description |
|---|---|
| **Metric descriptor** | Definition (name, type, labels) |
| **Time series** | Data points over time for one metric |
| **Metric type** | `custom.googleapis.com/your/metric/name` |
| **Value type** | INT64, DOUBLE, BOOL, STRING |
| **Metric kind** | GAUGE (current value), CUMULATIVE, DELTA |

```
  custom.googleapis.com/disk/usage_percent
  ┌──────────────────────────────────────────┐
  │  Value: 73.5 (DOUBLE, GAUGE)             │
  │  Labels:                                 │
  │    instance: web-server-01               │
  │    mount_point: /mnt/data                │
  │  Timestamp: 2026-04-08T14:30:00Z         │
  └──────────────────────────────────────────┘
```

---

## Part 2 — Hands-On Lab (60 min)

### Prerequisites

```bash
export PROJECT_ID=$(gcloud config get-value project)
export ZONE=europe-west2-a
export REGION=europe-west2
export PREFIX="lab39"
```

### Step 1 — Create a VM for Monitoring

```bash
gcloud compute instances create monitor-vm-${PREFIX} \
  --zone=${ZONE} \
  --machine-type=e2-small \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --boot-disk-size=10GB \
  --tags=${PREFIX} \
  --scopes=monitoring-write,logging-write \
  --metadata=startup-script='#!/bin/bash
apt-get update -qq
apt-get install -y -qq curl jq bc stress-ng
'

sleep 60
```

### Step 2 — Write the Monitoring Script

```bash
gcloud compute ssh monitor-vm-${PREFIX} --zone=${ZONE} --command="
sudo tee /opt/monitor.sh << 'SCRIPT_EOF'
#!/bin/bash
#
# System Monitoring Script
# Logs to file + sends custom metrics to Cloud Monitoring
#
set -euo pipefail

LOG='/var/log/monitor.log'
TIMESTAMP=\$(date -Iseconds)
HOSTNAME=\$(hostname)
INSTANCE_ID=\$(curl -s -H 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/instance/id)
ZONE=\$(curl -s -H 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/instance/zone | rev | cut -d/ -f1 | rev)
PROJECT=\$(curl -s -H 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/project/project-id)

# ─────────────────────────────────────
# Collect Metrics
# ─────────────────────────────────────

# Disk usage (root filesystem)
DISK_USAGE=\$(df / | tail -1 | awk '{print \$5}' | tr -d '%')

# Memory usage
MEM_TOTAL=\$(free -m | awk '/Mem:/{print \$2}')
MEM_USED=\$(free -m | awk '/Mem:/{print \$3}')
MEM_PERCENT=\$(echo \"scale=1; \${MEM_USED}*100/\${MEM_TOTAL}\" | bc)

# CPU load (1 minute average)
CPU_LOAD=\$(cat /proc/loadavg | awk '{print \$1}')
CPU_CORES=\$(nproc)
CPU_PERCENT=\$(echo \"scale=1; \${CPU_LOAD}*100/\${CPU_CORES}\" | bc)

# Uptime in hours
UPTIME_HOURS=\$(awk '{printf \"%.1f\", \$1/3600}' /proc/uptime)

# ─────────────────────────────────────
# Log to File
# ─────────────────────────────────────
echo \"\${TIMESTAMP} | host=\${HOSTNAME} | disk=\${DISK_USAGE}% | mem=\${MEM_PERCENT}% | cpu=\${CPU_PERCENT}% | uptime=\${UPTIME_HOURS}h\" >> \${LOG}

# ─────────────────────────────────────
# Alert Conditions (log warnings)
# ─────────────────────────────────────
if [ \${DISK_USAGE} -ge 80 ]; then
    echo \"\${TIMESTAMP} | WARNING: Disk usage at \${DISK_USAGE}% (threshold: 80%)\" >> \${LOG}
fi

if [ \$(echo \"\${MEM_PERCENT} >= 90\" | bc -l) -eq 1 ]; then
    echo \"\${TIMESTAMP} | WARNING: Memory usage at \${MEM_PERCENT}% (threshold: 90%)\" >> \${LOG}
fi

# ─────────────────────────────────────
# Send Custom Metric to Cloud Monitoring
# ─────────────────────────────────────
send_metric() {
    local METRIC_TYPE=\"\$1\"
    local VALUE=\"\$2\"

    ACCESS_TOKEN=\$(curl -s -H 'Metadata-Flavor: Google' \
        http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token | jq -r '.access_token')

    NOW=\$(date -u +%Y-%m-%dT%H:%M:%SZ)

    curl -s -X POST \
        \"https://monitoring.googleapis.com/v3/projects/\${PROJECT}/timeSeries\" \
        -H \"Authorization: Bearer \${ACCESS_TOKEN}\" \
        -H \"Content-Type: application/json\" \
        -d \"{
            \\\"timeSeries\\\": [{
                \\\"metric\\\": {
                    \\\"type\\\": \\\"custom.googleapis.com/\${METRIC_TYPE}\\\",
                    \\\"labels\\\": {
                        \\\"instance_name\\\": \\\"\${HOSTNAME}\\\"
                    }
                },
                \\\"resource\\\": {
                    \\\"type\\\": \\\"gce_instance\\\",
                    \\\"labels\\\": {
                        \\\"instance_id\\\": \\\"\${INSTANCE_ID}\\\",
                        \\\"zone\\\": \\\"\${ZONE}\\\",
                        \\\"project_id\\\": \\\"\${PROJECT}\\\"
                    }
                },
                \\\"points\\\": [{
                    \\\"interval\\\": {\\\"endTime\\\": \\\"\${NOW}\\\"},
                    \\\"value\\\": {\\\"doubleValue\\\": \${VALUE}}
                }]
            }]
        }\" > /dev/null 2>&1
}

send_metric \"vm/disk_usage_percent\" \"\${DISK_USAGE}\"
send_metric \"vm/memory_usage_percent\" \"\${MEM_PERCENT}\"
send_metric \"vm/cpu_load_percent\" \"\${CPU_PERCENT}\"

echo \"\${TIMESTAMP} | Metrics sent to Cloud Monitoring\" >> \${LOG}
SCRIPT_EOF

sudo chmod +x /opt/monitor.sh
echo 'Script created successfully'
"
```

### Step 3 — Test the Script Manually

```bash
gcloud compute ssh monitor-vm-${PREFIX} --zone=${ZONE} --command="
# Run it once
sudo /opt/monitor.sh

# Check the log
echo '--- Monitor Log ---'
cat /var/log/monitor.log
"
```

### Step 4 — Set Up Cron Job

```bash
gcloud compute ssh monitor-vm-${PREFIX} --zone=${ZONE} --command="
# Create cron job — runs every 5 minutes
sudo tee /etc/cron.d/monitoring << 'CRON_EOF'
# System monitoring — every 5 minutes
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

*/5 * * * * root /opt/monitor.sh >> /var/log/monitor-cron.log 2>&1
CRON_EOF

# Set correct permissions
sudo chmod 644 /etc/cron.d/monitoring

# Verify cron is running
sudo systemctl status cron --no-pager
echo '--- Cron jobs ---'
sudo crontab -l -u root 2>/dev/null || echo 'No root crontab'
echo '--- Cron.d files ---'
ls -la /etc/cron.d/
echo '--- monitoring cron ---'
cat /etc/cron.d/monitoring
"
```

### Step 5 — Generate Load and Observe

```bash
# Generate some CPU load
gcloud compute ssh monitor-vm-${PREFIX} --zone=${ZONE} --command="
# Stress for 60 seconds (2 CPU workers)
stress-ng --cpu 2 --timeout 60 &

# Run monitor while stress is active
sleep 5
sudo /opt/monitor.sh

echo '--- Latest log entries ---'
tail -5 /var/log/monitor.log
"

# Wait a few minutes, then check that cron produced output
sleep 360  # Wait 6 minutes for at least one cron execution

gcloud compute ssh monitor-vm-${PREFIX} --zone=${ZONE} --command="
echo '--- Cron output ---'
cat /var/log/monitor-cron.log 2>/dev/null || echo 'No cron output yet'
echo '--- Monitor log (last 10) ---'
tail -10 /var/log/monitor.log
"
```

### Step 6 — Verify Custom Metrics in Cloud Monitoring

```bash
# List custom metrics
gcloud monitoring metrics list \
  --filter="metric.type=starts_with(\"custom.googleapis.com/vm/\")" \
  --format="table(type,displayName)"

# Query recent data points for disk usage
gcloud monitoring time-series list \
  --filter="metric.type=\"custom.googleapis.com/vm/disk_usage_percent\"" \
  --start-time="$(date -u -d '-1 hour' +%Y-%m-%dT%H:%M:%SZ)" \
  --end-time="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --format="table(points.value.doubleValue,points.interval.endTime)"
```

### Cleanup

```bash
# Delete VM
gcloud compute instances delete monitor-vm-${PREFIX} --zone=${ZONE} --quiet

# Delete custom metric descriptors (optional)
for metric in disk_usage_percent memory_usage_percent cpu_load_percent; do
  gcloud monitoring metrics-descriptors delete \
    "custom.googleapis.com/vm/${metric}" --quiet 2>/dev/null
done
```

---

## Part 3 — Revision (15 min)

### Key Concepts

- **Custom monitoring scripts** fill gaps that standard agents don't cover
- **Cron** schedules script execution — use `/etc/cron.d/` for system scripts
- **Custom metrics** push data to Cloud Monitoring via the REST API
- Always log to a file AND send to Cloud Monitoring (local fallback)
- Include **alert conditions** in the script (threshold checks)
- Use `scopes=monitoring-write,logging-write` on the VM for API access

### Essential Commands

```bash
# Cron (system-level)
cat > /etc/cron.d/monitoring << 'EOF'
*/5 * * * * root /opt/monitor.sh >> /var/log/cron.log 2>&1
EOF
chmod 644 /etc/cron.d/monitoring

# Disk/memory/CPU checks
df / | tail -1 | awk '{print $5}' | tr -d '%'       # Disk %
free -m | awk '/Mem:/{print $3*100/$2}'               # Memory %
cat /proc/loadavg | awk '{print $1}'                  # CPU load

# Cloud Monitoring custom metrics
gcloud monitoring metrics list --filter="metric.type=starts_with(\"custom.googleapis.com/\")"

# Stress testing
stress-ng --cpu 2 --timeout 60
stress-ng --vm 1 --vm-bytes 256M --timeout 60
```

---

## Part 4 — Quiz (15 min)

<details>
<summary><strong>Q1: Your monitoring script runs via cron every 5 minutes, but you notice gaps in the data. What are the likely causes?</strong></summary>

**Answer:**

1. **Script error** — the script crashes silently. Fix: add `set -euo pipefail` and redirect stderr to the log file (`2>&1`)
2. **Cron permissions** — the cron.d file has wrong permissions (must be 644, owned by root) or wrong format
3. **API throttling** — too many custom metric writes. Cloud Monitoring has quotas.
4. **Network issue** — the metadata server or monitoring API is temporarily unreachable
5. **Time sync** — VM clock drift causes out-of-order timestamps, which the API may reject

**Debugging:**
```bash
# Check cron actually ran
grep CRON /var/log/syslog | tail -10
# Check script stderr
cat /var/log/monitor-cron.log
# Test script manually
sudo /opt/monitor.sh
```
</details>

<details>
<summary><strong>Q2: Should you use cron on the VM or Cloud Scheduler for running monitoring scripts? What are the trade-offs?</strong></summary>

**Answer:**

| Aspect | VM Cron | Cloud Scheduler |
|---|---|---|
| **Scope** | Single VM | Project-wide |
| **Survives VM delete** | No | Yes |
| **Can trigger external** | No (local only) | Yes (HTTP, Pub/Sub, App Engine) |
| **Observability** | Check syslog | Cloud Console, logs |
| **Complexity** | Simple | Requires target (Cloud Function, etc.) |
| **Best for** | Per-VM local checks | Centralized scheduled tasks |

**Use cron** for local VM checks (disk, memory, processes). **Use Cloud Scheduler** for fleet-wide tasks that should survive VM replacement, like triggering a Cloud Function to scan all VMs.
</details>

<details>
<summary><strong>Q3: You need to monitor 50 VMs with the same script. How do you deploy the monitoring cron job consistently?</strong></summary>

**Answer:**

1. **Bake into golden image:**
   - Include `/opt/monitor.sh` and `/etc/cron.d/monitoring` in the golden image build
   - Every VM from the image gets monitoring automatically

2. **Startup script:**
   ```bash
   gcloud compute project-info add-metadata \
     --metadata=startup-script-url=gs://bucket/deploy-monitoring.sh
   ```
   - Downloads and installs the monitoring script on every boot

3. **Instance template + MIG:**
   - Template includes the monitoring startup script
   - All MIG instances get it automatically

4. **Configuration management (advanced):**
   - Ansible/Puppet/Chef to push scripts to existing VMs
   - OS Config Agent (GCP-native) for patch/config management
</details>

<details>
<summary><strong>Q4: What's the maximum frequency you should push custom metrics to Cloud Monitoring, and why?</strong></summary>

**Answer:**

**Recommended minimum interval: 60 seconds (1 minute)**

- Cloud Monitoring's resolution for custom metrics is 1 minute
- Pushing more frequently than once per minute results in data points being **overwritten** (only the latest per minute is stored)
- Every 5 minutes is a practical default for most infrastructure monitoring
- Every 1 minute is appropriate for critical services (databases, SLA-bound apps)

**Quota considerations:**
- Custom metric write limit: 200 time series per request
- Project-level quota: ~6,000 write requests per minute
- 50 VMs × 3 metrics × 1/min = 150 writes/min = well within quota

**Cost:** Custom metrics are charged per metric descriptor and per million ingested data points. Be selective about what you monitor.
</details>
