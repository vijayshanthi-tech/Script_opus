# Day 53 — Scaling Strategy

> **Week 9 · MIG & Autoscaling**
> Estimated time: 2 hours | Region: `europe-west2` (London)
> Prerequisites: Days 49-52 completed

---

## Part 1 — Concept (30 min)

### Choosing the Right Scaling Signal

```
┌─────────────────────────────────────────────────────────────┐
│             SCALING SIGNAL DECISION TREE                     │
│                                                              │
│  Is your workload...                                         │
│                                                              │
│  CPU-bound?                                                  │
│  (computation, encoding, ML inference)                       │
│  └── YES → CPU-based autoscaling (target: 60-80%)           │
│                                                              │
│  Request-driven?                                             │
│  (web server, API, behind load balancer)                     │
│  └── YES → LB utilization (target: 0.8 capacity)            │
│                                                              │
│  Queue-driven?                                               │
│  (workers processing messages from Pub/Sub, SQS)            │
│  └── YES → Pub/Sub: unacked messages per instance           │
│                                                              │
│  Custom metric?                                              │
│  (GPU usage, connection count, queue depth in Redis)         │
│  └── YES → Cloud Monitoring custom metric                   │
│                                                              │
│  Time-predictable?                                           │
│  (daily peak at 9am, weekly spike on Monday)                │
│  └── YES → Predictive autoscaling + CPU-based               │
└─────────────────────────────────────────────────────────────┘
```

### CPU-Based vs Custom Metric Scaling

| Aspect              | CPU-Based                        | Custom Metric                      |
|---------------------|----------------------------------|------------------------------------|
| Signal              | Average CPU utilization          | Any Cloud Monitoring metric        |
| Setup complexity    | Simple — one flag                | Medium — requires metric pipeline  |
| Granularity         | Coarse (CPU is a proxy)          | Fine (exact business metric)       |
| Latency             | Metric delay ~60s                | Depends on metric push frequency   |
| Accuracy            | Good for CPU-bound work          | Better for I/O-bound or mixed work |
| Linux analogy       | `top` / `sar -u`                 | Custom Nagios plugin output        |

### Cooldown Periods Explained

```
Timeline (cooldown = 120s)
─────────────────────────────────────────────────────────────
  t=0     Load spike detected
  t=0     Autoscaler: ADD 2 VMs (3 → 5)
  t=0-120 COOLDOWN — no new scaling decisions
  t=30    New VMs still booting...
  t=90    New VMs ready, handling traffic
  t=120   Cooldown ends, autoscaler re-evaluates
  t=120   Load stable at 55% — no action needed
─────────────────────────────────────────────────────────────

Timeline (cooldown = 30s — TOO SHORT)
─────────────────────────────────────────────────────────────
  t=0     Load spike detected
  t=0     Autoscaler: ADD 2 VMs (3 → 5)
  t=30    Cooldown ends — new VMs still booting!
  t=30    Load still high → ADD 2 MORE VMs (5 → 7)
  t=60    Cooldown ends — some VMs still booting
  t=60    Load still high → ADD 2 MORE (7 → 9)
  t=90    All VMs ready — load drops to 25%
  t=120   Scale-in begins — remove excess VMs
  ↑ THRASHING — wasted resources, unstable instance count
─────────────────────────────────────────────────────────────
```

### Scale-In Controls

```
Without scale-in control:              With scale-in control:
─────────────────────                  ─────────────────────
10 VMs                                 10 VMs
  │ load drops →                         │ load drops →
  │ t+0:  10 → 4 (remove 6!)            │ t+0:    10 → 8 (max 2 removed)
  │       ← SUDDEN DROP                 │ t+5min: 8 → 6  (max 2 removed)
  │                                      │ t+10min: 6 → 4  (max 2 removed)
  │ Risk: traffic spike during           │ ← GRADUAL, SAFE
  │ scale-in = outage                    │
```

### Predictive Autoscaling

```
┌─────────────────────────────────────────────────────────┐
│          PREDICTIVE AUTOSCALING                          │
│                                                          │
│  Load                                                    │
│  ▲                                                       │
│  │        ╭──╮ actual                                    │
│  │   ╭──╮│  │   traffic                                 │
│  │  │   ││  │╮                                          │
│  │  │   │╰──╯│                                          │
│  │  ╰──╯     ╰──                                        │
│  │                                                       │
│  │    ╭──╮ predicted                                     │
│  │ ╭─╯  ╰──╮   (ML-based,                              │
│  │╯        ╰── using 14-day                              │
│  │              history)                                  │
│  │                                                       │
│  │  VMs pre-scaled                                       │
│  │  BEFORE traffic arrives                               │
│  └──────────────────────────── Time                      │
│       9am    12pm   3pm   6pm                            │
└─────────────────────────────────────────────────────────┘
```

### Right-Sizing for Cost Optimization

