# Day 2 (Tue) — Compute Engine VM Components

## Today's Objective

Understand the core components that make up a Compute Engine virtual machine — machine types, images, disks, networking, and metadata. Then create a Linux VM, SSH into it via Cloud Shell, and document the configuration.

**Source:** [Google Cloud Skills Boost: Create a VM](https://www.cloudskillsboost.google/focuses/3563) | [Docs: Compute Engine](https://cloud.google.com/compute/docs)

**Deliverable:** SSH proof (screenshot) + VM config notes

---

## Part 1: Concept (30 minutes)

### 1.1 What Is Compute Engine?

Compute Engine is GCP's **Infrastructure as a Service (IaaS)**. It lets you create and run virtual machines on Google's infrastructure.

```
┌─────────────────────────────────────────────────────────────┐
│                    COMPUTE ENGINE VM                         │
│                                                              │
│   ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐  │
│   │  Machine Type │  │   Boot Disk  │  │  Network Interface│  │
│   │              │  │              │  │                  │  │
│   │  vCPUs       │  │  OS Image    │  │  VPC / Subnet    │  │
│   │  Memory (GB) │  │  Size (GB)   │  │  Internal IP     │  │
│   │  (e.g. e2-   │  │  Type (SSD/  │  │  External IP     │  │
│   │   medium)    │  │   HDD)       │  │  Firewall rules  │  │
│   └──────────────┘  └──────────────┘  └──────────────────┘  │
│                                                              │
│   ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐  │
│   │  Metadata    │  │  Service     │  │  Labels / Tags   │  │
│   │              │  │  Account     │  │                  │  │
│   │  startup-    │  │              │  │  env:dev         │  │
│   │  script      │  │  IAM scopes  │  │  team:data       │  │
│   │  ssh-keys    │  │  for API     │  │  purpose:lab     │  │
│   │              │  │  access      │  │                  │  │
│   └──────────────┘  └──────────────┘  └──────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

> **Linux analogy:** Creating a VM on Compute Engine is like provisioning a server — you pick the CPU/RAM spec, choose an OS image (like picking a distro ISO), attach storage, and configure networking. Except there's no racking, no BIOS, no kickstart file.

---

### 1.2 Machine Types

Machine types define the **vCPU and memory** combination for your VM.

#### Machine Type Families

| Family | Prefix | Use Case | Example |
|---|---|---|---|
| **General purpose** | `e2`, `n2`, `n2d`, `n1` | Balanced workloads, web servers, small DBs | `e2-medium` (2 vCPU, 4 GB) |
| **Compute optimized** | `c2`, `c2d` | HPC, gaming, single-threaded apps | `c2-standard-4` (4 vCPU, 16 GB) |
| **Memory optimized** | `m2`, `m3` | In-memory DBs (SAP HANA, Redis) | `m2-ultramem-208` (208 vCPU, 5.75 TB) |
| **Accelerator optimized** | `a2`, `g2` | ML training, GPU workloads | `a2-highgpu-1g` (12 vCPU, 85 GB, 1 A100 GPU) |

#### Common E2 Machine Types (Best for Learning)

| Machine Type | vCPUs | Memory (GB) | Monthly Cost (approx.) |
|---|---|---|---|
| `e2-micro` | 0.25 (shared) | 1 | ~$7 (free tier eligible) |
| `e2-small` | 0.5 (shared) | 2 | ~$14 |
| `e2-medium` | 1 (shared) | 4 | ~$27 |
| `e2-standard-2` | 2 | 8 | ~$49 |
| `e2-standard-4` | 4 | 16 | ~$97 |

#### Custom Machine Types

If predefined types don't fit, you can create **custom machine types**:
```bash
# Example: 6 vCPUs, 20 GB RAM
gcloud compute instances create my-vm \
  --custom-cpu=6 --custom-memory=20GB
```

#### Shared-Core vs Dedicated

| Type | How It Works | Best For |
|---|---|---|
| **Shared-core** (`e2-micro`, `e2-small`, `e2-medium`) | CPU is shared (bursting allowed). Cheapest | Dev/test, lightweight tasks, learning |
| **Dedicated** (`e2-standard-*`, `n2-*`, etc.) | Full vCPU cores. Predictable performance | Production, sustained workloads |

> **Key takeaway:** For all your learning labs, `e2-micro` (free tier) or `e2-small` is more than enough.

---

### 1.3 Images (Operating Systems)

An **image** is the OS template used to create the **boot disk** of a VM.

#### Public Images (Provided by Google)

| OS Family | Image Name | Notes |
|---|---|---|
| **Debian** | `debian-11`, `debian-12` | Default, lightweight, great for labs |
| **Ubuntu** | `ubuntu-2204-lts`, `ubuntu-2404-lts` | Popular, large community |
| **CentOS** | `centos-stream-9` | RHEL-compatible (familiar to you!) |
| **Rocky Linux** | `rocky-linux-9` | CentOS replacement |
| **RHEL** | `rhel-9` | Enterprise, premium image (extra cost) |
| **Windows** | `windows-server-2022-dc` | Premium (license cost) |
| **Container-Optimized OS** | `cos-stable` | Minimal, runs containers only |

#### Custom Images

```bash
# Create a custom image from an existing disk
gcloud compute images create my-golden-image \
  --source-disk=my-vm-disk \
  --source-disk-zone=europe-west2-a
```

> **Linux analogy:** Public images are like official distro ISOs. Custom images are like your golden image/kickstart template that has your standard tools pre-installed.

---

### 1.4 Disks (Storage)

VMs need disks. There are several types:

```
┌───────────────────────────────────────────────────┐
│                    VM Instance                     │
│                                                    │
│  ┌─────────────┐   ┌─────────────┐               │
│  │  Boot Disk   │   │ Additional  │               │
│  │  (required)  │   │   Disk(s)   │               │
│  │              │   │  (optional) │               │
│  │  Contains OS │   │  Data disk  │               │
│  │  10-2048 GB  │   │  10-64TB    │               │
│  └─────────────┘   └─────────────┘               │
│                                                    │
│  Also attachable:                                  │
│  • Local SSD (375 GB each, ephemeral, ultra-fast) │
│  • Cloud Storage bucket (via gcsfuse or gsutil)    │
└───────────────────────────────────────────────────┘
```

#### Disk Types

| Disk Type | Code | IOPS (Read) | Throughput | Cost | Use Case |
|---|---|---|---|---|---|
| **Standard (HDD)** | `pd-standard` | 0.75/GB | 120 MB/s | Cheapest | Bulk storage, logs, backups |
| **Balanced (SSD)** | `pd-balanced` | 6/GB | 240 MB/s | Mid-range | General purpose (best default) |
| **SSD** | `pd-ssd` | 30/GB | 480 MB/s | Higher | Databases, high I/O |
| **Extreme** | `pd-extreme` | 120/GB | 2.4 GB/s | Highest | Enterprise DBs (SAP, Oracle) |
| **Local SSD** | `local-ssd` | 900K total | 9.4 GB/s | N/A (included) | Caching, temp data (ephemeral!) |

#### Key Disk Concepts

| Concept | Explanation |
|---|---|
| **Persistent Disk** | Network-attached, survives VM deletion (if "delete with instance" is unchecked) |
| **Local SSD** | Physically attached to host machine. Extremely fast but **data is lost** when VM stops |
| **Snapshots** | Point-in-time backups of persistent disks. Incremental, stored in Cloud Storage |
| **Auto-delete** | By default, boot disk is deleted when VM is deleted. Can be changed |
| **Resize** | Persistent disks can be resized (increased only) without downtime |

> **Linux analogy:** Persistent disks are like SAN/NAS LUNs. Local SSDs are like directly attached NVMe drives. Snapshots are like LVM snapshots.

---

### 1.5 Networking

Every VM gets a **network interface** connected to a VPC.

```
┌─────────────────────────────────────────┐
│              VPC Network                 │
│                                          │
│    ┌────────────────────────────┐        │
│    │   Subnet: europe-west2     │        │
│    │   Range: 10.154.0.0/20     │        │
│    │                            │        │
│    │   ┌──────────────────┐     │        │
│    │   │      VM          │     │        │
│    │   │                  │     │        │
│    │   │ Internal IP:     │     │        │
│    │   │  10.154.0.2      │     │        │
│    │   │                  │     │        │
│    │   │ External IP:     │     │        │
│    │   │  34.89.xx.xx     │     │        │
│    │   │  (ephemeral or   │     │        │
│    │   │   static)        │     │        │
│    │   └──────────────────┘     │        │
│    └────────────────────────────┘        │
│                                          │
│    Firewall Rules:                       │
│    • default-allow-ssh (tcp:22)          │
│    • default-allow-icmp (ping)           │
│    • default-allow-internal (all in VPC) │
└─────────────────────────────────────────┘
```

#### Networking Concepts

| Concept | Description |
|---|---|
| **VPC** | Virtual Private Cloud — your private network in GCP (like a VLAN) |
| **Subnet** | Regional IP range within a VPC. Auto-mode creates subnets in every region |
| **Internal IP** | Private IP within the subnet. Always assigned. Free |
| **External IP** | Public IP for internet access. Ephemeral (changes on restart) or static (fixed, costs money) |
| **Firewall Rules** | Control inbound/outbound traffic. Based on tags, service accounts, or IP ranges |
| **Network Tags** | Labels on VMs to target firewall rules (e.g., tag `web-server` → allow port 80) |

> **Linux analogy:** A VPC is your network segment. Subnets are your IP ranges. Firewall rules are `iptables`/`firewalld` rules applied at the cloud level.

---

### 1.6 Metadata & Startup Scripts

**Metadata** is key-value data attached to a VM that the VM can query at runtime.

| Metadata Key | Description | Example |
|---|---|---|
| `startup-script` | Shell script that runs on every boot | Install packages, configure services |
| `ssh-keys` | SSH public keys for user access | Auto-injected by `gcloud compute ssh` |
| `shutdown-script` | Runs when the VM is stopping | Graceful shutdown, cleanup |
| Custom keys | Any key-value pair you define | `env=dev`, `role=worker` |

```bash
# Set a startup script when creating a VM
gcloud compute instances create my-vm \
  --metadata=startup-script='#!/bin/bash
apt-get update
apt-get install -y nginx
systemctl start nginx'
```

The VM can query its own metadata from inside:
```bash
# From inside the VM
curl -H "Metadata-Flavor: Google" \
  http://metadata.google.internal/computeMetadata/v1/instance/name
```

> **Linux analogy:** Startup scripts replace cloud-init user data or kickstart %post scripts. Metadata is like instance facts in Ansible.

---

### 1.7 Service Accounts & IAM Scopes

Every VM runs with a **service account** — an identity that determines what GCP APIs the VM can access.

```
┌─────────────────────────────────────────────────┐
│                    VM Instance                   │
│                                                  │
│  Service Account: compute@developer.gsa.google   │
│  Scopes: storage-ro, logging-write, monitoring   │
│                                                  │
│  This VM can:                                    │
│   ✅ Read from GCS                               │
│   ✅ Write logs to Cloud Logging                  │
│   ✅ Send metrics to Cloud Monitoring             │
│   ❌ Write to GCS                                │
│   ❌ Query BigQuery                              │
└─────────────────────────────────────────────────┘
```

| Concept | Description |
|---|---|
| **Default service account** | Auto-created per project (`PROJECT_NUMBER-compute@developer.gserviceaccount.com`). Has Editor role — too broad for production |
| **Custom service account** | Best practice. Create one per app with minimal permissions |
| **Scopes** | Legacy access control. Limits what APIs the VM can call. Being replaced by IAM roles |

> **Best practice:** In production, use a **custom service account** with only the IAM roles needed (principle of least privilege). Avoid the default service account.

---

### 1.8 VM Lifecycle

```
    CREATE ──► STAGING ──► RUNNING ──► STOPPING ──► TERMINATED
                              │                         │
                              │    RESET (reboot)       │
                              ◄─── SUSPEND ────►  SUSPENDED
                              │
                              └──► DELETE (gone forever)
```

| State | Billing | Description |
|---|---|---|
| **RUNNING** | Charged (CPU + RAM + disk) | VM is up and working |
| **STOPPED / TERMINATED** | Disk charged only (no CPU/RAM) | VM is off, disk preserved |
| **SUSPENDED** | Disk + memory charged | VM paused, state saved to disk |
| **DELETED** | Nothing | VM and (optionally) disks are gone |

> **Cost tip:** Always **stop or delete** VMs after labs. A running `e2-medium` costs ~$0.04/hour = ~$27/month.

---

## Part 2: Hands-On Lab (60 minutes)

### Lab: Create a Linux VM + SSH via Cloud Shell

---

### Step 1: Open Cloud Shell (2 min)

1. Go to [console.cloud.google.com](https://console.cloud.google.com)
2. Make sure your project is selected (top-left dropdown)
3. Click the **Cloud Shell** icon (terminal icon, top-right)
4. Wait for the shell to initialize

```bash
# Verify you're in the right project
gcloud config get-value project
```

---

### Step 2: Create a Linux VM via gcloud (10 min)

```bash
# Create a Debian VM in europe-west2-a
gcloud compute instances create lab-vm-day2 \
  --zone=europe-west2-a \
  --machine-type=e2-micro \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --boot-disk-size=10GB \
  --boot-disk-type=pd-balanced \
  --tags=lab-vm \
  --labels=env=learning,day=2 \
  --metadata=startup-script='#!/bin/bash
echo "VM created on $(date)" > /tmp/startup-log.txt
apt-get update -qq
apt-get install -y -qq tree htop jq'
```

**Expected output:**
```
Created [https://www.googleapis.com/compute/v1/projects/YOUR_PROJECT/zones/europe-west2-a/instances/lab-vm-day2].
NAME          ZONE             MACHINE_TYPE  PREEMPTIBLE  INTERNAL_IP  EXTERNAL_IP   STATUS
lab-vm-day2   europe-west2-a   e2-micro                   10.154.0.X   34.89.XX.XX   RUNNING
```

> **What each flag does:**

| Flag | Purpose |
|---|---|
| `--zone` | Where the VM is physically located |
| `--machine-type` | CPU/RAM spec (e2-micro = 0.25 vCPU shared, 1 GB RAM) |
| `--image-family` | OS family (auto-selects latest Debian 12 image) |
| `--image-project` | Where the image lives (Google's public image project) |
| `--boot-disk-size` | Boot disk size in GB |
| `--boot-disk-type` | Disk performance tier |
| `--tags` | Network tags for firewall rules |
| `--labels` | Key-value metadata for organization and billing |
| `--metadata` | Startup script to run on first boot |

---

### Step 3: SSH into the VM via Cloud Shell (5 min)

```bash
# SSH into the VM
gcloud compute ssh lab-vm-day2 --zone=europe-west2-a
```

**First time:** gcloud will generate SSH keys and push them to the VM. You may be prompted to set a passphrase (press Enter to skip).

**Expected output:**
```
WARNING: The private SSH key file for gcloud does not exist.
WARNING: The public SSH key file for gcloud does not exist.
WARNING: You do not have an SSH key for gcloud.
WARNING: SSH keygen will be executed to generate a key.
Generating public/private rsa key pair.
...
your-username@lab-vm-day2:~$
```

> **Take a screenshot here for your deliverable!** This proves SSH access is working.

---

### Step 4: Explore the VM from Inside (15 min)

Run these commands inside the VM to understand its configuration:

```bash
# === SYSTEM INFO ===
echo "=== Hostname ==="
hostname

echo "=== OS Version ==="
cat /etc/os-release | grep PRETTY_NAME

echo "=== Kernel ==="
uname -r

echo "=== CPU Info ==="
lscpu | grep -E "^CPU\(s\)|Model name|Thread"

echo "=== Memory ==="
free -h

echo "=== Disk ==="
df -h /

echo "=== Disk Type (check for SSD vs HDD) ==="
lsblk

echo "=== Startup Script Result ==="
cat /tmp/startup-log.txt

echo "=== Installed extras (from startup script) ==="
which tree && tree --version
which htop && htop --version
which jq && jq --version
```

**Expected output (approximate):**
```
=== Hostname ===
lab-vm-day2

=== OS Version ===
PRETTY_NAME="Debian GNU/Linux 12 (bookworm)"

=== Kernel ===
6.1.0-XX-cloud-amd64

=== CPU Info ===
CPU(s):          2
Model name:      Intel(R) Xeon(R) CPU @ 2.20GHz

=== Memory ===
              total        used        free
Mem:          983Mi        XXXMi       XXXMi

=== Disk ===
Filesystem      Size  Used Avail Use% Mounted on
/dev/sda1       9.8G  1.5G  7.9G  16% /
```

---

### Step 5: Query Instance Metadata from Inside the VM (10 min)

The metadata server is accessible at `169.254.169.254` or `metadata.google.internal`:

```bash
# Base URL shorthand
METADATA="http://metadata.google.internal/computeMetadata/v1"
HEADER="Metadata-Flavor: Google"

echo "=== Instance Name ==="
curl -s -H "$HEADER" "$METADATA/instance/name"
echo ""

echo "=== Zone ==="
curl -s -H "$HEADER" "$METADATA/instance/zone"
echo ""

echo "=== Machine Type ==="
curl -s -H "$HEADER" "$METADATA/instance/machine-type"
echo ""

echo "=== Internal IP ==="
curl -s -H "$HEADER" "$METADATA/instance/network-interfaces/0/ip"
echo ""

echo "=== External IP ==="
curl -s -H "$HEADER" "$METADATA/instance/network-interfaces/0/access-configs/0/external-ip"
echo ""

echo "=== Project ID ==="
curl -s -H "$HEADER" "$METADATA/project/project-id"
echo ""

echo "=== Service Account ==="
curl -s -H "$HEADER" "$METADATA/instance/service-accounts/default/email"
echo ""

echo "=== All Instance Attributes ==="
curl -s -H "$HEADER" "$METADATA/instance/attributes/?recursive=true"
echo ""
```

> **Why this matters:** Many GCP services and scripts use the metadata server to discover their own identity, project, and service account — without hardcoding anything.

---

### Step 6: View VM Details from gcloud (5 min)

Exit the VM first:
```bash
exit
```

Back in Cloud Shell:
```bash
# Describe the full VM configuration
gcloud compute instances describe lab-vm-day2 \
  --zone=europe-west2-a \
  --format="yaml(name,zone,machineType,status,disks,networkInterfaces,labels,metadata,serviceAccounts)"
```

Also try a summary table:
```bash
# List all VMs
gcloud compute instances list

# Formatted output for your notes
gcloud compute instances describe lab-vm-day2 \
  --zone=europe-west2-a \
  --format="table(
    name,
    zone.basename(),
    machineType.basename(),
    status,
    networkInterfaces[0].networkIP:label=INTERNAL_IP,
    networkInterfaces[0].accessConfigs[0].natIP:label=EXTERNAL_IP,
    disks[0].diskSizeGb:label=DISK_GB
  )"
```

---

### Step 7: Create the Same VM via Console (Optional - 10 min)

For comparison, create a VM using the Console UI:

1. Go to **Compute Engine → VM Instances → CREATE INSTANCE**
2. Observe all the fields — they map exactly to the `gcloud` flags:

| Console Field | gcloud Flag | Value |
|---|---|---|
| Name | (positional) | `lab-vm-console` |
| Region / Zone | `--zone` | `europe-west2-a` |
| Machine type | `--machine-type` | `e2-micro` |
| Boot disk → Change | `--image-family`, `--boot-disk-*` | Debian 12, 10 GB, Balanced |
| Networking → Network tags | `--tags` | `lab-vm` |
| Management → Labels | `--labels` | `env=learning` |
| Management → Metadata | `--metadata` | startup-script |

3. **Before clicking Create**, click **"Equivalent command line"** at the bottom — this gives you the exact `gcloud` command
4. Click **CREATE**

---

### Step 8: Clean Up (3 min)

**Important: Delete VMs to avoid charges.**

```bash
# Delete the VM (boot disk auto-deletes by default)
gcloud compute instances delete lab-vm-day2 \
  --zone=europe-west2-a \
  --quiet

# If you created the console VM too:
gcloud compute instances delete lab-vm-console \
  --zone=europe-west2-a \
  --quiet

# Verify no VMs are running
gcloud compute instances list
```

**Expected output:**
```
Listed 0 items.
```

---

## Part 3: Revision (15 minutes)

### 5-Minute Revision Sheet

#### VM Components at a Glance

| Component | What It Is | Key Choices |
|---|---|---|
| **Machine Type** | CPU + RAM spec | `e2-micro` (free tier) for labs; `e2-standard-*` for workloads |
| **Image** | OS template for boot disk | Debian 12 (default), Ubuntu, CentOS, Rocky Linux, RHEL |
| **Boot Disk** | Persistent disk with OS | `pd-balanced` (good default), 10-2048 GB |
| **Network** | VPC + subnet + IPs + firewall | Auto-mode VPC for learning; custom VPC for production |
| **Metadata** | Key-value pairs (startup script, SSH keys) | `startup-script`, custom keys |
| **Service Account** | VM's identity for API access | Default (broad), Custom (best practice) |
| **Labels** | Key-value tags for organization | `env:dev`, `team:data` |
| **Tags** | Network tags for firewall targeting | `web-server`, `allow-ssh` |

#### Machine Type Cheat Sheet

| Need | Machine Type | vCPU | RAM |
|---|---|---|---|
| Free tier / labs | `e2-micro` | 0.25 (shared) | 1 GB |
| Light workloads | `e2-small` | 0.5 (shared) | 2 GB |
| General purpose | `e2-medium` | 1 (shared) | 4 GB |
| Production | `e2-standard-2` | 2 | 8 GB |
| Heavy compute | `c2-standard-4` | 4 | 16 GB |
| Lots of memory | `n2-highmem-4` | 4 | 32 GB |

#### Disk Type Cheat Sheet

| Disk | IOPS | Best For |
|---|---|---|
| `pd-standard` | Low | Logs, backup, cheap storage |
| `pd-balanced` | Medium | Default for most VMs |
| `pd-ssd` | High | Databases |
| `local-ssd` | Very High | Cache, temp data (**ephemeral!**) |

#### Key gcloud Commands

```bash
# Create a VM
gcloud compute instances create VM_NAME \
  --zone=ZONE --machine-type=TYPE --image-family=IMAGE

# SSH into a VM
gcloud compute ssh VM_NAME --zone=ZONE

# List all VMs
gcloud compute instances list

# Describe a VM (full details)
gcloud compute instances describe VM_NAME --zone=ZONE

# Stop a VM (disk charges only)
gcloud compute instances stop VM_NAME --zone=ZONE

# Start a stopped VM
gcloud compute instances start VM_NAME --zone=ZONE

# Delete a VM
gcloud compute instances delete VM_NAME --zone=ZONE --quiet

# List available machine types in a zone
gcloud compute machine-types list --zone=ZONE

# List available images
gcloud compute images list --filter="family:debian"
```

---

## Part 4: Quiz (15 minutes)

### Self-Test Questions

**Q1:** What are the four main machine type families in Compute Engine? When would you use each?
<details>
<summary>Answer</summary>
<b>General purpose</b> (e2, n2) — balanced workloads, web servers, dev/test.<br>
<b>Compute optimized</b> (c2) — HPC, gaming, batch processing, single-threaded apps.<br>
<b>Memory optimized</b> (m2, m3) — in-memory databases (SAP HANA, Redis), large dataset analytics.<br>
<b>Accelerator optimized</b> (a2, g2) — ML training/inference, GPU workloads.
</details>

**Q2:** What's the difference between a persistent disk and a local SSD?
<details>
<summary>Answer</summary>
<b>Persistent disk:</b> Network-attached storage. Survives VM stop/delete (if configured). Can be resized, snapshotted, and attached to other VMs.<br>
<b>Local SSD:</b> Physically attached to the host machine. Extremely fast (900K IOPS) but <b>ephemeral</b> — data is lost when the VM stops, is preempted, or the host fails. Use only for caches or temporary data.
</details>

**Q3:** You need a VM with 6 vCPUs and 20 GB RAM, but no predefined machine type matches. What do you do?
<details>
<summary>Answer</summary>
Create a <b>custom machine type</b>:<br>
<code>gcloud compute instances create my-vm --custom-cpu=6 --custom-memory=20GB</code><br>
Custom machine types let you specify exact vCPU and memory configurations.
</details>

**Q4:** Explain the difference between an internal IP and an external IP. When would a VM not need an external IP?
<details>
<summary>Answer</summary>
<b>Internal IP:</b> Private IP within the VPC subnet. Always assigned. Used for communication between resources in the same VPC. Free.<br>
<b>External IP:</b> Public IP for internet access. Can be ephemeral (changes on restart) or static (fixed, ~$3/month when not attached to a running VM).<br>
A VM doesn't need an external IP when: it only communicates within the VPC, accesses the internet via a <b>Cloud NAT</b> gateway, or is behind a <b>load balancer</b>. Removing external IPs improves security.
</details>

**Q5:** Why is using the default service account on a production VM a bad practice?
<details>
<summary>Answer</summary>
The default service account has the <b>Editor role</b> on the project, which grants read/write access to almost all resources. This violates the <b>principle of least privilege</b>. If the VM is compromised, the attacker has broad access. Best practice: create a <b>custom service account</b> with only the specific IAM roles the VM needs.
</details>

**Q6:** A VM is in TERMINATED state. Are you still being charged?
<details>
<summary>Answer</summary>
You are <b>not charged for CPU and memory</b> when the VM is stopped/terminated. However, you are <b>still charged for persistent disks</b> (boot disk and any data disks) and <b>static external IPs</b> that remain reserved. To stop all charges, delete the VM and its disks.
</details>

**Q7:** How does a startup script get delivered to the VM? Where would you check if it ran successfully?
<details>
<summary>Answer</summary>
The startup script is stored in the VM's <b>metadata</b> (key: <code>startup-script</code>). On boot, the guest agent reads it from the metadata server (<code>http://metadata.google.internal</code>) and executes it.<br>
To check if it ran: look at <b>serial port output</b> (<code>gcloud compute instances get-serial-port-output VM_NAME</code>) or check <b>Cloud Logging</b> → <code>syslog</code> for the metadata script runner logs.
</details>

**Q8:** You want to find out a VM's project ID and zone from inside the VM (without hardcoding). How?
<details>
<summary>Answer</summary>
Query the <b>metadata server</b>:<br>
<code>curl -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/project/project-id</code><br>
<code>curl -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/zone</code><br>
The metadata server is always available at <code>169.254.169.254</code> or <code>metadata.google.internal</code> and requires the <code>Metadata-Flavor: Google</code> header.
</details>

---

## Deliverable Checklist

- [ ] **SSH proof screenshot** — Terminal showing `your-username@lab-vm-day2:~$` prompt
- [ ] **VM config notes** — Copy the outputs from Step 4 (system info) and Step 6 (gcloud describe) into a notes file

### VM Config Notes Template

Save this as your deliverable:

```
=== VM Configuration Notes (Day 2) ===
Date: ____________________

VM Name:        lab-vm-day2
Zone:           europe-west2-a
Machine Type:   e2-micro
Image:          debian-12
Boot Disk:      10 GB pd-balanced
Internal IP:    10.154.0.____
External IP:    34.89.____.____ 
Service Account: ____-compute@developer.gserviceaccount.com

OS:             Debian GNU/Linux 12 (bookworm)
Kernel:         6.1.0-__-cloud-amd64
CPU(s):         ____
Memory:         ____ MB
Disk Used:      ____ / 9.8 GB

Startup Script: Ran successfully (checked /tmp/startup-log.txt)
Installed:      tree, htop, jq via startup script

Metadata Server Test:
  - Instance name: ✅
  - Zone: ✅
  - Machine type: ✅
  - Internal/External IP: ✅
  - Service Account: ✅

Cleanup:        VM deleted after lab ✅
```

---

## What's Next

Tomorrow (Day 3) continues with the next topic in your study plan. You now understand all the building blocks of a Compute Engine VM — machine types, disks, networking, metadata, and service accounts.
