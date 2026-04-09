# Day 52 — Health Checks & Rolling Updates

> **Week 9 · MIG & Autoscaling**
> Estimated time: 2 hours | Region: `europe-west2` (London)
> Prerequisites: Day 51 completed

---

## Part 1 — Concept (30 min)

### Health Checks — The Heartbeat Monitor

Health checks are how GCP determines if a VM instance is alive and serving traffic. Think of it as a sophisticated `ping` + `curl` combination that runs continuously.

```
Linux Analogy
─────────────
  Nagios/Zabbix health probe:
    check_http -H 10.0.0.5 -p 80 -u /health -t 5
    ↳ Every 10s, timeout 5s, 3 failures = CRITICAL

  GCP Health Check:
    http_health_check:
      port: 80
      request_path: /health
      check_interval: 10s
      timeout: 5s
      unhealthy_threshold: 3
```

### Health Check Lifecycle

```
┌─────────────────────────────────────────────────────────┐
│              HEALTH CHECK STATE MACHINE                   │
│                                                           │
│  Instance Created                                         │
│       │                                                   │
│       ▼                                                   │
│  ┌─────────────┐   initial_delay_sec                     │
│  │  UNKNOWN     │──────────────────┐                     │
│  └─────────────┘                   │                     │
│                                    ▼                     │
│                    ┌─────────────────────────┐           │
│                    │   Probing starts         │           │
│                    └────────────┬────────────┘           │
│                                │                         │
│                    ┌───────────┴───────────┐             │
│                    ▼                       ▼             │
│          ┌──────────────┐       ┌──────────────┐        │
│          │   HEALTHY    │       │  UNHEALTHY   │        │
│          │ (N successes)│◄─────►│ (M failures) │        │
│          └──────────────┘       └──────┬───────┘        │
│                                        │                 │
│                                        ▼                 │
│                                ┌───────────────┐        │
│                                │  AUTO-HEAL    │        │
│                                │  (recreate VM)│        │
│                                └───────────────┘        │
└─────────────────────────────────────────────────────────┘
```

### Health Check Parameters

| Parameter              | Description                           | Default | Recommendation        |
|------------------------|---------------------------------------|---------|-----------------------|
| `check_interval_sec`   | Time between probes                  | 5s      | 10s for production     |
| `timeout_sec`          | Max wait for response                | 5s      | 5s                    |
| `healthy_threshold`    | Consecutive successes to mark healthy | 2       | 2                     |
| `unhealthy_threshold`  | Consecutive failures to mark unhealthy| 2       | 3-5 (avoid flapping)  |
| `initial_delay_sec`    | Grace period after VM creation       | 300s    | Match startup time    |

### Health Check Types

| Type   | Checks                     | Use Case                      |
|--------|----------------------------|-------------------------------|
| HTTP   | GET request → expect 200   | Web servers, APIs             |
| HTTPS  | GET with TLS               | Secure endpoints              |
| TCP    | TCP connect succeeds       | Databases, custom services    |
| SSL    | TLS handshake succeeds     | SSL-terminated services       |
| gRPC   | gRPC health check protocol | gRPC services                 |

### Rolling Updates

```
┌──────────────────────────────────────────────────────────┐
│               ROLLING UPDATE SEQUENCE                     │
│                                                           │
│  Template v1: [VM-1] [VM-2] [VM-3] [VM-4]               │
│                                                           │
│  Step 1: Create surge instance with v2                    │
│  Template v1: [VM-1] [VM-2] [VM-3] [VM-4]               │
│  Template v2: [VM-5]  ← new (surge)                      │
│                                                           │
│  Step 2: VM-5 passes health check → remove VM-1          │
│  Template v1:         [VM-2] [VM-3] [VM-4]               │
│  Template v2: [VM-5]                                      │
│                                                           │
│  Step 3: Create VM-6 (surge) → wait healthy → remove VM-2│
│  Template v1:                [VM-3] [VM-4]               │
│  Template v2: [VM-5] [VM-6]                               │
│                                                           │
│  ...continues until all VMs are on v2...                  │
│                                                           │
│  Final: Template v2: [VM-5] [VM-6] [VM-7] [VM-8]        │
└──────────────────────────────────────────────────────────┘
```

### Rolling Update Parameters

| Parameter                | Description                                    | Impact                        |
|--------------------------|------------------------------------------------|-------------------------------|
| `maxSurge`               | Extra VMs allowed during update               | Higher = faster, more costly  |
| `maxUnavailable`         | VMs allowed offline during update             | 0 = zero-downtime             |
| `type`                   | PROACTIVE (auto) or OPPORTUNISTIC (manual)    | PROACTIVE for auto-updates    |
| `minimal_action`         | Minimum action: NONE, REFRESH, RESTART, REPLACE | REPLACE for template changes |
| `replacement_method`     | SUBSTITUTE (new name) or RECREATE (same name) | SUBSTITUTE is safer           |

### Canary Updates

