# Day 37 — Startup Scripts & Cloud-Init

> **Week 7 — Automation & Ops** | ⏱ 2 hours | Region: `europe-west2`

---

## Part 1 — Concept (30 min)

### Startup Scripts — VM Bootstrap Automation

When a Compute Engine VM boots, it can execute a **startup script** automatically — like a cloud-native version of `/etc/rc.local` or a systemd unit that runs once.

**Linux analogy:**

| Linux Concept | GCP Equivalent |
|---|---|
| `/etc/rc.local` | `startup-script` metadata |
| systemd `ExecStartPre=` | Startup script runs before you SSH in |
| User-data (cloud-init) | `user-data` metadata key |
| `/etc/init.d/` scripts | Startup script + shutdown script |
| Downloading from NFS at boot | `startup-script-url` (loads from GCS) |

### How Startup Scripts Work

```
┌────────────────────────────────────────────────────────────┐
│                 VM Boot Sequence                           │
│                                                            │
│  1. Hypervisor creates VM                                  │
│  2. BIOS/UEFI → GRUB → Kernel boots                       │
│  3. systemd starts services                                │
│  4. Guest Agent starts                                     │
│  5. Guest Agent reads metadata:                            │
│     ┌──────────────────────────────────────────────────┐   │
│     │  http://metadata.google.internal/computeMetadata/ │   │
│     │    v1/instance/attributes/startup-script          │   │
│     └──────────────────────────────────────────────────┘   │
│  6. Script executes as ROOT                                │
│  7. Output goes to:                                        │
│     - Serial port 1 (console output)                       │
│     - /var/log/syslog (or journalctl)                      │
│  8. VM is "running" regardless of script success/failure   │
│                                                            │
│  Key: VM status = RUNNING ≠ script completed               │
└────────────────────────────────────────────────────────────┘
```

### Metadata Keys

| Key | Purpose | Size Limit |
|---|---|---|
| `startup-script` | Inline bash script | 256 KB |
| `startup-script-url` | URL to script (GCS recommended) | Script file unlimited |
| `shutdown-script` | Runs on VM stop/delete (best-effort) | 256 KB |
| `shutdown-script-url` | URL to shutdown script | Script file unlimited |
| `user-data` | Cloud-init format (if supported) | 256 KB |

### Execution Order

```
┌─────────────────────────────────────────────────┐
│          Script Execution Order                 │
│                                                 │
│  ON BOOT:                                       │
│  ┌─────────────────────────────────────────┐    │
│  │  1. startup-script-url (downloaded)     │    │
│  │  2. startup-script (inline metadata)    │    │
│  │     (Only ONE runs — url takes          │    │
│  │      priority if both are set)          │    │
│  └─────────────────────────────────────────┘    │
│                                                 │
│  ON STOP / DELETE:                              │
│  ┌─────────────────────────────────────────┐    │
│  │  1. shutdown-script-url (downloaded)    │    │
│  │  2. shutdown-script (inline metadata)   │    │
│  │     Best-effort: ~90 seconds max        │    │
│  │     (preemptible VMs: ~30 seconds)      │    │
│  └─────────────────────────────────────────┘    │
│                                                 │
│  RE-RUNS:                                       │
│  Startup script runs on EVERY boot              │
│  (not just first boot — unlike cloud-init)      │
└─────────────────────────────────────────────────┘
```

### Cloud-Init

Cloud-init is the **industry standard** for VM initialisation on Linux. GCP supports it on some images (Ubuntu, COS).

```
┌────────────────────────────────────────────────┐
│           cloud-init vs startup-script         │
│                                                │
│  cloud-init:                                   │
│  + Runs only on FIRST boot (by default)        │
│  + Declarative YAML format                     │
│  + Handles users, packages, files, runcmd      │
│  + Cross-cloud portable                        │
│  - Not all GCP images support it               │
│                                                │
│  startup-script:                               │
│  + Works on ALL GCP images                     │
│  + Runs on EVERY boot                          │
│  + Imperative bash (flexibility)               │
│  - Must handle idempotency yourself            │
│  - GCP-specific                                │
└────────────────────────────────────────────────┘
```

### Debugging Startup Scripts

