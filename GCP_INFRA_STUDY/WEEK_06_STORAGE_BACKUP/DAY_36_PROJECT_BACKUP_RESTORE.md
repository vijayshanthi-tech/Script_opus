# Day 36 — PROJECT: Backup & Restore Lab

> **Week 6 — Storage & Backup** | ⏱ 2 hours | Region: `europe-west2`

---

## Project Overview

Combine everything from Week 6 into a complete backup & restore solution:
- Cloud Storage with lifecycle policies and versioning
- VM snapshot scheduling and cross-region snapshots
- Custom images for golden OS baseline
- End-to-end backup/restore with verification

---

## Architecture Diagram

```
┌───────────────────────────────────────────────────────────────────────┐
│                    BACKUP & RESTORE ARCHITECTURE                      │
│                    Region: europe-west2                                │
│                                                                       │
│  ┌─────────────────────────────────────────────────────────────────┐  │
│  │                        APPLICATION TIER                         │  │
│  │                                                                 │  │
│  │  ┌──────────────────┐          ┌──────────────────┐            │  │
│  │  │   web-server-01  │          │   app-server-01  │            │  │
│  │  │   (from golden   │          │   (from golden   │            │  │
│  │  │    image)        │          │    image)        │            │  │
│  │  │                  │          │                  │            │  │
│  │  │  Boot: 10GB      │          │  Boot: 10GB      │            │  │
│  │  │  Data: 20GB      │          │  Data: 50GB      │            │  │
│  │  └────────┬─────────┘          └────────┬─────────┘            │  │
│  │           │                              │                     │  │
│  └───────────┼──────────────────────────────┼─────────────────────┘  │
│              │                              │                        │
│  ┌───────────┼──────────────────────────────┼─────────────────────┐  │
│  │           │     BACKUP TIER              │                     │  │
│  │           ▼                              ▼                     │  │
│  │  ┌────────────────┐            ┌────────────────┐              │  │
│  │  │ Snapshot Policy│            │ Snapshot Policy│              │  │
│  │  │ Daily 02:00    │            │ Hourly         │              │  │
│  │  │ Retain 7 days  │            │ Retain 24 hrs  │              │  │
│  │  └────────┬───────┘            └────────┬───────┘              │  │
│  │           │                              │                     │  │
│  │           ▼                              ▼                     │  │
│  │  ┌──────────────────────────────────────────────┐              │  │
│  │  │            Snapshot Storage (GCS)             │              │  │
│  │  │            Location: europe-west2             │              │  │
│  │  └──────────────────────────────────────────────┘              │  │
│  │                                                                │  │
│  └────────────────────────────────────────────────────────────────┘  │
│                                                                       │
│  ┌────────────────────────────────────────────────────────────────┐   │
│  │                    OBJECT STORAGE TIER                          │   │
│  │                                                                │   │
│  │  ┌──────────────────────────────────────────────────────────┐  │   │
│  │  │ Bucket: PROJECT-backup-archive                            │  │   │
│  │  │ Versioning: ON                                           │  │   │
│  │  │ Uniform Access: ON                                       │  │   │
│  │  │                                                          │  │   │
│  │  │ Lifecycle:                                               │  │   │
│  │  │   STANDARD ──30d──► NEARLINE ──90d──► COLDLINE ──365d──► DELETE │
│  │  │   Noncurrent versions: keep 3, delete rest               │  │   │
│  │  └──────────────────────────────────────────────────────────┘  │   │
│  │                                                                │   │
│  └────────────────────────────────────────────────────────────────┘   │
│                                                                       │
│  ┌────────────────────────────────────────────────────────────────┐   │
│  │                    IMAGE TIER                                   │   │
│  │                                                                │   │
│  │  Image Family: "golden-base"                                   │   │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐                     │   │
│  │  │ v1 (dep) │  │ v2 (dep) │  │ v3 ◄LIVE │                     │   │
│  │  └──────────┘  └──────────┘  └──────────┘                     │   │
│  │                                                                │   │
│  │  Instance Template: "golden-template"                          │   │
│  │  → References image-family/golden-base                         │   │
│  └────────────────────────────────────────────────────────────────┘   │
└───────────────────────────────────────────────────────────────────────┘
```

---

## Implementation

### Variables

```bash
export PROJECT_ID=$(gcloud config get-value project)
export ZONE=europe-west2-a
export REGION=europe-west2
export BUCKET="${PROJECT_ID}-backup-archive-lab36"
export PREFIX="lab36"
```

### Phase 1 — Golden Image (15 min)

