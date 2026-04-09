# Day 35 — Backup & Restore Runbook

> **Week 6 — Storage & Backup** | ⏱ 2 hours | Region: `europe-west2`

---

## Part 1 — Concept (30 min)

### Why Runbooks?

A runbook is a **step-by-step operational procedure** that anyone on the team can follow — even at 3 AM under pressure. In Linux ops, you've likely had tribal knowledge in someone's head. Runbooks make that explicit.

**Linux analogy:**

| Linux Ops | Structured Runbook |
|---|---|
| "Ask Dave, he knows how to restore the DB" | Documented restore procedure with exact commands |
| Notes in /root/README.txt | Versioned runbook in Git with review history |
| "Run the backup script" (which one? where?) | Step-by-step with pre-checks and verification |
| "It worked last time" | Tested quarterly with documented results |

### Runbook Structure

```
┌─────────────────────────────────────────────────────┐
│              Runbook Template Structure              │
│                                                     │
│  1. HEADER                                          │
│     ├── Title, Version, Last Tested                 │
│     ├── Author, Reviewers                           │
│     └── RTO/RPO Targets                             │
│                                                     │
│  2. PREREQUISITES                                   │
│     ├── Required permissions                        │
│     ├── Tools / CLI versions                        │
│     └── Access to resources                         │
│                                                     │
│  3. BACKUP PROCEDURE                                │
│     ├── Pre-flight checks                           │
│     ├── Step-by-step backup commands                │
│     └── Verification after backup                   │
│                                                     │
│  4. RESTORE PROCEDURE                               │
│     ├── Identify the correct backup                 │
│     ├── Step-by-step restore commands               │
│     ├── Post-restore verification                   │
│     └── Service restart / cutover                   │
│                                                     │
│  5. VALIDATION                                      │
│     ├── Data integrity checks                       │
│     ├── Application health checks                   │
│     └── Sign-off checklist                          │
│                                                     │
│  6. TROUBLESHOOTING                                 │
│     ├── Common errors and fixes                     │
│     └── Escalation contacts                         │
│                                                     │
│  7. TEST LOG                                        │
│     ├── Date tested, by whom                        │
│     ├── Duration, issues found                      │
│     └── Sign-off                                    │
└─────────────────────────────────────────────────────┘
```

### RTO / RPO Verification

```
┌───────────────────────────────────────────────────┐
│           RTO/RPO Verification Process            │
│                                                   │
│  STEP 1: Record last backup timestamp             │
│          RPO_actual = now - last_backup_time       │
│          RPO_actual <= RPO_target? ✓               │
│                                                   │
│  STEP 2: Start timer                              │
│          Execute full restore procedure            │
│          Stop timer when service is UP             │
│          RTO_actual = elapsed_time                 │
│          RTO_actual <= RTO_target? ✓               │
│                                                   │
│  STEP 3: Record in test log                       │
│          ┌──────────────────────────────────┐     │
│          │ Date:      2026-04-08            │     │
│          │ Tester:    V. Brabhaharan        │     │
│          │ RPO_target: 24h  RPO_actual: 22h │     │
│          │ RTO_target: 30m  RTO_actual: 12m │     │
│          │ Result:    PASS                  │     │
│          └──────────────────────────────────┘     │
└───────────────────────────────────────────────────┘
```

### Common Restore Patterns

| Scenario | What to Restore | Method |
|---|---|---|
| Disk corruption | Single disk | Snapshot → new disk → swap |
| VM failure | Entire VM | Machine image → new VM |
| Accidental file delete | Specific files | GCS versioning → restore object |
| Region outage | Full workload | Cross-region snapshot → new region |
| Config drift | OS baseline | Golden image → rebuild VM |

---

## Part 2 — Hands-On Lab (60 min)

### Goal: Write and Test a Complete Backup/Restore Runbook

### Step 1 — Set Up the Environment

