# Day 49 — Managed Instance Group (MIG) Concepts

> **Week 9 · MIG & Autoscaling**
> Estimated time: 2 hours | Region: `europe-west2` (London)
> Prerequisites: ACE-level GCE knowledge, Weeks 1-8 completed

---

## Part 1 — Concept (30 min)

### What Is a Managed Instance Group?

A **Managed Instance Group (MIG)** is a collection of identical VM instances that GCP manages as a single entity. Think of it as `systemd` managing multiple identical worker processes — if one dies, systemd restarts it automatically.

```
Linux Analogy
─────────────
  systemd service (Type=notify, Restart=always)
       │
       ├── worker-1   ← if killed, systemd restarts it
       ├── worker-2
       └── worker-3

  MIG (target_size=3)
       │
       ├── instance-1   ← if unhealthy, MIG recreates it
       ├── instance-2
       └── instance-3
```

### Core Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    MANAGED INSTANCE GROUP                     │
│                                                               │
│  ┌──────────────────┐                                        │
│  │ Instance Template │──── "Blueprint" for every VM           │
│  │  - machine type   │     (like a Packer / cloud-init        │
│  │  - boot disk      │      template)                         │
│  │  - startup script │                                        │
│  │  - network/tags   │                                        │
│  └────────┬─────────┘                                        │
│           │                                                   │
│           ▼                                                   │
│  ┌────────────────────────────────────────────┐              │
│  │  VM-1  │  VM-2  │  VM-3  │ ... │  VM-N    │              │
│  │ (zone) │ (zone) │ (zone) │     │ (zone)   │              │
│  └────────────────────────────────────────────┘              │
│           │                                                   │
│           ▼                                                   │
│  ┌──────────────────┐    ┌─────────────────┐                │
│  │   Autoscaler     │    │  Health Check   │                │
│  │ (scale 1..N)     │    │ (auto-heal)     │                │
│  └──────────────────┘    └─────────────────┘                │
└─────────────────────────────────────────────────────────────┘
```

### Instance Templates

An instance template is an **immutable blueprint** — you cannot edit it, only create a new version.

| Property          | Description                              | Linux Analogy              |
|-------------------|------------------------------------------|----------------------------|
| Machine type      | CPU/RAM spec (e.g. `e2-medium`)          | Hardware allocation        |
| Boot disk image   | OS image or custom image                 | ISO / golden image         |
| Startup script    | Runs on every boot                       | `/etc/rc.local` or systemd |
| Network / Subnetwork | VPC placement                         | Interface bond config      |
| Service account   | API identity for the VM                  | Run-as user (`--user=`)    |
| Labels / Tags     | Metadata for firewall & org              | SELinux labels             |
| Metadata          | Key-value pairs                          | `/etc/sysconfig` vars      |

### Stateless vs Stateful MIG

| Feature               | Stateless MIG                        | Stateful MIG                         |
|------------------------|--------------------------------------|--------------------------------------|
| Use case               | Web frontends, API servers           | Databases, legacy apps               |
| Disk behaviour         | Ephemeral; recreated from template   | Persistent disks preserved           |
| IP behaviour           | New IP on recreation                 | Can preserve internal/external IP    |
| Instance names         | Auto-generated                       | Can be preserved                     |
| Auto-healing           | Delete + recreate from scratch       | Recreate keeping state               |
| Linux analogy          | Stateless containers (`docker run`)  | VMs with `/data` mounts             |
| Scaling                | Full autoscaling support             | Limited (manual or cautious scaling) |

### Zonal vs Regional MIG

```
Zonal MIG (single zone)             Regional MIG (multi-zone)
┌──────────────────┐                ┌──────────────────────────────────┐
│ europe-west2-a   │                │ europe-west2-a  │  europe-west2-b │
│  VM-1            │                │  VM-1           │   VM-3          │
│  VM-2            │                │  VM-2           │   VM-4          │
│  VM-3            │                │                 │                 │
└──────────────────┘                │ europe-west2-c  │                 │
                                    │  VM-5           │                 │
                                    │  VM-6           │                 │
                                    └──────────────────────────────────┘
