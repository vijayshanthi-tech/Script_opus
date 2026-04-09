# Day 42 — PROJECT: Golden VM Baseline Automation

> **Week 7 — Automation & Ops** | ⏱ 2 hours | Region: `europe-west2`

---

## Project Overview

Combine everything from Week 7 into a complete automated golden VM baseline:
- Startup scripts for package installation and hardening (Day 37-38)
- Monitoring scripts with cron (Day 39)
- Log rotation and housekeeping (Day 40)
- Ops runbook with pre/post checks (Day 41)

---

## Architecture Diagram

```
┌──────────────────────────────────────────────────────────────────────┐
│               GOLDEN VM BASELINE AUTOMATION                          │
│               Region: europe-west2                                   │
│                                                                      │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │                    SCRIPT STORAGE (GCS)                        │  │
│  │                                                                │  │
│  │  gs://PROJECT-golden-scripts/                                  │  │
│  │  ├── golden-setup.sh        (packages + hardening)             │  │
│  │  ├── monitor.sh             (monitoring + custom metrics)      │  │
│  │  ├── disk-cleanup.sh        (housekeeping)                     │  │
│  │  └── logrotate-apps.conf    (log rotation config)              │  │
│  └───────────────────────────────┬────────────────────────────────┘  │
│                                  │                                   │
│                          downloaded on boot                          │
│                                  │                                   │
│  ┌───────────────────────────────▼────────────────────────────────┐  │
│  │                    GOLDEN VM INSTANCE                          │  │
│  │                                                                │  │
│  │  ┌──────────────────────┐  ┌──────────────────────────────┐   │  │
│  │  │  PACKAGES            │  │  HARDENING                    │   │  │
│  │  │  • nginx             │  │  • SSH: no root, no password  │   │  │
│  │  │  • curl / jq         │  │  • Kernel: sysctl hardened    │   │  │
│  │  │  • htop / iotop      │  │  • fail2ban enabled           │   │  │
│  │  │  • fail2ban          │  │  • auditd with rules          │   │  │
│  │  │  • auditd            │  │  • unattended-upgrades        │   │  │
│  │  └──────────────────────┘  └──────────────────────────────┘   │  │
│  │                                                                │  │
│  │  ┌──────────────────────┐  ┌──────────────────────────────┐   │  │
│  │  │  MONITORING          │  │  HOUSEKEEPING                 │   │  │
│  │  │  • /opt/monitor.sh   │  │  • logrotate configs          │   │  │
│  │  │  • cron: */5 min     │  │  • /opt/disk-cleanup.sh       │   │  │
│  │  │  • Cloud Monitoring  │  │  • cron: weekly cleanup        │   │  │
│  │  │    custom metrics    │  │  • disk space alerts           │   │  │
│  │  └──────────────────────┘  └──────────────────────────────┘   │  │
│  │                                                                │  │
│  └────────────────────────────────────────────────────────────────┘  │
│                                                                      │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │                    TERRAFORM                                   │  │
│  │                                                                │  │
│  │  ┌──────────┐  ┌──────────────┐  ┌────────────────────────┐   │  │
│  │  │ GCS      │  │ Instance     │  │ Resource Policy        │   │  │
│  │  │ Bucket   │──│ Template     │──│ (Snapshot Schedule)    │   │  │
│  │  │ (scripts)│  │ (golden ref) │  │                        │   │  │
│  │  └──────────┘  └──────┬───────┘  └────────────────────────┘   │  │
│  │                       │                                        │  │
│  │                       ▼                                        │  │
│  │              ┌──────────────────┐                              │  │
│  │              │ Compute Instance │                              │  │
│  │              │ (from template)  │                              │  │
│  │              └──────────────────┘                              │  │
│  └────────────────────────────────────────────────────────────────┘  │
│                                                                      │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │                    VERIFICATION                                │  │
│  │  preflight-check.sh → provision → post-deploy-check.sh        │  │
│  └────────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────┘
```

---

## Implementation

### Variables

```bash
export PROJECT_ID=$(gcloud config get-value project)
export ZONE=europe-west2-a
export REGION=europe-west2
export PREFIX="lab42"
export SCRIPT_BUCKET="${PROJECT_ID}-golden-scripts-${PREFIX}"
```

