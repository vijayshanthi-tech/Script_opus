# Week 1, Day 2 (Tue) — Disks & Snapshots

## Today's Objective

Master Persistent Disk types, snapshots, disk management, and restore procedures on Compute Engine.

**Source:** [Docs: Persistent Disk](https://cloud.google.com/compute/docs/disks) | [Docs: Snapshots](https://cloud.google.com/compute/docs/disks/create-snapshots)

**Deliverable:** Snapshot proof (screenshot) + step-by-step restore notes

---

## Part 1: Concept (30 minutes)

### 1.1 Disk Types on Compute Engine

```
┌──────────────────────────────────────────────────────────┐
│                    DISK TYPES                              │
│                                                           │
│  ┌────────────┐ ┌────────────┐ ┌──────────┐ ┌─────────┐  │
│  │pd-standard │ │pd-balanced │ │ pd-ssd   │ │pd-extreme│  │
│  │            │ │            │ │          │ │          │  │
│  │ HDD-backed │ │ SSD-backed │ │ SSD high │ │ SSD max  │  │
│  │ Low IOPS   │ │ Mid IOPS   │ │ IOPS     │ │ IOPS     │  │
│  │ Cheapest   │ │ Best       │ │ Databases│ │ SAP/     │  │
│  │ Logs/bulk  │ │ default    │ │          │ │ Oracle   │  │
│  └────────────┘ └────────────┘ └──────────┘ └─────────┘  │
│                                                           │
│  ┌────────────────┐                                       │
│  │   Local SSD    │  Physically attached. Blazing fast.   │
│  │   (ephemeral!) │  Data LOST on stop/delete/preempt.    │
│  └────────────────┘                                       │
└──────────────────────────────────────────────────────────┘
```

| Disk Type | IOPS (read/GB) | Throughput | Cost ($/GB/mo) | Use Case |
|---|---|---|---|---|
| `pd-standard` | 0.75 | 120 MB/s | ~$0.04 | Logs, backups, bulk storage |
| `pd-balanced` | 6 | 240 MB/s | ~$0.10 | General purpose (best default) |
| `pd-ssd` | 30 | 480 MB/s | ~$0.17 | Databases, high I/O |
| `pd-extreme` | 120 | 2.4 GB/s | ~$0.125 | Enterprise DBs (provisioned IOPS) |
| `local-ssd` | 900K total | 9.4 GB/s | included w/ VM | Caching, temp data only |

### 1.2 Persistent Disk Key Concepts

| Concept | Description |
|---|---|
| **Network-attached** | PDs connect over network, not physically. Can detach and reattach |
| **Zonal / Regional** | Zonal PDs live in one zone. Regional PDs replicate across 2 zones (HA) |
| **Resize only up** | Can increase size online, never shrink |
| **Multi-reader** | PDs can attach read-only to multiple VMs (zonal PDs only) |
| **Auto-delete** | Boot disk auto-deletes with VM by default (configurable) |
| **Encryption** | Always encrypted at rest (Google-managed, CMEK, or CSEK) |

### 1.3 Snapshots — Point-in-Time Backups

```
┌───────────────────────────────────────────────────┐
│               SNAPSHOT LIFECYCLE                    │
│                                                    │
│  Disk ──► Snapshot 1 (full)                        │
│            │                                       │
│            ├──► Snapshot 2 (incremental)            │
│            │     │                                  │
│            │     ├──► Snapshot 3 (incremental)      │
│            │     │                                  │
│  Each snapshot only stores CHANGED blocks           │
│  since the previous snapshot                        │
│                                                    │
│  Restore: Create new disk from any snapshot         │
└───────────────────────────────────────────────────┘
```

| Feature | Detail |
|---|---|
| **Incremental** | Only changed blocks since last snapshot are stored |
| **Global resource** | Snapshots can be used to create disks in ANY region |
| **Scheduling** | Snapshot schedules can automate regular backups |
| **Consistency** | Crash-consistent by default. For app-consistent: freeze I/O or stop VM |
| **Storage location** | Multi-regional (default), regional, or specific location |
| **Cost** | Only charged for stored bytes (incremental = cheap) |

### 1.4 Snapshot vs Image vs Machine Image

| Type | What It Captures | Use Case |
|---|---|---|
| **Snapshot** | Single disk contents | Backup, DR, point-in-time recovery |
| **Image** | Boot disk + metadata (machine type, etc.) | Create identical VMs (golden images) |
| **Machine Image** | Entire VM (all disks, network, metadata) | Full VM clone/migration |

---

## Part 2: Hands-On Lab (60 minutes)

### Step 1: Create a VM with a Data Disk (10 min)

```bash
# Create a VM with boot disk + additional data disk
gcloud compute instances create disk-lab-vm \
  --zone=europe-west2-a \
  --machine-type=e2-micro \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --boot-disk-size=10GB \
  --boot-disk-type=pd-balanced \
  --create-disk=name=data-disk,size=20GB,type=pd-standard,auto-delete=no

# Verify disks
gcloud compute disks list --filter="zone:europe-west2-a"
```

### Step 2: Format and Mount the Data Disk (10 min)

```bash
# SSH into VM
gcloud compute ssh disk-lab-vm --zone=europe-west2-a

# Inside the VM:
# List block devices
lsblk

# Format the data disk (usually /dev/sdb)
sudo mkfs.ext4 -m 0 -F -E lazy_itable_init=0,lazy_journal_init=0 /dev/sdb

# Create mount point and mount
sudo mkdir -p /mnt/data
sudo mount -o discard,defaults /dev/sdb /mnt/data
sudo chmod a+w /mnt/data

# Add to fstab for persistence
echo UUID=$(sudo blkid -s UUID -o value /dev/sdb) /mnt/data ext4 discard,defaults,nofail 0 2 | sudo tee -a /etc/fstab

# Create test data
echo "Important data - $(date)" > /mnt/data/important.txt
echo "Config file v1" > /mnt/data/config.txt
ls -la /mnt/data/

exit
```

### Step 3: Create a Snapshot (10 min)

```bash
# Create snapshot of data disk
gcloud compute snapshots create data-disk-snapshot-v1 \
  --source-disk=data-disk \
  --source-disk-zone=europe-west2-a \
  --description="First snapshot with test data" \
  --labels=env=lab,day=2

# List snapshots
gcloud compute snapshots list

# Describe the snapshot
gcloud compute snapshots describe data-disk-snapshot-v1
```

### Step 4: Modify Data and Take Another Snapshot (10 min)

```bash
# SSH back in and modify data
gcloud compute ssh disk-lab-vm --zone=europe-west2-a

echo "New data added - $(date)" >> /mnt/data/important.txt
echo "Config file v2 - updated" > /mnt/data/config.txt
echo "Brand new file" > /mnt/data/newfile.txt
cat /mnt/data/important.txt

exit

# Take incremental snapshot
gcloud compute snapshots create data-disk-snapshot-v2 \
  --source-disk=data-disk \
  --source-disk-zone=europe-west2-a \
  --description="Second snapshot - incremental"

# Compare snapshot sizes
gcloud compute snapshots list \
  --format="table(name,diskSizeGb,storageBytes.yesno(yes='Has Data', no='Empty'),status)"
```

### Step 5: Restore from Snapshot (15 min)

```bash
# Create a new disk from snapshot v1 (the earlier one)
gcloud compute disks create restored-data-disk \
  --source-snapshot=data-disk-snapshot-v1 \
  --zone=europe-west2-a \
  --type=pd-standard

# Attach to VM
gcloud compute instances attach-disk disk-lab-vm \
  --disk=restored-data-disk \
  --zone=europe-west2-a \
  --mode=ro

# SSH in and verify the restored data
gcloud compute ssh disk-lab-vm --zone=europe-west2-a

sudo mkdir -p /mnt/restored
sudo mount -o ro /dev/sdc /mnt/restored

echo "=== Original (current) ==="
cat /mnt/data/important.txt
echo ""
echo "=== Restored (from snapshot v1) ==="
cat /mnt/restored/important.txt
echo ""
echo "=== Check for newfile.txt (should NOT exist in restored) ==="
ls /mnt/restored/newfile.txt 2>&1

exit
```

### Step 6: Create a Snapshot Schedule (5 min)

```bash
# Create a snapshot schedule (daily at 2 AM UTC, keep 7 days)
gcloud compute resource-policies create snapshot-schedule daily-backup \
  --region=europe-west2 \
  --max-retention-days=7 \
  --on-source-disk-delete=keep-auto-snapshots \
  --daily-schedule \
  --start-time=02:00

# Attach schedule to disk
gcloud compute disks add-resource-policies data-disk \
  --resource-policies=daily-backup \
  --zone=europe-west2-a

# Verify
gcloud compute resource-policies describe daily-backup --region=europe-west2
```

### Step 7: Clean Up

```bash
gcloud compute instances delete disk-lab-vm --zone=europe-west2-a --quiet
gcloud compute disks delete data-disk restored-data-disk --zone=europe-west2-a --quiet
gcloud compute snapshots delete data-disk-snapshot-v1 data-disk-snapshot-v2 --quiet
gcloud compute resource-policies delete daily-backup --region=europe-west2 --quiet
```

---

## Part 3: Revision (15 minutes)

- **4 PD types:** `pd-standard` (cheap), `pd-balanced` (default), `pd-ssd` (fast), `pd-extreme` (max)
- **Local SSD:** Fastest but ephemeral — data lost on stop/delete
- **Snapshots** are incremental, global, and can restore to any region
- **Snapshot vs Image:** Snapshot = disk backup; Image = boot template; Machine Image = full VM
- **Snapshot schedules** automate daily/weekly backups with retention
- **PDs can resize up** without downtime, never shrink
- **Regional PDs** replicate across 2 zones for HA

### Key Commands

```bash
gcloud compute disks create DISK --size=SIZE --type=TYPE --zone=ZONE
gcloud compute instances attach-disk VM --disk=DISK --zone=ZONE
gcloud compute snapshots create SNAP --source-disk=DISK --source-disk-zone=ZONE
gcloud compute disks create NEW_DISK --source-snapshot=SNAP --zone=ZONE
gcloud compute resource-policies create snapshot-schedule NAME --daily-schedule --start-time=HH:MM
```

---

## Part 4: Quiz (15 minutes)

**Q1:** What is the difference between `pd-balanced` and `pd-ssd`?
<details><summary>Answer</summary>
Both are SSD-backed. <b>pd-balanced</b> offers 6 IOPS/GB and 240 MB/s throughput — good for most workloads. <b>pd-ssd</b> offers 30 IOPS/GB and 480 MB/s — better for databases and high I/O. pd-ssd costs ~70% more.
</details>

**Q2:** Are snapshots full or incremental?
<details><summary>Answer</summary>
The first snapshot is full. All subsequent snapshots are <b>incremental</b> — only changed blocks since the last snapshot are stored. This makes them storage-efficient and cost-effective.
</details>

**Q3:** You accidentally deleted a VM. The boot disk was auto-deleted. The data disk was not. How do you recover?
<details><summary>Answer</summary>
The data disk still exists (auto-delete=no). Create a new VM and <b>attach the existing data disk</b>: <code>gcloud compute instances attach-disk NEW_VM --disk=data-disk</code>. For the boot disk, you need a <b>snapshot or image</b> taken beforehand.
</details>

**Q4:** Can you shrink a persistent disk from 100GB to 50GB?
<details><summary>Answer</summary>
<b>No.</b> Persistent disks can only be resized <b>upward</b>. You cannot decrease disk size. If you need a smaller disk, create a new smaller disk, copy data over, and delete the old one.
</details>