```

| Aspect              | Zonal MIG                   | Regional MIG                       |
|----------------------|-----------------------------|------------------------------------|
| Availability         | Single zone                 | Spreads across up to 3 zones       |
| Max instances        | Up to 1,000                 | Up to 2,000                        |
| Zone failure impact  | All instances affected      | Only ~1/3 affected                 |
| Use case             | Dev/test, cost-sensitive    | Production, HA workloads           |
| Linux analogy        | Single-rack deployment      | Multi-rack / multi-DC deployment   |

### When to Use MIG

| Scenario                        | Use MIG? | Reason                                        |
|---------------------------------|----------|-----------------------------------------------|
| Stateless web app               | ✅ Yes   | Perfect fit — auto-heal + autoscale           |
| Backend API fleet               | ✅ Yes   | Identical workers, easy to scale              |
| Batch processing workers        | ✅ Yes   | Scale out for jobs, scale in when idle        |
| Database primary                | ❌ No    | Use Cloud SQL or single-instance management   |
| Legacy app with local state     | ⚠️ Maybe | Stateful MIG with persistent disks            |
| One-off dev/test VM             | ❌ No    | Overhead; just create a standalone VM         |
| Behind a load balancer          | ✅ Yes   | MIG integrates directly with GCP LB           |

### Key MIG Operations

| Operation          | What It Does                                 | gcloud flag / concept        |
|--------------------|----------------------------------------------|------------------------------|
| Create             | Launches N identical VMs from template        | `--size=N`                   |
| Resize             | Change target size manually                  | `resize --new-size=N`        |
| Rolling update     | Gradually migrate to new template            | `rolling-action start-update`|
| Canary update      | Update subset to test new template           | `--canary-version`           |
| Auto-heal          | Replace failed instances via health check    | `--health-check`             |
| Autoscale          | Dynamically adjust size based on metrics     | `autoscaling-policies`       |

---

## Part 2 — Hands-On Lab (60 min)

### Lab Objective

Create an instance template and deploy both a zonal and regional MIG to understand the differences.

### Step 1 — Set Variables

```bash
export PROJECT_ID=$(gcloud config get-value project)
export REGION=europe-west2
export ZONE=europe-west2-a
```

### Step 2 — Create an Instance Template

```bash
gcloud compute instance-templates create web-template-v1 \
    --machine-type=e2-micro \
    --image-family=debian-12 \
    --image-project=debian-cloud \
    --region=$REGION \
    --tags=http-server \
    --metadata=startup-script='#!/bin/bash
apt-get update && apt-get install -y nginx
HOSTNAME=$(hostname)
echo "<h1>Hello from $HOSTNAME</h1>" > /var/www/html/index.html
systemctl start nginx'
```

### Step 3 — Verify the Template

```bash
# List templates (like listing Packer templates)
gcloud compute instance-templates list

# Describe the template
gcloud compute instance-templates describe web-template-v1
```

### Step 4 — Create a Zonal MIG

```bash
gcloud compute instance-groups managed create zonal-mig \
    --template=web-template-v1 \
    --size=2 \
    --zone=$ZONE

# Watch instances come up
watch -n 5 "gcloud compute instance-groups managed list-instances zonal-mig --zone=$ZONE"
```

### Step 5 — Create a Regional MIG

```bash
gcloud compute instance-groups managed create regional-mig \
    --template=web-template-v1 \
    --size=3 \
    --region=$REGION

# See how instances spread across zones
gcloud compute instance-groups managed list-instances regional-mig \
    --region=$REGION \
    --format="table(instance, zone, status)"
```

### Step 6 — Test MIG Self-Healing

```bash
# Delete one instance manually (simulate crash)
INSTANCE_NAME=$(gcloud compute instance-groups managed list-instances zonal-mig \
    --zone=$ZONE --format="value(instance)" | head -1)

gcloud compute instances delete $INSTANCE_NAME --zone=$ZONE --quiet

