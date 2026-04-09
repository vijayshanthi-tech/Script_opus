# Day 33 — VM Backup Strategy

> **Week 6 — Storage & Backup** | ⏱ 2 hours | Region: `europe-west2`

---

## Part 1 — Concept (30 min)

### Snapshots — The Primary Backup Mechanism

Compute Engine snapshots are **incremental, block-level** backups of persistent disks. Think of them like LVM snapshots on Linux — only changed blocks are stored.

```
┌──────────────────────────────────────────────────────┐
│              Incremental Snapshot Chain               │
│                                                      │
│  Disk (200 GB)                                       │
│  ┌──────────────┐                                    │
│  │ Block 1  [A] │                                    │
│  │ Block 2  [B] │                                    │
│  │ Block 3  [C] │                                    │
│  │ Block 4  [D] │                                    │
│  └──────────────┘                                    │
│                                                      │
│  Snapshot 1 (full): [A][B][C][D]   → 200 GB stored   │
│  Snapshot 2 (incr): [A'][  ][  ][D'] → ~2 blocks     │
│  Snapshot 3 (incr): [  ][B'][ ][  ] → ~1 block       │
│                                                      │
│  Each snapshot is independently restorable!           │
│  (GCS resolves the chain internally)                 │
└──────────────────────────────────────────────────────┘
```

**Linux analogy:**

| Linux | GCP Snapshots |
|---|---|
| `lvcreate --snapshot` | `gcloud compute disks snapshot` |
| LVM COW snapshot | Incremental block-level |
| Stored on same VG | Stored in GCS (separate from disk) |
| Must be on same host | Can be in different region |
| Manual scheduling | Snapshot schedules (automated) |

### Snapshot Scheduling

```
┌────────────────────────────────────────────────────┐
│               Snapshot Schedule                    │
│                                                    │
│  Resource Policy: "daily-backup-policy"            │
│                                                    │
│  ┌──────────────────────────────────────────────┐  │
│  │  Schedule:  Every day at 02:00 UTC           │  │
│  │  Retention: Keep 7 snapshots                 │  │
│  │  Location:  europe-west2 (same region)       │  │
│  │  Labels:    env=prod, backup=daily           │  │
│  │  Chain:     Keep dependency chain intact      │  │
│  └──────────────────────────────────────────────┘  │
│                                                    │
│  Attached to:                                      │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐         │
│  │ disk-web │  │ disk-app │  │ disk-db  │         │
│  └──────────┘  └──────────┘  └──────────┘         │
└────────────────────────────────────────────────────┘
```

### Cross-Region Snapshots

```
┌─────────────────┐                ┌─────────────────┐
│  europe-west2   │                │  us-central1     │
│                 │                │                  │
│  ┌───────────┐  │   Snapshot     │  ┌───────────┐  │
│  │   VM      │  │   stored in   │  │  Restore   │  │
│  │   Disk    │──┼──multi-region──┼─►│  new disk  │  │
│  │           │  │   or specific  │  │  from snap │  │
│  └───────────┘  │   region       │  └───────────┘  │
└─────────────────┘                └─────────────────┘

Storage locations for snapshots:
  • Same region (cheapest, fastest)
  • Multi-region (eu, us, asia)
  • Specific other region
```

### RPO / RTO Concepts

| Metric | Definition | Linux Analogy |
|---|---|---|
| **RPO** (Recovery Point Objective) | Max acceptable data loss (time) | How old is your last `tar` backup? |
| **RTO** (Recovery Time Objective) | Max acceptable downtime | How long to `tar xf` and restart services? |

```
  Data loss ◄────── RPO ──────► Disaster ◄────── RTO ──────► Recovery
  (last backup)                  (event)                      (service up)

  Example:
  Daily snapshot at 02:00 → disaster at 18:00 → RPO = 16 hours
  Restore takes 30 min → RTO = 30 min

  Hourly snapshot at 17:00 → disaster at 18:00 → RPO = 1 hour
  Same restore → RTO = 30 min
```

### Backup Validation

A backup you haven't tested is NOT a backup. Validation means:

1. **Restore test** — Create a disk from snapshot, attach to test VM, verify data
2. **Integrity check** — File checksums, database consistency checks
3. **Document results** — When tested, who tested, what was verified
4. **Schedule regular tests** — Monthly at minimum, quarterly for DR

---

## Part 2 — Hands-On Lab (60 min)

### Prerequisites

```bash
export PROJECT_ID=$(gcloud config get-value project)
export ZONE=europe-west2-a
export REGION=europe-west2
export VM_NAME="backup-lab33"
export DISK_NAME="${VM_NAME}"
export POLICY_NAME="daily-backup-lab33"
```

### Step 1 — Create a VM with a Data Disk

