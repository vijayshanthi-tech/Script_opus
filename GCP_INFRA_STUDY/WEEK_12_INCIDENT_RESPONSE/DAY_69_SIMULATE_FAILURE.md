# Day 69 — Simulate Failure

> **Week 12 · Incident Response**
> Estimated time: 2 hours | Region: `europe-west2` (London)
> Prerequisites: Day 68 completed

---

## Part 1 — Concept (30 min)

### Chaos Engineering Lite

```
"Everything fails, all the time." — Werner Vogels, CTO Amazon

Traditional approach:                Chaos approach:
┌──────────────────────┐            ┌──────────────────────┐
│ Wait for failure     │            │ CAUSE failure        │
│         │            │            │         │            │
│         ▼            │            │         ▼            │
│ Panic, scramble      │            │ Observe, learn       │
│         │            │            │         │            │
│         ▼            │            │         ▼            │
│ Fix under pressure   │            │ Fix calmly           │
│         │            │            │         │            │
│         ▼            │            │         ▼            │
│ "Hope it doesn't     │            │ "We know this works  │
│  happen again"       │            │  because we tested"  │
└──────────────────────┘            └──────────────────────┘
```

### Failure Scenarios Matrix

```
┌──────────────────────────────────────────────────────────────┐
│              FAILURE SCENARIOS TO TEST                         │
│                                                               │
│  COMPUTE FAILURES:                                           │
│  ├── VM stopped unexpectedly                                  │
│  ├── VM terminated (preemptible/spot)                        │
│  ├── Process crash (OOM, segfault)                           │
│  └── CPU saturation (runaway process)                        │
│                                                               │
│  STORAGE FAILURES:                                           │
│  ├── Disk full (100%)                                        │
│  ├── Disk I/O saturation                                     │
│  └── Disk detached                                           │
│                                                               │
│  NETWORK FAILURES:                                           │
│  ├── Firewall misconfiguration                               │
│  ├── DNS resolution failure                                  │
│  ├── High packet loss                                        │
│  └── Port blocked                                            │
│                                                               │
│  APPLICATION FAILURES:                                       │
│  ├── Service process killed                                  │
│  ├── Configuration error                                     │
│  ├── Memory leak (gradual)                                   │
│  └── Log partition full                                      │
└──────────────────────────────────────────────────────────────┘
```

### Detection Expectations

| Failure | Expected Detection Method | Expected Time | Linux Analogy |
|---------|--------------------------|---------------|---------------|
| VM stopped | Uptime check fails | 1-5 min | `ping` timeout |
| CPU saturated | CPU metric alert | 10-15 min | `top` + Nagios |
| Disk full | Disk metric alert | 5-10 min | `df -h` + monit |
| Process killed | Custom health check | 1-5 min | `systemctl` failure |
| SSH failure | Audit log pattern | 1-5 min | `auth.log` alert |
| Network blocked | Connectivity test fails | 1-5 min | `iptables` log |

### Blast Radius Control

```
┌──────────────────────────────────────────────────────────┐
│              BLAST RADIUS CONTROL                         │
│                                                           │
│  Rule 1: Always test in NON-PRODUCTION first             │
│  Rule 2: Have a KILL SWITCH (stop the chaos)             │
│  Rule 3: SINGLE FAILURE at a time                        │
│  Rule 4: MONITOR DURING the test                         │
│  Rule 5: Document EXPECTED vs ACTUAL behaviour           │
│                                                           │
│  Safety Net:                                              │
│  ┌─────────────────────────────────────────────┐         │
│  │  Test VM     →  Break it  →  Observe alerts │         │
│  │  (isolated)     (known)      (validate)     │         │
│  │                                              │         │
│  │  Kill Switch: gcloud compute instances start │         │
│  │  Rollback: snapshot restore                  │         │
│  └─────────────────────────────────────────────┘         │
│                                                           │
│  Linux analogy: Testing DR in a VM, not on the           │
│  production database server                               │
└──────────────────────────────────────────────────────────┘
```

---

## Part 2 — Hands-On Lab (60 min)

### Lab Objective

Simulate five failure scenarios, verify monitoring catches each one, and practice the detection-to-response workflow.

### Step 1 — Set Variables and Create Test VM

