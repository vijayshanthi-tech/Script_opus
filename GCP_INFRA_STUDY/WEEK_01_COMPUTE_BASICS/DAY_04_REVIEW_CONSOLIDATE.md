# Week 1, Day 4 (Thu) — Review & Consolidate (Days 1-3)

## Today's Objective

Consolidate everything from Days 1-3: SSH/OS Login, Disks/Snapshots, and VM Components. Fill gaps, link concepts together, and build a cheat sheet.

**Deliverable:** Consolidated notes document covering all Week 1 concepts so far

---

## Part 1: Concept Review (30 minutes)

### 1.1 How Everything Connects

```
┌──────────────────────────────────────────────────────────────┐
│                  COMPLETE VM PICTURE                           │
│                                                               │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │  ACCESS (Day 1)                                         │  │
│  │  • OS Login (IAM-controlled, recommended)               │  │
│  │  • Metadata SSH keys (simple, less secure)              │  │
│  │  • IAP Tunnel (no external IP needed)                   │  │
│  └─────────────────────────────────────────────────────────┘  │
│                          │                                    │
│                          ▼                                    │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │  VM COMPONENTS (Day 3)                                  │  │
│  │  • Machine Type (CPU + RAM)                             │  │
│  │  • Image (OS template → boot disk)                      │  │
│  │  • Network (VPC, IPs, firewall)                         │  │
│  │  • Metadata (startup script, SSH keys, custom)          │  │
│  │  • Service Account (API access identity)                │  │
│  │  • Labels/Tags (organization, cost, firewall targeting) │  │
│  └─────────────────────────────────────────────────────────┘  │
│                          │                                    │
│                          ▼                                    │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │  STORAGE & BACKUP (Day 2)                               │  │
│  │  • Boot disk (pd-balanced default)                      │  │
│  │  • Data disk (separate, survives VM deletion)           │  │
│  │  • Snapshots (incremental backup, global)               │  │
│  │  • Snapshot schedules (automated daily/weekly)          │  │
│  │  • Images (golden template for cloning)                 │  │
│  └─────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────┘
```

### 1.2 Decision Matrix — "What Should I Use?"

| Scenario | Solution |
|---|---|
| Need to SSH securely to a team VM | OS Login + IAP Tunnel |
| VM has no external IP | `gcloud compute ssh --tunnel-through-iap` |
| Need to back up a data disk | Snapshot (incremental, cheap) |
| Need to create 10 identical VMs | Custom Image from golden VM |
| Need to clone entire VM (all disks + config) | Machine Image |
| Need daily automatic backups | Snapshot Schedule |
| Need cheapest possible VM for labs | `e2-micro` (free tier) |
| Need to install packages on first boot | Startup script in metadata |
| VM needs to access GCS but nothing else | Custom Service Account with `storage.objectViewer` role |

---

## Part 2: Hands-On — Integration Exercise (60 minutes)

Build a complete VM setup using everything from Days 1-3:

### Step 1: Create a Custom Service Account (5 min)

```bash
# Create SA with minimal permissions
gcloud iam service-accounts create lab-vm-sa \
  --display-name="Lab VM Service Account"

# Grant only logging and monitoring write
gcloud projects add-iam-policy-binding $(gcloud config get-value project) \
  --member="serviceAccount:lab-vm-sa@$(gcloud config get-value project).iam.gserviceaccount.com" \
  --role="roles/logging.logWriter"

gcloud projects add-iam-policy-binding $(gcloud config get-value project) \
  --member="serviceAccount:lab-vm-sa@$(gcloud config get-value project).iam.gserviceaccount.com" \
  --role="roles/monitoring.metricWriter"
```

### Step 2: Create a Complete VM (10 min)

```bash
PROJECT_ID=$(gcloud config get-value project)

gcloud compute instances create review-lab-vm \
  --zone=europe-west2-a \
  --machine-type=e2-micro \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --boot-disk-size=10GB \
  --boot-disk-type=pd-balanced \
  --create-disk=name=review-data-disk,size=20GB,type=pd-standard,auto-delete=no \
  --service-account=lab-vm-sa@${PROJECT_ID}.iam.gserviceaccount.com \
  --scopes=logging-write,monitoring-write \
  --metadata=enable-oslogin=TRUE \
  --tags=lab-vm,no-external-access \
  --labels=env=learning,week=1,day=4
```

### Step 3: SSH via IAP and Set Up Data Disk (10 min)

