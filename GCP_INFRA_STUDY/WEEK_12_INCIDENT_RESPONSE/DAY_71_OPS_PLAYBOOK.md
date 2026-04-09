# Day 71 — Ops Playbook v1

> **Week 12 · Incident Response**
> Estimated time: 2 hours | Region: `europe-west2` (London)
> Prerequisites: Day 70 completed

---

## Part 1 — Concept (30 min)

### What is an Ops Playbook?

```
Without Playbook:                    With Playbook:
┌──────────────────────┐            ┌──────────────────────┐
│ Alert fires at 3 AM  │            │ Alert fires at 3 AM  │
│         │            │            │         │            │
│         ▼            │            │         ▼            │
│ "What do I do?"      │            │ Open playbook        │
│ Search Slack history │            │ Step 1: Check X      │
│ Ask senior engineer  │            │ Step 2: Run Y        │
│ Trial and error      │            │ Step 3: Fix Z        │
│         │            │            │         │            │
│         ▼            │            │         ▼            │
│ 60 min MTTR          │            │ 15 min MTTR          │
│ Stress, uncertainty  │            │ Calm, methodical     │
└──────────────────────┘            └──────────────────────┘
```

### Playbook Structure

```
┌──────────────────────────────────────────────────────────────┐
│                  OPS PLAYBOOK STRUCTURE                        │
│                                                               │
│  ┌──────────────────────────────────────────────────┐        │
│  │ ESCALATION MATRIX                                 │        │
│  │ Who to call, when, and how                        │        │
│  └──────────────────────────────────────────────────┘        │
│                                                               │
│  ┌──────────────────────────────────────────────────┐        │
│  │ RUNBOOKS (per scenario)                           │        │
│  │ ├── VM Down / Unresponsive                        │        │
│  │ ├── Disk Full                                     │        │
│  │ ├── High CPU / Memory                             │        │
│  │ ├── SSH Failure                                   │        │
│  │ ├── Network / Connectivity                        │        │
│  │ ├── Application Error Spike                       │        │
│  │ └── Security Incident                             │        │
│  └──────────────────────────────────────────────────┘        │
│                                                               │
│  ┌──────────────────────────────────────────────────┐        │
│  │ COMMON COMMANDS REFERENCE                         │        │
│  │ Quick-reference for frequent operations           │        │
│  └──────────────────────────────────────────────────┘        │
│                                                               │
│  ┌──────────────────────────────────────────────────┐        │
│  │ POST-INCIDENT CHECKLIST                           │        │
│  │ Clean up, verify, write RCA                       │        │
│  └──────────────────────────────────────────────────┘        │
└──────────────────────────────────────────────────────────────┘
```

### Escalation Matrix

```
┌──────────────────────────────────────────────────────────────┐
│                   ESCALATION MATRIX                            │
│                                                               │
│  SEVERITY │ RESPONSE TIME │ WHO             │ HOW            │
│  ─────────┼───────────────┼─────────────────┼────────────────│
│  P1       │ 15 min        │ On-Call Eng     │ PagerDuty page │
│  (down)   │               │ + Team Lead     │ + Phone call   │
│           │               │ + Mgr (30 min)  │                │
│  ─────────┼───────────────┼─────────────────┼────────────────│
│  P2       │ 1 hour        │ On-Call Eng     │ PagerDuty page │
│  (degrad) │               │                 │                │
│  ─────────┼───────────────┼─────────────────┼────────────────│
│  P3       │ Next bus day  │ Team queue      │ Email / Ticket │
│  (warning)│               │                 │                │
│  ─────────┼───────────────┼─────────────────┼────────────────│
│  P4       │ Within sprint │ Backlog         │ Ticket         │
│  (info)   │               │                 │                │
│                                                               │
│  ESCALATION TRIGGERS:                                        │
│  • No ack after 15 min → escalate to Team Lead              │
│  • No resolution after 30 min → escalate to Manager         │
│  • Data loss or security → immediate P1 + Security team     │
│                                                               │
│  Linux analogy: On-call rotation + pager duty ≈              │
│  cron + mail + nagios escalation                             │
└──────────────────────────────────────────────────────────────┘
```

