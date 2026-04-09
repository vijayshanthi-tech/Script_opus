# Day 87 — Alert on Suspicious Actions: Log-Based Alerts

> **Week 15 — Audit & Compliance** | ⏱ 2 hours | Region: `europe-west2`
> Student profile: 6 yrs Linux infra, 3 yrs RHDS LDAP, ACE certified

---

## Part 1 — Concept (30 min)

### 1.1 What to Alert On

```
  SECURITY-CRITICAL EVENTS TO MONITOR
  ════════════════════════════════════

  ┌──────────────────────────────────────────────────────────┐
  │  PRIORITY 1 — ALERT IMMEDIATELY                          │
  ├──────────────────────────────────────────────────────────┤
  │  • SA key creation    (credential leak risk)             │
  │  • Owner role granted (full project control)             │
  │  • Firewall allow-all created (network exposure)         │
  │  • SA granted Editor/Owner (over-privilege)              │
  │  • Org policy disabled (security guardrail removed)      │
  ├──────────────────────────────────────────────────────────┤
  │  PRIORITY 2 — ALERT WITHIN HOURS                         │
  ├──────────────────────────────────────────────────────────┤
  │  • IAM changes outside business hours                    │
  │  • New external IP assigned                              │
  │  • Bulk resource deletion                                │
  │  • Unusual API calls from SA                             │
  ├──────────────────────────────────────────────────────────┤
  │  PRIORITY 3 — DAILY REVIEW                               │
  ├──────────────────────────────────────────────────────────┤
  │  • Any IAM changes (normal operations review)            │
  │  • Permission denied spikes                              │
  │  • New service accounts created                          │
  │  • API enabled/disabled                                  │
  └──────────────────────────────────────────────────────────┘
```

**Linux analogy:**
| GCP Alert | Linux Equivalent |
|-----------|------------------|
| SA key created | SSH key added to `authorized_keys` |
| Owner role granted | User added to `sudoers` / `wheel` |
| Firewall allow-all | `iptables -F` (flush all rules) |
| Bulk resource deletion | `rm -rf /` attempt |
| Permission denied spike | Failed `sudo` attempts in `/var/log/secure` |

### 1.2 Log-Based Alert Architecture

```
  ┌──────────────┐    ┌───────────────┐    ┌─────────────────┐
  │ Cloud Logging │───▶│ Log-based     │───▶│ Alerting Policy │
  │ (audit logs)  │    │ Metric        │    │ (threshold/     │
  └──────────────┘    │ (filter →     │    │  absence)       │
                      │  counter)     │    └────────┬────────┘
                      └───────────────┘             │
                                              ┌─────▼──────┐
                                              │ Notification│
                                              │ Channel     │
                                              ├─────────────┤
                                              │ • Email     │
                                              │ • Slack     │
                                              │ • PagerDuty │
                                              │ • Webhook   │
                                              │ • Pub/Sub   │
                                              └─────────────┘

  ALTERNATIVE: Log-based alert (direct, no metric)
  ┌──────────────┐    ┌──────────────────┐    ┌──────────────┐
  │ Cloud Logging │───▶│ Log-based Alert │───▶│ Notification │
  │              │    │ (filter match   │    │ Channel      │
  │              │    │  → alert)       │    │              │
  └──────────────┘    └──────────────────┘    └──────────────┘
```

### 1.3 Alert Filters for Critical Events

```
  SA KEY CREATION ALERT
  ═════════════════════
  protoPayload.methodName="google.iam.admin.v1.CreateServiceAccountKey"

  OWNER ROLE GRANTED
  ══════════════════
  protoPayload.methodName="SetIamPolicy"
  protoPayload.serviceData.policyDelta.bindingDeltas.role="roles/owner"
  protoPayload.serviceData.policyDelta.bindingDeltas.action="ADD"

  FIREWALL RULE CHANGES
  ═════════════════════
  resource.type="gce_firewall_rule"
  protoPayload.methodName=("v1.compute.firewalls.insert" OR
                           "v1.compute.firewalls.update" OR
                           "v1.compute.firewalls.delete")

  PRIVILEGE ESCALATION PATTERNS
  ═════════════════════════════
  protoPayload.methodName="SetIamPolicy"
  protoPayload.serviceData.policyDelta.bindingDeltas.role:(
    "roles/owner" OR "roles/editor" OR "roles/iam.securityAdmin")
```