### Phase 1 — Create Scripts and Upload to GCS (15 min)

```bash
# Create bucket
gsutil mb -p ${PROJECT_ID} -l ${REGION} -b on gs://${SCRIPT_BUCKET}

# ─────────────────────────────────────
# Script 1: golden-setup.sh (main startup)
# ─────────────────────────────────────
cat > /tmp/golden-setup.sh << 'SETUP_EOF'
#!/bin/bash
set -euo pipefail

VERSION="1.0"
MARKER="/opt/.golden-setup-v${VERSION}-complete"
LOG="/var/log/golden-setup.log"
exec > >(tee -a "$LOG") 2>&1

echo "=== Golden Setup v${VERSION} Begin: $(date) ==="

if [ -f "${MARKER}" ]; then
    echo "Setup v${VERSION} already completed. Skipping."
    exit 0
fi

export DEBIAN_FRONTEND=noninteractive

# ── PACKAGES ──
echo "[1/6] Installing packages..."
apt-get update -qq
apt-get install -y -qq \
    nginx curl jq htop iotop bc \
    fail2ban \
    unattended-upgrades apt-listchanges \
    auditd \
    logrotate

# ── NGINX CONFIG ──
echo "[2/6] Configuring nginx..."
INSTANCE_NAME=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/name)
cat > /var/www/html/index.html << NGINX_EOF
<!DOCTYPE html>
<html><body>
<h1>Golden VM: ${INSTANCE_NAME}</h1>
<p>Version: ${VERSION} | Built: $(date -Iseconds)</p>
</body></html>
NGINX_EOF
systemctl enable nginx && systemctl restart nginx

# ── SSH HARDENING ──
echo "[3/6] Hardening SSH..."
[ ! -f /etc/ssh/sshd_config.orig ] && cp /etc/ssh/sshd_config /etc/ssh/sshd_config.orig
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#\?X11Forwarding.*/X11Forwarding no/' /etc/ssh/sshd_config
sed -i 's/^#\?MaxAuthTries.*/MaxAuthTries 3/' /etc/ssh/sshd_config
systemctl restart sshd

# ── KERNEL HARDENING ──
echo "[4/6] Hardening kernel..."
cat > /etc/sysctl.d/99-hardening.conf << 'SYSCTL_EOF'
net.ipv4.ip_forward = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.log_martians = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
SYSCTL_EOF
sysctl -p /etc/sysctl.d/99-hardening.conf

# ── FAIL2BAN ──
echo "[5/6] Configuring fail2ban + auditd..."
systemctl enable fail2ban && systemctl restart fail2ban

cat > /etc/audit/rules.d/hardening.rules << 'AUDIT_EOF'
-w /etc/ssh/sshd_config -p wa -k sshd_config
-w /etc/passwd -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/sudoers -p wa -k sudoers
AUDIT_EOF
systemctl enable auditd && systemctl restart auditd

# ── UNATTENDED UPGRADES ──
echo "[6/6] Configuring auto-updates..."
cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'APT_EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
APT_EOF

# ── DOWNLOAD ADDITIONAL SCRIPTS FROM GCS ──
BUCKET=$(curl -s -H "Metadata-Flavor: Google" \
  http://metadata.google.internal/computeMetadata/v1/instance/attributes/scripts-bucket 2>/dev/null || echo "")

if [ -n "${BUCKET}" ]; then
    echo "Downloading ops scripts from gs://${BUCKET}/..."
    gsutil cp gs://${BUCKET}/monitor.sh /opt/monitor.sh 2>/dev/null || true
    gsutil cp gs://${BUCKET}/disk-cleanup.sh /opt/disk-cleanup.sh 2>/dev/null || true
    gsutil cp gs://${BUCKET}/logrotate-apps.conf /etc/logrotate.d/apps 2>/dev/null || true
    chmod +x /opt/monitor.sh /opt/disk-cleanup.sh 2>/dev/null || true
fi

# ── CRON JOBS ──
cat > /etc/cron.d/golden-ops << 'CRON_EOF'
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Monitoring — every 5 minutes
*/5 * * * * root /opt/monitor.sh >> /var/log/monitor-cron.log 2>&1

# Disk cleanup — Sunday 03:00
0 3 * * 0 root /opt/disk-cleanup.sh >> /var/log/cleanup-cron.log 2>&1
CRON_EOF
chmod 644 /etc/cron.d/golden-ops

# ── COMPLETE ──
apt-get clean -qq
touch "${MARKER}"
echo "=== Golden Setup v${VERSION} Complete: $(date) ==="
SETUP_EOF

# ─────────────────────────────────────
# Script 2: monitor.sh
# ─────────────────────────────────────
cat > /tmp/monitor.sh << 'MONITOR_EOF'
#!/bin/bash
set -euo pipefail

LOG="/var/log/monitor.log"
TIMESTAMP=$(date -Iseconds)
HOSTNAME=$(hostname)

DISK_USAGE=$(df / | tail -1 | awk '{print $5}' | tr -d '%')
MEM_TOTAL=$(free -m | awk '/Mem:/{print $2}')
MEM_USED=$(free -m | awk '/Mem:/{print $3}')
MEM_PERCENT=$(echo "scale=1; ${MEM_USED}*100/${MEM_TOTAL}" | bc)
CPU_LOAD=$(cat /proc/loadavg | awk '{print $1}')

echo "${TIMESTAMP} | host=${HOSTNAME} | disk=${DISK_USAGE}% | mem=${MEM_PERCENT}% | cpu_load=${CPU_LOAD}" >> ${LOG}

if [ ${DISK_USAGE} -ge 80 ]; then
    echo "${TIMESTAMP} | WARNING: Disk at ${DISK_USAGE}%" >> ${LOG}
fi
MONITOR_EOF

# ─────────────────────────────────────
# Script 3: disk-cleanup.sh
# ─────────────────────────────────────
cat > /tmp/disk-cleanup.sh << 'CLEANUP_EOF'
#!/bin/bash
set -euo pipefail

LOG="/var/log/disk-cleanup.log"
echo "=== Cleanup: $(date -Iseconds) ===" >> ${LOG}

BEFORE=$(df / | tail -1 | awk '{print $5}')
apt-get clean -qq
find /tmp -type f -mtime +7 -delete 2>/dev/null || true
find /var/tmp -type f -mtime +30 -delete 2>/dev/null || true
find /var/log -name '*.gz' -mtime +30 -delete 2>/dev/null || true
AFTER=$(df / | tail -1 | awk '{print $5}')

echo "  Before: ${BEFORE}, After: ${AFTER}" >> ${LOG}
CLEANUP_EOF

# ─────────────────────────────────────
# Script 4: logrotate-apps.conf
# ─────────────────────────────────────
cat > /tmp/logrotate-apps.conf << 'LOGROTATE_EOF'
/var/log/monitor.log /var/log/monitor-cron.log /var/log/golden-setup.log /var/log/disk-cleanup.log /var/log/cleanup-cron.log {
    weekly
    rotate 4
    compress
    delaycompress
    missingok
    notifempty
    create 0640 root adm
}
LOGROTATE_EOF

# Upload all scripts to GCS
gsutil cp /tmp/golden-setup.sh gs://${SCRIPT_BUCKET}/golden-setup.sh
gsutil cp /tmp/monitor.sh gs://${SCRIPT_BUCKET}/monitor.sh
gsutil cp /tmp/disk-cleanup.sh gs://${SCRIPT_BUCKET}/disk-cleanup.sh
gsutil cp /tmp/logrotate-apps.conf gs://${SCRIPT_BUCKET}/logrotate-apps.conf

echo "Scripts uploaded to gs://${SCRIPT_BUCKET}/"
gsutil ls gs://${SCRIPT_BUCKET}/
```

