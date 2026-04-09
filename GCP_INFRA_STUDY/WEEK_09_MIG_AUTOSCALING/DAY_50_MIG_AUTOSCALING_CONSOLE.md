# Day 50 — Create MIG + Autoscaling via Console & gcloud

> **Week 9 · MIG & Autoscaling**
> Estimated time: 2 hours | Region: `europe-west2` (London)
> Prerequisites: Day 49 MIG Concepts completed

---

## Part 1 — Concept (30 min)

### Autoscaling Overview

Autoscaling automatically adjusts the number of VM instances in a MIG based on load. Think of it as a smarter version of spawning worker processes with a process manager.

```
Linux Analogy
─────────────
  Apache MPM prefork:
    MinSpareServers  5    ← min instances
    MaxSpareServers  10
    MaxRequestWorkers 50  ← max instances
    ServerLimit      50

  GCP Autoscaler:
    min_replicas:  2      ← min instances
    max_replicas: 10      ← max instances
    target: cpu=0.6       ← scale trigger
```

### Autoscaling Signals

```
┌─────────────────────────────────────────────────────┐
│                   AUTOSCALER                         │
│                                                      │
│  Signal Sources:                                     │
│  ┌───────────────┐  ┌──────────────┐                │
│  │  CPU Usage    │  │ LB Serving   │                │
│  │  (default)    │  │  Capacity    │                │
│  └───────┬───────┘  └──────┬───────┘                │
│          │                 │                         │
│  ┌───────────────┐  ┌──────────────┐                │
│  │ Cloud Monitor │  │  Pub/Sub     │                │
│  │ Custom Metric │  │  Queue Depth │                │
│  └───────┬───────┘  └──────┬───────┘                │
│          │                 │                         │
│          ▼                 ▼                         │
│  ┌─────────────────────────────────┐                │
│  │   Scaling Decision Engine       │                │
│  │                                 │                │
│  │  current_load > target?         │                │
│  │    → SCALE OUT (add VMs)        │                │
│  │  current_load < target?         │                │
│  │    → SCALE IN  (remove VMs)     │                │
│  └─────────────────────────────────┘                │
│          │                                           │
│          ▼                                           │
│  ┌─────────────────────────────────┐                │
│  │   Enforce min/max boundaries    │                │
│  └─────────────────────────────────┘                │
└─────────────────────────────────────────────────────┘
```

### Autoscaling Metric Types

| Metric Type              | Signal                         | Best For                          |
|--------------------------|--------------------------------|-----------------------------------|
| **CPU utilization**      | Average CPU across all VMs     | General-purpose workloads         |
| **LB serving capacity**  | Requests-per-second per VM     | HTTP backend services             |
| **Custom Cloud Monitor** | Any Cloud Monitoring metric    | Queue depth, custom app metrics   |
| **Pub/Sub queue**        | Unacked messages per VM        | Async processing workers          |

### Scaling Parameters

| Parameter        | Description                                      | Typical Value    |
|------------------|--------------------------------------------------|------------------|
| `min_replicas`   | Minimum instances (never goes below)             | 2 (prod), 1 (dev)|
| `max_replicas`   | Maximum instances (cost ceiling)                 | 10-50            |
| `target`         | Desired utilization level (0.0 - 1.0)            | 0.6 (60%)        |
| `cooldown`       | Seconds to wait before next scaling decision     | 60 (default)     |
| `scale_in_control` | Max VMs to remove per time window              | Varies           |

### Console Workflow

```
Console → Compute Engine → Instance Groups
    │
    ├── 1. Create Instance Template
    │       Machine type, image, startup script, network
    │
    ├── 2. Create Instance Group (Managed)
    │       Select template, set initial size, choose zone/region
    │
    └── 3. Configure Autoscaling
            Enable autoscaling
            Set metric (CPU / LB / Custom)
            Set min, max, target
            Set cooldown period
```

### How the Autoscaler Calculates

```
Recommended Size = CEIL( Current_Load / Target_Utilization )

Example:
  3 VMs, each at 80% CPU, target = 60%

  Total load  = 3 × 0.80 = 2.40
  Recommended = CEIL(2.40 / 0.60) = CEIL(4.0) = 4 VMs

  → Autoscaler adds 1 VM (3 → 4)
```