```
┌──────────────────────────────────────────────────────┐
│            Debugging Methods                         │
│                                                      │
│  1. Serial Console Output:                           │
│     gcloud compute instances get-serial-port-output  │
│     VM --zone=ZONE                                   │
│                                                      │
│  2. SSH and check logs:                              │
│     journalctl -u google-startup-scripts.service     │
│     cat /var/log/syslog | grep startup               │
│                                                      │
│  3. Check metadata:                                  │
│     curl -H "Metadata-Flavor: Google" \              │
│       http://metadata.google.internal/               │
│       computeMetadata/v1/instance/                   │
│       attributes/startup-script                      │
│                                                      │
│  4. Re-run manually:                                 │
│     sudo google_metadata_script_runner startup       │
│                                                      │
│  5. Check exit code in serial output:                │
│     Look for "startup-script exit status"            │
└──────────────────────────────────────────────────────┘
```

---

## Part 2 — Hands-On Lab (60 min)

### Prerequisites

```bash
export PROJECT_ID=$(gcloud config get-value project)
export ZONE=europe-west2-a
export REGION=europe-west2
export PREFIX="lab37"
```

### Step 1 — VM with Inline Startup Script

```bash
# Create VM with a complex startup script
gcloud compute instances create startup-inline-${PREFIX} \
  --zone=${ZONE} \
  --machine-type=e2-micro \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --tags=${PREFIX} \
  --metadata=startup-script='#!/bin/bash
set -euo pipefail

LOG="/var/log/startup-script-custom.log"
exec > >(tee -a "$LOG") 2>&1

echo "=== Startup Script Begin: $(date) ==="
echo "Hostname: $(hostname)"
echo "Instance: $(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/name)"

# Update packages
apt-get update -qq
apt-get install -y -qq nginx curl jq htop

# Configure nginx
cat > /var/www/html/index.html << INNEREOF
<!DOCTYPE html>
<html>
<body>
<h1>Server: $(hostname)</h1>
<p>Built: $(date)</p>
<p>Region: $(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/zone | cut -d/ -f4)</p>
</body>
</html>
INNEREOF

systemctl enable nginx
systemctl restart nginx

# Create a marker file so we know the script ran
touch /tmp/startup-complete
echo "=== Startup Script End: $(date) ==="
'

# Wait for startup to complete
sleep 90

# Check serial output for startup script logs
gcloud compute instances get-serial-port-output startup-inline-${PREFIX} \
  --zone=${ZONE} 2>/dev/null | tail -30

# Verify via SSH
gcloud compute ssh startup-inline-${PREFIX} --zone=${ZONE} --command="
echo '--- Startup log ---'
tail -20 /var/log/startup-script-custom.log
echo '--- Nginx test ---'
curl -s localhost
echo '--- Marker file ---'
ls -la /tmp/startup-complete
"
```

### Step 2 — VM with Script from GCS

```bash
# Create a GCS bucket for scripts
export SCRIPT_BUCKET="${PROJECT_ID}-scripts-${PREFIX}"
gsutil mb -p ${PROJECT_ID} -l ${REGION} -b on gs://${SCRIPT_BUCKET}

# Upload a startup script
cat > /tmp/startup-from-gcs.sh << 'EOF'
#!/bin/bash
set -euo pipefail

LOG="/var/log/startup-gcs.log"
exec > >(tee -a "$LOG") 2>&1

echo "=== GCS Startup Script: $(date) ==="

# Install packages
apt-get update -qq
apt-get install -y -qq nginx prometheus-node-exporter 2>/dev/null || apt-get install -y -qq nginx

# Configure monitoring endpoint
cat > /var/www/html/health << 'HEALTH'
{"status":"healthy","timestamp":"TIMESTAMP"}
HEALTH
sed -i "s/TIMESTAMP/$(date -Iseconds)/" /var/www/html/health

systemctl enable nginx
systemctl restart nginx

echo "=== GCS Startup Complete: $(date) ==="
EOF

gsutil cp /tmp/startup-from-gcs.sh gs://${SCRIPT_BUCKET}/startup.sh

# Create VM pointing to the GCS script
gcloud compute instances create startup-gcs-${PREFIX} \
  --zone=${ZONE} \
  --machine-type=e2-micro \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --tags=${PREFIX} \
  --scopes=storage-ro \
  --metadata=startup-script-url=gs://${SCRIPT_BUCKET}/startup.sh

sleep 90

# Verify
gcloud compute ssh startup-gcs-${PREFIX} --zone=${ZONE} --command="
cat /var/log/startup-gcs.log
curl -s localhost/health
"
```

### Step 3 — Shutdown Script