```bash
# Create VM
gcloud compute instances create ${VM_NAME} \
  --zone=${ZONE} \
  --machine-type=e2-micro \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --boot-disk-size=10GB \
  --tags=lab33

# Create and attach a data disk
gcloud compute disks create data-disk-lab33 \
  --zone=${ZONE} \
  --size=10GB \
  --type=pd-standard

gcloud compute instances attach-disk ${VM_NAME} \
  --zone=${ZONE} \
  --disk=data-disk-lab33

# SSH in and write test data
gcloud compute ssh ${VM_NAME} --zone=${ZONE} --command="
sudo mkfs.ext4 /dev/sdb
sudo mkdir -p /mnt/data
sudo mount /dev/sdb /mnt/data
echo 'Critical data - version 1' | sudo tee /mnt/data/important.txt
echo 'Database record 12345' | sudo tee /mnt/data/db-record.txt
sudo md5sum /mnt/data/*.txt | sudo tee /mnt/data/checksums.md5
cat /mnt/data/checksums.md5
"
```

### Step 2 — Take a Manual Snapshot

```bash
# Snapshot the data disk
gcloud compute disks snapshot data-disk-lab33 \
  --zone=${ZONE} \
  --snapshot-names=data-snap-manual-lab33 \
  --storage-location=${REGION} \
  --description="Manual snapshot for Day 33 lab"

# Verify
gcloud compute snapshots describe data-snap-manual-lab33
gcloud compute snapshots list --filter="name~lab33"
```

### Step 3 — Create a Snapshot Schedule (Resource Policy)

```bash
# Create daily snapshot schedule
gcloud compute resource-policies create snapshot-schedule ${POLICY_NAME} \
  --region=${REGION} \
  --max-retention-days=7 \
  --on-source-disk-delete=keep-auto-snapshots \
  --daily-schedule \
  --start-time=02:00 \
  --storage-location=${REGION}

# Attach the policy to the data disk
gcloud compute disks add-resource-policies data-disk-lab33 \
  --zone=${ZONE} \
  --resource-policies=${POLICY_NAME}

# Verify
gcloud compute resource-policies describe ${POLICY_NAME} --region=${REGION}

gcloud compute disks describe data-disk-lab33 --zone=${ZONE} \
  --format="yaml(resourcePolicies)"
```

### Step 4 — Test Cross-Region Restore

```bash
# Create a disk from the snapshot in a different zone
gcloud compute disks create restored-disk-lab33 \
  --zone=europe-west2-b \
  --source-snapshot=data-snap-manual-lab33 \
  --type=pd-standard

# Create a test VM in the other zone
gcloud compute instances create restore-test-lab33 \
  --zone=europe-west2-b \
  --machine-type=e2-micro \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --disk=name=restored-disk-lab33,auto-delete=no

# Verify data integrity
gcloud compute ssh restore-test-lab33 --zone=europe-west2-b --command="
sudo mkdir -p /mnt/data
sudo mount /dev/sdb /mnt/data
echo '--- Restored Files ---'
ls -la /mnt/data/
echo '--- Content Check ---'
cat /mnt/data/important.txt
echo '--- Checksum Verification ---'
cd /mnt/data && sudo md5sum -c checksums.md5
"
```

### Step 5 — Document Backup Plan

```bash
cat << 'EOF'
=== BACKUP PLAN — Lab 33 ===

Target:        data-disk-lab33 (10GB pd-standard)
Schedule:      Daily at 02:00 UTC
Retention:     7 days (7 snapshots)
Location:      europe-west2
RPO:           24 hours (daily snapshots)
RTO:           ~10 minutes (disk creation + mount)

Restore Procedure:
  1. Identify latest good snapshot
  2. Create disk from snapshot (same or different zone)
  3. Attach to replacement VM
  4. Mount and verify checksums
  5. Update DNS/LB if needed

Validation:
  - Tested:    [DATE]
  - Checksums: PASSED
  - Restore:   ~5 min for 10GB disk
EOF
```

### Step 6 — Terraform Version

```hcl
resource "google_compute_resource_policy" "daily_backup" {
  name    = "daily-backup-tf-lab33"
  region  = "europe-west2"
  project = var.project_id

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
      storage_locations = ["europe-west2"]
      labels = {
        env    = "lab"
        backup = "daily"
      }
    }
  }
}

resource "google_compute_disk" "data" {
  name  = "data-disk-tf-lab33"
  zone  = "europe-west2-a"
  size  = 10
  type  = "pd-standard"

  resource_policies = [google_compute_resource_policy.daily_backup.id]
}

variable "project_id" {
  type = string
}
```

### Cleanup

```bash
# Delete VMs
gcloud compute instances delete ${VM_NAME} --zone=${ZONE} --quiet
gcloud compute instances delete restore-test-lab33 --zone=europe-west2-b --quiet

# Delete disks (if not auto-deleted with VM)
gcloud compute disks delete data-disk-lab33 --zone=${ZONE} --quiet
gcloud compute disks delete restored-disk-lab33 --zone=europe-west2-b --quiet

# Delete snapshots
gcloud compute snapshots delete data-snap-manual-lab33 --quiet

# Delete resource policy
gcloud compute resource-policies delete ${POLICY_NAME} --region=${REGION} --quiet

# Terraform:
# terraform destroy -auto-approve
```

---

## Part 3 — Revision (15 min)