---

## Part 2 — Hands-On Lab (60 min)

### Lab Objective

Create a MIG with CPU-based autoscaling, generate load to trigger scale-out, and observe the autoscaler in action.

### Step 1 — Set Variables

```bash
export PROJECT_ID=$(gcloud config get-value project)
export REGION=europe-west2
export ZONE=europe-west2-a
```

### Step 2 — Create Instance Template with CPU-Intensive Startup

```bash
gcloud compute instance-templates create autoscale-template \
    --machine-type=e2-micro \
    --image-family=debian-12 \
    --image-project=debian-cloud \
    --region=$REGION \
    --tags=http-server,allow-ssh \
    --metadata=startup-script='#!/bin/bash
apt-get update && apt-get install -y nginx stress-ng
HOSTNAME=$(hostname)
cat > /var/www/html/index.html <<EOF
<h1>Hello from $HOSTNAME</h1>
<p>Instance is running.</p>
EOF
systemctl enable nginx && systemctl start nginx'
```

### Step 3 — Create the MIG

```bash
gcloud compute instance-groups managed create autoscale-mig \
    --template=autoscale-template \
    --size=2 \
    --zone=$ZONE
```

### Step 4 — Configure CPU-Based Autoscaling

```bash
gcloud compute instance-groups managed set-autoscaling autoscale-mig \
    --zone=$ZONE \
    --min-num-replicas=2 \
    --max-num-replicas=6 \
    --target-cpu-utilization=0.60 \
    --cool-down-period=60
```

### Step 5 — Verify Autoscaler Configuration

```bash
# Describe the autoscaler
gcloud compute instance-groups managed describe autoscale-mig \
    --zone=$ZONE \
    --format="yaml(autoscaler)"

# List instances
gcloud compute instance-groups managed list-instances autoscale-mig \
    --zone=$ZONE \
    --format="table(instance.basename(), status, currentAction)"
```

### Step 6 — Create Firewall Rule for Health Checks

```bash
gcloud compute firewall-rules create allow-health-check \
    --network=default \
    --action=allow \
    --direction=ingress \
    --source-ranges=130.211.0.0/22,35.191.0.0/16 \
    --target-tags=http-server \
    --rules=tcp:80
```

### Step 7 — Generate Load to Trigger Scale-Out

```bash
# SSH into one instance and stress the CPU
INSTANCE=$(gcloud compute instance-groups managed list-instances autoscale-mig \
    --zone=$ZONE --format="value(instance)" | head -1)

# Run stress on the VM (2 CPU workers for 300 seconds)
gcloud compute ssh $INSTANCE --zone=$ZONE -- \
    "sudo stress-ng --cpu 2 --timeout 300s &"

# SSH into second instance and stress it too
INSTANCE2=$(gcloud compute instance-groups managed list-instances autoscale-mig \
    --zone=$ZONE --format="value(instance)" | tail -1)

gcloud compute ssh $INSTANCE2 --zone=$ZONE -- \
    "sudo stress-ng --cpu 2 --timeout 300s &"
```

### Step 8 — Monitor Autoscaling

```bash
# Watch instances being added (check every 30 seconds)
watch -n 30 "gcloud compute instance-groups managed list-instances autoscale-mig \
    --zone=$ZONE --format='table(instance.basename(), status)'"

# Check autoscaler status
gcloud compute instance-groups managed describe autoscale-mig \
    --zone=$ZONE \
    --format="value(status.autoscaler.details)"
```

### Step 9 — Observe Scale-In After Load Stops

```bash
# After stress-ng completes (5 min), watch instances being removed
# The autoscaler will gradually scale back to min (2)
watch -n 30 "gcloud compute instance-groups managed list-instances autoscale-mig \
    --zone=$ZONE --format='table(instance.basename(), status)'"
```

### Step 10 — Configure LB-Based Autoscaling (Alternative)

