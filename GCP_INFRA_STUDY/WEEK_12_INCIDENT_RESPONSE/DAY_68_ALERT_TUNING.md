# Day 68 — Alert Tuning

> **Week 12 · Incident Response**
> Estimated time: 2 hours | Region: `europe-west2` (London)
> Prerequisites: Day 67 completed

---

## Part 1 — Concept (30 min)

### The Alert Fatigue Problem

```
BAD ALERTS:                          GOOD ALERTS:
┌──────────────────────┐            ┌──────────────────────┐
│ 200 alerts/day       │            │ 5 alerts/day         │
│         │            │            │         │            │
│         ▼            │            │         ▼            │
│ Team ignores all     │            │ Each one matters     │
│         │            │            │         │            │
│         ▼            │            │         ▼            │
│ Real incident buried │            │ Immediate response   │
│ in noise             │            │         │            │
│         │            │            │         ▼            │
│         ▼            │            │ 30 min MTTR          │
│ 4 hour MTTR          │            │                      │
└──────────────────────┘            └──────────────────────┘
```

### Alert Priority Levels

```
┌──────────────────────────────────────────────────────────────┐
│                    ALERT PRIORITY LEVELS                       │
│                                                               │
│  P1 - CRITICAL (Page immediately, 24/7)                      │
│  ├── Service completely down                                  │
│  ├── Data loss occurring                                      │
│  ├── Security breach detected                                │
│  └── Response: < 15 min                                      │
│                                                               │
│  P2 - HIGH (Page during business hours)                      │
│  ├── Service degraded (>50% error rate)                      │
│  ├── Single point of failure engaged                         │
│  ├── Disk > 90% full                                         │
│  └── Response: < 1 hour                                      │
│                                                               │
│  P3 - MEDIUM (Email, next business day)                      │
│  ├── Performance degraded (<20% impact)                      │
│  ├── Disk > 80% full                                         │
│  ├── Certificate expiring in 14 days                         │
│  └── Response: < 1 business day                              │
│                                                               │
│  P4 - LOW (Ticket, within sprint)                            │
│  ├── Non-critical warning                                     │
│  ├── Optimization opportunity                                 │
│  └── Response: within sprint/week                            │
│                                                               │
│  INFO - No alert (Dashboard/log only)                        │
│  ├── Health check passing                                     │
│  ├── Routine operations                                       │
│  └── Informational metrics                                    │
└──────────────────────────────────────────────────────────────┘
```

### Alert Tuning Techniques

| Technique | Description | Linux Analogy |
|-----------|-------------|---------------|
| **Threshold tuning** | Adjust trigger value (80%→90%) | `monit` threshold config |
| **Duration window** | Require sustained condition (5 min not 1 min) | `fail2ban maxretry/findtime` |
| **Grouping** | Combine related alerts into one | `logrotate` group rotation |
| **Suppression** | Mute during maintenance | `cron` quiet hours |
| **Rate limiting** | Max alerts per hour | `iptables --limit` |
| **Auto-resolution** | Close when condition clears | `systemd Restart=` |

### The Golden Signals (SRE)

```
┌───────────────────────────────────────────────────────┐
│              THE FOUR GOLDEN SIGNALS                    │
│                                                        │
│  ┌─────────────────┐    ┌─────────────────┐           │
│  │ 1. LATENCY      │    │ 2. TRAFFIC      │           │
│  │ How long do     │    │ How much demand │           │
│  │ requests take?  │    │ is hitting the  │           │
│  │                 │    │ system?         │           │
│  │ Alert: p99 >   │    │ Alert: sudden   │           │
│  │ 500ms for 5min │    │ drop > 50%      │           │
│  └─────────────────┘    └─────────────────┘           │
│                                                        │
│  ┌─────────────────┐    ┌─────────────────┐           │
│  │ 3. ERRORS       │    │ 4. SATURATION   │           │
│  │ What's the rate │    │ How full is the │           │
│  │ of failures?    │    │ system?         │           │
│  │                 │    │                 │           │
│  │ Alert: error    │    │ Alert: CPU >    │           │
│  │ rate > 1% for  │    │ 90% for 10min  │           │
│  │ 5min            │    │                 │           │
│  └─────────────────┘    └─────────────────┘           │
│                                                        │
│  Linux analogy:                                        │
│  1. time curl     2. netstat -c                        │
│  3. journalctl -p err  4. df -h / top                 │
└───────────────────────────────────────────────────────┘
```

