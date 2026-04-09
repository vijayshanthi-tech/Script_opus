# Week 1, Day 6 (Sat) — PROJECT: Secure VM Baseline

## Project Objective

Build a **production-ready, hardened Linux VM** on GCP from scratch, combining everything learned this week: SSH security (Day 1), disk management (Day 2), VM components (Day 3), integrated setup (Day 4), and OS hardening (Day 5).

**Deliverable:** Complete README + architecture diagram + screenshots

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    SECURE VM BASELINE                             │
│                                                                  │
│  ┌──────────────────────────────────────────────────────┐        │
│  │  VPC: default (or custom)                             │        │
│  │                                                       │        │
│  │  Firewall Rules:                                      │        │
│  │  ✅ Allow SSH from IAP only (35.235.240.0/20)         │        │
│  │  ❌ No direct SSH from 0.0.0.0/0                      │        │
│  │                                                       │        │
│  │  ┌─────────────────────────────────────────────────┐  │        │
│  │  │  VM: secure-baseline-vm                         │  │        │
│  │  │                                                 │  │        │
│  │  │  Machine Type: e2-small                         │  │        │
│  │  │  OS: Debian 12 (hardened)                       │  │        │
│  │  │  Shielded VM: ✅ Secure Boot + vTPM + Integrity │  │        │
│  │  │  External IP: ❌ None                            │  │        │
│  │  │  OS Login: ✅ Enabled                            │  │        │
│  │  │  Service Account: Custom (minimal roles)        │  │        │
│  │  │                                                 │  │        │
│  │  │  ┌──────────────┐  ┌──────────────┐             │  │        │
│  │  │  │  Boot Disk   │  │  Data Disk   │             │  │        │
│  │  │  │  10GB SSD    │  │  20GB Std    │             │  │        │
│  │  │  │  pd-balanced │  │  pd-standard │             │  │        │
│  │  │  │  auto-delete │  │  NO auto-del │             │  │        │
│  │  │  └──────────────┘  └──────────────┘             │  │        │
│  │  │                                                 │  │        │
│  │  │  Hardening Applied:                             │  │        │
│  │  │  • SSH: Key-only, no root, timeouts             │  │        │
│  │  │  • Kernel: SYN cookies, no IP fwd, no redirects │  │        │
│  │  │  • Services: Unused disabled                    │  │        │
│  │  │  • Users: Non-root admin with sudo              │  │        │
│  │  │  • Banner: Warning banner                       │  │        │
│  │  └─────────────────────────────────────────────────┘  │        │
│  │                                                       │        │
│  │  Snapshot Schedule: Daily at 02:00 UTC, 7-day retain  │        │
│  └──────────────────────────────────────────────────────┘        │
│                                                                  │
│  Access: gcloud compute ssh --tunnel-through-iap                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Build Steps

### Phase 1: Infrastructure Setup (20 min)

#### 1.1 Create Custom Service Account

```bash
PROJECT_ID=$(gcloud config get-value project)

gcloud iam service-accounts create secure-vm-sa \
  --display-name="Secure VM Service Account"

# Minimal roles: logging + monitoring only
for role in roles/logging.logWriter roles/monitoring.metricWriter; do
  gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:secure-vm-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="$role"
done
```

#### 1.2 Create Firewall Rule (SSH via IAP Only)

```bash
# Delete default allow-ssh if it exists (allow SSH from anywhere)
gcloud compute firewall-rules delete default-allow-ssh --quiet 2>/dev/null

# Create IAP-only SSH rule
gcloud compute firewall-rules create allow-ssh-iap-only \
  --direction=INGRESS \
  --priority=1000 \
  --network=default \
  --action=ALLOW \
  --rules=tcp:22 \
  --source-ranges=35.235.240.0/20 \
  --target-tags=secure-vm \
  --description="Allow SSH only via IAP Tunnel"
```

#### 1.3 Create the VM

```bash
gcloud compute instances create secure-baseline-vm \
  --zone=europe-west2-a \
  --machine-type=e2-small \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --boot-disk-size=10GB \
  --boot-disk-type=pd-balanced \
  --create-disk=name=secure-data-disk,size=20GB,type=pd-standard,auto-delete=no \
  --no-address \
  --service-account=secure-vm-sa@${PROJECT_ID}.iam.gserviceaccount.com \
  --scopes=logging-write,monitoring-write \
  --metadata=enable-oslogin=TRUE \
  --shielded-secure-boot \
  --shielded-vtpm \
  --shielded-integrity-monitoring \
  --tags=secure-vm \
  --labels=env=production,project=secure-baseline,week=1
```

#### 1.4 Create Snapshot Schedule

```bash
gcloud compute resource-policies create snapshot-schedule daily-backup-7d \
  --region=europe-west2 \
  --max-retention-days=7 \
  --on-source-disk-delete=keep-auto-snapshots \
  --daily-schedule \
  --start-time=02:00

gcloud compute disks add-resource-policies secure-data-disk \
  --resource-policies=daily-backup-7d \
  --zone=europe-west2-a
```

---

### Phase 2: OS Hardening (25 min)

```bash
# SSH via IAP
gcloud compute ssh secure-baseline-vm --zone=europe-west2-a --tunnel-through-iap
```

#### 2.1 Patch the OS

```bash
sudo apt-get update && sudo apt-get upgrade -y && sudo apt-get autoremove -y
```