### 1.4 Escalation Patterns to Watch

```
  PRIVILEGE ESCALATION INDICATORS
  ════════════════════════════════

  ┌─────────────────────────────────────────────────┐
  │  PATTERN 1: Self-escalation                     │
  │  User grants themselves a higher role            │
  │  Alert: WHO = target member in SetIamPolicy      │
  ├─────────────────────────────────────────────────┤
  │  PATTERN 2: SA key + broad role                 │
  │  SA gets Editor role, then key is created        │
  │  Alert: key creation for any SA with Editor      │
  ├─────────────────────────────────────────────────┤
  │  PATTERN 3: New SA + immediate broad role        │
  │  SA created and given Owner within 5 minutes     │
  │  Alert: correlate CreateSA + SetIamPolicy        │
  ├─────────────────────────────────────────────────┤
  │  PATTERN 4: Firewall rule allowing all traffic   │
  │  0.0.0.0/0 with all ports                       │
  │  Alert: firewall insert with sourceRanges=ALL    │
  └─────────────────────────────────────────────────┘
```

> **RHDS parallel:** In RHDS, you'd monitor `access-log` for: `aci` modifications (≈ IAM changes), bind attempts with `cn=Directory Manager` (≈ Owner role usage), `nsDS5ReplicaCredentials` changes (≈ SA key rotation), ACI granting `(targetattr="*")(allow all)` (≈ over-privilege). You'd use `logwatch` or custom scripts piped to alerting.

---

## Part 2 — Hands-On Lab (60 min)

### Prerequisites
```bash
export PROJECT_ID=$(gcloud config get-value project)
export REGION=europe-west2
export ZONE=europe-west2-a
```

### Lab 2.1 — Create Log-Based Metric for SA Key Creation

```bash
# Create a log-based metric that counts SA key creation events
gcloud logging metrics create sa-key-creation-count \
  --description="Counts SA key creation events" \
  --log-filter='protoPayload.methodName="google.iam.admin.v1.CreateServiceAccountKey"' \
  --project=$PROJECT_ID

# Verify metric
echo "--- Log-based metrics ---"
gcloud logging metrics list --project=$PROJECT_ID \
  --format="table(name, filter)"
```

### Lab 2.2 — Create Log-Based Metric for IAM Changes

```bash
# Create metric for IAM policy changes
gcloud logging metrics create iam-policy-changes-count \
  --description="Counts IAM policy changes" \
  --log-filter='protoPayload.methodName="SetIamPolicy"' \
  --project=$PROJECT_ID

# Create metric for firewall changes
gcloud logging metrics create firewall-changes-count \
  --description="Counts firewall rule changes" \
  --log-filter='resource.type="gce_firewall_rule" protoPayload.methodName=~"firewalls"' \
  --project=$PROJECT_ID

# List all custom metrics
echo "--- All custom log-based metrics ---"
gcloud logging metrics list --project=$PROJECT_ID \
  --format="table(name, description, filter)"
```

### Lab 2.3 — Create a Notification Channel

```bash
# Create an email notification channel
gcloud beta monitoring channels create \
  --type=email \
  --display-name="Security Alerts Email" \
  --channel-labels=email_address="$(gcloud config get-value account)" \
  --project=$PROJECT_ID 2>/dev/null

# List notification channels
echo "--- Notification channels ---"
gcloud beta monitoring channels list --project=$PROJECT_ID \
  --format="table(name.basename(), displayName, type)" 2>/dev/null || \
  echo "Note: Monitoring channels can also be created via Console"

# Get the channel ID for alerting
CHANNEL_ID=$(gcloud beta monitoring channels list --project=$PROJECT_ID \
  --format="value(name)" --limit=1 2>/dev/null)
echo "Channel: $CHANNEL_ID"
```

### Lab 2.4 — Create Alerting Policies