```bash
# Create base VM
gcloud compute instances create golden-base-${PREFIX} \
  --zone=${ZONE} \
  --machine-type=e2-micro \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --boot-disk-size=10GB \
  --metadata=startup-script='#!/bin/bash
apt-get update && apt-get install -y nginx htop iotop curl jq
echo "Golden Base v1 - Built $(date)" > /var/www/html/index.html
systemctl enable nginx
# Hardening
sed -i "s/#PermitRootLogin.*/PermitRootLogin no/" /etc/ssh/sshd_config
echo "net.ipv4.ip_forward = 0" >> /etc/sysctl.d/99-hardening.conf
sysctl -p /etc/sysctl.d/99-hardening.conf'

# Wait for setup
sleep 90

# Verify
gcloud compute ssh golden-base-${PREFIX} --zone=${ZONE} --command="
nginx -v 2>&1
curl -s localhost
cat /etc/ssh/sshd_config | grep PermitRootLogin
"

# Stop and create image
gcloud compute instances stop golden-base-${PREFIX} --zone=${ZONE}

gcloud compute images create golden-base-v1 \
  --source-disk=golden-base-${PREFIX} \
  --source-disk-zone=${ZONE} \
  --family=golden-base \
  --description="Debian 12 + Nginx + hardening - v1" \
  --labels=version=v1,week=6

# Create instance template
gcloud compute instance-templates create golden-template-${PREFIX} \
  --machine-type=e2-micro \
  --image-family=golden-base \
  --boot-disk-size=10GB \
  --tags=http-server,${PREFIX} \
  --region=${REGION} \
  --labels=env=lab,week=6
```

### Phase 2 — Application VMs with Data (10 min)

```bash
# Create web server from golden image
gcloud compute instances create web-server-${PREFIX} \
  --zone=${ZONE} \
  --source-instance-template=golden-template-${PREFIX}

# Create app server with data disk
gcloud compute instances create app-server-${PREFIX} \
  --zone=${ZONE} \
  --source-instance-template=golden-template-${PREFIX} \
  --create-disk=name=app-data-${PREFIX},size=20GB,type=pd-standard,auto-delete=no

# Set up data on app server
gcloud compute ssh app-server-${PREFIX} --zone=${ZONE} --command="
sudo mkfs.ext4 /dev/sdb
sudo mkdir -p /mnt/data
sudo mount /dev/sdb /mnt/data
for i in \$(seq 1 10); do
  echo \"App record \${i} - created \$(date)\" | sudo tee /mnt/data/record-\${i}.dat
done
sudo md5sum /mnt/data/record-*.dat | sudo tee /mnt/data/checksums.md5
echo '=== Data created ==='
ls -la /mnt/data/
"
```

### Phase 3 — Snapshot Schedules (10 min)

```bash
# Daily schedule for web server boot disk
gcloud compute resource-policies create snapshot-schedule daily-web-${PREFIX} \
  --region=${REGION} \
  --max-retention-days=7 \
  --daily-schedule \
  --start-time=02:00 \
  --storage-location=${REGION}

# Hourly schedule for app server data disk (higher RPO requirement)
gcloud compute resource-policies create snapshot-schedule hourly-app-${PREFIX} \
  --region=${REGION} \
  --max-retention-days=2 \
  --hourly-schedule \
  --hours-in-cycle=1 \
  --start-time=00:00 \
  --storage-location=${REGION}

# Attach policies
gcloud compute disks add-resource-policies web-server-${PREFIX} \
  --zone=${ZONE} \
  --resource-policies=daily-web-${PREFIX}

gcloud compute disks add-resource-policies app-data-${PREFIX} \
  --zone=${ZONE} \
  --resource-policies=hourly-app-${PREFIX}

# Take initial manual snapshots
gcloud compute disks snapshot web-server-${PREFIX} \
  --zone=${ZONE} \
  --snapshot-names=web-boot-initial-${PREFIX} \
  --storage-location=${REGION}

gcloud compute disks snapshot app-data-${PREFIX} \
  --zone=${ZONE} \
  --snapshot-names=app-data-initial-${PREFIX} \
  --storage-location=${REGION}
```

### Phase 4 — Cloud Storage with Lifecycle (10 min)

```bash
# Create versioned bucket with lifecycle
gsutil mb -p ${PROJECT_ID} -c STANDARD -l ${REGION} -b on gs://${BUCKET}
gsutil versioning set on gs://${BUCKET}

# Upload application backups
for i in 1 2 3; do
  echo "App backup version ${i} - $(date)" > /tmp/app-backup-v${i}.tar.gz
  gsutil cp /tmp/app-backup-v${i}.tar.gz gs://${BUCKET}/backups/app-backup.tar.gz
done

# Set lifecycle rules
cat > /tmp/lifecycle-lab36.json << 'EOF'
{
  "rule": [
    {
      "action": {"type": "SetStorageClass", "storageClass": "NEARLINE"},
      "condition": {"age": 30, "matchesStorageClass": ["STANDARD"]}
    },
    {
      "action": {"type": "SetStorageClass", "storageClass": "COLDLINE"},
      "condition": {"age": 90, "matchesStorageClass": ["NEARLINE"]}
    },
    {
      "action": {"type": "Delete"},
      "condition": {"age": 365}
    },
    {
      "action": {"type": "Delete"},
      "condition": {"numNewerVersions": 3, "isLive": false}
    }
  ]
}
EOF

gsutil lifecycle set /tmp/lifecycle-lab36.json gs://${BUCKET}
gsutil lifecycle get gs://${BUCKET}
```