```bash
export PROJECT_ID=$(gcloud config get-value project)
export ZONE=europe-west2-a
export REGION=europe-west2
export VM_NAME="runbook-vm-lab35"
export DISK_DATA="runbook-data-lab35"

# Create VM with a data disk
gcloud compute instances create ${VM_NAME} \
  --zone=${ZONE} \
  --machine-type=e2-micro \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --boot-disk-size=10GB \
  --create-disk=name=${DISK_DATA},size=10GB,type=pd-standard,auto-delete=yes \
  --tags=lab35

# Set up data on the data disk
gcloud compute ssh ${VM_NAME} --zone=${ZONE} --command="
sudo mkfs.ext4 /dev/sdb
sudo mkdir -p /mnt/data
sudo mount /dev/sdb /mnt/data
echo 'Production database record 1' | sudo tee /mnt/data/db-001.dat
echo 'Production database record 2' | sudo tee /mnt/data/db-002.dat
echo 'Application config v3.1' | sudo tee /mnt/data/app-config.yaml
sudo md5sum /mnt/data/* | sudo tee /mnt/data/checksums.md5
echo '--- Files on data disk ---'
ls -la /mnt/data/
cat /mnt/data/checksums.md5
"
```

### Step 2 — Write the Runbook

Create this runbook document — this IS the deliverable:

```bash
cat > /tmp/backup_restore_runbook.md << 'RUNBOOK_EOF'
# Backup & Restore Runbook — runbook-vm-lab35

| Field | Value |
|---|---|
| Version | 1.0 |
| Author | V. Brabhaharan |
| Last Tested | YYYY-MM-DD |
| RTO Target | 15 minutes |
| RPO Target | 24 hours |
| Region | europe-west2 |
| Zone | europe-west2-a |

## Prerequisites

- [ ] `gcloud` CLI authenticated with project access
- [ ] Permissions: `compute.snapshots.create`, `compute.disks.create`, `compute.instances.create`
- [ ] Access to the target VM and disk names
- [ ] This runbook reviewed within the last 90 days

## 1. Backup Procedure

### 1.1 Pre-Flight Checks

```bash
# Verify the VM and disk exist
gcloud compute instances describe runbook-vm-lab35 --zone=europe-west2-a --format="value(status)"
gcloud compute disks describe runbook-data-lab35 --zone=europe-west2-a --format="value(status)"

# Check current snapshot count
gcloud compute snapshots list --filter="sourceDisk~runbook-data-lab35" --format="table(name,creationTimestamp,diskSizeGb)"
```

### 1.2 Create Snapshot

```bash
# Flush writes (if possible — SSH to VM first)
gcloud compute ssh runbook-vm-lab35 --zone=europe-west2-a --command="sudo sync"

# Create snapshot with timestamp
SNAP_NAME="runbook-data-$(date +%Y%m%d-%H%M%S)"
gcloud compute disks snapshot runbook-data-lab35 \
  --zone=europe-west2-a \
  --snapshot-names=${SNAP_NAME} \
  --storage-location=europe-west2 \
  --description="Scheduled backup - $(date)"
```

### 1.3 Verify Backup

```bash
# Confirm snapshot exists
gcloud compute snapshots describe ${SNAP_NAME}

# Record size
gcloud compute snapshots describe ${SNAP_NAME} --format="value(storageBytes)"
```

## 2. Restore Procedure

### 2.1 Identify Backup to Restore

```bash
# List available snapshots (newest first)
gcloud compute snapshots list \
  --filter="sourceDisk~runbook-data-lab35" \
  --sort-by=~creationTimestamp \
  --format="table(name,creationTimestamp,storageBytes)"

# Choose the snapshot to restore
RESTORE_SNAP="<snapshot-name-from-above>"
```

### 2.2 Create Disk from Snapshot

```bash
gcloud compute disks create restored-data-lab35 \
  --zone=europe-west2-a \
  --source-snapshot=${RESTORE_SNAP} \
  --type=pd-standard
```

### 2.3 Swap Disks on VM

```bash
# Stop VM
gcloud compute instances stop runbook-vm-lab35 --zone=europe-west2-a

# Detach old disk
gcloud compute instances detach-disk runbook-vm-lab35 \
  --zone=europe-west2-a \
  --disk=runbook-data-lab35

# Attach restored disk
gcloud compute instances attach-disk runbook-vm-lab35 \
  --zone=europe-west2-a \
  --disk=restored-data-lab35

