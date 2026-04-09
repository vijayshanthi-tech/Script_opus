# Day 54 — PROJECT: Scalable VM Group

> **Week 9 · MIG & Autoscaling — Capstone Project**
> Estimated time: 2 hours | Region: `europe-west2` (London)
> Prerequisites: Days 49-53 completed

---

## Part 1 — Concept & Architecture (30 min)

### Project Overview

Build a **production-grade auto-scaling VM group** with health checks, rolling updates, monitoring, and cost controls. This consolidates everything from Week 9.

### Architecture Diagram

```
┌──────────────────────────────────────────────────────────────────┐
│                    SCALABLE VM GROUP PROJECT                       │
│                                                                   │
│  ┌──────────────────────────────────────────────────────────┐    │
│  │                      VPC: default                         │    │
│  │                   europe-west2 (London)                   │    │
│  │                                                           │    │
│  │  ┌──────────────────────────────────────────────────┐    │    │
│  │  │         Regional MIG: web-prod-mig                │    │    │
│  │  │         (min=2, max=8, CPU target=60%)            │    │    │
│  │  │                                                    │    │    │
│  │  │  zone-a          zone-b          zone-c           │    │    │
│  │  │  ┌──────┐       ┌──────┐       ┌──────┐          │    │    │
│  │  │  │ VM-1 │       │ VM-3 │       │ VM-5 │          │    │    │
│  │  │  │nginx │       │nginx │       │nginx │          │    │    │
│  │  │  └──┬───┘       └──┬───┘       └──┬───┘          │    │    │
│  │  │     │               │               │              │    │    │
│  │  │  ┌──────┐       ┌──────┐       ┌──────┐          │    │    │
│  │  │  │ VM-2 │       │ VM-4 │       │ VM-6 │          │    │    │
│  │  │  │nginx │       │nginx │       │nginx │          │    │    │
│  │  │  └──────┘       └──────┘       └──────┘          │    │    │
│  │  └──────────────────────────────────────────────────┘    │    │
│  │           │                                               │    │
│  │           ▼                                               │    │
│  │  ┌──────────────────┐   ┌────────────────────────┐      │    │
│  │  │  Health Check     │   │  Autoscaler            │      │    │
│  │  │  HTTP :80/health  │   │  CPU=60%, cooldown=120 │      │    │
│  │  │  interval=10s     │   │  scale-in: max 2/5min  │      │    │
│  │  │  unhealthy=3      │   │  predictive: enabled   │      │    │
│  │  └──────────────────┘   └────────────────────────┘      │    │
│  │                                                           │    │
│  │  ┌──────────────────┐   ┌────────────────────────┐      │    │
│  │  │  Firewall Rules   │   │  Cloud Monitoring      │      │    │
│  │  │  - HC probes: ✓   │   │  - CPU dashboard       │      │    │
│  │  │  - HTTP 80: ✓     │   │  - Instance count alert│      │    │
│  │  │  - IAP SSH: ✓     │   │  - Health state alert  │      │    │
│  │  └──────────────────┘   └────────────────────────┘      │    │
│  └──────────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────────┘
```

### Deployment Checklist

| #  | Task                                    | Status |
|----|-----------------------------------------|--------|
| 1  | Create instance template with nginx     | ☐      |
| 2  | Create HTTP health check                | ☐      |
| 3  | Create regional MIG with auto-healing   | ☐      |
| 4  | Configure CPU autoscaler                | ☐      |
| 5  | Add scale-in controls                   | ☐      |
| 6  | Create firewall rules                   | ☐      |
| 7  | Create v2 template                      | ☐      |
| 8  | Perform rolling update to v2            | ☐      |
| 9  | Create monitoring dashboard             | ☐      |
| 10 | Test auto-healing (stop nginx)          | ☐      |
| 11 | Test autoscaling (stress CPU)           | ☐      |
| 12 | Verify rolling update                   | ☐      |
| 13 | Cleanup all resources                   | ☐      |

---

## Part 2 — Hands-On Lab (60 min)

### Step 1 — Environment Setup

```bash
export PROJECT_ID=$(gcloud config get-value project)
export REGION=europe-west2
```

### Step 2 — Firewall Rules

```bash
# Allow health check probes
gcloud compute firewall-rules create allow-hc-probes \
    --network=default \
    --action=allow \
    --direction=ingress \
    --source-ranges=130.211.0.0/22,35.191.0.0/16 \
    --target-tags=web-prod \
    --rules=tcp:80

# Allow HTTP from anywhere (for testing)
gcloud compute firewall-rules create allow-http-web \
    --network=default \
    --action=allow \
    --direction=ingress \
    --source-ranges=0.0.0.0/0 \
    --target-tags=web-prod \
    --rules=tcp:80

# Allow IAP SSH
gcloud compute firewall-rules create allow-iap-ssh \
    --network=default \
    --action=allow \
    --direction=ingress \
    --source-ranges=35.235.240.0/20 \
    --target-tags=web-prod \
    --rules=tcp:22
```