### Phase 2 — Terraform Configuration (10 min)

```bash
mkdir -p /tmp/golden-tf-${PREFIX}
cat > /tmp/golden-tf-${PREFIX}/main.tf << 'TF_EOF'
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# Snapshot schedule for boot disk
resource "google_compute_resource_policy" "daily_backup" {
  name   = "daily-backup-${var.prefix}"
  region = var.region

  snapshot_schedule_policy {
    schedule {
      daily_schedule {
        days_in_cycle = 1
        start_time    = "02:00"
      }
    }
    retention_policy {
      max_retention_days    = 7
      on_source_disk_delete = "KEEP_AUTO_SNAPSHOTS"
    }
    snapshot_properties {
      storage_locations = [var.region]
      labels = {
        backup = "daily"
        env    = var.environment
      }
    }
  }
}

# Instance template
resource "google_compute_instance_template" "golden" {
  name_prefix  = "golden-${var.prefix}-"
  machine_type = var.machine_type
  region       = var.region

  disk {
    source_image = "debian-cloud/debian-12"
    disk_size_gb = 20
    disk_type    = "pd-balanced"
    auto_delete  = true
    boot         = true

    resource_policies = [google_compute_resource_policy.daily_backup.id]
  }

  network_interface {
    network = "default"
    access_config {}
  }

  metadata = {
    startup-script-url = "gs://${var.scripts_bucket}/golden-setup.sh"
    scripts-bucket     = var.scripts_bucket
  }

  service_account {
    scopes = ["storage-ro", "monitoring-write", "logging-write"]
  }

  tags = ["http-server", "monitoring", var.prefix]

  labels = {
    env     = var.environment
    team    = "platform"
    managed = "terraform"
    week    = "7"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Single instance from template
resource "google_compute_instance_from_template" "golden_vm" {
  name                     = "${var.environment}-golden-ew2-001"
  zone                     = var.zone
  source_instance_template = google_compute_instance_template.golden.id
}

# Variables
variable "project_id" {
  type = string
}

variable "region" {
  type    = string
  default = "europe-west2"
}

variable "zone" {
  type    = string
  default = "europe-west2-a"
}

variable "prefix" {
  type    = string
  default = "lab42"
}

variable "environment" {
  type    = string
  default = "lab"
}

variable "machine_type" {
  type    = string
  default = "e2-small"
}

variable "scripts_bucket" {
  type = string
}

# Outputs
output "instance_name" {
  value = google_compute_instance_from_template.golden_vm.name
}

output "instance_ip" {
  value = google_compute_instance_from_template.golden_vm.network_interface[0].access_config[0].nat_ip
}

output "template_name" {
  value = google_compute_instance_template.golden.name
}
TF_EOF

echo "Terraform config created at /tmp/golden-tf-${PREFIX}/"
```

