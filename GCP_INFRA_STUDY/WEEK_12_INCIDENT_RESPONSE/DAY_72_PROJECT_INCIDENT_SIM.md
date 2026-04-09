# Day 72 — PROJECT: Incident Simulation + RCA Report

> **Week 12 · Incident Response — Capstone Project**
> Estimated time: 2 hours | Region: `europe-west2` (London)
> Prerequisites: Days 67–71 completed

---

## Part 1 — Concept (30 min)

### Project Overview

This capstone ties together everything from Week 12: logging strategy, alert tuning, failure simulation, RCA writing, and the ops playbook. You will **create infrastructure, simulate a realistic multi-fault incident, detect it, respond using your playbook, resolve it, and write a complete RCA.**

### Target Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│                 INCIDENT SIMULATION ARCHITECTURE                      │
│                                                                       │
│  ┌──────────────────────────────────────────────────────────────┐    │
│  │            VPC: incident-vpc (10.30.0.0/24)                   │    │
│  │                                                                │    │
│  │  ┌─────────────────┐     ┌─────────────────┐                 │    │
│  │  │  web-server      │     │  app-server      │                 │    │
│  │  │  (nginx)         │     │  (simulated app) │                 │    │
│  │  │  10.30.0.10      │────▶│  10.30.0.11      │                 │    │
│  │  │                  │     │                   │                 │    │
│  │  │  Fault 1:        │     │  Fault 2:         │                 │    │
│  │  │  Disk fills up   │     │  Process killed   │                 │    │
│  │  └─────────────────┘     └─────────────────┘                 │    │
│  │                                                                │    │
│  │  Firewall Rules:                                               │    │
│  │  ✓ IAP SSH (35.235.240.0/20)                                  │    │
│  │  ✓ Internal (10.30.0.0/24)                                    │    │
│  │  ✗ Fault 3: Block app-server port (firewall misconfig)        │    │
│  │                                                                │    │
│  └──────────────────────────────────────────────────────────────┘    │
│                                                                       │
│  Monitoring:                                                         │
│  ┌─────────────────────────────────────────────┐                    │
│  │  Alert 1: Disk > 85% on web-server          │                    │
│  │  Alert 2: Error rate spike (log-based)       │                    │
│  │  Alert 3: VM connectivity failure            │                    │
│  │  Notification: Email channel                  │                    │
│  └─────────────────────────────────────────────┘                    │
│                                                                       │
│  Incident Flow:                                                      │
│  Inject faults → Detect via alerts → Respond via playbook            │
│  → Resolve → Write RCA                                               │
└──────────────────────────────────────────────────────────────────────┘
```

### Incident Scenario Summary

| Phase | Time | What Happens |
|-------|------|-------------|
| Setup | 0:00 | Deploy 2 VMs + monitoring + alerts |
| Inject | 0:15 | Three faults injected simultaneously |
| Detect | 0:20 | Alerts fire, logs show anomalies |
| Respond | 0:25 | Follow playbook to triage and fix |
| Resolve | 0:40 | All services restored |
| RCA | 0:45 | Write full RCA document |

---

## Part 2 — Hands-On Lab (60 min)

### Phase 1: Setup Infrastructure (15 min)

#### Step 1 — Set Variables

```bash
export PROJECT_ID=$(gcloud config get-value project)
export REGION=europe-west2
export ZONE=europe-west2-a
```

#### Step 2 — Create VPC and Firewall

```bash
gcloud compute networks create incident-vpc --subnet-mode=custom

gcloud compute networks subnets create incident-subnet \
    --network=incident-vpc \
    --region=$REGION \
    --range=10.30.0.0/24

# IAP SSH
gcloud compute firewall-rules create incident-allow-iap \
    --network=incident-vpc \
    --action=allow \
    --direction=ingress \
    --source-ranges=35.235.240.0/20 \
    --rules=tcp:22

# Internal
gcloud compute firewall-rules create incident-allow-internal \
    --network=incident-vpc \
    --action=allow \
    --direction=ingress \
    --source-ranges=10.30.0.0/24 \
    --rules=all