### Runbook Quality Criteria

| Criteria | Bad Runbook | Good Runbook |
|----------|-------------|-------------|
| Audience | Expert only | Any team member |
| Commands | "Check the logs" | `gcloud logging read 'FILTER' --limit=5` |
| Decisions | Vague guidance | Decision tree with conditions |
| Variables | Hardcoded project IDs | `$PROJECT_ID`, `$ZONE` placeholders |
| Testing | Never tested | Tested monthly |
| Updates | Written once, never updated | Updated after every incident |

---

## Part 2 — Hands-On Lab (60 min)

### Lab Objective

Build an Ops Playbook with runbooks for the five most common GCP VM incidents, then test each runbook.

### Step 1 — Create the Playbook File

```bash
export PROJECT_ID=$(gcloud config get-value project)
export REGION=europe-west2
export ZONE=europe-west2-a

mkdir -p ~/playbooks
cat > ~/playbooks/ops-playbook-v1.md << 'PLAYBOOK'
# Ops Playbook v1 — GCP Infrastructure

## Quick Reference

```bash
# Set your environment
export PROJECT_ID=$(gcloud config get-value project)
export REGION=europe-west2
export ZONE=europe-west2-a
```

---

## Runbook 1: VM Down / Unresponsive

**Alert**: Uptime check failed / VM not responding

### Triage (2 minutes)

```bash
# Check VM status
gcloud compute instances describe $VM_NAME --zone=$ZONE \
    --format="table(status, lastStartTimestamp, scheduling.preemptible)"

# If status = TERMINATED (preemptible) or STOPPED:
gcloud compute instances start $VM_NAME --zone=$ZONE
```

### Diagnose (5 minutes)

```bash
# Check serial console output (if SSH fails)
gcloud compute instances get-serial-port-output $VM_NAME --zone=$ZONE | tail -50

# Check recent audit logs
gcloud logging read \
    'resource.type="gce_instance" AND resource.labels.instance_id="INSTANCE_ID"
     AND severity>=WARNING' \
    --limit=10 --format="table(timestamp,severity,textPayload)"

# Check if VM was stopped by someone
gcloud logging read \
    'protoPayload.methodName=~"instances.(stop|delete|reset)"
     AND protoPayload.resourceName=~"VM_NAME"' \
    --limit=5
```

### Fix

| Condition | Action |
|-----------|--------|
| VM STOPPED | `gcloud compute instances start $VM_NAME --zone=$ZONE` |
| VM TERMINATED (spot) | Recreate with `gcloud compute instances create` |
| VM RUNNING but unresponsive | `gcloud compute instances reset $VM_NAME --zone=$ZONE` |
| Kernel panic (serial log) | Stop, detach disk, mount on rescue VM, fix |

### Verify

```bash
gcloud compute ssh $VM_NAME --zone=$ZONE --command="uptime && systemctl list-units --failed"
```

---

## Runbook 2: Disk Full

**Alert**: Disk utilization > 90%

### Triage (2 minutes)

```bash
gcloud compute ssh $VM_NAME --zone=$ZONE --command="df -h; echo '---'; du -sh /var/log/* 2>/dev/null | sort -rh | head -10"
```

### Quick Fix (5 minutes)

```bash
gcloud compute ssh $VM_NAME --zone=$ZONE --command="
    # Clean package cache
    sudo apt-get clean
    
    # Rotate and clean old logs
    sudo journalctl --vacuum-time=3d
    sudo journalctl --vacuum-size=100M
    
    # Find large files
    sudo find / -type f -size +100M -exec ls -lh {} \; 2>/dev/null
    
    # Clean temp files older than 7 days
    sudo find /tmp -type f -mtime +7 -delete
    
    # Check after cleanup
    df -h /