### Phase 3 — Deploy with gcloud (or Terraform) (10 min)

```bash
# Using gcloud (simpler for lab)
gcloud compute instances create lab-golden-ew2-001 \
  --zone=${ZONE} \
  --machine-type=e2-small \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --boot-disk-size=20GB \
  --boot-disk-type=pd-balanced \
  --tags=http-server,monitoring,${PREFIX} \
  --labels=env=lab,team=platform,managed=gcloud,week=7 \
  --scopes=storage-ro,monitoring-write,logging-write \
  --metadata=startup-script-url=gs://${SCRIPT_BUCKET}/golden-setup.sh,scripts-bucket=${SCRIPT_BUCKET}

echo "Waiting for golden setup to complete..."
sleep 120
```

### Phase 4 — Full Verification (10 min)

```bash
VM_NAME="lab-golden-ew2-001"

echo "============================================"
echo "  GOLDEN VM FULL VERIFICATION"
echo "  VM: ${VM_NAME}"
echo "  $(date)"
echo "============================================"

gcloud compute ssh ${VM_NAME} --zone=${ZONE} --command="
PASS=0; FAIL=0
check() {
    if eval \"\$2\" > /dev/null 2>&1; then
        echo \"  [PASS] \$1\"; ((PASS++))
    else
        echo \"  [FAIL] \$1\"; ((FAIL++))
    fi
}

echo ''
echo '--- Startup Script ---'
check 'Setup marker exists' '[ -f /opt/.golden-setup-v1.0-complete ]'

echo ''
echo '--- Packages ---'
for pkg in nginx curl jq htop iotop fail2ban auditd; do
    check \"Package: \${pkg}\" \"dpkg -l | grep -q \${pkg}\"
done

echo ''
echo '--- Services ---'
for svc in nginx fail2ban auditd cron; do
    check \"Service: \${svc}\" \"systemctl is-active \${svc}\"
done

echo ''
echo '--- SSH Hardening ---'
check 'PermitRootLogin no' 'grep -q \"PermitRootLogin no\" /etc/ssh/sshd_config'
check 'PasswordAuth no' 'grep -q \"PasswordAuthentication no\" /etc/ssh/sshd_config'
check 'X11Forwarding no' 'grep -q \"X11Forwarding no\" /etc/ssh/sshd_config'
check 'MaxAuthTries 3' 'grep -q \"MaxAuthTries 3\" /etc/ssh/sshd_config'

echo ''
echo '--- Kernel Hardening ---'
check 'ip_forward=0' '[ \"\$(sysctl -n net.ipv4.ip_forward)\" = \"0\" ]'
check 'accept_redirects=0' '[ \"\$(sysctl -n net.ipv4.conf.all.accept_redirects)\" = \"0\" ]'
check 'tcp_syncookies=1' '[ \"\$(sysctl -n net.ipv4.tcp_syncookies)\" = \"1\" ]'

echo ''
echo '--- Audit Rules ---'
check 'SSH config audited' 'auditctl -l | grep -q sshd_config'
check 'User identity audited' 'auditctl -l | grep -q identity'
check 'Sudoers audited' 'auditctl -l | grep -q sudoers'

echo ''
echo '--- Ops Scripts ---'
check 'monitor.sh present' '[ -f /opt/monitor.sh ]'
check 'monitor.sh executable' '[ -x /opt/monitor.sh ]'
check 'disk-cleanup.sh present' '[ -f /opt/disk-cleanup.sh ]'
check 'Cron job configured' '[ -f /etc/cron.d/golden-ops ]'
check 'Logrotate config' '[ -f /etc/logrotate.d/apps ]'

echo ''
echo '--- Application ---'
check 'Nginx HTTP 200' '[ \"\$(curl -s -o /dev/null -w \"%{http_code}\" localhost)\" = \"200\" ]'

echo ''
echo '--- Quick Monitor Test ---'
/opt/monitor.sh
check 'Monitor log has data' '[ -s /var/log/monitor.log ]'

echo ''
echo '============================================'
echo \"  Results: \${PASS} passed, \${FAIL} failed\"
echo '============================================'
[ \${FAIL} -eq 0 ] && echo '  VM VERIFIED — Ready for service' || echo '  ISSUES FOUND — Review failures'
"
```