### Key Concepts

- Snapshots are **incremental** but each is **independently restorable**
- **Snapshot schedules** (resource policies) automate backups — like cron for snapshots
- **RPO** = max data loss time; **RTO** = max downtime to recover
- Cross-region snapshots enable **disaster recovery** to another region
- **Untested backups are not backups** — validate with regular restore tests
- Snapshots capture **disk-level** state — flush writes before snapshotting

### Essential Commands

```bash
# Manual snapshot
gcloud compute disks snapshot DISK --zone=ZONE \
  --snapshot-names=NAME --storage-location=REGION

# List/describe snapshots
gcloud compute snapshots list
gcloud compute snapshots describe NAME

# Snapshot schedule (resource policy)
gcloud compute resource-policies create snapshot-schedule NAME \
  --region=REGION --max-retention-days=N --daily-schedule --start-time=HH:MM

# Attach policy to disk
gcloud compute disks add-resource-policies DISK --zone=ZONE \
  --resource-policies=POLICY

# Restore from snapshot
gcloud compute disks create NEW-DISK --zone=ZONE \
  --source-snapshot=SNAPSHOT

# Delete snapshot
gcloud compute snapshots delete NAME
```

---

## Part 4 — Quiz (15 min)

<details>
<summary><strong>Q1: Your production DB VM needs RPO of 1 hour and RTO of 15 minutes. How do you configure backups?</strong></summary>

**Answer:**

**For RPO ≤ 1 hour:**
- Create an **hourly snapshot schedule** on the database disk
- Use `--hourly-schedule --hours-in-cycle=1` flag
- Retention: keep 24-168 snapshots depending on compliance needs
- Store in the same region for fastest restore

**For RTO ≤ 15 minutes:**
- Pre-create a **standby VM** (stopped) with the same machine type and network config
- On failure: create a disk from the latest snapshot (~2-5 min for small disks), attach to standby VM, start VM (~1 min), verify DB consistency (~2-3 min)
- Automate with a Cloud Function triggered by uptime check failure

**Additional measures:**
- Enable disk `fsfreeze` or use application-consistent snapshots for the DB
- Consider persistent disk replication (`pd-balanced` with `--replica-zones`) for near-zero RPO
</details>

<details>
<summary><strong>Q2: Are GCP snapshots full or incremental? What happens if you delete an intermediate snapshot?</strong></summary>

**Answer:** GCP snapshots are **incremental** — only changed blocks since the last snapshot are stored. However, they are **independently restorable** because:

When you **delete an intermediate snapshot**, GCP automatically handles the chain:
- Any blocks that the deleted snapshot held exclusively are **moved** to the next snapshot
- No data loss occurs — the remaining snapshots remain fully restorable
- This is transparent to the user

**Example:**
```
Snap1 [A,B,C] → Snap2 [A',D] → Snap3 [B',E]
Delete Snap2 → blocks A',D moved to Snap3
Snap1 [A,B,C] → Snap3 [A',B',D,E] (all data preserved)
```

This is different from LVM snapshots on Linux, where chain dependencies are strict.
</details>

<details>
<summary><strong>Q3: How do you take an application-consistent snapshot of a VM running a MySQL database?</strong></summary>

**Answer:**

1. **Flush and lock the database:**
   ```bash
   mysql -e "FLUSH TABLES WITH READ LOCK;"
   ```

2. **Freeze the filesystem:**
   ```bash
   sudo fsfreeze --freeze /mnt/data
   ```

3. **Take the snapshot:**
   ```bash
   gcloud compute disks snapshot data-disk --zone=ZONE --snapshot-names=db-consistent-snap
   ```

4. **Unfreeze and unlock:**
   ```bash
   sudo fsfreeze --unfreeze /mnt/data
   mysql -e "UNLOCK TABLES;"
   ```

**For automation:** Use a startup-script or cron job that wraps these steps, or use GCP's **VSS integration** for Windows or scripted hooks for Linux. You can also use **guest flush** with the `--guest-flush` flag if the guest environment supports it.
</details>

<details>
<summary><strong>Q4: What's the difference between a snapshot schedule retention of 7 days vs 30 days in terms of cost and protection?</strong></summary>

**Answer:**

| Aspect | 7-day retention | 30-day retention |
|---|---|---|
| **Max snapshots** | 7 (daily) | 30 (daily) |
| **Recovery window** | Can restore up to 7 days back | Can restore up to 30 days back |
| **Storage cost** | Lower (fewer snapshots stored) | ~4x higher |
| **Protection** | Covers accidental deletion within a week | Covers corruption discovered late |
| **RPO unchanged** | 24 hours (daily schedule) | 24 hours (daily schedule) |

**Cost efficiency tip:** Since snapshots are incremental, the cost difference between 7 and 30 days depends on the **change rate** of the disk. If data changes rarely (static content), 30-day retention costs only slightly more. If data changes heavily (databases), the incremental blocks add up significantly.

**Recommendation:** Use 7-day for dev/test, 30-day for prod, and combine with lifecycle policies on the snapshot storage location.
</details>