### Step 3 — Instance Template v1

```bash
gcloud compute instance-templates create web-prod-v1 \
    --machine-type=e2-small \
    --image-family=debian-12 \
    --image-project=debian-cloud \
    --region=$REGION \
    --tags=web-prod \
    --metadata=startup-script='#!/bin/bash
set -e
apt-get update && apt-get install -y nginx stress-ng
HOSTNAME=$(hostname)
ZONE=$(curl -sf -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/zone | cut -d/ -f4)
cat > /var/www/html/index.html <<EOF
<!DOCTYPE html>
<html>
<body>
<h1>Web App v1</h1>
<p>Host: $HOSTNAME</p>
<p>Zone: $ZONE</p>
<p>Deployed: $(date -u +"%Y-%m-%dT%H:%M:%SZ")</p>
</body>
</html>
EOF
echo "OK" > /var/www/html/health
systemctl enable nginx && systemctl start nginx'
```

### Step 4 — Health Check

```bash
gcloud compute health-checks create http web-prod-hc \
    --port=80 \
    --request-path=/health \
    --check-interval=10s \
    --timeout=5s \
    --healthy-threshold=2 \
    --unhealthy-threshold=3
```

### Step 5 — Regional MIG with Auto-Healing

```bash
gcloud compute instance-groups managed create web-prod-mig \
    --template=web-prod-v1 \
    --size=4 \
    --region=$REGION \
    --health-check=web-prod-hc \
    --initial-delay=120

# Set named port for future LB integration
gcloud compute instance-groups managed set-named-ports web-prod-mig \
    --region=$REGION \
    --named-ports=http:80
```

### Step 6 — Configure Autoscaler

```bash
gcloud compute instance-groups managed set-autoscaling web-prod-mig \
    --region=$REGION \
    --min-num-replicas=2 \
    --max-num-replicas=8 \
    --target-cpu-utilization=0.60 \
    --cool-down-period=120 \
    --scale-in-control max-scaled-in-replicas=2,time-window=300
```

### Step 7 — Verify Deployment

```bash
# List instances across zones
gcloud compute instance-groups managed list-instances web-prod-mig \
    --region=$REGION \
    --format="table(instance.basename(), zone.basename(), status, healthState[0].healthState)"

# Wait for all instances to be HEALTHY (2-3 min)
watch -n 15 "gcloud compute instance-groups managed list-instances web-prod-mig \
    --region=$REGION --format='table(instance.basename(), zone.basename(), status, healthState[0].healthState)'"
```

### Step 8 — Test Auto-Healing

```bash
# Pick an instance and break nginx
INSTANCE=$(gcloud compute instance-groups managed list-instances web-prod-mig \
    --region=$REGION --format="value(instance)" | head -1)
INST_ZONE=$(gcloud compute instance-groups managed list-instances web-prod-mig \
    --region=$REGION --format="value(instance, zone)" | head -1 | awk '{print $2}')

gcloud compute ssh $INSTANCE --zone=$INST_ZONE -- "sudo systemctl stop nginx"

# Watch auto-healing kick in
watch -n 15 "gcloud compute instance-groups managed list-instances web-prod-mig \
    --region=$REGION --format='table(instance.basename(), status, healthState[0].healthState, currentAction)'"
```

### Step 9 — Rolling Update to v2

```bash
# Create v2 template
gcloud compute instance-templates create web-prod-v2 \
    --machine-type=e2-small \
    --image-family=debian-12 \
    --image-project=debian-cloud \
    --region=$REGION \
    --tags=web-prod \
    --metadata=startup-script='#!/bin/bash
set -e
apt-get update && apt-get install -y nginx stress-ng
HOSTNAME=$(hostname)
ZONE=$(curl -sf -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/zone | cut -d/ -f4)
cat > /var/www/html/index.html <<EOF
<!DOCTYPE html>
<html>
<body>
<h1>Web App v2 — Updated!</h1>
<p>Host: $HOSTNAME</p>
<p>Zone: $ZONE</p>
<p>Deployed: $(date -u +"%Y-%m-%dT%H:%M:%SZ")</p>
</body>
</html>
EOF
echo "OK" > /var/www/html/health
systemctl enable nginx && systemctl start nginx'

# Rolling update with zero downtime
gcloud compute instance-groups managed rolling-action start-update web-prod-mig \
    --region=$REGION \
    --version=template=web-prod-v2 \
    --max-surge=1 \
    --max-unavailable=0

# Watch the update
watch -n 15 "gcloud compute instance-groups managed list-instances web-prod-mig \
    --region=$REGION --format='table(instance.basename(), zone.basename(), status, currentAction, version.instanceTemplate.basename())'"
```

### Step 10 — Create Monitoring Alert