# Start VM
gcloud compute instances start runbook-vm-lab35 --zone=europe-west2-a
```

### 2.4 Post-Restore Verification

```bash
gcloud compute ssh runbook-vm-lab35 --zone=europe-west2-a --command="
sudo mkdir -p /mnt/data
sudo mount /dev/sdb /mnt/data
echo '--- Restored Files ---'
ls -la /mnt/data/
echo '--- Checksum Verification ---'
cd /mnt/data && sudo md5sum -c checksums.md5
echo '--- Content Verification ---'
cat /mnt/data/db-001.dat
cat /mnt/data/app-config.yaml
"
```

## 3. Validation Checklist

- [ ] All files present on restored disk
- [ ] Checksums match (md5sum -c passes)
- [ ] Application config is correct version
- [ ] Services start correctly
- [ ] No error messages in system logs

## 4. Troubleshooting

| Issue | Cause | Fix |
|---|---|---|
| Snapshot creation fails | Disk busy or quota exceeded | Check `gcloud compute project-info describe` for quota |
| Mount fails after restore | Different device name | Check `lsblk`, try `/dev/sdb` or `/dev/sdc` |
| Checksum mismatch | Writes in progress during snapshot | Use `fsfreeze` before snapshot |
| VM won't start | Boot disk issue | Detach and reattach boot disk |

## 5. Test Log

| Date | Tester | RPO (actual) | RTO (actual) | Result | Notes |
|---|---|---|---|---|---|
| YYYY-MM-DD | V. Brabhaharan | | | | |

RUNBOOK_EOF

echo "Runbook written to /tmp/backup_restore_runbook.md"
```

### Step 3 — Execute the Backup Procedure

```bash
# Follow the runbook — take a backup
gcloud compute ssh ${VM_NAME} --zone=${ZONE} --command="sudo sync"

SNAP_NAME="runbook-data-$(date +%Y%m%d-%H%M%S)"
gcloud compute disks snapshot ${DISK_DATA} \
  --zone=${ZONE} \
  --snapshot-names=${SNAP_NAME} \
  --storage-location=${REGION} \
  --description="Runbook test backup - $(date)"

# Verify
gcloud compute snapshots describe ${SNAP_NAME}
echo "Snapshot created: ${SNAP_NAME}"
```

### Step 4 — Simulate Disaster

```bash
# Corrupt the data
gcloud compute ssh ${VM_NAME} --zone=${ZONE} --command="
echo 'CORRUPTED DATA' | sudo tee /mnt/data/db-001.dat
echo '--- Data is now corrupted ---'
cat /mnt/data/db-001.dat
cd /mnt/data && sudo md5sum -c checksums.md5
"
# Should show: FAILED for db-001.dat
```

### Step 5 — Execute the Restore Procedure (Time It!)

```bash
echo "=== RESTORE START: $(date) ==="

# Create restored disk
gcloud compute disks create restored-data-lab35 \
  --zone=${ZONE} \
  --source-snapshot=${SNAP_NAME} \
  --type=pd-standard

# Stop VM, swap disks
gcloud compute instances stop ${VM_NAME} --zone=${ZONE}

gcloud compute instances detach-disk ${VM_NAME} \
  --zone=${ZONE} \
  --disk=${DISK_DATA}

gcloud compute instances attach-disk ${VM_NAME} \
  --zone=${ZONE} \
  --disk=restored-data-lab35

gcloud compute instances start ${VM_NAME} --zone=${ZONE}
sleep 20

# Verify
gcloud compute ssh ${VM_NAME} --zone=${ZONE} --command="
sudo mkdir -p /mnt/data
sudo mount /dev/sdb /mnt/data
echo '--- Restored Files ---'
ls -la /mnt/data/
echo '--- Checksum Verification ---'
cd /mnt/data && sudo md5sum -c checksums.md5
"

echo "=== RESTORE COMPLETE: $(date) ==="
```

### Cleanup

```bash
# Delete VM (deletes attached disks with auto-delete)
gcloud compute instances delete ${VM_NAME} --zone=${ZONE} --quiet

# Delete detached original disk (if it still exists)
gcloud compute disks delete ${DISK_DATA} --zone=${ZONE} --quiet 2>/dev/null

# Delete snapshot
gcloud compute snapshots delete ${SNAP_NAME} --quiet

# Clean up local files
rm -f /tmp/backup_restore_runbook.md
```

---

## Part 3 — Revision (15 min)

### Key Concepts