# HTTP for nginx
gcloud compute firewall-rules create incident-allow-http \
    --network=incident-vpc \
    --action=allow \
    --direction=ingress \
    --source-ranges=10.30.0.0/24 \
    --rules=tcp:80 \
    --target-tags=web
```

#### Step 3 — Create Web Server

```bash
gcloud compute instances create web-server \
    --zone=$ZONE \
    --machine-type=e2-small \
    --image-family=debian-12 \
    --image-project=debian-cloud \
    --network=incident-vpc \
    --subnet=incident-subnet \
    --private-network-ip=10.30.0.10 \
    --no-address \
    --tags=web \
    --metadata=startup-script='#!/bin/bash
apt-get update -y
apt-get install -y nginx stress-ng
systemctl start nginx
echo "web-server ready" > /var/log/setup.log'
```

#### Step 4 — Create App Server

```bash
gcloud compute instances create app-server \
    --zone=$ZONE \
    --machine-type=e2-small \
    --image-family=debian-12 \
    --image-project=debian-cloud \
    --network=incident-vpc \
    --subnet=incident-subnet \
    --private-network-ip=10.30.0.11 \
    --no-address \
    --tags=app \
    --metadata=startup-script='#!/bin/bash
apt-get update -y
# Simulate an app process
while true; do echo "$(date): app heartbeat" >> /var/log/app.log; sleep 10; done &
echo "app-server ready" > /var/log/setup.log'
```

#### Step 5 — Create Monitoring Alerts

```bash
# Create notification channel
gcloud monitoring channels create \
    --display-name="Incident Sim - Email" \
    --type=email \
    --channel-labels=email_address=$(gcloud config get-value account) 2>/dev/null

CHANNEL_ID=$(gcloud monitoring channels list \
    --filter='displayName="Incident Sim - Email"' \
    --format="value(name)" | head -1)

# Log-based metric for errors
gcloud logging metrics create incident-error-rate \
    --description="Error log entries rate" \
    --log-filter='severity>=ERROR AND resource.type="gce_instance"'

echo "Setup complete. Waiting for VMs to initialise..."
sleep 90
```

#### Step 6 — Verify Setup

```bash
# Check both VMs are running
gcloud compute instances list --filter="zone:$ZONE AND name~'server'" \
    --format="table(name, status, networkInterfaces[0].networkIP)"

# Verify SSH works via IAP
gcloud compute ssh web-server --zone=$ZONE --tunnel-through-iap \
    --command="cat /var/log/setup.log; systemctl status nginx --no-pager | head -3"

gcloud compute ssh app-server --zone=$ZONE --tunnel-through-iap \
    --command="cat /var/log/setup.log; tail -3 /var/log/app.log"
```

### Phase 2: Inject Faults (5 min)

```bash
echo "=== FAULT INJECTION START: $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
INCIDENT_START=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Fault 1: Fill web-server disk
echo "Injecting Fault 1: Disk fill on web-server..."
gcloud compute ssh web-server --zone=$ZONE --tunnel-through-iap --command="
    dd if=/dev/zero of=/tmp/fault-disk-fill bs=1M count=7000 2>/dev/null
    echo 'Fault 1 injected. Disk:'
    df -h /
"

# Fault 2: Kill app process on app-server
echo "Injecting Fault 2: Kill app process on app-server..."
gcloud compute ssh app-server --zone=$ZONE --tunnel-through-iap --command="
    pkill -f 'app heartbeat'
    echo 'Fault 2 injected. App process:'
    pgrep -a heartbeat || echo 'PROCESS NOT FOUND'
"

# Fault 3: Block internal HTTP traffic (firewall misconfig)
echo "Injecting Fault 3: Firewall misconfiguration..."
gcloud compute firewall-rules create incident-block-http \
    --network=incident-vpc \
    --action=deny \
    --direction=ingress \
    --source-ranges=10.30.0.0/24 \
    --rules=tcp:80 \
    --target-tags=web \
    --priority=100

echo ""
echo "=== ALL FAULTS INJECTED ==="
echo "Three faults are now active:"
echo "  1. web-server: disk nearly full"
echo "  2. app-server: application process killed"
echo "  3. HTTP traffic to web-server blocked by firewall"
```

### Phase 3: Detect (5 min)

```bash
echo "=== DETECTION PHASE ==="
echo ""