### Phase 5 — Test Restore End-to-End (15 min)

```bash
echo "=========================================="
echo " RESTORE TEST START: $(date)"
echo "=========================================="

# Simulate disaster on app server
gcloud compute ssh app-server-${PREFIX} --zone=${ZONE} --command="
echo 'CORRUPTED' | sudo tee /mnt/data/record-1.dat
echo '--- Data corrupted ---'
cd /mnt/data && sudo md5sum -c checksums.md5 2>&1 | head -3
"

# Restore from snapshot
gcloud compute disks create restored-app-data-${PREFIX} \
  --zone=${ZONE} \
  --source-snapshot=app-data-initial-${PREFIX} \
  --type=pd-standard

# Stop, swap, start
gcloud compute instances stop app-server-${PREFIX} --zone=${ZONE}
gcloud compute instances detach-disk app-server-${PREFIX} --zone=${ZONE} --disk=app-data-${PREFIX}
gcloud compute instances attach-disk app-server-${PREFIX} --zone=${ZONE} --disk=restored-app-data-${PREFIX}
gcloud compute instances start app-server-${PREFIX} --zone=${ZONE}
sleep 20

# Verify
gcloud compute ssh app-server-${PREFIX} --zone=${ZONE} --command="
sudo mkdir -p /mnt/data
sudo mount /dev/sdb /mnt/data
echo '=== RESTORED FILES ==='
ls -la /mnt/data/
echo '=== CHECKSUM VERIFICATION ==='
cd /mnt/data && sudo md5sum -c checksums.md5
echo '=== DATA SAMPLE ==='
cat /mnt/data/record-1.dat
"

# Test GCS restore (versioning)
echo "--- GCS Version Restore ---"
gsutil ls -a gs://${BUCKET}/backups/app-backup.tar.gz
# Restore oldest version:
# gsutil cp gs://${BUCKET}/backups/app-backup.tar.gz#GENERATION gs://${BUCKET}/backups/app-backup-restored.tar.gz

echo "=========================================="
echo " RESTORE TEST COMPLETE: $(date)"
echo "=========================================="
```

---

## Verification Checklist

```
GOLDEN IMAGE
  [ ] Custom image created from hardened VM
  [ ] Image added to family "golden-base"
  [ ] Instance template references image family
  [ ] New VMs boot from golden image with nginx running

SNAPSHOT BACKUPS
  [ ] Daily snapshot schedule attached to web server disk
  [ ] Hourly snapshot schedule attached to app data disk
  [ ] Manual snapshots created successfully
  [ ] Snapshots stored in europe-west2

CLOUD STORAGE
  [ ] Bucket created with uniform access
  [ ] Versioning enabled — multiple versions visible
  [ ] Lifecycle rules applied (transition + deletion)

RESTORE TEST
  [ ] Data corruption simulated
  [ ] Disk restored from snapshot
  [ ] Disk swapped on VM
  [ ] Checksums verified after restore     ← CRITICAL
  [ ] GCS version restore tested

DOCUMENTATION
  [ ] Backup runbook written with exact commands
  [ ] RTO measured and recorded
  [ ] RPO targets confirmed against schedule
```

---

## Cleanup

```bash
# Delete VMs
for vm in golden-base-${PREFIX} web-server-${PREFIX} app-server-${PREFIX}; do
  gcloud compute instances delete ${vm} --zone=${ZONE} --quiet 2>/dev/null
done

# Delete disks
for disk in app-data-${PREFIX} restored-app-data-${PREFIX}; do
  gcloud compute disks delete ${disk} --zone=${ZONE} --quiet 2>/dev/null
done

# Delete snapshots
for snap in web-boot-initial-${PREFIX} app-data-initial-${PREFIX}; do
  gcloud compute snapshots delete ${snap} --quiet 2>/dev/null
done

# Delete resource policies
for policy in daily-web-${PREFIX} hourly-app-${PREFIX}; do
  gcloud compute resource-policies delete ${policy} --region=${REGION} --quiet 2>/dev/null
done

# Delete instance template
gcloud compute instance-templates delete golden-template-${PREFIX} --quiet 2>/dev/null

# Delete image
gcloud compute images delete golden-base-v1 --quiet 2>/dev/null

# Delete GCS bucket
gsutil rm -r gs://${BUCKET} 2>/dev/null

# Clean local files
rm -f /tmp/lifecycle-lab36.json /tmp/app-backup-*.tar.gz
```

---

## Reflection Questions

1. How would you extend this to support **cross-region DR** (e.g., failover to us-central1)?
2. What would change if the app server ran a **database** requiring application-consistent snapshots?
3. How would you **automate** the restore test to run monthly without manual intervention?
4. What **monitoring** would you add to alert if a snapshot schedule fails?
