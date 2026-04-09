# Week 1, Day 3 (Wed) — Compute Engine VM Components

## Today's Objective

Understand the core components that make up a Compute Engine VM — machine types, images, disks, networking, and metadata. Create a Linux VM, SSH via Cloud Shell, and document the configuration.

**Source:** [Skills Boost: Create a VM](https://www.cloudskillsboost.google/focuses/3563) | [Docs: Compute Engine](https://cloud.google.com/compute/docs)

**Deliverable:** SSH proof (screenshot) + VM config notes

---

## Part 1: Concept (30 minutes)

### 1.1 VM Building Blocks

```
┌─────────────────────────────────────────────────────────────┐
│                    COMPUTE ENGINE VM                         │
│                                                              │
│   ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐  │
│   │  Machine Type │  │   Boot Disk  │  │  Network Interface│  │
│   │  vCPUs + RAM  │  │  OS Image    │  │  VPC / Subnet    │  │
│   │  e.g. e2-micro│  │  Size + Type │  │  Internal/Ext IP │  │
│   └──────────────┘  └──────────────┘  └──────────────────┘  │
│                                                              │
│   ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐  │
│   │  Metadata    │  │  Service     │  │  Labels / Tags   │  │
│   │  startup-    │  │  Account     │  │  env:dev         │  │
│   │  script, keys│  │  IAM scopes  │  │  team:data       │  │
│   └──────────────┘  └──────────────┘  └──────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### 1.2 Machine Type Families

| Family | Prefix | Use Case |
|---|---|---|
| **General purpose** | `e2`, `n2`, `n2d` | Web servers, dev/test, balanced workloads |
| **Compute optimized** | `c2`, `c2d` | HPC, batch, single-threaded apps |
| **Memory optimized** | `m2`, `m3` | In-memory DBs (SAP HANA, Redis) |
| **Accelerator optimized** | `a2`, `g2` | ML training, GPU workloads |

#### Common Types for Learning

| Type | vCPUs | RAM | Free Tier? |
|---|---|---|---|
| `e2-micro` | 0.25 (shared) | 1 GB | Yes |
| `e2-small` | 0.5 (shared) | 2 GB | No |
| `e2-medium` | 1 (shared) | 4 GB | No |
| `e2-standard-2` | 2 | 8 GB | No |

### 1.3 Images & Boot Disks

| OS Family | Image | Notes |
|---|---|---|
| Debian | `debian-12` | Default, lightweight |
| Ubuntu | `ubuntu-2204-lts` | Popular, large community |
| Rocky Linux | `rocky-linux-9` | CentOS replacement |
| Container-Optimized OS | `cos-stable` | Minimal, containers only |

### 1.4 Metadata & Startup Scripts

```bash
# Startup script runs on EVERY boot
--metadata=startup-script='#!/bin/bash
apt-get update && apt-get install -y nginx'

# Query metadata from inside the VM
curl -H "Metadata-Flavor: Google" \
  http://metadata.google.internal/computeMetadata/v1/instance/name
```

### 1.5 Service Accounts

| Type | Description |
|---|---|
| **Default SA** | Auto-created, has Editor role (too broad!) |
| **Custom SA** | Best practice — minimal IAM roles |

### 1.6 VM Lifecycle & Billing

| State | CPU/RAM Billed? | Disk Billed? |
|---|---|---|
| RUNNING | Yes | Yes |
| STOPPED | No | Yes |
| DELETED | No | No (if disks also deleted) |

---

## Part 2: Hands-On Lab (60 minutes)

### Step 1: Create a Linux VM (10 min)

```bash
gcloud compute instances create vm-components-lab \
  --zone=europe-west2-a \
  --machine-type=e2-micro \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --boot-disk-size=10GB \
  --boot-disk-type=pd-balanced \
  --tags=lab-vm \
  --labels=env=learning,week=1,day=3 \
  --metadata=startup-script='#!/bin/bash
echo "VM boot: $(date)" > /tmp/startup-log.txt
apt-get update -qq && apt-get install -y -qq tree htop jq'
```

### Step 2: SSH via Cloud Shell (5 min)

```bash
gcloud compute ssh vm-components-lab --zone=europe-west2-a

# Take a screenshot here — this is your SSH proof!
```

### Step 3: Explore the VM (15 min)

```bash
echo "=== Hostname ===" && hostname
echo "=== OS ===" && cat /etc/os-release | grep PRETTY_NAME
echo "=== Kernel ===" && uname -r
echo "=== CPU ===" && lscpu | grep -E "^CPU\(s\)|Model name"
echo "=== Memory ===" && free -h
echo "=== Disk ===" && df -h /
echo "=== Startup Log ===" && cat /tmp/startup-log.txt
echo "=== Extras ===" && which tree htop jq
```

### Step 4: Query Metadata Server (10 min)

```bash
META="http://metadata.google.internal/computeMetadata/v1"
H="Metadata-Flavor: Google"

echo "Name: $(curl -s -H "$H" $META/instance/name)"
echo "Zone: $(curl -s -H "$H" $META/instance/zone)"
echo "Type: $(curl -s -H "$H" $META/instance/machine-type)"
echo "Int IP: $(curl -s -H "$H" $META/instance/network-interfaces/0/ip)"
echo "Ext IP: $(curl -s -H "$H" $META/instance/network-interfaces/0/access-configs/0/external-ip)"
echo "Project: $(curl -s -H "$H" $META/project/project-id)"
echo "SA: $(curl -s -H "$H" $META/instance/service-accounts/default/email)"

exit
```

### Step 5: Describe VM from Outside (10 min)

```bash
gcloud compute instances describe vm-components-lab \
  --zone=europe-west2-a \
  --format="table(name,zone.basename(),machineType.basename(),status,
    networkInterfaces[0].networkIP:label=INT_IP,
    networkInterfaces[0].accessConfigs[0].natIP:label=EXT_IP,
    disks[0].diskSizeGb:label=DISK_GB)"