```bash
gcloud compute ssh review-lab-vm --zone=europe-west2-a

# Mount data disk
sudo mkfs.ext4 -m 0 -F /dev/sdb
sudo mkdir -p /mnt/data
sudo mount /dev/sdb /mnt/data
sudo chmod a+w /mnt/data

# Create test data
echo "Review lab data - $(date)" > /mnt/data/testfile.txt
echo "Configuration v1" > /mnt/data/config.txt

exit
```

### Step 4: Take a Snapshot (5 min)

```bash
gcloud compute snapshots create review-snapshot \
  --source-disk=review-data-disk \
  --source-disk-zone=europe-west2-a \
  --labels=week=1,type=review
```

### Step 5: Verify Everything (15 min)

```bash
echo "=== VM Details ==="
gcloud compute instances describe review-lab-vm \
  --zone=europe-west2-a \
  --format="yaml(name,machineType.basename(),serviceAccounts[0].email,metadata,labels,tags,disks)"

echo ""
echo "=== Disks ==="
gcloud compute disks list --filter="zone:europe-west2-a"

echo ""
echo "=== Snapshots ==="
gcloud compute snapshots list

echo ""
echo "=== Service Account ==="
gcloud iam service-accounts list --filter="email:lab-vm-sa"
```

### Step 6: Simulate Restore (10 min)

```bash
# Delete the VM (data disk survives because auto-delete=no)
gcloud compute instances delete review-lab-vm --zone=europe-west2-a --quiet

# Verify data disk still exists
gcloud compute disks list --filter="name:review-data-disk"

# Recreate VM and attach existing data disk
gcloud compute instances create review-lab-vm-restored \
  --zone=europe-west2-a \
  --machine-type=e2-micro \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --disk=name=review-data-disk,auto-delete=no

# SSH and verify data is intact
gcloud compute ssh review-lab-vm-restored --zone=europe-west2-a
sudo mkdir -p /mnt/data && sudo mount /dev/sdb /mnt/data
cat /mnt/data/testfile.txt
# Should show "Review lab data" from earlier!
exit
```

### Step 7: Clean Up (5 min)

```bash
gcloud compute instances delete review-lab-vm-restored --zone=europe-west2-a --quiet
gcloud compute disks delete review-data-disk --zone=europe-west2-a --quiet
gcloud compute snapshots delete review-snapshot --quiet
gcloud iam service-accounts delete lab-vm-sa@$(gcloud config get-value project).iam.gserviceaccount.com --quiet
```

---

## Part 3: Revision (15 minutes)

### Master Cheat Sheet — Week 1 (Days 1-4)

| Topic | Key Takeaway |
|---|---|
| SSH | OS Login > metadata keys. IAP Tunnel for private VMs |
| Disks | `pd-balanced` default. Data disks: set `auto-delete=no` |
| Snapshots | Incremental, global, cheap. Automate with schedules |
| Machine Types | `e2-micro` for labs. Custom types for specific needs |
| Images | OS template for boot disk. Create custom golden images |
| Metadata | Startup scripts, SSH keys. VM queries at `metadata.google.internal` |
| Service Accounts | Custom SA > default SA. Principle of least privilege |
| Labels/Tags | Labels for cost tracking. Tags for firewall rules |
| Lifecycle | RUNNING = charged. STOPPED = disk charges only. DELETE to stop all |

---

## Part 4: Quiz (15 minutes)

**Q1:** You need a VM that can write logs but cannot read/write to any other service. How do you set this up?
<details><summary>Answer</summary>Create a <b>custom service account</b> with only <code>roles/logging.logWriter</code>. Attach it to the VM. Do NOT use the default service account (which has Editor role).</details>

**Q2:** A VM was deleted but the data disk survived. How is this possible and how do you recover?
<details><summary>Answer</summary>The data disk had <code>auto-delete=no</code> set. To recover: create a new VM and <b>attach the existing disk</b> using <code>--disk=name=DISK_NAME</code>.</details>

**Q3:** Walk through the steps to fully secure SSH access to a production VM.
<details><summary>Answer</summary>1) Enable <b>OS Login</b> (metadata: enable-oslogin=TRUE). 2) Remove external IP. 3) Use <b>IAP Tunnel</b> for SSH. 4) Grant <code>compute.osLogin</code> role only to authorized users. 5) Restrict firewall to IAP ranges only (35.235.240.0/20).</details>

**Q4:** Compare snapshot vs image vs machine image — when to use each.
<details><summary>Answer</summary><b>Snapshot:</b> Back up a single disk (incremental, point-in-time). <b>Image:</b> Template for boot disk to create identical VMs (golden image). <b>Machine Image:</b> Full VM clone (all disks + network + metadata) for migration/DR.</details>