```bash
export PROJECT_ID=$(gcloud config get-value project)
export REGION=europe-west2
export ZONE=europe-west2-a
export VM_NAME=chaos-test-vm

# Create VM with Ops Agent
gcloud compute instances create $VM_NAME \
    --zone=$ZONE \
    --machine-type=e2-small \
    --image-family=debian-12 \
    --image-project=debian-cloud \
    --tags=chaos-test \
    --metadata=startup-script='#!/bin/bash
apt-get update -y
apt-get install -y stress-ng htop
curl -sSO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh
bash add-google-cloud-ops-agent-repo.sh --also-install
echo "Setup complete" > /var/log/chaos-ready.log'
```

### Step 2 — Wait for VM Setup

```bash
# Wait for startup script to complete (~3 minutes)
echo "Waiting for VM setup..."
for i in $(seq 1 12); do
    STATUS=$(gcloud compute ssh $VM_NAME --zone=$ZONE --command="cat /var/log/chaos-ready.log 2>/dev/null" 2>/dev/null)
    if [ "$STATUS" = "Setup complete" ]; then
        echo "VM ready!"
        break
    fi
    echo "Waiting... ($i/12)"
    sleep 15
done
```

### Scenario 1 — CPU Saturation

```bash
echo "=== SCENARIO 1: CPU SATURATION ==="
echo "Expected: CPU metric rises above 90%"
echo ""

# Start CPU stress
gcloud compute ssh $VM_NAME --zone=$ZONE --command="
    echo 'Starting CPU stress for 10 minutes...'
    nohup stress-ng --cpu 2 --timeout 600 > /dev/null 2>&1 &
    echo 'PID:' \$!
"

# Monitor from outside
echo ""
echo "Check monitoring:"
echo "  gcloud monitoring time-series list \\"
echo "    --filter='metric.type=\"compute.googleapis.com/instance/cpu/utilization\"' \\"
echo "    --limit=5"
echo ""

# Verify CPU is high
sleep 60
gcloud compute ssh $VM_NAME --zone=$ZONE --command="
    echo '=== CPU CHECK ==='
    uptime
    echo ''
    top -bn1 | head -5
"

# Kill switch — stop the stress
gcloud compute ssh $VM_NAME --zone=$ZONE --command="
    pkill stress-ng
    echo 'CPU stress stopped'
    uptime
"
echo "✅ Scenario 1 complete"
```

### Scenario 2 — Disk Full

```bash
echo "=== SCENARIO 2: DISK FULL ==="
echo "Expected: Disk usage alert triggers"
echo ""

# Fill the disk (leave 5% free to avoid system crash)
gcloud compute ssh $VM_NAME --zone=$ZONE --command="
    echo 'Current disk usage:'
    df -h /
    echo ''
    
    # Calculate space to fill (fill to 92%)
    TOTAL_KB=\$(df / | tail -1 | awk '{print \$2}')
    USED_KB=\$(df / | tail -1 | awk '{print \$3}')
    TARGET_KB=\$(( TOTAL_KB * 92 / 100 ))
    FILL_KB=\$(( TARGET_KB - USED_KB ))
    
    if [ \$FILL_KB -gt 0 ]; then
        echo \"Filling \${FILL_KB}KB to reach 92%...\"
        dd if=/dev/zero of=/tmp/disk-filler bs=1K count=\$FILL_KB 2>/dev/null
    fi
    
    echo ''
    echo 'After filling:'
    df -h /
"

# Wait and check monitoring
echo "Check Cloud Monitoring for disk usage spike"
echo ""

# Kill switch — free the space
gcloud compute ssh $VM_NAME --zone=$ZONE --command="
    rm -f /tmp/disk-filler
    echo 'Disk freed:'
    df -h /
"
echo "✅ Scenario 2 complete"
```

### Scenario 3 — Process Kill

```bash
echo "=== SCENARIO 3: PROCESS KILL ==="
echo "Expected: Ops Agent stops reporting; health check failure"
echo ""

# Kill the Ops Agent (simulating process crash)
gcloud compute ssh $VM_NAME --zone=$ZONE --command="
    echo 'Ops Agent status BEFORE:'
    sudo systemctl status google-cloud-ops-agent --no-pager | head -5
    echo ''
    
    # Kill the agent
    sudo systemctl stop google-cloud-ops-agent
    
    echo 'Ops Agent status AFTER:'
    sudo systemctl status google-cloud-ops-agent --no-pager | head -5
"

echo ""
echo "Monitor: Ops Agent metrics should stop arriving in ~2 minutes"
echo "In production, this would trigger a 'process not running' alert"
echo ""

# Kill switch — restart the agent
sleep 30
gcloud compute ssh $VM_NAME --zone=$ZONE --command="
    sudo systemctl start google-cloud-ops-agent
    echo 'Ops Agent restarted:'
    sudo systemctl status google-cloud-ops-agent --no-pager | head -5
"
echo "✅ Scenario 3 complete"
```

