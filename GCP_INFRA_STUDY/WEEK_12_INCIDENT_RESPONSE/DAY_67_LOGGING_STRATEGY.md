# Day 67 — Logging Strategy

> **Week 12 · Incident Response**
> Estimated time: 2 hours | Region: `europe-west2` (London)
> Prerequisites: Week 11 completed

---

## Part 1 — Concept (30 min)

### Why Logging Strategy Matters

```
Without Strategy:                    With Strategy:
┌─────────────────────┐             ┌─────────────────────┐
│ Incident happens    │             │ Incident happens    │
│         │           │             │         │           │
│         ▼           │             │         ▼           │
│ "Where are the      │             │ Structured logs     │
│  logs?"             │             │ readily available   │
│         │           │             │         │           │
│         ▼           │             │         ▼           │
│ Logs scattered,     │             │ Log-based metrics   │
│ inconsistent format │             │ trigger alert       │
│         │           │             │         │           │
│         ▼           │             │         ▼           │
│ Hours to find root  │             │ 15 min to RCA      │
│ cause               │             │                     │
└─────────────────────┘             └─────────────────────┘
```

### GCP Logging Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                   GCP LOGGING ARCHITECTURE                        │
│                                                                   │
│  Log Sources:                                                    │
│  ┌────────────┐  ┌───────────┐  ┌──────────────┐               │
│  │ Audit Logs │  │ Platform  │  │ Application  │               │
│  │ (auto)     │  │ Logs      │  │ Logs         │               │
│  │            │  │ (auto)    │  │ (Ops Agent)  │               │
│  │ • Admin    │  │ • VPC Flow│  │ • syslog     │               │
│  │   Activity │  │ • GCE ops │  │ • app logs   │               │
│  │ • Data     │  │ • LB logs │  │ • custom     │               │
│  │   Access   │  │ • NAT     │  │              │               │
│  │ • System   │  │ • DNS     │  │              │               │
│  │   Event    │  │           │  │              │               │
│  └─────┬──────┘  └─────┬─────┘  └──────┬───────┘               │
│        │               │               │                         │
│        └───────────┬───┴───────────────┘                         │
│                    │                                              │
│                    ▼                                              │
│  ┌─────────────────────────────────────────┐                    │
│  │          Cloud Logging                   │                    │
│  │                                          │                    │
│  │  ┌──────────┐  ┌──────────┐  ┌───────┐ │                    │
│  │  │ Log      │  │ Log-based│  │ Log   │ │                    │
│  │  │ Router   │  │ Metrics  │  │ Sinks │ │                    │
│  │  │ (filter  │  │ (count   │  │ (to   │ │                    │
│  │  │  + route)│  │  events) │  │ GCS,  │ │                    │
│  │  └──────────┘  └─────┬────┘  │ BQ)   │ │                    │
│  │                      │       └───────┘ │                    │
│  └──────────────────────┼─────────────────┘                    │
│                         │                                        │
│                         ▼                                        │
│  ┌─────────────────────────────────────────┐                    │
│  │        Cloud Monitoring                  │                    │
│  │  → Alert Policy → Notification Channel  │                    │
│  └─────────────────────────────────────────┘                    │
└──────────────────────────────────────────────────────────────────┘
```

### Log Types Comparison

| Log Type | Auto-enabled | Content | Retention | Linux Analogy |
|----------|-------------|---------|-----------|---------------|
| **Admin Activity** | Yes (free, can't disable) | Who did what (API calls) | 400 days | `auth.log` |
| **Data Access** | No (must enable, costs) | Who read/listed what | 30 days default | `audit.log` (auditd) |
| **System Event** | Yes (free) | GCP system actions | 400 days | systemd journal |
| **VPC Flow** | No (must enable, costs) | Network flow records | 30 days default | `tcpdump` summary |
| **Platform Logs** | Varies | Service-specific ops | 30 days default | `/var/log/syslog` |
| **Application Logs** | No (Ops Agent needed) | Your app output | 30 days default | `journalctl -u myapp` |

### What to Log — Decision Framework

```
┌─────────────────────────────────────────────────────────┐
│              WHAT TO LOG                                  │
│                                                          │
│  ALWAYS LOG (Non-negotiable):                           │
│  ├── Authentication events (login, logout, failure)     │
│  ├── Authorization changes (IAM bindings)               │
│  ├── Resource creation/deletion                         │
│  ├── Network changes (FW rules, routes)                 │
│  └── Security-relevant errors                           │
│                                                          │
│  LOG IN PRODUCTION:                                      │
│  ├── Data access (who read sensitive data)              │
│  ├── VPC flow logs (network forensics)                  │
│  ├── Application errors and warnings                    │
│  └── Load balancer access logs                          │
│                                                          │
│  LOG SELECTIVELY:                                        │
│  ├── Debug/trace logs (dev only, costs $$$)             │
│  ├── Health check passes (noisy, sample)                │
│  └── Routine cron output (log failures only)            │
│                                                          │
│  NEVER LOG:                                              │
│  ├── Passwords, tokens, API keys                        │
│  ├── PII without masking                                │
│  ├── Credit card numbers                                │
│  └── Raw request bodies with sensitive data             │
└─────────────────────────────────────────────────────────┘
```

### Structured Logging

```
UNSTRUCTURED (bad):
"Error processing order 12345 for user john@example.com"