### Good vs Bad Alert Design

| Aspect | Bad Alert | Good Alert |
|--------|-----------|-----------|
| Condition | CPU > 50% | CPU > 90% for 10 min |
| Duration | Instant (1 data point) | Sustained (5+ min) |
| Actionable | "CPU is high" | "Web server CPU saturated, check traffic spike or runaway process" |
| Documentation | None | Links to runbook |
| Notification | Email to team@ | PagerDuty → on-call person |
| Auto-resolve | No | Yes, when condition clears |

---

## Part 2 — Hands-On Lab (60 min)

### Lab Objective

Create a tiered alerting system with proper thresholds, duration windows, and notification channels.

### Step 1 — Set Variables

```bash
export PROJECT_ID=$(gcloud config get-value project)
export REGION=europe-west2
export ZONE=europe-west2-a
```

### Step 2 — Create Test VM

```bash
gcloud compute instances create alert-test-vm \
    --zone=$ZONE \
    --machine-type=e2-small \
    --image-family=debian-12 \
    --image-project=debian-cloud \
    --tags=alert-test
```

### Step 3 — Create Notification Channel (Email)

```bash
# Create email notification channel
gcloud monitoring channels create \
    --display-name="Alert Tuning Lab - Email" \
    --type=email \
    --channel-labels=email_address=$(gcloud config get-value account) \
    --description="Lab notification channel"

# Get the channel ID
CHANNEL_ID=$(gcloud monitoring channels list \
    --filter='displayName="Alert Tuning Lab - Email"' \
    --format="value(name)")
echo "Channel: $CHANNEL_ID"
```

### Step 4 — Create P2 Alert: CPU Over 90% for 10 Minutes

```bash
# This is a GOOD alert: high threshold + sustained duration
cat > /tmp/cpu-alert-policy.json << EOF
{
  "displayName": "P2: VM CPU > 90% for 10min",
  "documentation": {
    "content": "## Runbook\n1. SSH to the VM\n2. Run \`top\` to find the process\n3. Check if traffic spike or runaway process\n4. Scale up or kill process if needed\n5. If recurring, investigate autoscaling",
    "mimeType": "text/markdown"
  },
  "conditions": [
    {
      "displayName": "CPU utilization > 90%",
      "conditionThreshold": {
        "filter": "resource.type = \"gce_instance\" AND metric.type = \"compute.googleapis.com/instance/cpu/utilization\"",
        "comparison": "COMPARISON_GT",
        "thresholdValue": 0.9,
        "duration": "600s",
        "aggregations": [
          {
            "alignmentPeriod": "60s",
            "perSeriesAligner": "ALIGN_MEAN"
          }
        ]
      }
    }
  ],
  "combiner": "OR",
  "notificationChannels": ["$CHANNEL_ID"],
  "alertStrategy": {
    "autoClose": "1800s"
  }
}
EOF

gcloud monitoring policies create --policy-from-file=/tmp/cpu-alert-policy.json
```

### Step 5 — Create P3 Alert: Disk Over 80%

```bash
cat > /tmp/disk-alert-policy.json << EOF
{
  "displayName": "P3: VM Disk > 80% full",
  "documentation": {
    "content": "## Runbook\n1. SSH to VM\n2. \`df -h\` to check usage\n3. \`du -sh /var/log/*\` for log bloat\n4. Clean old logs: \`journalctl --vacuum-time=7d\`\n5. If persistent, resize disk",
    "mimeType": "text/markdown"
  },
  "conditions": [
    {
      "displayName": "Disk utilization > 80%",
      "conditionThreshold": {
        "filter": "resource.type = \"gce_instance\" AND metric.type = \"agent.googleapis.com/disk/percent_used\" AND metric.labels.state = \"used\"",
        "comparison": "COMPARISON_GT",
        "thresholdValue": 80,
        "duration": "300s",
        "aggregations": [
          {
            "alignmentPeriod": "60s",
            "perSeriesAligner": "ALIGN_MEAN"
          }
        ]
      }
    }
  ],
  "combiner": "OR",
  "notificationChannels": ["$CHANNEL_ID"],
  "alertStrategy": {
    "autoClose": "3600s"
  }
}
EOF

gcloud monitoring policies create --policy-from-file=/tmp/disk-alert-policy.json
```

### Step 6 — Create Alert from Log-Based Metric

