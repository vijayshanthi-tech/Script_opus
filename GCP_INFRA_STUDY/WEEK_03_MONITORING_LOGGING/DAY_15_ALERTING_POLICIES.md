# Day 15 — Alerting Policies: Conditions, Channels & Alert Fatigue

> **Week 3 · Monitoring & Logging** | Region: `europe-west2` | Study time: 2 hours

---

## Part 1 — Concept (30 min)

### 1.1 What Are Alerting Policies?

Alerting policies are rules that fire **when a metric crosses a threshold** — like configuring Nagios check thresholds or `cron` scripts that page you when disk is full. GCP Monitoring evaluates policies continuously.

| Linux Analogy | GCP Equivalent |
|---|---|
| Nagios check threshold | Alert condition |
| `/etc/nagios/contacts.cfg` | Notification channel |
| Nagios CRITICAL/WARNING | Alerting severity levels |
| PagerDuty integration | Notification channel (PagerDuty, email, Slack) |
| Alert flapping suppression | Auto-close duration / alert fatigue controls |

### 1.2 Alerting Architecture

```
┌────────────────────────────────────────────────────────┐
│                  ALERTING POLICY                        │
│                                                        │
│  ┌──────────────────────────────────────────────┐      │
│  │  CONDITION(S)                                │      │
│  │  "CPU utilization > 0.80 for 5 minutes"      │      │
│  │                                              │      │
│  │  Metric: compute.googleapis.com/instance/     │      │
│  │          cpu/utilization                      │      │
│  │  Threshold: > 0.80                           │      │
│  │  Duration: 300s                              │      │
│  │  Aggregation: mean, per instance             │      │
│  └──────────────┬───────────────────────────────┘      │
│                 │                                       │
│                 │ condition met                         │
│                 ▼                                       │
│  ┌──────────────────────────────────────────────┐      │
│  │  INCIDENT CREATED                            │      │
│  │  (auto-opens, tracks state)                  │      │
│  └──────────────┬───────────────────────────────┘      │
│                 │                                       │
│                 ▼                                       │
│  ┌──────────────────────────────────────────────┐      │
│  │  NOTIFICATION CHANNELS                       │      │
│  │  ┌─────────┐  ┌─────────┐  ┌──────────┐     │      │
│  │  │  Email  │  │  Slack  │  │ PagerDuty│     │      │
│  │  └─────────┘  └─────────┘  └──────────┘     │      │
│  └──────────────────────────────────────────────┘      │
│                                                        │
│  Auto-close: when condition is no longer met           │
└────────────────────────────────────────────────────────┘
```

### 1.3 Alert Condition Types

| Condition Type | Use Case | Example |
|---|---|---|
| **Metric threshold** | Value crosses a boundary | CPU > 80% for 5 min |
| **Metric absence** | No data received | Heartbeat metric missing for 10 min |
| **Log-based metric** | Alert on log patterns | ERROR count > 50 in 5 min |
| **Uptime check** | Endpoint unreachable | HTTP check fails from ≥ 2 regions |
| **Process health** | Process not running | `nginx` process count = 0 |

### 1.4 Notification Channels

| Channel Type | Description | When to Use |
|---|---|---|
| Email | Simple email notification | Low-urgency, async alerts |
| SMS | Text message | Medium-urgency |
| Slack | Chat integration | Team awareness |
| PagerDuty | Incident management | On-call rotation |
| Webhook | Custom HTTP POST | Integration with custom systems |
| Pub/Sub | Message queue | Automated response pipelines |
| Mobile app | Cloud Console mobile | On-the-go monitoring |

### 1.5 Alert Fatigue & Best Practices

Alert fatigue = too many alerts, team ignores them all. Like the boy who cried wolf.