"
```

### If Still Full — Resize Disk

```bash
# Resize the persistent disk (online, no downtime)
DISK_NAME=$(gcloud compute instances describe $VM_NAME --zone=$ZONE \
    --format="value(disks[0].source)" | awk -F/ '{print $NF}')

CURRENT_SIZE=$(gcloud compute disks describe $DISK_NAME --zone=$ZONE \
    --format="value(sizeGb)")
NEW_SIZE=$((CURRENT_SIZE + 20))

gcloud compute disks resize $DISK_NAME --zone=$ZONE --size=${NEW_SIZE}GB

# Extend filesystem inside VM
gcloud compute ssh $VM_NAME --zone=$ZONE --command="
    sudo growpart /dev/sda 1
    sudo resize2fs /dev/sda1
    df -h /
"
```

### Verify

```bash
gcloud compute ssh $VM_NAME --zone=$ZONE --command="df -h /"
```

---

## Runbook 3: High CPU / Memory

**Alert**: CPU > 90% for 10 minutes

### Triage (2 minutes)

```bash
gcloud compute ssh $VM_NAME --zone=$ZONE --command="
    echo '=== UPTIME ==='
    uptime
    echo '=== TOP PROCESSES (CPU) ==='
    ps aux --sort=-%cpu | head -10
    echo '=== TOP PROCESSES (MEM) ==='
    ps aux --sort=-%mem | head -10
    echo '=== MEMORY ==='
    free -h
"
```

### Decision Tree

```
CPU > 90%?
├── Single process using all CPU?
│   ├── Known process (e.g., batch job) → Wait or add resources
│   ├── Unknown process → kill -15 PID, investigate
│   └── Mining malware → SECURITY INCIDENT (escalate)
│
├── Many processes, all legitimate?
│   └── Scale up: gcloud compute instances set-machine-type
│       (requires stop/start)
│
└── Load average > 2x CPU cores?
    └── Check I/O wait: iostat -x 1 5
        ├── High iowait → disk issue (see Runbook 2)
        └── Low iowait → genuine CPU saturation
```

### Fix

```bash
# Kill a runaway process
gcloud compute ssh $VM_NAME --zone=$ZONE --command="sudo kill -15 PID"

# Scale up (requires stop)
gcloud compute instances stop $VM_NAME --zone=$ZONE
gcloud compute instances set-machine-type $VM_NAME --zone=$ZONE \
    --machine-type=e2-medium
gcloud compute instances start $VM_NAME --zone=$ZONE
```

### Verify

```bash
gcloud compute ssh $VM_NAME --zone=$ZONE --command="uptime; top -bn1 | head -5"
```

---

## Runbook 4: SSH Failure

**Alert**: Cannot SSH to VM

### Triage (2 minutes)

```bash
# Check VM is running
gcloud compute instances describe $VM_NAME --zone=$ZONE --format="value(status)"

# Check firewall rules
gcloud compute firewall-rules list --filter="network:$NETWORK" \
    --format="table(name, direction, allowed, sourceRanges, targetTags)"

# Try IAP tunnel specifically
gcloud compute ssh $VM_NAME --zone=$ZONE --tunnel-through-iap \
    --ssh-flag="-v" 2>&1 | tail -20
```

### Decision Tree

```
SSH fails?
├── VM STOPPED → Start it (Runbook 1)
├── Connection timeout?
│   ├── Check firewall: is 35.235.240.0/20 allowed on tcp:22?
│   ├── Check VM tags match firewall target-tags
│   └── Check VPC routes
├── Connection refused?
│   ├── SSHD not running → serial console to restart
│   └── Port changed → check /etc/ssh/sshd_config
├── Permission denied?
│   ├── OS Login issues → check IAM roles
│   ├── SSH key issues → re-add metadata
│   └── Account locked → serial console
└── Host key changed?
    └── Remove old key: ssh-keygen -R HOSTNAME
