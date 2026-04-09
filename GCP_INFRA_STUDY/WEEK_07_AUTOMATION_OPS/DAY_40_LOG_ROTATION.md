# Day 40 — Log Rotation & Housekeeping

> **Week 7 — Automation & Ops** | ⏱ 2 hours | Region: `europe-west2`

---

## Part 1 — Concept (30 min)

### Why Log Rotation Matters

Every Linux admin has seen it: a VM dies because `/var/log` filled the disk. In cloud, this is even more expensive — you're paying for that disk. Log rotation and housekeeping are essential ops hygiene.

**Linux analogy — you already know this!**

| Concept | On-Prem (Your 6 Years) | Cloud (Same Problem, Same Fix) |
|---|---|---|
| Log rotation | `logrotate` + cron | Same `logrotate` + Cloud Logging |
| Disk alerts | Nagios `check_disk` | Ops Agent + Cloud Monitoring |
| Old file cleanup | `find -mtime +30 -delete` | Same + lifecycle on GCS |
| Temp file cleanup | `tmpwatch` / `systemd-tmpfiles` | Same `systemd-tmpfiles` |

### Logrotate Architecture

```
┌──────────────────────────────────────────────────────────┐
│                  logrotate Flow                          │
│                                                          │
│  /etc/cron.daily/logrotate                               │
│       │                                                  │
│       ▼                                                  │
│  /usr/sbin/logrotate /etc/logrotate.conf                 │
│       │                                                  │
│       ├──► /etc/logrotate.d/nginx                        │
│       │    /var/log/nginx/*.log {                        │
│       │        daily                                     │
│       │        rotate 14                                 │
│       │        compress                                  │
│       │        delaycompress                             │
│       │        missingok                                 │
│       │        notifempty                                │
│       │        postrotate                                │
│       │            systemctl reload nginx                │
│       │        endscript                                 │
│       │    }                                             │
│       │                                                  │
│       ├──► /etc/logrotate.d/syslog                       │
│       │    /var/log/syslog { ... }                       │
│       │                                                  │
│       └──► /etc/logrotate.d/custom-app                   │
│            /var/log/myapp/*.log { ... }                  │
│                                                          │
│  State tracked in: /var/lib/logrotate/status             │
└──────────────────────────────────────────────────────────┘
```

### Logrotate Directives

| Directive | Meaning | Example |
|---|---|---|
| `daily/weekly/monthly` | Rotation frequency | `daily` |
| `rotate N` | Keep N rotated files | `rotate 14` (2 weeks) |
| `compress` | Gzip old logs | Saves 60-90% space |
| `delaycompress` | Don't compress most recent rotated | Helps tail -f |
| `missingok` | Don't error if log file is missing | Prevents cron failures |
| `notifempty` | Skip rotation if file is empty | Avoids empty .gz files |
| `copytruncate` | Truncate original (for apps that hold FD) | When postrotate won't work |
| `postrotate/endscript` | Command to run after rotation | Reload app to reopen files |
| `maxsize 100M` | Rotate if size exceeds threshold | Regardless of schedule |
| `dateext` | Use date in rotated filename | `app.log-20260408.gz` |

### Disk Space Monitoring Strategy

```
┌────────────────────────────────────────────────────┐
│            Disk Space Management                   │
│                                                    │
│  PROACTIVE (before problems):                      │
│  ┌──────────────────────────────────────────────┐  │
│  │  1. logrotate (daily)                        │  │
│  │  2. Cleanup scripts (weekly cron)            │  │
│  │  3. systemd-tmpfiles (automatic)             │  │
│  │  4. GCS lifecycle (for object storage)       │  │
│  └──────────────────────────────────────────────┘  │
│                                                    │
│  REACTIVE (alert and respond):                     │
│  ┌──────────────────────────────────────────────┐  │
│  │  70% → INFO  (housekeeping review)           │  │
│  │  80% → WARN  (run cleanup, plan action)      │  │
│  │  90% → CRIT  (immediate cleanup required)    │  │
│  │  95% → EMERGENCY (app may crash)             │  │
│  └──────────────────────────────────────────────┘  │
│                                                    │
│  AUTOMATED (no human needed):                      │
│  ┌──────────────────────────────────────────────┐  │
│  │  Cron script:                                │  │
│  │  • Delete files older than retention policy  │  │
│  │  • Clean /tmp, /var/cache                    │  │
│  │  • Truncate runaway logs                     │  │
│  │  • Report via Cloud Monitoring               │  │
│  └──────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────┘
```