STRUCTURED (good):
{
  "severity": "ERROR",
  "message": "Order processing failed",
  "orderId": "12345",
  "userId": "u-abc-123",     ← NOT email (PII)
  "errorCode": "PAYMENT_DECLINED",
  "timestamp": "2024-01-15T14:30:00Z",
  "traceId": "abc-xyz-123"
}
```

| Aspect | Unstructured | Structured |
|--------|-------------|-----------|
| Search | Regex / grep | Field-based queries |
| Metrics | Hard to extract | Easy aggregation |
| Alerting | Fragile patterns | Reliable field match |
| Dashboards | Manual parsing | Automatic |
| Linux analogy | `echo "error"` | `logger -p local0.err --rfc5424` |

---

## Part 2 — Hands-On Lab (60 min)

### Lab Objective

Configure a complete logging strategy: enable Data Access logs, create log-based metrics, set up a log sink, and query logs effectively.

### Step 1 — Set Variables

```bash
export PROJECT_ID=$(gcloud config get-value project)
export REGION=europe-west2
export ZONE=europe-west2-a
```

### Step 2 — Enable Data Access Audit Logs

```bash
# Enable Data Access logs for Compute Engine
cat > /tmp/audit-policy.json << 'EOF'
{
  "auditConfigs": [
    {
      "service": "compute.googleapis.com",
      "auditLogConfigs": [
        { "logType": "ADMIN_READ" },
        { "logType": "DATA_READ" },
        { "logType": "DATA_WRITE" }
      ]
    },
    {
      "service": "storage.googleapis.com",
      "auditLogConfigs": [
        { "logType": "DATA_READ" },
        { "logType": "DATA_WRITE" }
      ]
    }
  ]
}
EOF

# Get current policy, merge, and set
gcloud projects get-iam-policy $PROJECT_ID --format=json > /tmp/current-policy.json

# View what audit configs exist
gcloud projects get-iam-policy $PROJECT_ID \
    --format="json(auditConfigs)"
```

### Step 3 — Generate Some Logs

```bash
# Create a test VM (generates Admin Activity logs)
gcloud compute instances create log-test-vm \
    --zone=$ZONE \
    --machine-type=e2-micro \
    --image-family=debian-12 \
    --image-project=debian-cloud

# Describe it (generates Data Access log if enabled)
gcloud compute instances describe log-test-vm --zone=$ZONE > /dev/null

# List instances (generates Data Access log)
gcloud compute instances list --filter="zone:$ZONE" > /dev/null
```

### Step 4 — Query Admin Activity Logs

```bash
# Who created VMs in the last hour?
gcloud logging read \
    'resource.type="gce_instance"
     logName="projects/'$PROJECT_ID'/logs/cloudaudit.googleapis.com%2Factivity"
     protoPayload.methodName="v1.compute.instances.insert"' \
    --limit=5 \
    --format="table(timestamp, protoPayload.authenticationInfo.principalEmail, protoPayload.resourceName)"

# Who deleted VMs?
gcloud logging read \
    'logName="projects/'$PROJECT_ID'/logs/cloudaudit.googleapis.com%2Factivity"
     protoPayload.methodName="v1.compute.instances.delete"' \
    --limit=5 \
    --format="table(timestamp, protoPayload.authenticationInfo.principalEmail)"