```

### Fix: Re-enable SSH via Serial Console

```bash
# If SSHD crashed and you can't SSH:
# 1. Enable serial port temporarily
gcloud compute instances add-metadata $VM_NAME --zone=$ZONE \
    --metadata=serial-port-enable=TRUE

# 2. Connect via serial console (Cloud Console UI)
# 3. Fix SSHD:
#    sudo systemctl restart sshd
# 4. Disable serial port after fix
gcloud compute instances add-metadata $VM_NAME --zone=$ZONE \
    --metadata=serial-port-enable=FALSE
```

### Fix: Firewall Issue

```bash
# Re-add IAP SSH rule
gcloud compute firewall-rules create emergency-iap-ssh \
    --network=$NETWORK \
    --action=allow \
    --direction=ingress \
    --source-ranges=35.235.240.0/20 \
    --rules=tcp:22 \
    --priority=100
```

---

## Runbook 5: Security Incident

**Alert**: Unusual IAM activity / Unknown VM created / SCC finding

### FIRST RESPONSE (Immediately)

```
1. DO NOT PANIC
2. DO NOT DELETE EVIDENCE (logs, VMs, disks)
3. Record start time: date -u
4. Open an incident channel
5. Escalate to Security Team
```

### Triage (5 minutes)

```bash
# Who did what recently?
gcloud logging read \
    'logName="projects/'$PROJECT_ID'/logs/cloudaudit.googleapis.com%2Factivity"
     timestamp>="INCIDENT_TIME"' \
    --limit=20 \
    --format="table(timestamp, protoPayload.authenticationInfo.principalEmail, protoPayload.methodName)"

# Any new service account keys created?
gcloud logging read \
    'protoPayload.methodName="google.iam.admin.v1.CreateServiceAccountKey"' \
    --limit=10

# Any new firewall rules opened?
gcloud logging read \
    'resource.type="gce_firewall_rule" AND protoPayload.methodName=~"insert|patch"' \
    --limit=10

# Any new VMs created?
gcloud logging read \
    'protoPayload.methodName="v1.compute.instances.insert"
     timestamp>="INCIDENT_TIME"' \
    --limit=10
```

### Containment

```bash
# Disable compromised service account
gcloud iam service-accounts disable SA@PROJECT.iam.gserviceaccount.com

# Revoke SA keys
gcloud iam service-accounts keys list --iam-account=SA@PROJECT.iam.gserviceaccount.com
gcloud iam service-accounts keys delete KEY_ID --iam-account=SA@PROJECT.iam.gserviceaccount.com

# Block network on suspicious VM (don't delete it — preserve evidence)
gcloud compute firewall-rules create quarantine-vm \
    --network=NETWORK \
    --action=deny \
    --direction=ingress \
    --rules=all \
    --target-tags=quarantine \
    --priority=100

gcloud compute instances add-tags SUSPICIOUS_VM --zone=ZONE --tags=quarantine
```

### Preserve Evidence

```bash
# Snapshot the suspicious VM's disk
gcloud compute disks snapshot DISK_NAME --zone=ZONE \
    --snapshot-names=forensic-snapshot-$(date +%Y%m%d)

# Export logs to GCS
gcloud logging read 'timestamp>="INCIDENT_TIME"' \
    --format=json > incident-logs-$(date +%Y%m%d).json
```

---

## Post-Incident Checklist

- [ ] Service restored and verified
- [ ] All temporary fixes documented
- [ ] Monitoring confirming normal operation
- [ ] Stakeholders notified of resolution
- [ ] RCA scheduled (within 48 hours)
- [ ] Action items created in ticket system
- [ ] Playbook updated if needed
PLAYBOOK

echo "Playbook created at ~/playbooks/ops-playbook-v1.md"
wc -l ~/playbooks/ops-playbook-v1.md
```