```
┌─────────────────────────────────────────────┐
│            CANARY UPDATE                     │
│                                              │
│  80% on v1:  [VM-1] [VM-2] [VM-3] [VM-4]   │
│  20% on v2:  [VM-5]                          │
│                                              │
│  Monitor v2 for errors...                    │
│  If OK  → promote to 100%                   │
│  If BAD → rollback (set v1 to 100%)         │
└─────────────────────────────────────────────┘
```

### Proactive Instance Redistribution (Regional MIG)

```
Normal State:                      After zone-b outage:
┌──────┐ ┌──────┐ ┌──────┐       ┌──────┐ ┌──────┐ ┌──────┐
│zone-a│ │zone-b│ │zone-c│       │zone-a│ │zone-b│ │zone-c│
│ VM-1 │ │ VM-3 │ │ VM-5 │       │ VM-1 │ │  ❌  │ │ VM-5 │
│ VM-2 │ │ VM-4 │ │ VM-6 │  ──►  │ VM-2 │ │      │ │ VM-6 │
└──────┘ └──────┘ └──────┘       │ VM-7 │ │      │ │ VM-8 │
 2 each    2 each   2 each       └──────┘ └──────┘ └──────┘
                                   3         0        3
                                  Redistributed to maintain 6 total
```

---

## Part 2 — Hands-On Lab (60 min)

### Lab Objective

Configure health checks with auto-healing, perform a rolling update, and test a canary deployment.

### Step 1 — Set Variables

```bash
export PROJECT_ID=$(gcloud config get-value project)
export REGION=europe-west2
export ZONE=europe-west2-a
```

### Step 2 — Create Template v1

```bash
gcloud compute instance-templates create web-v1 \
    --machine-type=e2-micro \
    --image-family=debian-12 \
    --image-project=debian-cloud \
    --tags=http-server \
    --metadata=startup-script='#!/bin/bash
apt-get update && apt-get install -y nginx
HOSTNAME=$(hostname)
cat > /var/www/html/index.html <<EOF
<h1>Version 1 - $HOSTNAME</h1>
EOF
cat > /var/www/html/health <<EOF
OK
EOF
systemctl enable nginx && systemctl start nginx'
```

### Step 3 — Create Health Check

```bash
gcloud compute health-checks create http web-health-check \
    --port=80 \
    --request-path=/health \
    --check-interval=10s \
    --timeout=5s \
    --healthy-threshold=2 \
    --unhealthy-threshold=3
```

### Step 4 — Create MIG with Auto-Healing

```bash
gcloud compute instance-groups managed create web-mig \
    --template=web-v1 \
    --size=3 \
    --zone=$ZONE \
    --health-check=web-health-check \
    --initial-delay=120

# Set named port
gcloud compute instance-groups managed set-named-ports web-mig \
    --zone=$ZONE \
    --named-ports=http:80
```

### Step 5 — Verify Health Status

```bash
# Wait for instances to become healthy (2-3 min)
watch -n 10 "gcloud compute instance-groups managed list-instances web-mig \
    --zone=$ZONE --format='table(instance.basename(), status, healthState[0].healthState)'"
```

### Step 6 — Test Auto-Healing

```bash
# SSH into an instance and break nginx (simulate failure)
INSTANCE=$(gcloud compute instance-groups managed list-instances web-mig \
    --zone=$ZONE --format="value(instance)" | head -1)

gcloud compute ssh $INSTANCE --zone=$ZONE -- "sudo systemctl stop nginx"

# Watch — the health check will fail, MIG will recreate the instance
watch -n 10 "gcloud compute instance-groups managed list-instances web-mig \
    --zone=$ZONE --format='table(instance.basename(), status, healthState[0].healthState, currentAction)'"
```

### Step 7 — Create Template v2

```bash
gcloud compute instance-templates create web-v2 \
    --machine-type=e2-micro \
    --image-family=debian-12 \
    --image-project=debian-cloud \
    --tags=http-server \
    --metadata=startup-script='#!/bin/bash
apt-get update && apt-get install -y nginx
HOSTNAME=$(hostname)
cat > /var/www/html/index.html <<EOF
<h1>Version 2 - $HOSTNAME</h1>
<p>Updated deployment!</p>
EOF
cat > /var/www/html/health <<EOF
OK
EOF
systemctl enable nginx && systemctl start nginx'
```

### Step 8 — Perform Rolling Update

```bash
gcloud compute instance-groups managed rolling-action start-update web-mig \
    --zone=$ZONE \
    --version=template=web-v2 \
    --max-surge=1 \
    --max-unavailable=0

# Watch the rolling update in progress
watch -n 10 "gcloud compute instance-groups managed list-instances web-mig \
    --zone=$ZONE --format='table(instance.basename(), status, currentAction, version.instanceTemplate.basename())'"
```

### Step 9 — Test Canary Update

