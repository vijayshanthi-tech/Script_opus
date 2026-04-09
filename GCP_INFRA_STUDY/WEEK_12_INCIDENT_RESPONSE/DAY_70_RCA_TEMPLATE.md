# Day 70 — RCA Write-Up Template

> **Week 12 · Incident Response**
> Estimated time: 2 hours | Region: `europe-west2` (London)
> Prerequisites: Day 69 completed

---

## Part 1 — Concept (30 min)

### Why RCA (Root Cause Analysis)?

```
Without RCA:                         With RCA:
┌───────────────────────┐           ┌───────────────────────┐
│ Incident happens      │           │ Incident happens      │
│         │             │           │         │             │
│         ▼             │           │         ▼             │
│ Fix the symptom       │           │ Fix the symptom       │
│         │             │           │         │             │
│         ▼             │           │         ▼             │
│ "We fixed it!"        │           │ RCA: WHY did it       │
│         │             │           │ happen?               │
│         ▼             │           │         │             │
│ Same issue in 3 weeks │           │         ▼             │
│                       │           │ Action items prevent  │
│                       │           │ recurrence            │
└───────────────────────┘           └───────────────────────┘
```

### RCA Structure

```
┌──────────────────────────────────────────────────────────────┐
│                  RCA DOCUMENT STRUCTURE                        │
│                                                               │
│  1. INCIDENT SUMMARY                                         │
│     What happened? One paragraph.                            │
│                                                               │
│  2. TIMELINE                                                 │
│     Chronological events from detection to resolution.       │
│                                                               │
│  3. ROOT CAUSE                                               │
│     The actual underlying cause (not the symptom).           │
│                                                               │
│  4. FIVE WHYS ANALYSIS                                       │
│     Drill down from symptom to root cause.                   │
│                                                               │
│  5. IMPACT                                                   │
│     What was affected? Duration? Users? Data?                │
│                                                               │
│  6. CONTRIBUTING FACTORS                                     │
│     What made it worse or delayed detection?                 │
│                                                               │
│  7. ACTION ITEMS                                             │
│     Specific, assigned, deadlined tasks to prevent           │
│     recurrence.                                              │
│                                                               │
│  8. LESSONS LEARNED                                          │
│     What did we learn? What worked? What didn't?             │
└──────────────────────────────────────────────────────────────┘
```

### The Five Whys Method

```
Problem: Production web server returned 503 errors for 45 minutes.

Why 1: The web server process crashed.
   → Why did the process crash?

Why 2: The server ran out of memory (OOM kill).
   → Why did it run out of memory?

Why 3: A memory leak in the application accumulated over 2 weeks.
   → Why wasn't the memory leak detected?

Why 4: No memory usage alert was configured above 80%.
   → Why was there no alert?

Why 5: The monitoring checklist didn't include memory alerts for this service.
   → ROOT CAUSE: Monitoring was incomplete for this service.

Action Items:
1. Fix the memory leak (code fix)
2. Add memory alert at 80% (monitoring)
3. Create a monitoring checklist for all new services (process)
4. Schedule memory leak scan in CI/CD (prevention)
```

### Blameless RCA Culture

| Blame Culture | Blameless Culture |
|--------------|-------------------|
| "Who did this?" | "What happened and why?" |
| Person is fired/punished | System is improved |
| People hide mistakes | People report quickly |
| Root cause: "human error" | Root cause: missing safeguard |
| Same incident repeats | Prevention implemented |
| Linux analogy: blame the admin | Linux analogy: improve the runbook |

### Timeline Format

```
TIME (UTC)   │ EVENT                        │ SOURCE
─────────────┼──────────────────────────────┼──────────────
14:00        │ Deploy v2.3.1 to prod        │ CI/CD log
14:15        │ Memory usage climbing         │ Cloud Monitoring
14:32        │ First 503 error reported      │ LB access log
14:35        │ Alert fires: error rate >5%   │ Alert policy
14:37        │ On-call acknowledges alert    │ PagerDuty
14:42        │ SSH to VM, identify OOM       │ Manual
14:48        │ Roll back to v2.3.0           │ CI/CD
14:50        │ Error rate drops to 0%        │ Cloud Monitoring
15:00        │ Incident declared resolved    │ Manual
```

---

## Part 2 — Hands-On Lab (60 min)

### Lab Objective