# Check 1: Disk alert
echo "--- CHECK 1: Disk Usage ---"
gcloud compute ssh web-server --zone=$ZONE --tunnel-through-iap \
    --command="df -h / | tail -1"

# Check 2: App process
echo "--- CHECK 2: App Process ---"
gcloud compute ssh app-server --zone=$ZONE --tunnel-through-iap \
    --command="pgrep -a heartbeat || echo 'ALERT: App process not running!'"

# Check 3: Connectivity
echo "--- CHECK 3: HTTP Connectivity ---"
gcloud compute ssh app-server --zone=$ZONE --tunnel-through-iap \
    --command="curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 http://10.30.0.10 || echo 'ALERT: Cannot reach web-server on port 80!'"

# Check audit logs for firewall changes
echo "--- CHECK 4: Recent Firewall Changes ---"
gcloud logging read \
    'resource.type="gce_firewall_rule"
     logName="projects/'$PROJECT_ID'/logs/cloudaudit.googleapis.com%2Factivity"
     timestamp>="'$INCIDENT_START'"' \
    --limit=3 \
    --format="table(timestamp, protoPayload.methodName, protoPayload.resourceName)"
```

### Phase 4: Respond Using Playbook (10 min)

```bash
echo "=== RESPONSE PHASE (following playbook) ==="
echo ""