```bash
# Add a shutdown script to the GCS VM
gcloud compute instances add-metadata startup-gcs-${PREFIX} \
  --zone=${ZONE} \
  --metadata=shutdown-script='#!/bin/bash
echo "$(date) - VM shutting down, flushing data..." >> /var/log/shutdown.log
sync
echo "$(date) - Shutdown script complete" >> /var/log/shutdown.log
'

# Stop the VM to trigger shutdown script
gcloud compute instances stop startup-gcs-${PREFIX} --zone=${ZONE}

# Start it back up and check the log
gcloud compute instances start startup-gcs-${PREFIX} --zone=${ZONE}
sleep 60

gcloud compute ssh startup-gcs-${PREFIX} --zone=${ZONE} --command="
cat /var/log/shutdown.log 2>/dev/null || echo 'No shutdown log found'
"
```

### Step 4 — Debug a Failing Startup Script

```bash
# Create a VM with a deliberately broken script
gcloud compute instances create startup-broken-${PREFIX} \
  --zone=${ZONE} \
  --machine-type=e2-micro \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --tags=${PREFIX} \
  --metadata=startup-script='#!/bin/bash
set -euo pipefail
echo "Starting setup..."
apt-get install -y nonexistent-package-12345
echo "This line should NOT appear"
'

sleep 60

# Debug: Check serial output
echo "=== Serial Output ==="
gcloud compute instances get-serial-port-output startup-broken-${PREFIX} \
  --zone=${ZONE} 2>/dev/null | grep -A5 -i "startup-script"

# Debug: Check via SSH
gcloud compute ssh startup-broken-${PREFIX} --zone=${ZONE} --command="
echo '--- journalctl ---'
journalctl -u google-startup-scripts.service --no-pager | tail -20
echo '--- syslog ---'
grep -i startup /var/log/syslog | tail -10
"

# Fix: Update the metadata with a corrected script
gcloud compute instances add-metadata startup-broken-${PREFIX} \
  --zone=${ZONE} \
  --metadata=startup-script='#!/bin/bash
set -euo pipefail
echo "Starting setup (fixed)..."
apt-get update -qq
apt-get install -y -qq curl
echo "Setup complete!"
touch /tmp/fixed-startup-complete
'

# Re-run the startup script manually (without rebooting)
gcloud compute ssh startup-broken-${PREFIX} --zone=${ZONE} --command="
sudo google_metadata_script_runner startup
ls -la /tmp/fixed-startup-complete
"
```

### Step 5 — Cloud-Init (Ubuntu)

```bash
# Create cloud-init config
cat > /tmp/cloud-init.yaml << 'EOF'
#cloud-config
package_update: true
packages:
  - nginx
  - htop
  - curl

write_files:
  - path: /var/www/html/index.html
    content: |
      <h1>Cloud-Init Deployed</h1>
      <p>This server was configured by cloud-init</p>

runcmd:
  - systemctl enable nginx
  - systemctl start nginx
  - echo "cloud-init complete" > /tmp/cloud-init-done

final_message: "Cloud-init setup finished at $TIMESTAMP"
EOF

# Create Ubuntu VM with cloud-init
gcloud compute instances create cloudinit-${PREFIX} \
  --zone=${ZONE} \
  --machine-type=e2-micro \
  --image-family=ubuntu-2204-lts \
  --image-project=ubuntu-os-cloud \
  --tags=${PREFIX} \
  --metadata-from-file=user-data=/tmp/cloud-init.yaml

sleep 120

# Verify cloud-init execution
gcloud compute ssh cloudinit-${PREFIX} --zone=${ZONE} --command="
echo '--- cloud-init status ---'
cloud-init status
echo '--- cloud-init log ---'
tail -20 /var/log/cloud-init-output.log
echo '--- nginx test ---'
curl -s localhost
echo '--- marker ---'
cat /tmp/cloud-init-done 2>/dev/null
"
```

### Cleanup

```bash
# Delete VMs
for vm in startup-inline-${PREFIX} startup-gcs-${PREFIX} startup-broken-${PREFIX} cloudinit-${PREFIX}; do
  gcloud compute instances delete ${vm} --zone=${ZONE} --quiet 2>/dev/null
done

# Delete GCS bucket
gsutil rm -r gs://${SCRIPT_BUCKET} 2>/dev/null

# Clean local files
rm -f /tmp/startup-from-gcs.sh /tmp/cloud-init.yaml
```

---

## Part 3 — Revision (15 min)

### Key Concepts

- **Startup scripts** run on every boot as root — not just first boot
- `startup-script` = inline (256KB limit); `startup-script-url` = from GCS (unlimited)
- **Shutdown scripts** are best-effort (~90s max, ~30s on preemptible)
- **Cloud-init** runs on first boot only, supports YAML config, works on Ubuntu/COS
- Scripts run BEFORE SSH is available — VM status RUNNING ≠ script done
- **Always** make startup scripts idempotent (safe to re-run)