### Step 2 — Test Runbook 2 (Disk Full)

```bash
# Create test VM
gcloud compute instances create playbook-test-vm \
    --zone=$ZONE \
    --machine-type=e2-small \
    --image-family=debian-12 \
    --image-project=debian-cloud

# Simulate disk issue
gcloud compute ssh playbook-test-vm --zone=$ZONE --command="
    dd if=/dev/zero of=/tmp/filler bs=1M count=5000 2>/dev/null
    echo 'Disk after fill:'
    df -h /
"

# Now follow Runbook 2 to fix it
echo "=== Following Runbook 2: Disk Full ==="

# Triage
gcloud compute ssh playbook-test-vm --zone=$ZONE --command="
    df -h
    echo '---'
    du -sh /var/log/* 2>/dev/null | sort -rh | head -10
    echo '---'
    sudo find /tmp -type f -size +100M -exec ls -lh {} \;
"

# Quick Fix
gcloud compute ssh playbook-test-vm --zone=$ZONE --command="
    sudo rm -f /tmp/filler
    sudo apt-get clean
    sudo journalctl --vacuum-time=3d
    echo 'After cleanup:'
    df -h /
"

# Verify
gcloud compute ssh playbook-test-vm --zone=$ZONE --command="df -h /"
echo "✅ Runbook 2 test complete"
```

### Step 3 — Test Runbook 3 (High CPU)

```bash
# Simulate CPU issue
gcloud compute ssh playbook-test-vm --zone=$ZONE --command="
    sudo apt-get update -y && sudo apt-get install -y stress-ng
    nohup stress-ng --cpu 2 --timeout 120 > /dev/null 2>&1 &
    sleep 5
    echo 'Under stress:'
    uptime
"

# Follow Runbook 3
echo "=== Following Runbook 3: High CPU ==="

gcloud compute ssh playbook-test-vm --zone=$ZONE --command="
    echo '=== TRIAGE ==='
    uptime
    echo '=== TOP PROCESSES ==='
    ps aux --sort=-%cpu | head -5
    echo '=== ACTION: Kill stress ==='
    pkill stress-ng
    sleep 2
    echo '=== VERIFY ==='
    uptime
"
echo "✅ Runbook 3 test complete"
```

### Cleanup

```bash
gcloud compute instances delete playbook-test-vm --zone=$ZONE --quiet
```

---

## Part 3 — Revision (15 min)

### Key Concepts

- **Playbook** = collection of runbooks + escalation matrix + reference commands
- Every runbook has: Triage → Diagnose → Fix → Verify
- **Decision trees** handle multiple scenarios within one runbook
- **Escalation matrix** defines who/when/how at each severity
- Playbooks must be **tested regularly** (monthly simulations)
- Update the playbook **after every incident** (continuous improvement)
- Security incidents: **contain first**, preserve evidence, then investigate

### Five Key Runbooks

| # | Scenario | First Command |
|---|----------|---------------|
| 1 | VM down | `gcloud compute instances describe VM --format="value(status)"` |
| 2 | Disk full | SSH → `df -h; du -sh /var/log/* | sort -rh | head` |
| 3 | High CPU | SSH → `uptime; ps aux --sort=-%cpu | head` |
| 4 | SSH failure | `gcloud compute firewall-rules list; gcloud compute ssh --tunnel-through-iap -v` |
| 5 | Security | `gcloud logging read 'logName=~"cloudaudit"' --limit=20` |

---

## Part 4 — Quiz (15 min)

**Question 1: At 3 AM, an alert fires: "VM `prod-api-01` CPU > 95% for 15 min." Walk through your response using the playbook.**

<details>
<summary>Show Answer</summary>

**Step-by-step using Runbook 3 (High CPU):**

1. **Acknowledge** alert via PagerDuty (< 2 min)