```bash
# First ensure the metric exists from Day 67
gcloud logging metrics create vm-deletion-alert-metric \
    --description="VM deletion events" \
    --log-filter='resource.type="gce_instance"
        logName="projects/'$PROJECT_ID'/logs/cloudaudit.googleapis.com%2Factivity"
        protoPayload.methodName="v1.compute.instances.delete"' 2>/dev/null || true

# Create alert: any VM deletion triggers P2
cat > /tmp/vm-delete-alert.json << EOF
{
  "displayName": "P2: VM Deleted",
  "documentation": {
    "content": "## Runbook\n1. Check audit log for who deleted the VM\n2. Verify if planned deletion\n3. If unplanned, check IAM for unauthorized access\n4. Restore from snapshot if needed",
    "mimeType": "text/markdown"
  },
  "conditions": [
    {
      "displayName": "VM deletion detected",
      "conditionThreshold": {
        "filter": "resource.type = \"global\" AND metric.type = \"logging.googleapis.com/user/vm-deletion-alert-metric\"",
        "comparison": "COMPARISON_GT",
        "thresholdValue": 0,
        "duration": "0s",
        "aggregations": [
          {
            "alignmentPeriod": "60s",
            "perSeriesAligner": "ALIGN_COUNT"
          }
        ]
      }
    }
  ],
  "combiner": "OR",
  "notificationChannels": ["$CHANNEL_ID"],
  "alertStrategy": {
    "autoClose": "1800s"
  }
}
EOF

gcloud monitoring policies create --policy-from-file=/tmp/vm-delete-alert.json
```

### Step 7 — Create Uptime Check Alert

```bash
# Uptime check: is the VM's SSH port reachable?
# (Internal uptime check for private VMs)
gcloud monitoring uptime create alert-vm-ssh-check \
    --display-name="VM SSH Port Check" \
    --resource-type=gce-instance \
    --resource-labels=project_id=$PROJECT_ID,instance_id=$(gcloud compute instances describe alert-test-vm --zone=$ZONE --format='value(id)'),zone=$ZONE \
    --protocol=tcp \
    --port=22 \
    --period=5 \
    --timeout=10 2>/dev/null || echo "Uptime check may need Console for internal checks"
```

### Step 8 — List and Review Alert Policies

```bash
# List all alert policies
gcloud monitoring policies list \
    --format="table(displayName, enabled, conditions[0].conditionThreshold.thresholdValue, conditions[0].conditionThreshold.duration)"

# Describe a specific policy
POLICY_ID=$(gcloud monitoring policies list \
    --filter='displayName:"P2: VM CPU"' \
    --format="value(name)")
gcloud monitoring policies describe $POLICY_ID
```

### Step 9 — Test Alert: Trigger CPU Spike

```bash
# SSH and create CPU load
gcloud compute ssh alert-test-vm --zone=$ZONE --command="
    # Install stress tool
    sudo apt-get update -y && sudo apt-get install -y stress
    # Stress CPU for 15 minutes (to trigger 10min alert)
    nohup stress --cpu 2 --timeout 900 &
    echo 'CPU stress started. Alert should fire in ~12 minutes.'
"

# Monitor CPU from outside
echo "Waiting for metrics... Check Cloud Monitoring Console"
echo "Or run: gcloud monitoring dashboards list"
```

### Step 10 — Snooze an Alert (Maintenance Window)

```bash
# Create a snooze for planned maintenance
START=$(date -u -d '+5 minutes' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)
END=$(date -u -d '+65 minutes' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)

echo "To create a maintenance window (snooze), use Console:"
echo "Monitoring → Alerting → Snooze"
echo "Or use the API:"
echo "Start: $START"
echo "End: $END"
echo ""
echo "This prevents alert noise during planned maintenance."
```

### Cleanup

```bash
# Delete alert policies
for POLICY in $(gcloud monitoring policies list --format="value(name)"); do
    gcloud monitoring policies delete $POLICY --quiet
done

# Delete notification channel
gcloud monitoring channels delete $CHANNEL_ID --quiet 2>/dev/null

# Delete log metric
gcloud logging metrics delete vm-deletion-alert-metric --quiet 2>/dev/null

# Delete VM
gcloud compute instances delete alert-test-vm --zone=$ZONE --quiet
```

---

## Part 3 — Revision (15 min)

### Key Concepts