# IAM changes
gcloud logging read \
    'logName="projects/'$PROJECT_ID'/logs/cloudaudit.googleapis.com%2Factivity"
     protoPayload.methodName="SetIamPolicy"' \
    --limit=5 \
    --format="table(timestamp, protoPayload.authenticationInfo.principalEmail, resource.type)"
```

### Step 5 — Create Log-Based Metrics

```bash
# Metric: count VM deletions
gcloud logging metrics create vm-deletion-count \
    --description="Count of VM deletions" \
    --log-filter='resource.type="gce_instance"
        logName="projects/'$PROJECT_ID'/logs/cloudaudit.googleapis.com%2Factivity"
        protoPayload.methodName="v1.compute.instances.delete"'

# Metric: count IAM policy changes
gcloud logging metrics create iam-policy-changes \
    --description="Count of IAM policy modifications" \
    --log-filter='logName="projects/'$PROJECT_ID'/logs/cloudaudit.googleapis.com%2Factivity"
        protoPayload.methodName="SetIamPolicy"'

# Metric: count firewall rule changes
gcloud logging metrics create firewall-changes \
    --description="Count of firewall rule modifications" \
    --log-filter='resource.type="gce_firewall_rule"
        logName="projects/'$PROJECT_ID'/logs/cloudaudit.googleapis.com%2Factivity"'

# List your metrics
gcloud logging metrics list --format="table(name, description, filter)"
```

### Step 6 — Create Log Sink to Cloud Storage

```bash
# Create a GCS bucket for log archive
gsutil mb -l $REGION gs://${PROJECT_ID}-log-archive

# Create sink
gcloud logging sinks create audit-log-archive \
    gs://${PROJECT_ID}-log-archive \
    --log-filter='logName="projects/'$PROJECT_ID'/logs/cloudaudit.googleapis.com%2Factivity"'

# Get the sink's service account (needs bucket write access)
SINK_SA=$(gcloud logging sinks describe audit-log-archive --format="value(writerIdentity)")
echo "Sink SA: $SINK_SA"

# Grant the sink's SA write access to the bucket
gsutil iam ch ${SINK_SA}:objectCreator gs://${PROJECT_ID}-log-archive
```

### Step 7 — Advanced Log Queries

```bash
# All errors in the last hour
gcloud logging read 'severity=ERROR' \
    --limit=10 \
    --format="table(timestamp, resource.type, textPayload)"

# SSH login events
gcloud logging read \
    'resource.type="gce_instance" AND textPayload=~"sshd.*Accepted"' \
    --limit=5

# Failed authentication attempts
gcloud logging read \
    'protoPayload.status.code!=0 AND
     protoPayload.authenticationInfo.principalEmail!=""' \
    --limit=10 \
    --format="table(timestamp, protoPayload.authenticationInfo.principalEmail, protoPayload.status.message)"

# Log volume by type (useful for cost management)
gcloud logging read \
    'timestamp>="2024-01-01T00:00:00Z"' \
    --limit=100 \
    --format="value(logName)" | sort | uniq -c | sort -rn | head -20
```

### Step 8 — Compliance: Log Retention

```bash
# View default retention
gcloud logging buckets describe _Default --location=global \
    --format="yaml(retentionDays)"

# Extend retention to 90 days (for compliance)
gcloud logging buckets update _Default --location=global \
    --retention-days=90

# Verify
gcloud logging buckets list --format="table(name, retentionDays)"
```

### Cleanup

```bash
gcloud compute instances delete log-test-vm --zone=$ZONE --quiet
gcloud logging metrics delete vm-deletion-count --quiet
gcloud logging metrics delete iam-policy-changes --quiet
gcloud logging metrics delete firewall-changes --quiet
gcloud logging sinks delete audit-log-archive --quiet
gsutil rm -r gs://${PROJECT_ID}-log-archive 2>/dev/null
```

---

## Part 3 — Revision (15 min)

### Key Concepts

- **Admin Activity** logs are always on, free, 400-day retention — your safety net
- **Data Access** logs must be enabled per service — they cost money but are critical for security
- **Structured logging** enables field-based queries, metrics, and alerting
- **Log-based metrics** turn log events into numeric metrics for alerting
- **Log sinks** route logs to Cloud Storage (archive), BigQuery (analysis), or Pub/Sub (stream)
- Never log PII, passwords, or tokens — mask or use opaque IDs
- **Log Router** processes every log entry — use exclusion filters to reduce cost

### Essential Commands

```bash
# Read audit logs
gcloud logging read 'logName=~"cloudaudit" AND protoPayload.methodName="METHOD"' --limit=5