#### 2.2 Mount Data Disk

```bash
sudo mkfs.ext4 -m 0 -F /dev/sdb
sudo mkdir -p /mnt/data
sudo mount /dev/sdb /mnt/data
echo "UUID=$(sudo blkid -s UUID -o value /dev/sdb) /mnt/data ext4 discard,defaults,nofail 0 2" | sudo tee -a /etc/fstab
sudo chmod 750 /mnt/data
```

#### 2.3 Create Non-Root Admin

```bash
sudo useradd -m -s /bin/bash -G sudo sysadmin
sudo passwd sysadmin
```

#### 2.4 Harden SSH

```bash
sudo tee /etc/ssh/sshd_config.d/hardening.conf << 'EOF'
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication no
PermitEmptyPasswords no
X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
MaxAuthTries 3
AllowAgentForwarding no
Banner /etc/issue.net
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org
Ciphers aes256-gcm@openssh.com,aes128-gcm@openssh.com
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
EOF

sudo sshd -t && sudo systemctl restart sshd
```

#### 2.5 Harden Kernel

```bash
sudo tee /etc/sysctl.d/99-hardening.conf << 'EOF'
net.ipv4.ip_forward = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.log_martians = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.conf.all.accept_source_route = 0
EOF
sudo sysctl --system
```

#### 2.6 Disable Unnecessary Services

```bash
for svc in cups avahi-daemon bluetooth ModemManager; do
  sudo systemctl stop $svc 2>/dev/null
  sudo systemctl disable $svc 2>/dev/null
done
```

#### 2.7 File Permissions & Banner

```bash
sudo chmod 640 /etc/shadow /etc/gshadow
sudo chmod 600 /etc/crontab

sudo tee /etc/issue.net << 'EOF'
*************************************************************
* WARNING: Unauthorized access prohibited. All activity logged. *
*************************************************************
EOF
```

---

### Phase 3: Verification (15 min)

```bash
echo "=========================================="
echo "  SECURE VM BASELINE — VERIFICATION"
echo "=========================================="
echo ""
echo "1. SHIELDED VM"
# Check from outside after exit:

echo "2. OS LOGIN"
curl -s -H "Metadata-Flavor: Google" \
  http://metadata.google.internal/computeMetadata/v1/instance/attributes/enable-oslogin
echo ""

echo "3. NO EXTERNAL IP"
curl -s -H "Metadata-Flavor: Google" \
  http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip 2>&1
echo "(should be empty or error)"

echo "4. SERVICE ACCOUNT"
curl -s -H "Metadata-Flavor: Google" \
  http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/email
echo ""

echo "5. SSH HARDENING"
grep -rE "PermitRootLogin|PasswordAuthentication" /etc/ssh/sshd_config.d/
echo ""

echo "6. KERNEL HARDENING"
sysctl net.ipv4.ip_forward net.ipv4.tcp_syncookies
echo ""

echo "7. NON-ROOT ADMIN"
id sysadmin
echo ""

echo "8. DATA DISK"
df -h /mnt/data
echo ""

echo "=========================================="
echo "  ALL CHECKS COMPLETE"
echo "=========================================="

exit
```

Verify from outside:
```bash
# Shielded VM status
gcloud compute instances describe secure-baseline-vm \
  --zone=europe-west2-a \
  --format="yaml(shieldedInstanceConfig,shieldedInstanceIntegrityPolicy)"

# Snapshot schedule attached
gcloud compute disks describe secure-data-disk \
  --zone=europe-west2-a \
  --format="value(resourcePolicies)"

# Firewall rules
gcloud compute firewall-rules list --filter="name:allow-ssh-iap"
```

---

## Project Checklist

- [ ] Custom service account with minimal roles (logging + monitoring only)
- [ ] Firewall: SSH allowed only from IAP range (35.235.240.0/20)
- [ ] VM created with no external IP
- [ ] OS Login enabled
- [ ] Shielded VM (Secure Boot + vTPM + Integrity Monitoring)
- [ ] Data disk attached with `auto-delete=no`
- [ ] Snapshot schedule: daily at 02:00 UTC, 7-day retention
- [ ] OS fully patched
- [ ] Non-root admin user created
- [ ] SSH hardened (no root login, key-only, timeouts)
- [ ] Kernel hardened (no IP forwarding, SYN cookies, etc.)
- [ ] Unnecessary services disabled
- [ ] Login banner set
- [ ] Verification script passed all checks
- [ ] Screenshots captured

---

## Clean Up

```bash
gcloud compute instances delete secure-baseline-vm --zone=europe-west2-a --quiet
gcloud compute disks delete secure-data-disk --zone=europe-west2-a --quiet
gcloud compute resource-policies delete daily-backup-7d --region=europe-west2 --quiet
gcloud compute firewall-rules delete allow-ssh-iap-only --quiet
gcloud iam service-accounts delete secure-vm-sa@$(gcloud config get-value project).iam.gserviceaccount.com --quiet
```

---

## Week 1 Milestone

You can now:
- ✅ Create and configure VMs with all components
- ✅ Manage SSH access securely (OS Login + IAP)
- ✅ Manage disks, snapshots, and backup schedules
- ✅ Apply CIS-style hardening to Linux VMs
- ✅ Build a secure VM baseline end-to-end
- ✅ Explain all decisions in an interview context