### Common Housekeeping Targets

| Path | What | Cleanup Strategy |
|---|---|---|
| `/var/log/` | System + app logs | logrotate (daily, keep 14) |
| `/tmp/` | Temporary files | `systemd-tmpfiles` (10 days) |
| `/var/cache/apt/` | Package cache | `apt-get clean` (monthly) |
| `/var/tmp/` | Persistent temp | `systemd-tmpfiles` (30 days) |
| `/home/*/.cache/` | User caches | `find -mtime +30 -delete` |
| `/var/crash/` | Crash dumps | Review + delete (weekly) |
| Core dumps | Application crashes | gzip + archive or delete |

---

## Part 2 — Hands-On Lab (60 min)

### Prerequisites

```bash
export PROJECT_ID=$(gcloud config get-value project)
export ZONE=europe-west2-a
export PREFIX="lab40"
```

### Step 1 — Create a VM with Nginx (Log Generator)

```bash
gcloud compute instances create logrotate-vm-${PREFIX} \
  --zone=${ZONE} \
  --machine-type=e2-small \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --boot-disk-size=10GB \
  --tags=${PREFIX} \
  --metadata=startup-script='#!/bin/bash
apt-get update -qq && apt-get install -y -qq nginx curl
systemctl enable nginx && systemctl start nginx
'

sleep 60
```

### Step 2 — Generate Some Log Data

```bash
gcloud compute ssh logrotate-vm-${PREFIX} --zone=${ZONE} --command="
# Generate traffic to create log entries
for i in \$(seq 1 500); do
  curl -s localhost > /dev/null
  curl -s localhost/nonexistent 2>/dev/null || true
done

# Check log sizes
echo '--- Log sizes ---'
sudo du -sh /var/log/nginx/access.log
sudo du -sh /var/log/nginx/error.log
sudo wc -l /var/log/nginx/access.log /var/log/nginx/error.log

# Create a fake application log
sudo mkdir -p /var/log/myapp
for i in \$(seq 1 1000); do
  echo \"\$(date -Iseconds) INFO  Processing record \${i} - data payload here with some padding to simulate real log entries\" | sudo tee -a /var/log/myapp/app.log > /dev/null
done
sudo du -sh /var/log/myapp/app.log
"
```

### Step 3 — View Existing Logrotate Config

```bash
gcloud compute ssh logrotate-vm-${PREFIX} --zone=${ZONE} --command="
echo '=== Main logrotate config ==='
cat /etc/logrotate.conf

echo ''
echo '=== Nginx logrotate config ==='
cat /etc/logrotate.d/nginx

echo ''
echo '=== All logrotate.d configs ==='
ls -la /etc/logrotate.d/

echo ''
echo '=== Logrotate state ==='
sudo cat /var/lib/logrotate/status
"
```

### Step 4 — Create Custom Logrotate Config

```bash
gcloud compute ssh logrotate-vm-${PREFIX} --zone=${ZONE} --command="
# Configure logrotate for the custom app
sudo tee /etc/logrotate.d/myapp << 'EOF'
/var/log/myapp/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    dateext
    dateformat -%Y%m%d
    maxsize 50M
    create 0640 root adm
    postrotate
        # Signal the application to reopen log files
        # (adjust for your app — e.g., kill -USR1 \$(cat /var/run/myapp.pid))
        true
    endscript
}
EOF

echo '--- Config written ---'
cat /etc/logrotate.d/myapp
"
```

### Step 5 — Test Logrotate (Force Rotation)