| Strategy                      | Description                                          | Savings     |
|-------------------------------|------------------------------------------------------|-------------|
| Right machine type            | Don't over-provision (e2-micro vs n2-standard-4)     | 40-70%      |
| Preemptible/Spot VMs in MIG   | Use for fault-tolerant batch workloads               | 60-91%      |
| Committed Use Discounts (CUD) | 1 or 3-year commitment for baseline capacity         | 20-57%      |
| Scale to zero (min=0)         | No instances when idle (dev/test only)               | 100% idle   |
| Sustained Use Discounts       | Automatic for VMs running >25% of month              | Up to 30%   |
| Custom machine types          | Exact CPU/RAM ratio instead of predefined            | 5-20%       |

### Cost Optimization Architecture

```
┌─────────────────────────────────────────────────────┐
│           COST-OPTIMIZED MIG ARCHITECTURE            │
│                                                      │
│  Baseline (always on):  CUD instances                │
│  ┌────┐ ┌────┐                                      │
│  │VM-1│ │VM-2│  ← Committed Use Discount             │
│  └────┘ └────┘    (cheapest per-hour rate)           │
│                                                      │
│  Burst (autoscaled):  Regular on-demand              │
│  ┌────┐ ┌────┐                                      │
│  │VM-3│ │VM-4│  ← On-demand (scales with load)      │
│  └────┘ └────┘                                       │
│                                                      │
│  Extra burst:  Spot/Preemptible                      │
│  ┌────┐ ┌────┐                                      │
│  │VM-5│ │VM-6│  ← Spot VMs (cheapest, can be taken) │
│  └────┘ └────┘                                       │
└─────────────────────────────────────────────────────┘
```

---

## Part 2 — Hands-On Lab (60 min)

### Lab Objective

Configure different scaling strategies: CPU-based with tuned cooldown, custom metric scaling, and scale-in controls.

### Step 1 — Set Variables

```bash
export PROJECT_ID=$(gcloud config get-value project)
export REGION=europe-west2
export ZONE=europe-west2-a
```

### Step 2 — Create Instance Template

```bash
gcloud compute instance-templates create scale-strategy-tpl \
    --machine-type=e2-small \
    --image-family=debian-12 \
    --image-project=debian-cloud \
    --tags=http-server \
    --metadata=startup-script='#!/bin/bash
apt-get update && apt-get install -y nginx stress-ng
HOSTNAME=$(hostname)
echo "<h1>$HOSTNAME</h1>" > /var/www/html/index.html
echo "OK" > /var/www/html/health
systemctl enable nginx && systemctl start nginx'
```

### Step 3 — Create MIG

```bash
gcloud compute instance-groups managed create scale-strat-mig \
    --template=scale-strategy-tpl \
    --size=2 \
    --zone=$ZONE
```

### Step 4 — Configure CPU Autoscaling with Tuned Parameters

```bash
gcloud compute instance-groups managed set-autoscaling scale-strat-mig \
    --zone=$ZONE \
    --min-num-replicas=2 \
    --max-num-replicas=8 \
    --target-cpu-utilization=0.60 \
    --cool-down-period=120 \
    --scale-in-control max-scaled-in-replicas=2,time-window=300
```

### Step 5 — Verify Configuration

```bash
gcloud compute instance-groups managed describe scale-strat-mig \
    --zone=$ZONE \
    --format="yaml(autoscaler)"
```

### Step 6 — Enable Predictive Autoscaling

```bash
# Predictive autoscaling uses ML on 14-day history
# (needs historical data to work — won't show effect immediately)
gcloud beta compute instance-groups managed update-autoscaling scale-strat-mig \
    --zone=$ZONE \
    --cpu-utilization-predictive-method=optimize-availability
```

### Step 7 — Create Custom Metric (Cloud Monitoring)

```bash
# Create a custom metric descriptor for "active connections"
gcloud monitoring metrics-descriptors create \
    custom.googleapis.com/nginx/active_connections \
    --type=custom.googleapis.com/nginx/active_connections \
    --metric-kind=gauge \
    --value-type=int64 \
    --description="Number of active nginx connections" \
    --display-name="Nginx Active Connections"
```

### Step 8 — Configure Custom Metric Autoscaling

```bash
# Switch to custom metric scaling
gcloud compute instance-groups managed set-autoscaling scale-strat-mig \
    --zone=$ZONE \
    --min-num-replicas=2 \
    --max-num-replicas=8 \
    --update-stackdriver-metric=custom.googleapis.com/nginx/active_connections \
    --stackdriver-metric-utilization-target=100 \
    --stackdriver-metric-utilization-target-type=gauge
```

### Step 9 — Switch Back to CPU and Tune Scale-In

```bash
# Revert to CPU-based with aggressive scale-in protection
gcloud compute instance-groups managed set-autoscaling scale-strat-mig \
    --zone=$ZONE \
    --min-num-replicas=2 \
    --max-num-replicas=8 \
    --target-cpu-utilization=0.60 \
    --cool-down-period=120 \
    --scale-in-control max-scaled-in-replicas=1,time-window=600
```