---

## Verification Checklist

```
SCRIPTS IN GCS
  [ ] golden-setup.sh uploaded
  [ ] monitor.sh uploaded
  [ ] disk-cleanup.sh uploaded
  [ ] logrotate-apps.conf uploaded

GOLDEN VM BUILD
  [ ] VM created with correct tags, labels, scopes
  [ ] Startup script downloaded from GCS and executed
  [ ] All packages installed (nginx, fail2ban, auditd, etc.)
  [ ] SSH hardened (no root, no password, max 3 tries)
  [ ] Kernel hardened (sysctl parameters set)
  [ ] Fail2ban active
  [ ] Auditd with rules active
  [ ] Unattended-upgrades configured

OPS AUTOMATION
  [ ] monitor.sh running via cron (every 5 min)
  [ ] disk-cleanup.sh scheduled (weekly)
  [ ] Logrotate configured for custom logs
  [ ] Monitor log has data

TERRAFORM (optional)
  [ ] Instance template defined
  [ ] Snapshot schedule defined
  [ ] Instance created from template

DOCUMENTATION
  [ ] Ops runbook written
  [ ] Pre-flight check script works
  [ ] Post-deployment check script works
```

---

## Cleanup

```bash
# Delete VM
gcloud compute instances delete lab-golden-ew2-001 --zone=${ZONE} --quiet

# Delete GCS bucket
gsutil rm -r gs://${SCRIPT_BUCKET}

# Clean local files
rm -rf /tmp/golden-setup.sh /tmp/monitor.sh /tmp/disk-cleanup.sh \
       /tmp/logrotate-apps.conf /tmp/golden-tf-${PREFIX}
```

---

## Reflection Questions

1. How would you **version** the golden setup script to support rolling updates (v1 → v2)?
2. What would you add to support **Windows** VMs alongside Linux?
3. How would you integrate this with a **CI/CD pipeline** that automatically builds and tests golden images?
4. What **compliance checks** (CIS Benchmark Level 1) would you add beyond what's covered here?