### Essential Commands

```bash
# Create VM with inline startup script
gcloud compute instances create VM --metadata=startup-script='#!/bin/bash ...'

# Create VM with GCS startup script
gcloud compute instances create VM --metadata=startup-script-url=gs://BUCKET/script.sh

# Update startup script
gcloud compute instances add-metadata VM --metadata=startup-script='...'

# Debug: serial output
gcloud compute instances get-serial-port-output VM --zone=ZONE

# Debug: SSH and check logs
journalctl -u google-startup-scripts.service
grep startup /var/log/syslog

# Re-run startup script manually
sudo google_metadata_script_runner startup

# Cloud-init: check status and logs
cloud-init status
cat /var/log/cloud-init-output.log
```

---

## Part 4 — Quiz (15 min)

<details>
<summary><strong>Q1: Your startup script installs nginx, but when you SSH into the VM immediately after it shows "RUNNING", nginx is not yet installed. Why?</strong></summary>

**Answer:** The VM status changes to **RUNNING** as soon as the OS boots and the network is up — this happens **before** the startup script completes. The startup script runs asynchronously in the background.

**Solutions:**
1. **Wait longer** — use `sleep` or poll for a marker file
2. **Check for completion marker:** `while [ ! -f /tmp/startup-complete ]; do sleep 5; done`
3. **Check serial output:** `gcloud compute instances get-serial-port-output` shows real-time progress
4. **Use a health check** — application-level readiness check rather than VM status

**Best practice:** Have your startup script create a marker file (`touch /tmp/startup-complete`) as its last step, and check for that before declaring the VM ready.
</details>

<details>
<summary><strong>Q2: Your startup script runs every time the VM reboots, re-installing packages and overwriting config files. How do you make it idempotent?</strong></summary>

**Answer:** Use **guard clauses** — check if work is already done before doing it:

```bash
#!/bin/bash
# Guard: skip if already completed
if [ -f /opt/setup-complete ]; then
  echo "Setup already done, skipping."
  exit 0
fi

# Actual setup
apt-get update && apt-get install -y nginx
cp /tmp/config.yaml /etc/app/config.yaml
systemctl enable nginx

# Mark as complete
touch /opt/setup-complete
```

**Alternative approaches:**
- Use `apt-get install -y` (already idempotent — won't reinstall)
- Use `systemctl enable` (idempotent — won't fail if already enabled)
- For config files: check `md5sum` before overwriting
- Use cloud-init instead (runs only on first boot by default)
</details>

<details>
<summary><strong>Q3: When should you use `startup-script-url` (from GCS) instead of inline `startup-script`?</strong></summary>

**Answer:**

| Use `startup-script` (inline) | Use `startup-script-url` (GCS) |
|---|---|
| Short scripts (< 50 lines) | Long scripts (complex setup) |
| No external dependencies | Uses shared/versioned scripts |
| Quick prototyping | Production deployments |
| Self-contained logic | Multiple VMs share same script |

**Additional reasons for GCS:**
- **Versioning** — update the script in GCS, new VMs pick it up automatically
- **Size** — inline is limited to 256KB of metadata
- **Auditability** — GCS object versioning tracks script changes
- **Separation of concerns** — instance config vs script content are separate
- **Testing** — can test the script locally before uploading to GCS

**Important:** Ensure the VM's service account has `storage.objects.get` permission (or `--scopes=storage-ro`) to read from GCS.
</details>

<details>
<summary><strong>Q4: Your shutdown script needs to gracefully stop an application, upload final logs to GCS, and deregister from a load balancer. It sometimes doesn't complete. Why, and how do you fix it?</strong></summary>

**Answer:** GCP gives shutdown scripts a **limited execution window:**
- Regular VMs: ~90 seconds
- Preemptible/Spot VMs: ~30 seconds
- After the window, the VM is forcefully terminated

**Fixes:**
1. **Prioritize critical actions** — do the most important task first (deregister from LB)
2. **Run tasks in parallel:**
   ```bash
   app_stop &
   upload_logs &
   deregister_lb &
   wait  # Wait for all background jobs
   ```
3. **Pre-stage data** — keep logs in a ready-to-upload format, not requiring processing
4. **Use an external trigger** — instead of relying on the shutdown script, use a Cloud Function triggered by the VM's lifecycle event (audit log)
5. **Extend the window** — not possible via config, but design for the 90-second limit
</details>