```

### Step 6: Create via Console (Optional - 5 min)

Navigate to **Compute Engine → VM Instances → CREATE INSTANCE**. Before clicking Create, click **"Equivalent command line"** at the bottom.

### Step 7: Clean Up (5 min)

```bash
gcloud compute instances delete vm-components-lab --zone=europe-west2-a --quiet
```

---

## Part 3: Revision (15 minutes)

- **VM = Machine Type + Image + Disk + Network + Metadata + Service Account**
- `e2-micro` = free tier, 0.25 vCPU shared, 1 GB RAM
- **Startup scripts** run on every boot, delivered via metadata
- **Metadata server** at `169.254.169.254` — query instance identity without hardcoding
- **Default SA** has Editor role (too broad) — use custom SA in production
- **Stopped VMs** still charge for disks. Delete to stop all charges

### Key Commands
```bash
gcloud compute instances create/describe/list/delete/start/stop
gcloud compute machine-types list --zone=ZONE
gcloud compute images list --filter="family:debian"
```

---

## Part 4: Quiz (15 minutes)

**Q1:** What are the 4 machine type families? When to use each?
<details><summary>Answer</summary>General purpose (e2/n2) — balanced. Compute optimized (c2) — HPC. Memory optimized (m2/m3) — in-memory DBs. Accelerator optimized (a2/g2) — ML/GPU.</details>

**Q2:** A VM is STOPPED. What are you still charged for?
<details><summary>Answer</summary>Persistent disks (boot + data) and static external IPs. CPU/RAM charges stop.</details>

**Q3:** How does a startup script get delivered to a VM?
<details><summary>Answer</summary>Via the <b>metadata server</b>. The guest agent reads the <code>startup-script</code> key on boot and executes it. Check results in serial port output or Cloud Logging.</details>

**Q4:** Why not use the default service account in production?
<details><summary>Answer</summary>It has the <b>Editor role</b> (broad read/write access). If the VM is compromised, the attacker has wide access. Use a <b>custom SA</b> with only the needed IAM roles (least privilege).</details>

---

## VM Config Notes Template

```
=== VM Configuration Notes (Week 1, Day 3) ===
VM Name:        vm-components-lab
Zone:           europe-west2-a
Machine Type:   e2-micro
Image:          debian-12
Boot Disk:      10 GB pd-balanced
Internal IP:    _______________
External IP:    _______________
Service Account: _______________
OS:             Debian GNU/Linux 12
Kernel:         _______________
Startup Script: ✅ Ran successfully
Cleanup:        ✅ VM deleted
```