### Scenario 4 — VM Stop (Unexpected Shutdown)

```bash
echo "=== SCENARIO 4: VM STOP ==="
echo "Expected: Uptime check fails, audit log shows stop event"
echo ""

# Record the stop time
echo "Stopping VM at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Stop the VM
gcloud compute instances stop $VM_NAME --zone=$ZONE --quiet

# Check audit log for the stop event
sleep 10
gcloud logging read \
    'resource.type="gce_instance"
     logName="projects/'$PROJECT_ID'/logs/cloudaudit.googleapis.com%2Factivity"
     protoPayload.methodName="v1.compute.instances.stop"' \
    --limit=1 \
    --format="table(timestamp, protoPayload.authenticationInfo.principalEmail)"

echo ""
echo "VM stopped. Uptime checks should fail within 1-2 minutes."
echo ""

# Kill switch — restart
gcloud compute instances start $VM_NAME --zone=$ZONE
echo "Waiting for VM to start..."
sleep 30
echo "✅ Scenario 4 complete"
```

### Scenario 5 — Network Block (Firewall Misconfiguration)

```bash
echo "=== SCENARIO 5: FIREWALL MISCONFIGURATION ==="
echo "Expected: SSH stops working, connectivity check fails"
echo ""

# Block all SSH (simulating firewall misconfiguration)
gcloud compute firewall-rules create chaos-block-ssh \
    --network=default \
    --action=deny \
    --direction=ingress \
    --rules=tcp:22 \
    --priority=100 \
    --target-tags=chaos-test

echo "SSH blocked. Try connecting (will timeout):"
echo "  gcloud compute ssh $VM_NAME --zone=$ZONE  (will fail)"

# Verify SSH is blocked (set a short timeout)
gcloud compute ssh $VM_NAME --zone=$ZONE \
    --command="echo 'This should not work'" \
    --ssh-flag="-o ConnectTimeout=10" 2>&1 | head -3

echo ""
echo "SSH connection blocked as expected."

# Check the firewall rule in audit log
gcloud logging read \
    'resource.type="gce_firewall_rule"
     logName="projects/'$PROJECT_ID'/logs/cloudaudit.googleapis.com%2Factivity"' \
    --limit=1 \
    --format="table(timestamp, protoPayload.methodName, protoPayload.resourceName)"

# Kill switch — remove blocking rule
gcloud compute firewall-rules delete chaos-block-ssh --quiet
echo "Firewall rule removed. SSH should work again."

# Verify recovery
sleep 5
gcloud compute ssh $VM_NAME --zone=$ZONE --command="echo 'SSH recovered!'" 2>/dev/null
echo "✅ Scenario 5 complete"
```

### Step 3 — Review Detection Results

```bash
echo "=== DETECTION SUMMARY ==="
echo ""
echo "| Scenario | Detection | Time | Result |"
echo "|----------|-----------|------|--------|"
echo "| 1. CPU   | CPU metric| ~1m  | Check  |"
echo "| 2. Disk  | Disk met. | ~1m  | Check  |"
echo "| 3. OpsAgt| Gap in met| ~2m  | Check  |"
echo "| 4. VM off| Audit log | ~10s | Check  |"
echo "| 5. FW    | SSH fail  | ~10s | Check  |"
echo ""
echo "Review Cloud Monitoring dashboard for visual confirmation"
```

### Cleanup

```bash
gcloud compute instances delete $VM_NAME --zone=$ZONE --quiet
gcloud compute firewall-rules delete chaos-block-ssh --quiet 2>/dev/null
```

---

## Part 3 — Revision (15 min)

### Key Concepts

- **Chaos engineering** = deliberately injecting failure to find weaknesses
- Always test in **non-production** first, one failure at a time
- Every test needs a **kill switch** (how to stop the chaos immediately)
- Document **expected vs actual** behaviour for each scenario
- The five common failure modes: CPU, Disk, Process, VM, Network
- Cloud Monitoring detects metric-based failures in **1-5 minutes**
- Audit logs capture infrastructure changes **immediately**

### Kill Switch Commands

```bash
# CPU: kill stress process
gcloud compute ssh VM --command="pkill stress-ng"

# Disk: remove filler file
gcloud compute ssh VM --command="rm -f /tmp/disk-filler"

# Process: restart the service
gcloud compute ssh VM --command="sudo systemctl start SERVICE"

# VM stopped: start it back
gcloud compute instances start VM --zone=ZONE

# Firewall: delete blocking rule
gcloud compute firewall-rules delete RULE --quiet
```