```bash
# Create alert for SA key creation (using gcloud or REST API)
# Note: Complex alert policies are easier to create via Console

echo "=== ALERT POLICY DEFINITIONS ==="
echo ""
echo "Policy 1: SA Key Creation"
echo "  Metric: sa-key-creation-count"
echo "  Condition: count > 0 in 5 minutes"
echo "  Notification: Email"
echo ""
echo "Policy 2: High IAM Change Rate"
echo "  Metric: iam-policy-changes-count"
echo "  Condition: count > 10 in 1 hour"
echo "  Notification: Email"
echo ""
echo "Policy 3: Any Firewall Change"
echo "  Metric: firewall-changes-count"
echo "  Condition: count > 0 in 5 minutes"
echo "  Notification: Email"

# Create a simple alert using gcloud
cat > /tmp/alert-policy.json << EOF
{
  "displayName": "SA Key Creation Alert",
  "conditions": [
    {
      "displayName": "SA Key Created",
      "conditionThreshold": {
        "filter": "metric.type=\"logging.googleapis.com/user/sa-key-creation-count\" AND resource.type=\"global\"",
        "comparison": "COMPARISON_GT",
        "thresholdValue": 0,
        "duration": "0s",
        "aggregations": [
          {
            "alignmentPeriod": "300s",
            "perSeriesAligner": "ALIGN_COUNT"
          }
        ]
      }
    }
  ],
  "combiner": "OR",
  "enabled": true,
  "alertStrategy": {
    "autoClose": "604800s"
  }
}
EOF

gcloud alpha monitoring policies create \
  --policy-from-file=/tmp/alert-policy.json \
  --project=$PROJECT_ID 2>/dev/null || echo "Alert policy creation via JSON. Can also use Console."

# List alert policies
echo ""
echo "--- Alert policies ---"
gcloud alpha monitoring policies list --project=$PROJECT_ID \
  --format="table(displayName, enabled, conditions[0].displayName)" 2>/dev/null || \
  echo "Use Console: Monitoring → Alerting → Create Policy"
```

### Lab 2.5 — Test: Trigger a Key Creation Alert

```bash
# Create a test SA and key to trigger the alert
gcloud iam service-accounts create alert-test-sa \
  --display-name="Alert Test SA"

export ALERT_SA=alert-test-sa@${PROJECT_ID}.iam.gserviceaccount.com

# Create a key (this should trigger the alert)
echo "--- Creating SA key (should trigger alert) ---"
gcloud iam service-accounts keys create /tmp/alert-test-key.json \
  --iam-account=$ALERT_SA

echo "Key created. Alert should fire within 5 minutes."
echo ""

# Verify the event in logs
sleep 30
echo "--- Checking audit logs for key creation ---"
gcloud logging read '
  protoPayload.methodName="google.iam.admin.v1.CreateServiceAccountKey"
' --limit=3 --format="table(
  timestamp,
  protoPayload.authenticationInfo.principalEmail:label=WHO,
  protoPayload.request.name:label=SA
)" --project=$PROJECT_ID

# Check metric data
echo ""
echo "--- SA key creation metric value ---"
gcloud logging metrics describe sa-key-creation-count \
  --project=$PROJECT_ID --format=yaml
```

### 🧹 Cleanup

```bash
# Delete test key and SA
rm -f /tmp/alert-test-key.json
gcloud iam service-accounts delete $ALERT_SA --quiet 2>/dev/null

# Delete alert policies
for POLICY in $(gcloud alpha monitoring policies list --project=$PROJECT_ID \
  --format="value(name)" 2>/dev/null); do
  gcloud alpha monitoring policies delete $POLICY --quiet 2>/dev/null
done

# Delete notification channels
for CHANNEL in $(gcloud beta monitoring channels list --project=$PROJECT_ID \
  --format="value(name)" 2>/dev/null); do
  gcloud beta monitoring channels delete $CHANNEL --quiet --force 2>/dev/null
done

# Delete log-based metrics
gcloud logging metrics delete sa-key-creation-count --project=$PROJECT_ID --quiet 2>/dev/null
gcloud logging metrics delete iam-policy-changes-count --project=$PROJECT_ID --quiet 2>/dev/null
gcloud logging metrics delete firewall-changes-count --project=$PROJECT_ID --quiet 2>/dev/null

rm -f /tmp/alert-policy.json
```