```bash
# Create template v3
gcloud compute instance-templates create web-v3 \
    --machine-type=e2-micro \
    --image-family=debian-12 \
    --image-project=debian-cloud \
    --tags=http-server \
    --metadata=startup-script='#!/bin/bash
apt-get update && apt-get install -y nginx
HOSTNAME=$(hostname)
echo "<h1>Version 3 (Canary) - $HOSTNAME</h1>" > /var/www/html/index.html
echo "OK" > /var/www/html/health
systemctl enable nginx && systemctl start nginx'

# Deploy canary: 80% v2, 20% v3
gcloud compute instance-groups managed rolling-action start-update web-mig \
    --zone=$ZONE \
    --version=template=web-v2 \
    --canary-version=template=web-v3,target-size=1 \
    --max-surge=1 \
    --max-unavailable=0

# Check — should see mix of v2 and v3
gcloud compute instance-groups managed list-instances web-mig \
    --zone=$ZONE \
    --format="table(instance.basename(), version.instanceTemplate.basename())"
```

### Step 10 — Rollback Canary

```bash
# If canary looks bad, rollback to 100% v2
gcloud compute instance-groups managed rolling-action start-update web-mig \
    --zone=$ZONE \
    --version=template=web-v2 \
    --max-surge=1 \
    --max-unavailable=0
```

### Cleanup

```bash
gcloud compute instance-groups managed delete web-mig --zone=$ZONE --quiet
gcloud compute health-checks delete web-health-check --quiet
gcloud compute instance-templates delete web-v1 web-v2 web-v3 --quiet
```

---

## Part 3 — Revision (15 min)

### Key Concepts

- **Health checks** continuously probe VMs; failures trigger **auto-healing** (recreation)
- `initial_delay_sec` gives VMs time to boot before health checks start
- Use `unhealthy_threshold=3` or higher to avoid false positives
- **Rolling updates** gradually replace VMs from old template to new template
- `maxSurge=1, maxUnavailable=0` = zero-downtime rolling update
- **Canary updates** deploy a small percentage to the new template for testing
- **PROACTIVE** updates happen automatically; **OPPORTUNISTIC** wait for manual trigger
- **Proactive redistribution** rebalances regional MIGs after zone failures
- Health check source IPs: `130.211.0.0/22` and `35.191.0.0/16` — must allow in firewall

### Essential Commands

```bash
# Health checks
gcloud compute health-checks create http NAME --port=80 --request-path=/health
gcloud compute health-checks describe NAME

# MIG with auto-healing
gcloud compute instance-groups managed create NAME --health-check=HC --initial-delay=120

# Rolling update
gcloud compute instance-groups managed rolling-action start-update NAME \
    --version=template=NEW_TPL --max-surge=1 --max-unavailable=0 --zone=ZONE

# Canary update
gcloud compute instance-groups managed rolling-action start-update NAME \
    --version=template=STABLE --canary-version=template=CANARY,target-size=1

# Rollback
gcloud compute instance-groups managed rolling-action start-update NAME \
    --version=template=STABLE --zone=ZONE
```

---

## Part 4 — Quiz (15 min)

**Question 1: Your MIG's health check has `check_interval=5s`, `unhealthy_threshold=2`, and `initial_delay=60s`. A newly created VM takes 90 seconds to start nginx. What happens?**

<details>
<summary>Show Answer</summary>

The VM enters an **auto-healing loop**. Timeline:
- 0-60s: Health checks skipped (initial delay)
- 60s: Probing starts, but nginx isn't ready until 90s
- 65s: First failure
- 70s: Second failure → VM marked **UNHEALTHY** (threshold=2)
- MIG deletes VM and recreates it → same problem repeats

**Fix**: Set `initial_delay_sec = 120` (or longer) to exceed the 90s startup time. Always set initial delay ≥ application startup time + buffer.

</details>

**Question 2: During a rolling update with `maxSurge=2` and `maxUnavailable=1`, your MIG has target_size=4. What's the maximum and minimum number of running instances during the update?**

<details>
<summary>Show Answer</summary>

- **Maximum** = target_size + maxSurge = 4 + 2 = **6 instances**
- **Minimum** = target_size - maxUnavailable = 4 - 1 = **3 instances**

Higher maxSurge makes updates faster (more parallel replacements) but uses more resources temporarily. maxUnavailable=1 means at most 1 instance can be offline at any time.

</details>

**Question 3: You deployed a canary (20% on v3) and it's showing errors. How do you rollback?**

<details>
<summary>Show Answer</summary>

Set the MIG to 100% of the stable version:

```bash
gcloud compute instance-groups managed rolling-action start-update web-mig \
    --zone=europe-west2-a \
    --version=template=web-v2 \
    --max-surge=1 \
    --max-unavailable=0
```

This triggers a rolling update that replaces the canary instances (v3) with the stable template (v2). The `--canary-version` flag is omitted, so all instances converge to v2.

</details>

**Question 4: Why must you allow traffic from `130.211.0.0/22` and `35.191.0.0/16` in your firewall rules?**

<details>
<summary>Show Answer</summary>

These are the **Google health check probe IP ranges**. GCP health check probes originate from these addresses. If your firewall blocks them, health checks will always fail, causing:

1. All instances marked **UNHEALTHY**
2. Auto-healing continuously recreates instances (infinite loop)
3. Load balancer marks all backends as unhealthy (502 errors)

This is one of the most common GCP networking mistakes. Always create a firewall rule allowing these ranges on the health check port.

</details>

---

*Next: [Day 53 — Scaling Strategy](DAY_53_SCALING_STRATEGY.md)*