---

## Part 4 — Quiz (15 min)

**Question 1: You run a chaos test that fills a disk to 100%. The VM becomes unresponsive and you can't SSH in. How do you recover?**

<details>
<summary>Show Answer</summary>

Recovery when SSH is broken due to full disk:

1. **Stop the VM** (doesn't need SSH):
   ```bash
   gcloud compute instances stop VM --zone=ZONE
   ```

2. **Detach the boot disk:**
   ```bash
   gcloud compute instances detach-disk VM --disk=DISK --zone=ZONE
   ```

3. **Attach to a rescue VM:**
   ```bash
   gcloud compute instances attach-disk rescue-vm --disk=DISK --zone=ZONE
   gcloud compute ssh rescue-vm --command="
       sudo mkdir /mnt/rescue
       sudo mount /dev/sdb1 /mnt/rescue
       sudo rm /mnt/rescue/tmp/disk-filler
       sudo umount /mnt/rescue
   "
   ```

4. **Reattach to original VM and start:**
   ```bash
   gcloud compute instances detach-disk rescue-vm --disk=DISK
   gcloud compute instances attach-disk VM --disk=DISK --boot --zone=ZONE
   gcloud compute instances start VM
   ```

**Prevention**: Never fill past 95% in chaos tests. Always leave enough space for SSH to function.

Linux analogy: Booting from a USB rescue disk to fix a full root partition.

</details>

**Question 2: Your chaos test stopped the Ops Agent. How would you know if this happened in production without the test?**

<details>
<summary>Show Answer</summary>

Detect it by **alerting on metric gaps**:

1. **Create an "absent metric" alert** — triggers when expected metrics stop arriving:
   ```json
   {
     "conditionAbsent": {
       "filter": "metric.type=\"agent.googleapis.com/agent/uptime\"",
       "duration": "300s"
     }
   }
   ```

2. **Uptime check on the agent port** (if applicable)

3. **Process monitoring** via log-based metric:
   - Ops Agent logs its own status
   - Alert when "agent started" messages stop appearing

4. **External health check** that verifies metric freshness

The key insight: you must **monitor your monitoring**. If the agent dies, you lose visibility — unless you have an independent check.

Linux analogy: `monit` watching `collectd` — one monitoring tool ensures the other monitoring tool is running.

</details>

**Question 3: What's the difference between chaos engineering and destructive testing?**

<details>
<summary>Show Answer</summary>

| Aspect | Chaos Engineering | Destructive Testing |
|--------|------------------|-------------------|
| **Goal** | Verify monitoring and recovery work | Find breaking points |
| **Scope** | Controlled, single failure | Push to extremes |
| **Production** | Yes (after staging) | Never in production |
| **Duration** | Short, time-boxed | Until failure |
| **Kill switch** | Always available | May not have one |
| **Outcome** | Confidence in resilience | Knowledge of limits |
| **Blast radius** | Minimized | Potentially large |

Chaos engineering asks: "Does our system **detect and recover** from this failure?"
Destructive testing asks: "At what point does our system **break**?"

In this lab, we did chaos engineering: controlled failures with kill switches, observing detection latency.

</details>

**Question 4: In the firewall scenario, you blocked SSH. How would you recover if you didn't have `gcloud` access (e.g., only serial console)?**

<details>
<summary>Show Answer</summary>

If SSH and `gcloud` are both unavailable:

1. **Serial console** (if enabled): Connect via Cloud Console → VM → Serial console. Log in and fix iptables from inside.

2. **Startup script**: Add a metadata startup script that runs on reboot to fix the firewall:
   ```bash
   gcloud compute instances add-metadata VM \
       --metadata=startup-script='#!/bin/bash
   iptables -F  # flush host firewall rules'
   gcloud compute instances reset VM  # reboot
   ```

3. **Cloud Console UI**: Navigate to VPC → Firewall Rules → delete the blocking rule. No SSH needed.

4. **Another VM in the same VPC**: If you can reach another VM, modify the GCP firewall from there using `gcloud`.

**Prevention**: Never create deny-all firewall rules with priority < 1000. Always keep IAP access (35.235.240.0/20) as a fallback with high priority.

</details>

---

*Next: [Day 70 — RCA Write-Up Template](DAY_70_RCA_TEMPLATE.md)*