---

## Part 3 — Revision (15 min)

### Key Concepts
- **Priority 1 alerts:** SA key creation, Owner role granted, firewall allow-all, security guardrail disabled
- **Log-based metrics** convert log entries into numeric metrics for alerting
- **Log-based alerts** fire directly when a log filter matches (no metric needed)
- Alert flow: Log → Filter match → Metric increment → Threshold breached → Notification
- **Notification channels:** email, Slack, PagerDuty, SMS, webhooks, Pub/Sub
- **Escalation patterns:** self-escalation, SA key + broad role, rapid SA creation + privileged binding
- Alerts should be **actionable** — every alert should have a defined response procedure
- Avoid alert fatigue — start with Priority 1, tune thresholds over time

### Essential Commands
```bash
# Create log-based metric
gcloud logging metrics create METRIC_NAME \
  --log-filter='FILTER' --description="DESC"

# List metrics
gcloud logging metrics list

# Create notification channel
gcloud beta monitoring channels create --type=email \
  --display-name="NAME" --channel-labels=email_address="EMAIL"

# List alert policies
gcloud alpha monitoring policies list

# Test by checking recent log entries
gcloud logging read 'ALERT_FILTER' --limit=5
```

---

## Part 4 — Quiz (15 min)

**Q1.** A SA key is created at 3 AM on a Sunday. Should this trigger an alert? What should the response be?

<details><summary>Answer</summary>

**Yes, always alert on SA key creation** regardless of time. Response: (1) Identify who created the key — check `principalEmail` in audit logs. (2) Verify if this was authorized — check change management tickets. (3) If unauthorized, immediately **disable the key** and investigate. (4) If authorized, document why a key was needed instead of alternatives. (5) Ensure the key is stored securely (Secret Manager, not git). 3 AM on a Sunday is particularly suspicious.

</details>

**Q2.** You're getting 50+ IAM change alerts per day. How do you reduce alert fatigue without missing real threats?

<details><summary>Answer</summary>

1. **Separate high/low priority:** Keep immediate alerts for Owner/Editor grants, SA key creation. Move routine IAM changes to a daily digest.
2. **Exclude service agents:** Filter out Google-managed SA IAM changes (automated by GCP).
3. **Threshold tuning:** Alert on "more than X changes in Y minutes" instead of every single change.
4. **Condition refinement:** Only alert on role additions (`action="ADD"`), not removals.
5. **Team filtering:** Only alert when changes are outside the IAM admin team.

</details>

**Q3.** What five log-based metrics would you create for a production GCP project?

<details><summary>Answer</summary>

1. **SA key creation** — `protoPayload.methodName="...CreateServiceAccountKey"` — any key creation is notable
2. **Privileged role grants** — SetIamPolicy where role is owner/editor/securityAdmin — over-privilege risk
3. **Firewall modifications** — `resource.type="gce_firewall_rule"` — network exposure risk
4. **Permission denied spikes** — `protoPayload.status.code=7` count > threshold — possible attack probing
5. **Resource deletion** — `protoPayload.methodName=~"delete"` on critical resource types — data loss risk

</details>

**Q4.** Compare GCP log-based alerting to setting up alerts on RHDS access logs.

<details><summary>Answer</summary>

| GCP Log-Based Alerts | RHDS Log Alerting |
|---------------------|-------------------|
| Log-based metric + alerting policy | `logwatch` + custom scripts |
| Filter: `protoPayload.methodName` | `grep "MOD dn" access-log` |
| Notification channel (email/Slack) | `mail` command / nagios check |
| Managed service (auto-scales) | Self-hosted (you manage scripts) |
| GUI policy builder | Manual script writing |
| Alert on SA key creation | Alert on `nsDS5ReplicaCredentials` change |
| Alert on IAM change | Alert on ACI modify |
| Alert on firewall change | Alert on `iptables` rule change via auditd |

GCP provides the infrastructure; RHDS requires building it yourself. The detection logic and response procedures are the same.

</details>