```
  BAD: Alert on everything               GOOD: Alert on what matters
  ┌─────────────────────────┐            ┌────────────────────────────┐
  │ CPU > 50% → PAGE        │            │ CPU > 80% for 5m → EMAIL  │
  │ CPU > 60% → PAGE        │            │ CPU > 95% for 5m → PAGE   │
  │ CPU > 70% → PAGE        │            │ Disk > 85% → EMAIL        │
  │ CPU > 80% → PAGE        │            │ Disk > 95% → PAGE         │
  │ Disk > 50% → PAGE       │            │ Service down → PAGE       │
  │ Memory > 60% → PAGE     │            │ Error rate > 5% → EMAIL   │
  │ Network > 1MB/s → PAGE  │            │                            │
  │ Result: 200 alerts/day  │            │ Result: 2-3 alerts/day    │
  │ Team ignores ALL alerts │            │ Team trusts alerts         │
  └─────────────────────────┘            └────────────────────────────┘
```

**Best Practices:**

| Practice | Description |
|---|---|
| Set meaningful thresholds | Alert at 80% not 50%; use duration windows |
| Use severity tiers | EMAIL for warning, PAGE for critical |
| Duration window | Require the condition for N minutes (avoid spikes) |
| Auto-close | Let incidents close automatically when resolved |
| Documentation | Include runbook links in alert description |
| Test alerts | Verify they fire and reach the right people |

### 1.6 Incident Lifecycle

```
  CONDITION MET ──> INCIDENT OPENED ──> NOTIFICATION SENT
                          │
                          ▼
                    ACKNOWLEDGED (optional)
                          │
                          ▼
  CONDITION CLEARS ──> INCIDENT AUTO-CLOSED
```

| State | Meaning |
|---|---|
| Open | Condition is active, notifications sent |
| Acknowledged | Someone is investigating |
| Closed | Condition no longer met (auto or manual) |

---

## Part 2 — Hands-On Lab (60 min)

### Lab Goal

Create a notification channel (email), build a CPU alert policy (>80%), and trigger it with a stress test.

### Prerequisites

```bash
gcloud config set project YOUR_PROJECT_ID
gcloud config set compute/region europe-west2
gcloud config set compute/zone europe-west2-b
```

### Step 1 — Create a Test VM

```bash
gcloud compute instances create alert-test-vm \
    --zone=europe-west2-b \
    --machine-type=e2-small \
    --image-family=debian-12 \
    --image-project=debian-cloud \
    --metadata=startup-script='#!/bin/bash
apt-get update && apt-get install -y stress-ng'
```

### Step 2 — Create an Email Notification Channel

```bash
# Create a notification channel JSON definition
cat > /tmp/email-channel.json << 'EOF'
{
  "type": "email",
  "displayName": "Day15-Lab-Email",
  "labels": {
    "email_address": "YOUR_EMAIL@example.com"
  }
}
EOF

# Create the channel
gcloud monitoring channels create --channel-content-from-file=/tmp/email-channel.json

# List channels to get the channel ID
gcloud monitoring channels list \
    --format="table(name,displayName,type)"

# Store the channel name for later use
CHANNEL_ID=$(gcloud monitoring channels list \
    --filter="displayName='Day15-Lab-Email'" \
    --format="value(name)")

echo "Channel ID: $CHANNEL_ID"
```

### Step 3 — Create a CPU Alert Policy

```bash
# Get the VM instance ID
INSTANCE_ID=$(gcloud compute instances describe alert-test-vm \
    --zone=europe-west2-b --format="value(id)")

# Create alert policy JSON
cat > /tmp/cpu-alert-policy.json << EOF
{
  "displayName": "Day15-CPU-Alert-80pct",
  "documentation": {
    "content": "CPU utilization exceeded 80% on alert-test-vm. Check for runaway processes with 'top' or 'ps aux --sort=-%cpu'. This is a lab alert for Day 15.",
    "mimeType": "text/markdown"
  },
  "conditions": [
    {
      "displayName": "CPU > 80% for 2 minutes",
      "conditionThreshold": {
        "filter": "metric.type=\"compute.googleapis.com/instance/cpu/utilization\" AND resource.type=\"gce_instance\" AND resource.labels.instance_id=\"$INSTANCE_ID\"",
        "comparison": "COMPARISON_GT",
        "thresholdValue": 0.80,
        "duration": "120s",
        "aggregations": [
          {
            "alignmentPeriod": "60s",
            "perSeriesAligner": "ALIGN_MEAN"
          }
        ],
        "trigger": {
          "count": 1
        }
      }
    }
  ],
  "combiner": "OR",
  "notificationChannels": [
    "$CHANNEL_ID"
  ],
  "alertStrategy": {
    "autoClose": "1800s"
  }
}
EOF

# Create the policy
gcloud monitoring policies create --policy-from-file=/tmp/cpu-alert-policy.json

# List policies
gcloud monitoring policies list \
    --format="table(displayName,enabled,conditions.displayName)"
```