2. **Triage** (< 5 min):
   ```bash
   gcloud compute ssh prod-api-01 --zone=ZONE --tunnel-through-iap \
       --command="uptime; ps aux --sort=-%cpu | head -10; free -h"
   ```

3. **Decide** (decision tree):
   - Single process? → Identify and kill if safe
   - Many processes? → Check if traffic spike (LB logs)
   - Unknown process? → Potential security issue → escalate

4. **Fix** based on decision:
   - Traffic spike: Scale out (add instances to MIG) or scale up
   - Runaway process: `kill -15 PID`, investigate cause
   - Batch job: Let it complete if non-urgent

5. **Verify**:
   ```bash
   gcloud compute ssh prod-api-01 --command="uptime; top -bn1 | head -5"
   ```

6. **Document**: Update incident ticket, note actions taken, time to resolution

</details>

**Question 2: A new team member joins. How do you ensure they can handle a P2 incident at 3 AM with only the playbook?**

<details>
<summary>Show Answer</summary>

The playbook must be **self-contained** and **tested**:

1. **Onboarding**: Walk through each runbook with the new person during business hours
2. **Shadow on-call**: New person shadows experienced engineer for 1 week
3. **Game day**: Simulate each scenario in staging, have them follow the runbook
4. **Verify access**: Ensure they have:
   - `gcloud` configured with correct project
   - IAP SSH permissions
   - PagerDuty account
   - Access to monitoring dashboards
   - Slack/Teams access to incident channel
5. **Buddy system**: First solo on-call has a "secondary" they can escalate to
6. **Test the playbook**: If the new person can't follow it, the playbook needs improvement

The goal: any team member should be able to follow the runbook without needing to ask someone. If they have to ask, update the runbook.

</details>

**Question 3: Your playbook doesn't have a runbook for "database backup failure." An alert fires for exactly that. What do you do?**

<details>
<summary>Show Answer</summary>

**Immediate response** (apply general incident response):

1. **Triage**: What service? What failed? Check logs.
2. **Impact**: Is the database still running? When was last successful backup?
3. **Fix**: Manually trigger backup, fix the blocker
4. **Verify**: Confirm backup completed

**After the incident:**

1. Write an RCA
2. **Create a new runbook** for database backup failure and add it to the playbook
3. The new runbook should include:
   - How to check backup status
   - Common failure reasons (disk full, permission, timeout)
   - How to manually trigger backup
   - How to verify backup integrity
   - When to escalate (if data loss risk)

The playbook is a **living document** — every incident without a matching runbook should result in a new runbook.

</details>

**Question 4: Your security runbook says "don't delete the suspicious VM." A manager asks you to delete it immediately to "stop the attack." What do you do?**

<details>
<summary>Show Answer</summary>

**Follow the playbook — do not delete the VM:**

1. **Quarantine instead of delete**:
   ```bash
   # Block all traffic to/from the VM
   gcloud compute instances add-tags VM --tags=quarantine
   # quarantine tag has deny-all firewall rule
   ```

2. **Explain to the manager**: "Deleting the VM destroys forensic evidence. We need the disk for investigation. Quarantining it stops the attack while preserving evidence."

3. **Preserve evidence**:
   ```bash
   gcloud compute disks snapshot DISK --snapshot-names=forensic-$(date +%Y%m%d)
   ```

4. **If the manager insists**: Escalate to Security team lead. They have authority over incident handling.

5. **After forensics**: Then the VM can be deleted.

The key principle: **contain, don't destroy**. Network isolation stops the attack. Disk snapshots preserve evidence for root cause analysis, compliance, and potentially legal proceedings.

Linux analogy: Unplugging the network cable, not running `rm -rf /`.

</details>

---

*Next: [Day 72 — PROJECT: Incident Simulation + RCA Report](DAY_72_PROJECT_INCIDENT_SIM.md)*