- **Alert fatigue** is the #1 monitoring problem — 200 alerts/day means zero alerts/day
- **Four Golden Signals**: Latency, Traffic, Errors, Saturation — start here
- **Duration windows** prevent flapping (CPU spike for 1 second ≠ CPU problem)
- **Auto-close** resolves alerts when conditions clear (avoids stale incidents)
- **Runbook in documentation** field — every alert should tell you what to do
- **Notification channels**: Email for P3/P4, PagerDuty/SMS for P1/P2
- **Snooze/maintenance windows** prevent noise during planned work

### Essential Commands

```bash
# Create notification channel
gcloud monitoring channels create --type=email --channel-labels=email_address=USER@...

# Create alert policy from JSON
gcloud monitoring policies create --policy-from-file=policy.json

# List alert policies
gcloud monitoring policies list

# Delete alert policy
gcloud monitoring policies delete POLICY_NAME

# Create log-based metric (for alerting on log events)
gcloud logging metrics create NAME --log-filter='FILTER'
```

---

## Part 4 — Quiz (15 min)

**Question 1: Your team gets 150 alerts per day. Most are CPU > 50% spikes that resolve in 2 minutes. How do you fix this?**

<details>
<summary>Show Answer</summary>

Three changes:

1. **Raise the threshold**: 50% CPU is normal for most workloads → raise to **85-90%**
2. **Increase duration**: Require the condition for **10 minutes**, not instant
3. **Check if alerting on the right thing**: CPU spikes may be normal during batch jobs

Updated policy:
```json
{
  "comparison": "COMPARISON_GT",
  "thresholdValue": 0.9,
  "duration": "600s"
}
```

Result: From 150 alerts/day to maybe 2-3 alerts/day — each one genuinely indicates a problem.

Linux analogy: Changing `fail2ban` from `maxretry=1` (alert on every failed login) to `maxretry=5` (alert on brute force pattern).

</details>

**Question 2: You create an alert for disk usage > 90%. It fires at 3 AM on Saturday. The on-call engineer can't do anything until Monday. What's wrong with this setup?**

<details>
<summary>Show Answer</summary>

The alert is at the **wrong priority level** and **wrong threshold**:

| Fix | Change |
|-----|--------|
| **Threshold** | Create TWO alerts: P3 at 80% (email, business hours) AND P1 at 95% (page, 24/7) |
| **Timing** | P3 (80%) gives days of lead time → fix during work hours |
| **Actionability** | P1 (95%) is truly urgent → pages are justified |

Better design:
- **80% disk**: P3 → email to team → address within 1 business day
- **90% disk**: P2 → Slack notification → address same day
- **95% disk**: P1 → PagerDuty → wake someone up, disk is about to fill

The graduated approach gives **early warning** at reasonable hours and only pages for true emergencies.

</details>

**Question 3: What should every alert policy include besides the metric condition?**

<details>
<summary>Show Answer</summary>

Every alert must include:

1. **Documentation/Runbook**: Step-by-step response instructions
   ```json
   "documentation": {
     "content": "## Steps\n1. SSH to VM\n2. Run top\n3. ...",
     "mimeType": "text/markdown"
   }
   ```

2. **Auto-close duration**: Clear the alert when condition resolves
   ```json
   "alertStrategy": { "autoClose": "1800s" }
   ```

3. **Notification channel**: Who gets notified and how
   ```json
   "notificationChannels": ["projects/P/notificationChannels/ID"]
   ```

4. **Severity/Priority label**: P1/P2/P3/P4 in the display name

5. **Duration window**: Prevent flapping

Without these, the alert is just noise: nobody knows who should respond, what to do, or whether it auto-resolved.

</details>

**Question 4: You want to alert when a VM is deleted. What's the setup?**

<details>
<summary>Show Answer</summary>

Two-step setup using **log-based metric + alert policy**:

**Step 1 — Log-based metric:**
```bash
gcloud logging metrics create vm-deletion \
    --log-filter='resource.type="gce_instance"
        logName=~"cloudaudit.googleapis.com%2Factivity"
        protoPayload.methodName="v1.compute.instances.delete"'
```

**Step 2 — Alert policy on the metric:**
```bash
# Alert when count > 0 (any deletion)
# duration = 0s (immediate, since deletions are discrete events)
# Include runbook: who deleted? was it planned? restore from snapshot?
```

You can't alert directly on logs — you must convert the log event into a metric first. The metric counts occurrences of the matching log entries, and the alert fires when that count exceeds your threshold.

Alternative: Use Cloud Functions triggered by Pub/Sub log sink for more complex logic (e.g., only alert on production VMs).

</details>

---

*Next: [Day 69 — Simulate Failure](DAY_69_SIMULATE_FAILURE.md)*