Practice writing a real RCA by first creating an incident (from Day 69's scenarios), then gathering evidence from logs, and finally writing the RCA document.

### Step 1 — Create and Break the Test VM

```bash
export PROJECT_ID=$(gcloud config get-value project)
export REGION=europe-west2
export ZONE=europe-west2-a

# Create test VM
gcloud compute instances create rca-test-vm \
    --zone=$ZONE \
    --machine-type=e2-small \
    --image-family=debian-12 \
    --image-project=debian-cloud \
    --metadata=startup-script='#!/bin/bash
apt-get update -y && apt-get install -y stress-ng nginx
systemctl start nginx'

# Wait for setup
sleep 60
```

### Step 2 — Simulate an Incident

```bash
# Record start time
INCIDENT_START=$(date -u +%Y-%m-%dT%H:%M:%SZ)
echo "Incident start: $INCIDENT_START"

# Cause: Fill disk until nginx fails to write logs
gcloud compute ssh rca-test-vm --zone=$ZONE --command="
    # Fill the disk
    dd if=/dev/zero of=/tmp/disk-filler bs=1M count=8000 2>/dev/null
    echo 'Disk usage after fill:'
    df -h /
    
    # nginx will start failing when it can't write logs
    curl -s localhost > /dev/null 2>&1
    echo 'nginx status:'
    systemctl status nginx --no-pager | head -5
"
```

### Step 3 — Gather Evidence from Logs

```bash
# Get VM creation log
gcloud logging read \
    'resource.type="gce_instance"
     logName="projects/'$PROJECT_ID'/logs/cloudaudit.googleapis.com%2Factivity"
     protoPayload.methodName="v1.compute.instances.insert"
     protoPayload.resourceName=~"rca-test-vm"' \
    --limit=1 \
    --format="table(timestamp, protoPayload.authenticationInfo.principalEmail)" \
    > /tmp/rca-evidence-1.txt

cat /tmp/rca-evidence-1.txt
echo ""

# Get system logs from VM
gcloud compute ssh rca-test-vm --zone=$ZONE --command="
    echo '=== DISK STATUS ==='
    df -h /
    echo ''
    echo '=== RECENT SYSTEM ERRORS ==='
    journalctl -p err --since '1 hour ago' --no-pager | tail -20
    echo ''
    echo '=== NGINX STATUS ==='
    systemctl status nginx --no-pager
    echo ''
    echo '=== LARGE FILES ==='
    du -sh /tmp/* 2>/dev/null | sort -rh | head -5
" > /tmp/rca-evidence-2.txt 2>&1

cat /tmp/rca-evidence-2.txt
```

### Step 4 — Resolve the Incident

```bash
# Fix: remove the filler file
gcloud compute ssh rca-test-vm --zone=$ZONE --command="
    rm -f /tmp/disk-filler
    echo 'Disk after cleanup:'
    df -h /
    
    # Restart nginx
    sudo systemctl restart nginx
    echo 'nginx after restart:'
    curl -s localhost | head -5
"

INCIDENT_END=$(date -u +%Y-%m-%dT%H:%M:%SZ)
echo "Incident resolved: $INCIDENT_END"
```

### Step 5 — Write the RCA Document

```bash
cat > /tmp/RCA-$(date +%Y%m%d)-disk-full.md << 'RCADOC'
# RCA: Web Server Outage — Disk Full

| Field | Value |
|-------|-------|
| **Incident ID** | INC-2024-001 |
| **Date** | 2024-XX-XX |
| **Duration** | ~15 minutes |
| **Severity** | P2 (Service degraded) |
| **Author** | {YOUR NAME} |
| **Status** | Resolved |

## 1. Incident Summary

The nginx web server on `rca-test-vm` became unresponsive after the root
filesystem reached 100% capacity. The server could not write logs, causing
request failures. The incident was detected via monitoring (disk usage alert)
and resolved by removing unnecessary files and restarting the service.

## 2. Timeline (UTC)

| Time | Event | Source |
|------|-------|--------|
| HH:MM | VM created and nginx started | Audit log |
| HH:MM | Large file created in /tmp (8GB) | Manual action / process |
| HH:MM | Disk reached 100% | Cloud Monitoring |
| HH:MM | nginx started returning errors | LB log / curl test |
| HH:MM | Alert fired: disk > 90% | Cloud Monitoring alert |
| HH:MM | On-call acknowledged | PagerDuty |
| HH:MM | SSHed to VM, identified /tmp/disk-filler | Manual investigation |
| HH:MM | Removed file, restarted nginx | Manual remediation |
| HH:MM | Service restored, errors stopped | curl / monitoring |

## 3. Root Cause

A large temporary file (`/tmp/disk-filler`, 8GB) was created on the root
filesystem without cleanup, consuming all available disk space. When the disk
reached 100%, nginx could not write access/error logs and began failing
requests. No automatic disk cleanup or quota was in place.

## 4. Five Whys

1. **Why did nginx fail?** → It couldn't write to its log files.
2. **Why couldn't it write logs?** → The root filesystem was 100% full.
3. **Why was the disk full?** → A large temporary file consumed all space.
4. **Why wasn't there a cleanup process?** → No tmpwatch/tmpreaper was configured.
5. **Why wasn't disk usage alerted earlier?** → Disk alert was set at 90%, but the fill happened instantly (not gradually).

**Root cause**: Missing temporary file cleanup automation and insufficient disk monitoring granularity.

## 5. Impact

| Category | Impact |
|----------|--------|
| **Users affected** | All users of the web service |
| **Duration** | ~15 minutes |
| **Data loss** | None (stateless web server) |
| **Revenue impact** | None (internal service) |
| **SLA impact** | Within budget (99.9% = 43 min/month) |

## 6. Contributing Factors

1. **No disk cleanup cron**: No `tmpreaper` or equivalent to clean old temp files
2. **Alert threshold too high**: 90% threshold gave insufficient lead time
3. **Single disk**: All partitions on one disk; /tmp not separated
4. **No disk quota**: Processes could write unlimited data to /tmp

## 7. Action Items

| # | Action | Owner | Deadline | Priority |
|---|--------|-------|----------|----------|
| 1 | Install and configure `tmpreaper` for /tmp cleanup | Ops | 1 week | P2 |
| 2 | Add disk alert at 80% (warning) and 90% (critical) | Ops | 3 days | P1 |
| 3 | Separate /tmp onto its own partition in VM template | Infra | 2 weeks | P3 |
| 4 | Add disk quota for non-root users | Infra | 2 weeks | P3 |
| 5 | Configure nginx to handle disk-full gracefully | Dev | 1 week | P2 |
| 6 | Add runbook for "disk full" scenario | Ops | 1 week | P2 |

## 8. Lessons Learned

### What went well
- Alert fired within expected timeframe
- On-call acknowledged quickly
- Root cause was identified within 5 minutes

### What didn't go well
- Disk filled instantly (no gradual warning)
- No automated cleanup existed
- Runbook for disk-full was missing

### What we'll do differently
- Two-tier alerts (warning + critical) for all resource metrics
- Automated tmpwatch on all VMs via startup script
- Separate /tmp partition in new VM templates
RCADOC

echo "RCA written to /tmp/RCA-$(date +%Y%m%d)-disk-full.md"
cat /tmp/RCA-$(date +%Y%m%d)-disk-full.md
```

### Step 6 — Practice Querying Evidence

```bash
# Find all changes made to the VM
gcloud logging read \
    'resource.type="gce_instance"
     resource.labels.instance_id="'$(gcloud compute instances describe rca-test-vm --zone=$ZONE --format='value(id)')'"' \
    --limit=10 \
    --format="table(timestamp, protoPayload.methodName, protoPayload.authenticationInfo.principalEmail)"

# Find all error-level logs in the project for the incident window
gcloud logging read \
    'severity>=ERROR
     timestamp>="'$INCIDENT_START'"' \
    --limit=20 \
    --format="table(timestamp, resource.type, severity, textPayload)"
```

### Cleanup

```bash
gcloud compute instances delete rca-test-vm --zone=$ZONE --quiet
rm -f /tmp/rca-evidence-*.txt
```

---

## Part 3 — Revision (15 min)

### Key Concepts

- **RCA is blameless** — focus on systems, not people
- **Five Whys** drills past symptoms to actual root cause
- **Timeline** is the backbone — every RCA needs one
- **Action items** must be specific, assigned, and deadlined
- **Contributing factors** explain why detection/response was slow
- "Human error" is never the root cause — missing safeguards are
- RCA prevents recurrence; without it, incidents repeat

### RCA Template (Minimal)

```
# RCA: {Title}
## Summary: What happened in 2 sentences
## Timeline: Table with timestamp, event, source
## Root Cause: Five Whys analysis
## Impact: Users, duration, data loss
## Action Items: Table with action, owner, deadline
## Lessons Learned: What worked, what didn't
```

### Evidence-Gathering Commands

```bash
# Audit logs (who did what)
gcloud logging read 'logName=~"cloudaudit" AND resource.labels.instance_id="ID"' --limit=10

# Error logs during incident window
gcloud logging read 'severity>=ERROR AND timestamp>="START"' --limit=20

# VM system logs
gcloud compute ssh VM --command="journalctl -p err --since 'TIME' --no-pager"

# Disk, CPU, memory (from inside VM)
gcloud compute ssh VM --command="df -h; free -m; top -bn1 | head -10"
```

---

## Part 4 — Quiz (15 min)

**Question 1: A developer writes "Root cause: John accidentally deleted the production database." What's wrong with this RCA?**

<details>
<summary>Show Answer</summary>

**It's blaming a person, not analysing the system.** This violates blameless RCA culture and stops at the surface.

Apply Five Whys:
1. Why was the database deleted? → John ran `DROP DATABASE` in production
2. Why could he run that command? → He had admin access to the prod DB
3. Why did he have admin access? → No separate staging/prod IAM roles
4. Why was there no safety net? → No `deletion protection` or confirmation prompt
5. Why was deletion protection not enabled? → No checklist for database security controls

**Better root cause**: "Insufficient access controls and missing deletion safeguards allowed a routine operation to affect production."

**Action items**: Separate prod/staging IAM roles, enable deletion protection, add confirmation for destructive queries, implement point-in-time recovery.

</details>

**Question 2: What's the difference between "root cause" and "contributing factor"?**

<details>
<summary>Show Answer</summary>

| Aspect | Root Cause | Contributing Factor |
|--------|-----------|-------------------|
| **Definition** | The primary reason the incident happened | Made things worse or delayed resolution |
| **Fix priority** | Must fix to prevent recurrence | Should fix to reduce severity |
| **Count** | Usually 1 (sometimes 2) | Often several |
| **Example** | Memory leak in code | Missing memory alert |
| **Example** | Misconfigured firewall | No runbook for firewall issues |
| **Test** | "If we fix this, would the incident NOT happen?" | "If we fix this, would impact be less?" |

In the disk-full RCA:
- **Root cause**: Large temp file created without cleanup
- **Contributing factors**: No alert at 80%, no tmp partition, no disk quota, missing runbook

</details>

**Question 3: An incident lasted 45 minutes, but the alert fired at minute 2. What happened in the other 43 minutes and how do you improve?**

<details>
<summary>Show Answer</summary>

The 43-minute gap is the **response and remediation time**:

| Phase | Time | Problem |
|-------|------|---------|
| **Detection** | 0–2 min | ✅ Alert worked |
| **Acknowledgement** | 2–10 min | ⚠️ 8 min delay → improve on-call response SLA |
| **Diagnosis** | 10–25 min | ⚠️ 15 min to find root cause → need runbook |
| **Remediation** | 25–40 min | ⚠️ 15 min to fix → need automated remediation |
| **Verification** | 40–45 min | ✅ Reasonable |

Improvements:
1. **Runbook in alert**: Include diagnostic steps directly in the alert documentation
2. **Auto-remediation**: Cloud Function that can restart services or scale up automatically
3. **Better on-call tooling**: PagerDuty escalation after 5 min no-response
4. **Pre-staged commands**: Shell aliases or scripts for common fixes

Target: Detection (2 min) + Ack (2 min) + Diagnosis (5 min) + Fix (5 min) + Verify (1 min) = **15 min total**.

</details>

**Question 4: Your RCA has 12 action items. Is this a problem?**

<details>
<summary>Show Answer</summary>

**Yes.** Too many action items signal:

1. **Lack of prioritisation** — not all items prevent recurrence equally
2. **Unlikely to complete** — 12 items across a team will get deprioritised
3. **Scope creep** — RCA is turning into a wishlist

**Fix**: Categorise by impact:

| Priority | Action Items | Timeline |
|----------|-------------|----------|
| **P1** (prevents recurrence) | 2-3 items | This sprint |
| **P2** (reduces severity) | 2-3 items | Next sprint |
| **P3** (nice to have) | Move to backlog | Quarterly review |

Keep the RCA document focused on **3-5 key action items** with clear owners and deadlines. Put everything else in the team backlog.

Rule of thumb: If you can't remember all the action items, there are too many.

</details>

---

*Next: [Day 71 — Ops Playbook v1](DAY_71_OPS_PLAYBOOK.md)*