### Step 4 — Understanding the Policy

| Policy Field | Value | Meaning |
|---|---|---|
| `thresholdValue` | 0.80 | 80% CPU utilization |
| `duration` | 120s | Must exceed threshold for 2 min |
| `alignmentPeriod` | 60s | Average over 1-minute windows |
| `perSeriesAligner` | ALIGN_MEAN | Use mean of data points |
| `autoClose` | 1800s | Close incident 30 min after condition clears |
| `combiner` | OR | Any condition triggers alert |

### Step 5 — Trigger the Alert with Stress Test

```bash
# Run CPU stress to push above 80%
# e2-small has 2 vCPUs, stress all of them
gcloud compute ssh alert-test-vm --zone=europe-west2-b \
    --command="nohup stress-ng --cpu 2 --cpu-load 95 --timeout 600 > /dev/null 2>&1 &"

echo "Stress test running for 10 minutes at 95% CPU"
echo "Alert should fire within 3-5 minutes (2 min duration + metric delay)"
echo "Check your email and Console → Monitoring → Alerting"
```

### Step 6 — Monitor the Alert

```bash
# Check current CPU utilization
gcloud monitoring time-series list \
    --filter="metric.type=\"compute.googleapis.com/instance/cpu/utilization\" AND resource.labels.instance_id=\"$INSTANCE_ID\"" \
    --interval-start-time=$(date -u -d '10 minutes ago' '+%Y-%m-%dT%H:%M:%SZ') \
    --format="table(points.interval.endTime,points.value.doubleValue)"

# List current incidents
gcloud monitoring policies conditions list \
    $(gcloud monitoring policies list --filter="displayName='Day15-CPU-Alert-80pct'" --format="value(name)") \
    --format="table(displayName,name)"

echo ""
echo "Check Console → Monitoring → Alerting → Incidents"
echo "You should see an open incident for Day15-CPU-Alert-80pct"
```

### Step 7 — Stop Stress and Watch Auto-Close

```bash
# Kill the stress test
gcloud compute ssh alert-test-vm --zone=europe-west2-b \
    --command="sudo pkill stress-ng"

echo "Stress test stopped. CPU should drop below 80%"
echo "Incident will auto-close after 30 minutes (autoClose=1800s)"
echo "Or manually acknowledge/close in Console → Monitoring → Alerting"
```

### Step 8 — Create a Metric Absence Alert (Bonus)

```bash
# This alerts when a VM stops sending metrics (possible crash/shutdown)
cat > /tmp/absence-alert.json << EOF
{
  "displayName": "Day15-Metric-Absence-Alert",
  "documentation": {
    "content": "No CPU metrics received from alert-test-vm for 5 minutes. VM may be down.",
    "mimeType": "text/markdown"
  },
  "conditions": [
    {
      "displayName": "CPU metrics absent for 5 min",
      "conditionAbsent": {
        "filter": "metric.type=\"compute.googleapis.com/instance/cpu/utilization\" AND resource.type=\"gce_instance\" AND resource.labels.instance_id=\"$INSTANCE_ID\"",
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
  "notificationChannels": [
    "$CHANNEL_ID"
  ]
}
EOF

gcloud monitoring policies create --policy-from-file=/tmp/absence-alert.json

echo "Absence alert created. If the VM is stopped, alert fires after 5 min."
```

### Cleanup

```bash
# Delete alert policies
for POLICY in $(gcloud monitoring policies list \
    --filter="displayName:'Day15'" \
    --format="value(name)"); do
    gcloud monitoring policies delete "$POLICY" --quiet
done

# Delete notification channel
gcloud monitoring channels delete "$CHANNEL_ID" --quiet --force

# Delete VM
gcloud compute instances delete alert-test-vm --zone=europe-west2-b --quiet

# Clean up temp files
rm -f /tmp/email-channel.json /tmp/cpu-alert-policy.json /tmp/absence-alert.json
```