```bash
# Create alert for instance count dropping below 2
gcloud alpha monitoring policies create \
    --display-name="MIG Instance Count Low" \
    --condition-display-name="Instance count < 2" \
    --condition-filter='resource.type="instance_group" AND metric.type="compute.googleapis.com/instance_group/size"' \
    --condition-threshold-value=2 \
    --condition-threshold-comparison=COMPARISON_LT \
    --duration=300s \
    --if-state=ENABLED
```

### Cleanup

```bash
# Delete MIG (also deletes instances)
gcloud compute instance-groups managed delete web-prod-mig --region=$REGION --quiet

# Delete health check
gcloud compute health-checks delete web-prod-hc --quiet

# Delete templates
gcloud compute instance-templates delete web-prod-v1 web-prod-v2 --quiet

# Delete firewall rules
gcloud compute firewall-rules delete allow-hc-probes allow-http-web allow-iap-ssh --quiet
```

---

## Part 3 — Revision (15 min)

### Week 9 Summary

- **MIG** = fleet of identical VMs managed as one unit
- **Instance template** = immutable VM blueprint (machine type, image, script)
- **Zonal MIG** = single zone; **Regional MIG** = multi-zone HA
- **Autoscaler** metrics: CPU, LB utilization, custom, Pub/Sub
- Formula: `recommended = CEIL(total_load / target)`
- **Cooldown** must exceed VM boot time to prevent thrashing
- **Scale-in controls** limit removal rate for safety
- **Health checks** drive **auto-healing** — probe IPs: `130.211.0.0/22`, `35.191.0.0/16`
- **Rolling updates**: `maxSurge=1, maxUnavailable=0` = zero-downtime
- **Canary**: deploy small % to new template, then promote or rollback
- **Terraform**: `name_prefix` + `create_before_destroy` for template versioning

### Key Commands Cheat Sheet

```bash
# Templates
gcloud compute instance-templates create NAME --machine-type=TYPE --image-family=FAM

# MIG (regional)
gcloud compute instance-groups managed create NAME --template=TPL --size=N --region=REGION
gcloud compute instance-groups managed set-autoscaling NAME --region=REGION \
    --min-num-replicas=2 --max-num-replicas=8 --target-cpu-utilization=0.6

# Health check
gcloud compute health-checks create http NAME --port=80 --request-path=/health

# Rolling update
gcloud compute instance-groups managed rolling-action start-update NAME \
    --version=template=NEW --max-surge=1 --max-unavailable=0 --region=REGION
```

---

## Part 4 — Quiz (15 min)

**Question 1: You're designing a production MIG. Should you use zonal or regional, and why?**

<details>
<summary>Show Answer</summary>

**Regional MIG** for production. Reasons:
- Survives single-zone failures (instances spread across up to 3 zones)
- Proactive instance redistribution rebalances after zone outages
- Integrates with regional load balancers for true HA
- Only slight overhead: instances may have cross-zone latency (~1ms)

Use zonal only for dev/test or cost-sensitive non-critical workloads.

</details>

**Question 2: Your rolling update is stuck — new instances keep failing health checks. What should you check?**

<details>
<summary>Show Answer</summary>

Checklist:
1. **Startup script** — SSH into a new instance, check `/var/log/syslog` for script errors
2. **Health check path** — does the new template serve `/health` on port 80?
3. **Firewall rules** — are `130.211.0.0/22` and `35.191.0.0/16` allowed?
4. **initial_delay** — is it long enough for the app to start?
5. **Port mismatch** — does the health check port match the app listening port?

To unblock: rollback to the previous working template while investigating.

</details>

**Question 3: Your company wants to save costs on a MIG that handles batch jobs with predictable daily load. What combination of strategies would you recommend?**

<details>
<summary>Show Answer</summary>

1. **Committed Use Discounts (CUD)** for min_replicas baseline (always-on capacity)
2. **Predictive autoscaling** to pre-scale before the daily batch window
3. **Spot/Preemptible VMs** for burst capacity (batch jobs are fault-tolerant)
4. **Scale to min** outside batch hours (set min_replicas to match CUD count)
5. **Right-size** machine types — use Recommender API to check if VMs are over-provisioned

Combined savings: 40-70% vs on-demand at max capacity.

</details>

**Question 4: Draw the dependency order for creating these resources: Autoscaler, MIG, Instance Template, Health Check, Firewall Rule.**

<details>
<summary>Show Answer</summary>

```
Firewall Rule (independent) ──────────────────────────┐
                                                       │
Instance Template ─── depends on ──→ MIG ──→ Autoscaler │
                                      │                 │
Health Check (independent) ──→ MIG (auto_healing) ─────┘
```

Creation order:
1. **Firewall Rule** + **Health Check** + **Instance Template** (parallel, no dependencies)
2. **MIG** (depends on template + health check)
3. **Autoscaler** (depends on MIG)

In Terraform, you declare all resources and it figures out the dependency graph automatically.

</details>

---

*Next: [Week 10 — Load Balancing](../WEEK_10_LOAD_BALANCING/DAY_55_LB_TYPES.md)*