# Fix Fault 1: Disk — following Runbook 2
echo "--- FIX 1: Disk Full (Runbook 2) ---"
gcloud compute ssh web-server --zone=$ZONE --tunnel-through-iap --command="
    echo 'TRIAGE:'
    df -h /
    echo ''
    echo 'IDENTIFY:'
    du -sh /tmp/* 2>/dev/null | sort -rh | head -5
    echo ''
    echo 'FIX:'
    rm -f /tmp/fault-disk-fill
    echo ''
    echo 'VERIFY:'
    df -h /
"
echo "✅ Fault 1 resolved"
echo ""

# Fix Fault 2: Process — following Runbook 3
echo "--- FIX 2: App Process (Runbook 3 variant) ---"
gcloud compute ssh app-server --zone=$ZONE --tunnel-through-iap --command="
    echo 'TRIAGE:'
    pgrep -a heartbeat || echo 'App process not running'
    echo ''
    echo 'FIX: Restart the app process'
    nohup bash -c 'while true; do echo \"\$(date): app heartbeat\" >> /var/log/app.log; sleep 10; done' &
    sleep 2
    echo ''
    echo 'VERIFY:'
    pgrep -a heartbeat && echo 'Process running' || echo 'STILL DOWN'
    tail -2 /var/log/app.log
"
echo "✅ Fault 2 resolved"
echo ""

# Fix Fault 3: Firewall — following Runbook 4 (SSH variant)
echo "--- FIX 3: Firewall Misconfiguration (Runbook 4) ---"
echo "TRIAGE: Check firewall rules"
gcloud compute firewall-rules list --filter="network:incident-vpc" \
    --format="table(name, direction, allowed, denied, priority, targetTags)"
echo ""
echo "IDENTIFY: The 'incident-block-http' rule is blocking port 80"
echo "FIX: Remove the blocking rule"
gcloud compute firewall-rules delete incident-block-http --quiet
echo ""
echo "VERIFY: Test connectivity"
gcloud compute ssh app-server --zone=$ZONE --tunnel-through-iap \
    --command="curl -s -o /dev/null -w 'HTTP %{http_code}' --connect-timeout 5 http://10.30.0.10"
echo ""
echo "✅ Fault 3 resolved"

INCIDENT_END=$(date -u +%Y-%m-%dT%H:%M:%SZ)
echo ""
echo "=== ALL FAULTS RESOLVED ==="
echo "Incident duration: $INCIDENT_START to $INCIDENT_END"
```

### Phase 5: Verify Full Recovery

```bash
echo "=== VERIFICATION PHASE ==="
echo ""

# Full system check
echo "1. VM Status:"
gcloud compute instances list --filter="zone:$ZONE AND name~'server'" \
    --format="table(name, status)"
echo ""

echo "2. Disk Usage (web-server):"
gcloud compute ssh web-server --zone=$ZONE --tunnel-through-iap \
    --command="df -h / | tail -1"
echo ""

echo "3. App Process (app-server):"
gcloud compute ssh app-server --zone=$ZONE --tunnel-through-iap \
    --command="pgrep -a heartbeat && tail -1 /var/log/app.log"
echo ""

echo "4. HTTP Connectivity:"
gcloud compute ssh app-server --zone=$ZONE --tunnel-through-iap \
    --command="curl -s http://10.30.0.10 | head -5"
echo ""

echo "5. Firewall Rules:"
gcloud compute firewall-rules list --filter="network:incident-vpc" \
    --format="table(name, priority, allowed)"
echo ""

echo "=== ALL SYSTEMS NOMINAL ==="
```

### Phase 6: Write RCA

```bash
cat << 'RCAEOF'
# RCA: Multi-Fault Incident — Web + App Outage

| Field | Value |
|-------|-------|
| **Incident ID** | INC-2024-SIM-001 |
| **Date** | See timestamps above |
| **Duration** | ~15 minutes |
| **Severity** | P2 (Service degraded, multi-system) |
| **Author** | {YOUR NAME} |
| **Status** | Resolved, RCA complete |

## 1. Incident Summary

A multi-fault incident affected both the web server and application server.
Three concurrent issues occurred: disk full on web-server, application
process failure on app-server, and a firewall misconfiguration blocking
HTTP traffic. The combination caused complete service unavailability.

## 2. Timeline (UTC)

| Time | Event | Source |
|------|-------|--------|
| T+0  | Infrastructure deployed | gcloud |
| T+15 | Fault 1: Disk filled on web-server | Injected |
| T+15 | Fault 2: App process killed on app-server | Injected |
| T+15 | Fault 3: Firewall rule blocks HTTP | Injected |
| T+18 | Disk alert fires (web-server > 90%) | Cloud Monitoring |
| T+19 | HTTP connectivity check fails | Manual |
| T+20 | App heartbeat stops in logs | Cloud Logging |
| T+22 | Fault 1 resolved: disk cleaned | Manual (Runbook 2) |
| T+24 | Fault 2 resolved: process restarted | Manual (Runbook 3) |
| T+27 | Fault 3 identified via audit log | Cloud Audit Log |
| T+28 | Fault 3 resolved: FW rule deleted | Manual (Runbook 4) |
| T+30 | Full verification: all systems nominal | Manual checks |

## 3. Root Causes

### Fault 1: Disk Full
Large temporary file (7GB) created in /tmp without cleanup, consuming
nearly all disk space. Nginx couldn't write logs or serve pages.

### Fault 2: Process Killed
Application process terminated unexpectedly. No process supervisor
(systemd unit) to automatically restart it.

### Fault 3: Firewall Misconfiguration
A deny rule with priority 100 was added that blocked HTTP (tcp:80)
from internal sources to the web-server tag. This overrode the
existing allow rule.

## 4. Five Whys

### Why was the service down?
Three concurrent failures: disk, process, and network.

### Why did multiple things fail at once?
No defence-in-depth: each component was a single point of failure.

### Why was there no auto-recovery?
- Disk: no cleanup cron or monitoring at lower threshold
- Process: no systemd unit with Restart=always
- Firewall: no validation pipeline for firewall changes

### Why wasn't this caught in design?
No failure mode analysis during architecture review.

### Why no failure mode analysis?
Not part of the deployment checklist.

**Root cause**: Missing operational resilience controls — no auto-cleanup,
no process supervision, no firewall change validation.

## 5. Impact

| Category | Impact |
|----------|--------|
| Users affected | All users of both services |
| Duration | ~15 minutes |
| Data loss | None |
| SLA impact | Within budget |

## 6. Contributing Factors

1. No `tmpreaper` or equivalent on web-server
2. App process not managed by systemd (no auto-restart)
3. Firewall change not reviewed (no IaC / PR process)
4. Disk alert at 90% left insufficient reaction time
5. No connectivity checks between web and app servers

## 7. Action Items

| # | Action | Owner | Deadline | Priority |
|---|--------|-------|----------|----------|
| 1 | Add tmpreaper to all VM templates | Ops | 1 week | P1 |
| 2 | Create systemd unit for app process | Dev | 3 days | P1 |
| 3 | Implement Terraform for firewall rules (no manual) | Infra | 2 weeks | P2 |
| 4 | Add 80% disk warning alert | Ops | 3 days | P1 |
| 5 | Add cross-service health checks | Ops | 1 week | P2 |
| 6 | Update playbook with multi-fault procedure | Ops | 1 week | P2 |

## 8. Lessons Learned

### What went well
- Playbook runbooks were effective for individual fault resolution
- Audit logs immediately showed the firewall change
- Detection was fast once we checked

### What didn't go well
- Three faults at once was overwhelming (prioritisation needed)
- No automated detection for process death on app-server
- Firewall change had no approval workflow

### What we'll do differently
- Systemd for all application processes
- Terraform-only firewall changes (no manual gcloud)
- Pre-flight connectivity checks after infrastructure changes
- Multi-fault triage procedure in playbook
RCAEOF
```

### Cleanup

```bash
gcloud compute instances delete web-server app-server --zone=$ZONE --quiet
gcloud compute firewall-rules delete incident-allow-iap incident-allow-internal incident-allow-http --quiet
gcloud compute networks subnets delete incident-subnet --region=$REGION --quiet
gcloud compute networks delete incident-vpc --quiet
gcloud logging metrics delete incident-error-rate --quiet 2>/dev/null

for CHANNEL in $(gcloud monitoring channels list --filter='displayName:"Incident Sim"' --format="value(name)"); do
    gcloud monitoring channels delete $CHANNEL --quiet 2>/dev/null
done

echo "All resources cleaned up."
```

---

## Part 3 — Revision (15 min)

### Project Checklist

| # | Task | Status |
|---|------|--------|
| 1 | Infrastructure deployed (VPC, VMs, alerts) | ☐ |
| 2 | Three faults injected simultaneously | ☐ |
| 3 | Detection via monitoring + logs | ☐ |
| 4 | Response using playbook runbooks | ☐ |
| 5 | All three faults resolved | ☐ |
| 6 | Full system verification | ☐ |
| 7 | RCA written with Five Whys | ☐ |
| 8 | Action items assigned and deadlined | ☐ |
| 9 | Lessons learned documented | ☐ |
| 10 | All resources cleaned up | ☐ |

### Week 12 Summary Commands

```bash
# Logging
gcloud logging read 'FILTER' --limit=N
gcloud logging metrics create NAME --log-filter='FILTER'
gcloud logging sinks create NAME DESTINATION --log-filter='FILTER'

# Alerting
gcloud monitoring policies create --policy-from-file=policy.json
gcloud monitoring channels create --type=email --channel-labels=email_address=ADDR

# Chaos / Simulation
stress-ng --cpu N --timeout Ns          # CPU
dd if=/dev/zero of=/tmp/fill bs=1M count=N  # Disk
pkill PROCESS                           # Process kill
gcloud compute firewall-rules create    # Bad FW rule

# RCA Evidence
gcloud logging read 'logName=~"cloudaudit"' --limit=20
gcloud compute ssh VM --command="journalctl -p err"
gcloud compute ssh VM --command="df -h; free -m; top -bn1"
```

---

## Part 4 — Quiz (15 min)

**Question 1: During the simulation, you had three faults. What order should you fix them and why?**

<details>
<summary>Show Answer</summary>

**Priority order:**

| Priority | Fault | Reason |
|----------|-------|--------|
| **1st** | Firewall (Fault 3) | Blocks all HTTP traffic → total outage. Also, once fixed, you can verify if the other faults are actually causing issues or if it was just the firewall. |
| **2nd** | Disk Full (Fault 1) | Disk full can cascade: nginx fails, logs stop, monitoring gaps. Also easiest to fix (`rm` the file). |
| **3rd** | Process Kill (Fault 2) | Single process failure with no cascading impact. Restart is quick. |

**Triage principle**: Fix the fault with the **widest blast radius** first. Network issues affect everything; disk affects one server; a process affects one service.

In production, you'd also consider: which fault is **easiest to verify** is fixed? Start there to reduce the number of variables.

</details>

**Question 2: Your RCA has "firewall misconfiguration" as a root cause. A senior engineer says the real root cause is deeper. What do they mean?**

<details>
<summary>Show Answer</summary>

"Firewall misconfiguration" is the **proximate cause** (what happened), not the **root cause** (why it was possible).

Apply Five Whys deeper:
1. Why was HTTP blocked? → A deny rule was added
2. Why was a deny rule added manually? → No infrastructure-as-code requirement
3. Why no IaC? → Firewall changes weren't included in the change management process
4. Why no change management? → Ops team has direct `gcloud` access with no review step
5. Why no review step? → No policy enforcing Terraform-only changes

**Real root cause**: Missing change management controls for network security configurations.

**Action items**: Enforce Terraform-only firewall changes, require PR review, remove direct `gcloud compute firewall-rules` permissions from individual engineers.

</details>

**Question 3: You ran this simulation in a test environment. How would you make it safe to run a version in production?**

<details>
<summary>Show Answer</summary>

**Game Day planning for production:**

| Phase | Requirement |
|-------|-------------|
| **Scope** | Single, non-critical service (not the main database) |
| **Approval** | Written approval from engineering and management |
| **Communication** | Announce to all teams 48 hours before |
| **Kill switches** | Pre-tested rollback for every fault |
| **Monitoring** | Extra eyes on dashboards during the test |
| **Duration** | Strict time box (e.g., max 30 min) |
| **Blast radius** | Only affect one AZ / one service |
| **Abort criteria** | If real customer impact > threshold, stop immediately |
| **Business hours** | Run during low-traffic period, never during peak |
| **Backup** | Fresh snapshots/backups taken before starting |

Start with the **smallest possible failure** (e.g., kill one process on one non-critical VM) and gradually increase scope as you build confidence.

Companies like Netflix (Chaos Monkey) do this in production, but they built up to it over years.

</details>

**Question 4: Looking back at Weeks 9-12, name one thing from each week that directly contributed to making this incident response successful.**

<details>
<summary>Show Answer</summary>

| Week | Topic | Contribution to Incident Response |
|------|-------|----------------------------------|
| **9: MIG & Autoscaling** | Auto-healing health checks | VMs can self-recover from process failures without manual intervention |
| **10: Load Balancing** | Health check probes + LB logging | LB detects unhealthy backends automatically and routes around failures |
| **11: Security Posture** | IAP SSH + no public IP | Even during an incident, access is authenticated and audited. Attackers can't exploit the stressed system |
| **12: Incident Response** | Playbooks + RCA | Structured response reduces MTTR. RCA prevents recurrence |

The key insight: **infrastructure resilience reduces incident frequency**, and **ops processes reduce incident impact**. You need both.

</details>

---

*Congratulations! You've completed Week 12: Incident Response.*

*You've now completed the full GCP Infrastructure study plan (Weeks 1-12). You have the knowledge to design, deploy, secure, monitor, and operate production GCP infrastructure.*

---

## Course Completion Summary

| Week | Topic | Key Skill |
|------|-------|-----------|
| 1 | Compute Basics | VM creation, SSH, disks |
| 2 | Networking / VPC | VPC, subnets, firewall, NAT |
| 3 | Monitoring / Logging | Ops Agent, alerts, dashboards |
| 4 | Terraform Basics | HCL, state, plan/apply |
| 5 | Terraform Networking | VPC + FW as code |
| 6 | Storage / Backup | Disks, snapshots, GCS |
| 7 | Automation / Ops | Startup scripts, scheduling |
| 8 | Portfolio Review | Documentation, presentation |
| 9 | MIG & Autoscaling | Instance groups, auto-heal |
| 10 | Load Balancing | HTTP LB, health checks, CDN |
| 11 | Security Posture | IAM, Shielded VM, no public IP |
| 12 | Incident Response | Logging, alerts, chaos, RCA |