- A **runbook** is a step-by-step procedure anyone can follow under pressure
- Every runbook needs: prerequisites, procedure, verification, troubleshooting, test log
- **RTO** = how long to restore; **RPO** = how much data you lose — both must be **measured**
- **Untested runbooks are fiction** — schedule regular restore tests (quarterly minimum)
- Document the **swap pattern**: create new disk from snapshot → detach old → attach new
- Include **pre-flight checks** (does the resource exist? do I have permissions?)

### Runbook Checklist

```
[ ] Header with version, author, RTO/RPO targets
[ ] Prerequisites with permissions and tools
[ ] Backup procedure with pre-flight checks
[ ] Restore procedure with exact commands
[ ] Post-restore verification (checksums, service health)
[ ] Troubleshooting table for common issues
[ ] Test log with dates and results
[ ] Reviewed within last 90 days
```

---

## Part 4 — Quiz (15 min)

<details>
<summary><strong>Q1: Why is testing a backup/restore runbook regularly more important than writing it?</strong></summary>

**Answer:**

1. **Environments change** — new disks, renamed resources, updated permissions. A runbook written 6 months ago may reference resources that no longer exist.
2. **Commands break** — API changes, deprecated flags, new gcloud versions.
3. **Team knowledge** — new team members need to practice. A runbook that only the author has executed is a single point of failure.
4. **Timing validation** — the only way to verify RTO is to measure it. A runbook that claims "15 min RTO" but actually takes 45 min is dangerous.
5. **Confidence under pressure** — at 3 AM during an outage, you need muscle memory, not guesswork.

**Best practice:** Test quarterly. Rotate who executes the test so everyone is familiar with the procedure.
</details>

<details>
<summary><strong>Q2: Your restore test shows an RTO of 25 minutes but the SLA requires 15 minutes. What do you do?</strong></summary>

**Answer:** Optimize the recovery chain:

1. **Pre-create the restored disk** — keep a warm standby disk from the latest snapshot (reduces disk creation time)
2. **Use a pre-configured standby VM** — stopped VM with everything configured, just needs disk swap and start
3. **Automate the procedure** — script the entire restore into a single script/Cloud Function that can be triggered in one command
4. **Reduce disk size** — smaller disks restore faster. Separate OS from data.
5. **Use regional persistent disks** — replicated across zones, near-instant failover
6. **Parallel steps** — identify which steps can run concurrently (e.g., DNS update while VM is starting)

If optimization still can't meet 15 min, **renegotiate the SLA** with documented evidence of realistic RTO, or upgrade to a higher-availability architecture (active-active, replication).
</details>

<details>
<summary><strong>Q3: What's the difference between a backup runbook and a disaster recovery plan?</strong></summary>

**Answer:**

| Aspect | Backup Runbook | Disaster Recovery Plan |
|---|---|---|
| **Scope** | Single resource (disk, VM, bucket) | Entire workload / application |
| **Trigger** | Data corruption, accidental delete | Region/zone outage, major failure |
| **Steps** | Restore from snapshot/backup | Failover to secondary site/region |
| **People** | On-call engineer | Incident commander + team |
| **Communication** | Update ticket | Stakeholder notifications, war room |
| **Testing** | Restore a single disk | Full DR drill with all systems |
| **Duration** | Minutes | Hours to days |

A backup runbook is a **component** of a DR plan. The DR plan orchestrates multiple runbooks together with communication, escalation, and business continuity steps.
</details>

<details>
<summary><strong>Q4: You have 10 VMs with daily snapshot schedules. How do you verify all backups are running successfully?</strong></summary>

**Answer:**

1. **List recent snapshots and check timestamps:**
   ```bash
   gcloud compute snapshots list \
     --sort-by=~creationTimestamp \
     --format="table(name,sourceDisk.basename(),creationTimestamp)" \
     --limit=20
   ```

2. **Set up a monitoring script:**
   ```bash
   for disk in disk1 disk2 ... disk10; do
     LATEST=$(gcloud compute snapshots list \
       --filter="sourceDisk~${disk}" \
       --sort-by=~creationTimestamp \
       --limit=1 \
       --format="value(creationTimestamp)")
     # Alert if latest snapshot is older than 25 hours
   done
   ```

3. **Use Cloud Monitoring** — create a custom metric or alert policy on snapshot age
4. **Cloud Audit Logs** — monitor for `compute.snapshots.insert` events
5. **Monthly report** — document snapshot counts and ages per VM in a tracking spreadsheet
</details>