```bash
# Switch to LB utilization metric (for reference)
gcloud compute instance-groups managed set-autoscaling autoscale-mig \
    --zone=$ZONE \
    --min-num-replicas=2 \
    --max-num-replicas=6 \
    --target-load-balancing-utilization=0.8

# Switch back to CPU for cleanup
gcloud compute instance-groups managed set-autoscaling autoscale-mig \
    --zone=$ZONE \
    --min-num-replicas=2 \
    --max-num-replicas=6 \
    --target-cpu-utilization=0.60
```

### Cleanup

```bash
# Delete MIG (also deletes instances)
gcloud compute instance-groups managed delete autoscale-mig --zone=$ZONE --quiet

# Delete firewall rule
gcloud compute firewall-rules delete allow-health-check --quiet

# Delete template
gcloud compute instance-templates delete autoscale-template --quiet
```

---

## Part 3 — Revision (15 min)

### Key Concepts

- Autoscaling adjusts MIG size based on **metrics** (CPU, LB, custom, Pub/Sub)
- **Target utilization** is the desired metric level (e.g., 60% CPU)
- Formula: `recommended_size = CEIL(total_load / target_utilization)`
- **Cooldown period** prevents thrashing — waits N seconds between scale actions
- **min_replicas** ensures minimum availability; **max_replicas** caps cost
- Scale-out is fast (minutes); scale-in is gradual (conservative)
- Multiple metrics can be combined — autoscaler picks the one requiring the most instances

### Essential Commands

```bash
# Set CPU-based autoscaling
gcloud compute instance-groups managed set-autoscaling NAME \
    --zone=ZONE \
    --min-num-replicas=MIN \
    --max-num-replicas=MAX \
    --target-cpu-utilization=0.6 \
    --cool-down-period=60

# Set LB-based autoscaling
gcloud compute instance-groups managed set-autoscaling NAME \
    --zone=ZONE \
    --target-load-balancing-utilization=0.8

# Stop autoscaling (revert to manual)
gcloud compute instance-groups managed stop-autoscaling NAME --zone=ZONE

# Check autoscaler status
gcloud compute instance-groups managed describe NAME --zone=ZONE
```

---

## Part 4 — Quiz (15 min)

**Question 1: A MIG has 3 VMs each at 90% CPU. Target utilization is 60%. How many VMs will the autoscaler recommend?**

<details>
<summary>Show Answer</summary>

**5 VMs.**

Calculation:
- Total load = 3 × 0.90 = 2.70
- Recommended = CEIL(2.70 / 0.60) = CEIL(4.5) = **5**

The autoscaler will add 2 VMs (3 → 5) to bring average CPU down to ~54% (2.70 / 5).

</details>

**Question 2: What happens if you set the cooldown period too short?**

<details>
<summary>Show Answer</summary>

The autoscaler may **thrash** — rapidly scaling out and in because it makes decisions before new instances have fully warmed up and started handling load. New VMs take time to boot, install software, and register with health checks. A too-short cooldown means the autoscaler sees the same high load, adds more VMs, then sees low load once they all come up, and removes them. Default is 60 seconds; for apps with longer startup times, use 120-300 seconds.

</details>

**Question 3: You configure both CPU (target 60%) and LB utilization (target 80%) on the same autoscaler. If CPU says "need 4 VMs" and LB says "need 6 VMs", how many VMs will be created?**

<details>
<summary>Show Answer</summary>

**6 VMs.** When multiple autoscaling signals are configured, the autoscaler picks the signal that results in the **largest** number of instances. This ensures all metrics are satisfied. In this case, 6 VMs satisfies both the CPU requirement (4) and the LB requirement (6).

</details>

**Question 4: You want to prevent the autoscaler from removing more than 2 VMs in a 10-minute window. How do you configure this?**

<details>
<summary>Show Answer</summary>

Use **scale-in controls**:

```bash
gcloud compute instance-groups managed update-autoscaling my-mig \
    --zone=europe-west2-a \
    --scale-in-control max-scaled-in-replicas=2,time-window=600
```

Scale-in controls limit how aggressively the autoscaler removes instances. This prevents sudden capacity drops during traffic fluctuations. The `time-window` is in seconds (600 = 10 minutes).

</details>

---

*Next: [Day 51 — Terraform MIG](DAY_51_TERRAFORM_MIG.md)*