# Watch MIG recreate it automatically
watch -n 5 "gcloud compute instance-groups managed list-instances zonal-mig --zone=$ZONE"
```

### Step 7 — Inspect MIG Details

```bash
# Describe the MIG
gcloud compute instance-groups managed describe zonal-mig --zone=$ZONE

# Check the current target size
gcloud compute instance-groups managed describe zonal-mig \
    --zone=$ZONE \
    --format="value(targetSize)"
```

### Cleanup

```bash
# Delete MIGs
gcloud compute instance-groups managed delete zonal-mig --zone=$ZONE --quiet
gcloud compute instance-groups managed delete regional-mig --region=$REGION --quiet

# Delete template
gcloud compute instance-templates delete web-template-v1 --quiet
```

---

## Part 3 — Revision (15 min)

### Key Concepts

- A **MIG** manages a fleet of identical VMs created from an **instance template**
- Instance templates are **immutable** — create new versions, don't edit
- **Stateless MIG**: ephemeral VMs, full autoscaling (web servers, APIs)
- **Stateful MIG**: preserves disks/IPs across recreation (databases, legacy)
- **Zonal MIG**: single zone, simpler, cheaper
- **Regional MIG**: multi-zone (up to 3), HA, production-grade
- MIG provides **auto-healing**: detects failures and recreates instances
- MIG supports **rolling updates** and **canary deployments**
- Max instances: 1,000 (zonal), 2,000 (regional)

### Essential Commands

```bash
# Instance templates
gcloud compute instance-templates create NAME --machine-type=TYPE --image-family=FAM
gcloud compute instance-templates list
gcloud compute instance-templates describe NAME

# Zonal MIG
gcloud compute instance-groups managed create NAME --template=TPL --size=N --zone=ZONE
gcloud compute instance-groups managed list-instances NAME --zone=ZONE
gcloud compute instance-groups managed resize NAME --new-size=N --zone=ZONE

# Regional MIG
gcloud compute instance-groups managed create NAME --template=TPL --size=N --region=REGION
gcloud compute instance-groups managed list-instances NAME --region=REGION

# Delete
gcloud compute instance-groups managed delete NAME --zone=ZONE --quiet
```

---

## Part 4 — Quiz (15 min)

**Question 1: What is the primary difference between a zonal and regional MIG?**

<details>
<summary>Show Answer</summary>

A **zonal MIG** deploys all instances in a single zone, while a **regional MIG** distributes instances across up to 3 zones in a region. Regional MIGs provide higher availability — if one zone has an outage, only ~1/3 of instances are affected. For production workloads, regional MIGs are recommended.

</details>

**Question 2: You need to run a legacy application that stores session data on local disk. Which MIG type should you use?**

<details>
<summary>Show Answer</summary>

Use a **Stateful MIG**. Stateful MIGs preserve persistent disks, IP addresses, and instance names across recreation events. This ensures the local session data survives auto-healing. However, consider migrating session storage to an external service (Redis, Memorystore) for a fully stateless architecture.

</details>

**Question 3: An instance template has an incorrect startup script. How do you fix it?**

<details>
<summary>Show Answer</summary>

Instance templates are **immutable** — you cannot edit them. You must:
1. Create a **new** instance template with the corrected startup script
2. Perform a **rolling update** on the MIG to migrate instances to the new template
3. Optionally delete the old template

```bash
gcloud compute instance-templates create web-template-v2 --machine-type=e2-micro ...
gcloud compute instance-groups managed rolling-action start-update my-mig \
    --version=template=web-template-v2 --zone=europe-west2-a
```

</details>

**Question 4: You delete a VM that belongs to a MIG. What happens?**

<details>
<summary>Show Answer</summary>

The MIG automatically **recreates** the deleted instance to maintain the target size. This is the auto-healing behaviour — the MIG constantly reconciles actual state with desired state. This is analogous to `systemd` with `Restart=always` — if the process dies, systemd brings it back. The new instance is created from the current instance template.

</details>

---

*Next: [Day 50 — MIG Autoscaling via Console & gcloud](DAY_50_MIG_AUTOSCALING_CONSOLE.md)*