```bash
gcloud compute ssh logrotate-vm-${PREFIX} --zone=${ZONE} --command="
echo '=== Before rotation ==='
ls -la /var/log/myapp/

# Force rotation (debug mode first)
echo ''
echo '=== Dry-run (debug) ==='
sudo logrotate -d /etc/logrotate.d/myapp

# Actually rotate
echo ''
echo '=== Executing rotation ==='
sudo logrotate -f /etc/logrotate.d/myapp

echo ''
echo '=== After rotation ==='
ls -la /var/log/myapp/

# Run again to see compress kick in
# (First rotated file stays uncompressed due to delaycompress)
# Generate more data
for i in \$(seq 1 500); do
  echo \"\$(date -Iseconds) INFO  More data \${i}\" | sudo tee -a /var/log/myapp/app.log > /dev/null
done
sudo logrotate -f /etc/logrotate.d/myapp

echo ''
echo '=== After second rotation ==='
ls -la /var/log/myapp/
"
```

### Step 6 — Write a Cleanup Script

```bash
gcloud compute ssh logrotate-vm-${PREFIX} --zone=${ZONE} --command="
sudo tee /opt/disk-cleanup.sh << 'CLEANUP_EOF'
#!/bin/bash
#
# Disk Cleanup / Housekeeping Script
# Run weekly via cron
#
set -euo pipefail

LOG='/var/log/disk-cleanup.log'
TIMESTAMP=\$(date -Iseconds)

echo \"=== Cleanup Start: \${TIMESTAMP} ===\" >> \${LOG}

# Record disk usage before cleanup
BEFORE=\$(df / | tail -1 | awk '{print \$5}')

# 1. Clean apt cache
echo \"  [1] Cleaning apt cache...\" >> \${LOG}
apt-get clean -qq
apt-get autoremove -y -qq >> \${LOG} 2>&1

# 2. Clean old temp files (older than 7 days)
echo \"  [2] Cleaning /tmp (>7 days)...\" >> \${LOG}
find /tmp -type f -mtime +7 -not -name '.*' -delete 2>/dev/null || true
find /var/tmp -type f -mtime +30 -delete 2>/dev/null || true

# 3. Clean old log files not managed by logrotate
echo \"  [3] Cleaning old unmanaged logs...\" >> \${LOG}
find /var/log -name '*.gz' -mtime +30 -delete 2>/dev/null || true
find /var/log -name '*.old' -mtime +14 -delete 2>/dev/null || true
find /var/log -name '*.[0-9]' -mtime +14 -delete 2>/dev/null || true

# 4. Clean old core dumps
echo \"  [4] Cleaning core dumps...\" >> \${LOG}
find / -maxdepth 3 -name 'core.*' -mtime +7 -delete 2>/dev/null || true

# 5. Remove old kernels (keep current + 1 previous)
# echo \"  [5] Removing old kernels...\" >> \${LOG}
# apt-get autoremove --purge -y >> \${LOG} 2>&1

# 6. Truncate oversized logs (>500MB) that might not be rotated
echo \"  [6] Checking for oversized logs...\" >> \${LOG}
find /var/log -name '*.log' -size +500M -exec sh -c '
  echo "  TRUNCATING: {} (\$(du -sh {} | cut -f1))" >> /var/log/disk-cleanup.log
  > {}
' \;

# Record disk usage after cleanup
AFTER=\$(df / | tail -1 | awk '{print \$5}')

echo \"  Disk before: \${BEFORE}, after: \${AFTER}\" >> \${LOG}
echo \"=== Cleanup End: \$(date -Iseconds) ===\" >> \${LOG}
echo \"\" >> \${LOG}
CLEANUP_EOF

sudo chmod +x /opt/disk-cleanup.sh
echo 'Cleanup script created'
"
```

### Step 7 — Test the Cleanup Script