### Step 10 — Examine Right-Sizing Recommendations

```bash
# Check if GCP has right-sizing recommendations
gcloud recommender recommendations list \
    --project=$PROJECT_ID \
    --location=$ZONE \
    --recommender=google.compute.instance.MachineTypeRecommender \
    --format="table(name, description, primaryImpact.costProjection)"
```

### Cleanup

```bash
gcloud compute instance-groups managed delete scale-strat-mig --zone=$ZONE --quiet
gcloud compute instance-templates delete scale-strategy-tpl --quiet
```

---

## Part 3 — Revision (15 min)

### Key Concepts

- **CPU-based scaling**: simplest, good for compute-bound; target 60% is standard
- **LB-based scaling**: ties to request rate; best behind load balancer
- **Custom metric scaling**: any Cloud Monitoring metric; most flexible
- **Predictive autoscaling**: uses 14-day history to pre-scale before traffic arrives
- **Cooldown period**: must exceed VM startup time; prevents thrashing
- **Scale-in controls**: limit how fast instances are removed; prevents sudden drops
- **Cost optimization**: CUD for baseline, on-demand for burst, Spot for extra
- **Right-sizing**: use recommender; don't over-provision machine types
- Min=0 is possible for dev/test (scale to zero when idle)

### Essential Commands

```bash
# CPU autoscaling with scale-in control
gcloud compute instance-groups managed set-autoscaling NAME \
    --target-cpu-utilization=0.6 --cool-down-period=120 \
    --scale-in-control max-scaled-in-replicas=2,time-window=300

# Custom metric autoscaling
gcloud compute instance-groups managed set-autoscaling NAME \
    --update-stackdriver-metric=custom.googleapis.com/METRIC \
    --stackdriver-metric-utilization-target=VALUE \
    --stackdriver-metric-utilization-target-type=gauge

# Predictive autoscaling
gcloud beta compute instance-groups managed update-autoscaling NAME \
    --cpu-utilization-predictive-method=optimize-availability

# Right-sizing recommendations
gcloud recommender recommendations list --recommender=google.compute.instance.MachineTypeRecommender
```

---

## Part 4 — Quiz (15 min)

**Question 1: Your web API is I/O-bound (mostly waiting on database queries). CPU stays at 15% even under heavy load. What scaling signal should you use?**

<details>
<summary>Show Answer</summary>

CPU-based autoscaling won't work here because CPU doesn't reflect actual load. Options:

1. **LB utilization** — if behind a load balancer, scale based on requests-per-second per instance
2. **Custom metric** — push a metric like "active_connections" or "request_latency_p99" to Cloud Monitoring and scale on that
3. **Pub/Sub messages** — if the API queues work asynchronously

For an I/O-bound API behind an LB, **LB serving capacity** is the simplest choice. For more precision, use a **custom metric** like response latency.

</details>

**Question 2: You set `min_replicas=0` and `max_replicas=10`. What happens when there's zero traffic?**

<details>
<summary>Show Answer</summary>

The MIG scales to **zero instances** — no VMs running, no cost. When traffic arrives:

1. The autoscaler detects the signal (e.g., LB gets a request)
2. It scales from 0 → 1 (or more, depending on load)
3. The first request experiences **cold start latency** (VM boot + app startup)

This is ideal for **dev/test** or **batch workloads** but not recommended for production web services due to the cold start delay. For production, keep `min_replicas >= 2` for availability.

</details>

**Question 3: Your MIG uses predictive autoscaling. It's Monday morning and the system is pre-scaling before the daily peak. But today is a bank holiday with no traffic. What happens?**

<details>
<summary>Show Answer</summary>

Predictive autoscaling will **over-provision** — it scales based on historical patterns and doesn't know about holidays. However:

1. Predictive autoscaling only sets a **floor** — it doesn't override reactive scaling
2. If actual load is low, reactive autoscaling will eventually scale in
3. The **scale-in controls** may slow down the reduction

**Mitigation**: You can temporarily disable predictive autoscaling before known holidays, or combine it with scale-in controls that allow faster scale-in. Over time, the ML model learns from anomalies, but a single holiday won't retrain the model.

</details>

**Question 4: Your production MIG has 10 instances. Traffic drops sharply. Without scale-in controls, what risk do you face?**

<details>
<summary>Show Answer</summary>

Without scale-in controls, the autoscaler could remove **many instances at once** (e.g., 10 → 3 in one step). Risks:

1. **Traffic rebounds** faster than new VMs can be provisioned → temporary outage
2. **Connection draining** — existing requests on removed VMs get terminated
3. **Cascading failure** — remaining VMs get overwhelmed by shifted load

**Fix**: Always set `scale_in_control`:
```bash
--scale-in-control max-scaled-in-replicas=2,time-window=300
```
This limits removal to 2 VMs per 5-minute window, allowing gradual safe scale-in.

</details>

---

*Next: [Day 54 — PROJECT: Scalable VM Group](DAY_54_PROJECT_SCALABLE_VM.md)*