# Create log-based metric
gcloud logging metrics create NAME --log-filter='FILTER'

# Create log sink
gcloud logging sinks create NAME DESTINATION --log-filter='FILTER'

# Check retention
gcloud logging buckets describe _Default --location=global

# Update retention
gcloud logging buckets update _Default --location=global --retention-days=DAYS
```

---

## Part 4 — Quiz (15 min)

**Question 1: Your security team asks "Who changed IAM permissions on the production project last week?" Which log do you check?**

<details>
<summary>Show Answer</summary>

**Admin Activity audit logs.** These are:
- Always enabled (can't be disabled)
- Free (no additional cost)
- Retained for 400 days
- Contain all `SetIamPolicy` calls

Query:
```bash
gcloud logging read \
    'logName="projects/PROJECT/logs/cloudaudit.googleapis.com%2Factivity"
     protoPayload.methodName="SetIamPolicy"
     timestamp>="2024-01-08T00:00:00Z"' \
    --format="table(timestamp, protoPayload.authenticationInfo.principalEmail, protoPayload.request.policy.bindings)"
```

This shows exactly **who** (`principalEmail`) changed **what** (`policy.bindings`) and **when** (`timestamp`).

</details>

**Question 2: Your logging bill doubled last month. How do you diagnose and reduce it?**

<details>
<summary>Show Answer</summary>

1. **Find what's costing money** — check the Logs Router metrics:
   ```bash
   gcloud logging read "" --limit=1000 --format="value(logName)" | sort | uniq -c | sort -rn | head -10
   ```

2. **Common culprits:**
   - Data Access logs on high-traffic services (BigQuery, Storage)
   - VPC Flow logs at 100% sample rate (reduce to 50% or lower)
   - Debug-level application logs left on in production
   - Load balancer access logs at 100% sample rate

3. **Reduce costs:**
   - Create **exclusion filters** on the Log Router:
     ```bash
     gcloud logging sinks update _Default \
         --add-exclusion name=exclude-health-checks,filter='httpRequest.requestUrl=~"/health"'
     ```
   - Reduce VPC Flow log sample rate
   - Disable unnecessary Data Access logs
   - Route bulk logs to cheaper storage (GCS instead of Cloud Logging)

Admin Activity and System Event logs are **free** and can't be excluded.

</details>

**Question 3: An application writes `"User john@example.com failed login with password: abc123"` to Cloud Logging. What's wrong?**

<details>
<summary>Show Answer</summary>

Multiple security violations:

1. **Password in logs** — `password: abc123` is a credential. Anyone with log read access can see it.
2. **PII in plain text** — `john@example.com` is personally identifiable information.
3. **Unstructured format** — makes it hard to search and impossible to automatically redact.

**Correct approach:**
```json
{
  "severity": "WARNING",
  "message": "Authentication failed",
  "userId": "u-hash-abc123",
  "authMethod": "password",
  "failureReason": "INVALID_CREDENTIALS",
  "sourceIp": "203.0.113.50"
}
```

Changes: opaque user ID (not email), no password, structured format, appropriate severity level. If PII is logged accidentally, it must be purged — Cloud Logging has no native redaction, so prevention is critical.

</details>

**Question 4: What's the difference between a log-based metric and a log sink?**

<details>
<summary>Show Answer</summary>

| Aspect | Log-Based Metric | Log Sink |
|--------|-----------------|----------|
| **Purpose** | Count/measure events | Export log data |
| **Output** | Numeric metric in Monitoring | Logs in GCS/BQ/Pub/Sub |
| **Use case** | Alert on error rate | Long-term archive, analysis |
| **Latency** | Near real-time (~1 min) | Near real-time (batched) |
| **Cost** | Free (metric itself) | Destination storage costs |
| **Query** | MQL/PromQL in Monitoring | SQL in BigQuery, search in GCS |
| **Linux analogy** | `wc -l /var/log/error.log` | `rsyslog` forwarding to remote server |

**When to use each:**
- Log-based metric: "Alert me when error count > 10/min"
- Log sink: "Store all audit logs in BigQuery for 7-year compliance"
- Often used together: metric for alerting, sink for investigation

</details>

---

*Next: [Day 68 — Alert Tuning](DAY_68_ALERT_TUNING.md)*