```bash
gcloud compute ssh logrotate-vm-${PREFIX} --zone=${ZONE} --command="
echo '=== Disk usage before cleanup ==='
df -h /

# Create some junk to clean
sudo dd if=/dev/zero of=/tmp/old-file bs=1M count=10 2>/dev/null
sudo touch -d '2026-03-01' /tmp/old-file  # Make it 30+ days old
sudo dd if=/dev/zero of=/var/tmp/old-temp bs=1M count=5 2>/dev/null
sudo touch -d '2026-02-01' /var/tmp/old-temp

# Run cleanup
sudo /opt/disk-cleanup.sh

echo ''
echo '=== Disk usage after cleanup ==='
df -h /

echo ''
echo '=== Cleanup log ==='
cat /var/log/disk-cleanup.log
"
```

### Step 8 — Schedule with Cron

```bash
gcloud compute ssh logrotate-vm-${PREFIX} --zone=${ZONE} --command="
# Weekly cleanup — Sunday at 03:00
sudo tee /etc/cron.d/disk-cleanup << 'CRON_EOF'
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Weekly disk cleanup — every Sunday at 03:00
0 3 * * 0 root /opt/disk-cleanup.sh >> /var/log/disk-cleanup-cron.log 2>&1
CRON_EOF

sudo chmod 644 /etc/cron.d/disk-cleanup

echo '=== Scheduled cron jobs ==='
cat /etc/cron.d/disk-cleanup
echo ''
echo '=== All cron.d entries ==='
ls -la /etc/cron.d/
"
```

### Step 9 — Monitor Disk Space with Script

```bash
gcloud compute ssh logrotate-vm-${PREFIX} --zone=${ZONE} --command="
sudo tee /opt/disk-check.sh << 'DISKCHECK_EOF'
#!/bin/bash
THRESHOLD_WARN=70
THRESHOLD_CRIT=90

while IFS= read -r line; do
    USAGE=\$(echo \"\$line\" | awk '{print \$5}' | tr -d '%')
    MOUNT=\$(echo \"\$line\" | awk '{print \$6}')
    
    if [ \"\$USAGE\" -ge \"\$THRESHOLD_CRIT\" ]; then
        echo \"CRITICAL: \${MOUNT} at \${USAGE}% (threshold: \${THRESHOLD_CRIT}%)\"
    elif [ \"\$USAGE\" -ge \"\$THRESHOLD_WARN\" ]; then
        echo \"WARNING:  \${MOUNT} at \${USAGE}% (threshold: \${THRESHOLD_WARN}%)\"
    else
        echo \"OK:       \${MOUNT} at \${USAGE}%\"
    fi
done < <(df -h --output=pcent,target | tail -n +2)
DISKCHECK_EOF

sudo chmod +x /opt/disk-check.sh
sudo /opt/disk-check.sh
"
```

### Cleanup

```bash
gcloud compute instances delete logrotate-vm-${PREFIX} --zone=${ZONE} --quiet
```

---

## Part 3 — Revision (15 min)

### Key Concepts

- **logrotate** is the standard Linux log rotation tool — already in most distros
- Config at `/etc/logrotate.conf` + drop-ins at `/etc/logrotate.d/`
- Key directives: `daily`, `rotate N`, `compress`, `delaycompress`, `maxsize`, `postrotate`
- **Housekeeping scripts** handle what logrotate doesn't: /tmp, caches, core dumps
- Schedule cleanup with **cron** (weekly or daily)
- Monitor disk space with thresholds: 70% warn, 90% critical

### Essential Commands

```bash
# Logrotate
logrotate -d /etc/logrotate.d/myapp          # Dry run (debug)
logrotate -f /etc/logrotate.d/myapp          # Force rotation
cat /var/lib/logrotate/status                 # View state

# Disk usage
df -h                                         # Filesystem usage
du -sh /var/log/*                             # Directory sizes
find /var/log -name '*.gz' -mtime +30         # Old compressed logs

# Cleanup
find /tmp -type f -mtime +7 -delete           # Delete old temp files
apt-get clean                                  # Clear apt cache
apt-get autoremove -y                          # Remove unused packages

# Cron (system-level)
cat > /etc/cron.d/cleanup << 'EOF'
0 3 * * 0 root /opt/cleanup.sh >> /var/log/cleanup.log 2>&1
EOF
chmod 644 /etc/cron.d/cleanup
```