---

## Part 3 — Revision (15 min)

### Key Concepts

- Alerting policy = condition(s) + notification channel(s) + documentation
- **Condition types**: metric threshold, metric absence, log-based, uptime check
- **Duration window** = how long the condition must hold before firing (avoids spike alerts)
- **Notification channels**: email, SMS, Slack, PagerDuty, webhook, Pub/Sub
- **Alert fatigue**: too many low-value alerts → team ignores all alerts
- Best practice: meaningful thresholds + duration windows + severity tiers + runbook links
- **Auto-close**: automatically close incidents when condition clears (configurable)
- Incidents track lifecycle: Open → Acknowledged → Closed
- **Metric absence** alerts catch silent failures (VM crash, agent dead)

### Essential Commands

```bash
# Notification channels
gcloud monitoring channels create --channel-content-from-file=FILE.json
gcloud monitoring channels list
gcloud monitoring channels delete CHANNEL_ID --force

# Alert policies
gcloud monitoring policies create --policy-from-file=FILE.json
gcloud monitoring policies list
gcloud monitoring policies delete POLICY_NAME

# Check incidents
# Console → Monitoring → Alerting → Incidents
```

---

## Part 4 — Quiz (15 min)

**Question 1: Your CPU alert fires every few minutes but auto-closes immediately after. Your team is getting flooded with notifications. How do you fix this?**

<details>
<summary>Show Answer</summary>

This is **alert flapping** — the metric oscillates around the threshold. Fixes:

1. **Increase the duration window**: Change from 60s to 300s so the condition must hold for 5 minutes before firing
2. **Raise the threshold**: If 80% is too sensitive, try 85% or 90%
3. **Increase alignment period**: Use 5-minute average instead of 1-minute to smooth out spikes
4. **Increase auto-close duration**: Prevent rapid re-firing by keeping the incident open longer

In Linux terms: this is like a Nagios check flapping between OK and CRITICAL — you'd increase `max_check_attempts` or add hysteresis.

</details>

---

**Question 2: You created an alert policy but notifications never arrive at your email. The condition is firing (incident is visible in Console). What should you check?**

<details>
<summary>Show Answer</summary>

Troubleshooting checklist:
1. **Notification channel verified** — emails require clicking a verification link. Unverified channels are silently skipped.
2. **Channel linked to policy** — the policy must reference the channel's full resource name in `notificationChannels[]`.
3. **Spam folder** — GCP notification emails may be caught by spam filters.
4. **Channel type correct** — verify `gcloud monitoring channels list` shows the correct email address.
5. **IAM permissions** — the project must have Monitoring enabled and the channel must be in the same project as the policy.

</details>

---

**Question 3: What is the difference between a metric threshold condition and a metric absence condition?**

<details>
<summary>Show Answer</summary>

- **Metric threshold**: Fires when a metric **exists and exceeds** a value (e.g., CPU > 80%). The metric must be present.
- **Metric absence**: Fires when a metric **stops being reported** for a duration (e.g., no CPU data for 5 min). This catches silent failures.

Use threshold for "something is wrong." Use absence for "something has died." Absence alerts are critical for VMs that crash or agents that stop reporting — Nagios equivalent of "host unreachable."

</details>

---

**Question 4: You want a single alert policy that fires when EITHER CPU > 80% OR memory > 90%. How do you configure the policy combiner?**

<details>
<summary>Show Answer</summary>

Set the **combiner** to `"OR"` (which is the default). The policy has two conditions:
- Condition 1: CPU > 80% for 5 min
- Condition 2: Memory > 90% for 5 min

With `OR`, the alert fires if **either** condition is met. With `AND`, **both** must be true simultaneously.

```json
{
  "combiner": "OR",
  "conditions": [
    { "conditionThreshold": { ... CPU ... } },
    { "conditionThreshold": { ... Memory ... } }
  ]
}
```

Note: For memory metrics, you need the **Ops Agent** installed (auto-collected GCE metrics don't include memory).

</details>

---

*End of Day 15 — Tomorrow: Ops Agent for deep VM monitoring.*