---

## Part 4 — Quiz (15 min)

<details>
<summary><strong>Q1: An application writes to `/var/log/myapp/app.log` but holds the file descriptor open. After logrotate runs, the old file keeps growing. Why, and how do you fix it?</strong></summary>

**Answer:** The application opened the log file and holds the **file descriptor (FD)**. When logrotate renames the file (e.g., `app.log` → `app.log.1`), the app still writes to the same FD, which now points to `app.log.1`. The new empty `app.log` gets no writes.

**Fixes (choose one):**

1. **`postrotate` signal:** Send the app a signal to reopen its log file:
   ```
   postrotate
       kill -USR1 $(cat /var/run/myapp.pid)
   endscript
   ```

2. **`copytruncate`:** Instead of renaming, copy the file then truncate the original. The app's FD stays valid:
   ```
   /var/log/myapp/*.log {
       copytruncate
       ...
   }
   ```
   **Downside:** Tiny window where log lines can be lost between copy and truncate.

3. **Application fix:** Configure the app to use a logging library that auto-reopens files (e.g., Python's `WatchedFileHandler`).
</details>

<details>
<summary><strong>Q2: What's the difference between `compress` and `delaycompress`? When would you use both?</strong></summary>

**Answer:**

- **`compress`** — gzip rotated files to save space
- **`delaycompress`** — don't compress the most recently rotated file (compress it on the NEXT rotation)

**Why use both together?** The most recently rotated file (`app.log.1`) might still be actively tailed by monitoring tools or log shippers. If you compress it immediately, those tools break. `delaycompress` gives them one rotation cycle to finish reading.

```
Rotation 1: app.log → app.log.1 (uncompressed — being tailed)
Rotation 2: app.log.1 → app.log.2.gz (now compressed)
            app.log → app.log.1 (uncompressed — being tailed)
```

**Best practice:** Always pair `compress` with `delaycompress` unless the log is written by a tool that never holds FDs.
</details>

<details>
<summary><strong>Q3: Your VM runs out of disk space at 3 AM. The on-call engineer sees `/var/log/myapp/debug.log` is 45 GB. What's the fastest safe fix, and how do you prevent recurrence?</strong></summary>

**Answer:**

**Immediate fix (fastest, safe):**
```bash
# Truncate the file (keeps FD valid, frees space immediately)
> /var/log/myapp/debug.log
# OR
truncate -s 0 /var/log/myapp/debug.log
```

**DO NOT:** `rm /var/log/myapp/debug.log` — if the app holds the FD, space isn't freed until the app releases it. You'd need to restart the app to free space.

**Prevent recurrence:**
1. Add logrotate config with `maxsize 100M`:
   ```
   /var/log/myapp/debug.log {
       daily
       rotate 3
       compress
       maxsize 100M
       copytruncate
   }
   ```
2. Add disk monitoring alert at 80%
3. Review if debug-level logging is appropriate for production
4. Consider sending logs to Cloud Logging instead of local disk
</details>

<details>
<summary><strong>Q4: You have 20 VMs, each generating logs. How do you ensure consistent log rotation and housekeeping across all of them?</strong></summary>

**Answer:**

1. **Bake into golden image:**
   - Include logrotate configs in `/etc/logrotate.d/`
   - Include cleanup script in `/opt/`
   - Include cron job in `/etc/cron.d/`
   - All VMs from the golden image get identical config

2. **Startup script (supplementary):**
   - Download latest configs from GCS on boot
   - Handles updates without rebuilding the image

3. **Cloud Logging (centralize):**
   - Install Ops Agent on all VMs
   - Ship logs to Cloud Logging (no local storage concerns)
   - Set Cloud Logging retention policies and export to GCS for archival

4. **Fleet monitoring:**
   - Cloud Monitoring alert on disk usage > 80% for all VMs
   - Custom metric from monitoring script (Day 39) tracks disk usage
   - Dashboard showing disk usage across all VMs

5. **OS Config Agent:**
   - GCP's native configuration management
   - Push logrotate configs to all VMs in a project/folder
</details>
