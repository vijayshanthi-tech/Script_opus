# Day 90 — PROJECT: Audit Monitoring Dashboard

> **Week 15 — Audit & Compliance** | ⏱ 2 hours | Region: `europe-west2`
> Student profile: 6 yrs Linux infra, 3 yrs RHDS LDAP, ACE certified

---

## Part 1 — Concept (30 min)

### 1.1 Project Overview

```
  AUDIT MONITORING SYSTEM — ARCHITECTURE
  ═══════════════════════════════════════

  ┌────────────────────────────────────────────────────────┐
  │                  GCP PROJECT                            │
  │                                                        │
  │  ┌────────────┐   ┌─────────────┐   ┌──────────────┐  │
  │  │ Admin      │   │ Data Access │   │ System Event │  │
  │  │ Activity   │   │ Logs        │   │ Logs         │  │
  │  │ Logs       │   │             │   │              │  │
  │  └──────┬─────┘   └──────┬──────┘   └──────┬───────┘  │
  │         │                │                  │          │
  │         └────────────────┼──────────────────┘          │
  │                          │                             │
  │                   ┌──────▼──────┐                      │
  │                   │ Log Router  │                      │
  │                   └──┬──────┬──┘                      │
  │                      │      │                          │
  │           ┌──────────▼┐  ┌──▼───────────┐             │
  │           │ BigQuery  │  │ Compliance   │             │
  │           │ Dataset   │  │ Log Bucket   │             │
  │           │ (analysis)│  │ (365d retain)│             │
  │           └─────┬─────┘  └──────────────┘             │
  │                 │                                      │
  │           ┌─────▼─────────────────┐                    │
  │           │ Saved Queries:        │                    │
  │           │ • SA key creation     │                    │
  │           │ • Owner role grants   │                    │
  │           │ • Firewall changes    │                    │
  │           │ • Permission denied   │                    │
  │           └─────┬─────────────────┘                    │
  │                 │                                      │
  │           ┌─────▼─────────────────┐                    │
  │           │ Log-Based Metrics     │───▶ Alerting       │
  │           │ (counters for events) │    Policies        │
  │           └───────────────────────┘                    │
  └────────────────────────────────────────────────────────┘
```

### 1.2 Components to Build

| Component | Purpose | Tool |
|-----------|---------|------|
| Compliant log bucket | Long-term audit log storage (365 days) | `gcloud logging buckets` |
| BigQuery dataset | SQL analysis of audit logs | `bq mk` |
| Log sink to BQ | Stream audit logs to BigQuery | `gcloud logging sinks` |
| Log-based metrics (4x) | Count critical events | `gcloud logging metrics` |
| Alerting policies | Notify on critical events | `gcloud monitoring policies` |
| Saved BQ queries | Pre-built investigation queries | BigQuery Console |
| Compliance report script | Generate evidence on demand | Shell script |

### 1.3 Design Decisions

```
  DESIGN DECISION MATRIX
  ══════════════════════

  Decision: Where to store long-term audit logs?
  ┌──────────────┬───────────┬───────────┬──────────────┐
  │ Option       │ Query     │ Cost      │ Retention    │
  ├──────────────┼───────────┼───────────┼──────────────┤
  │ Cloud Logging│ Good      │ $$        │ 30d default  │
  │ Custom Bucket│ Good      │ $$        │ Up to 3650d  │
  │ BigQuery     │ Excellent │ $$$       │ Unlimited    │
  │ GCS (archive)│ Poor      │ $         │ Unlimited    │
  └──────────────┴───────────┴───────────┴──────────────┘
  
  ✅ Decision: Custom bucket (compliance) + BigQuery (analysis)

  Decision: What events generate immediate alerts?
  ┌──────────────────────────┬─────────┬────────────┐
  │ Event                    │ Urgency │ Alert Type │
  ├──────────────────────────┼─────────┼────────────┤
  │ SA key created           │ HIGH    │ Immediate  │
  │ Owner/Editor role granted│ HIGH    │ Immediate  │
  │ Firewall rule changed    │ HIGH    │ Immediate  │
  │ Permission denied spike  │ MEDIUM  │ Hourly     │
  │ Any IAM change           │ LOW     │ Daily      │
  └──────────────────────────┴─────────┴────────────┘
```

> **RHDS parallel:** This project is equivalent to building a centralized log analysis system in RHDS: forwarding `access-log` and `audit-log` to a syslog server (≈ log sink), loading into a SIEM or ELK stack (≈ BigQuery), creating dashboards in Kibana (≈ saved queries), and setting up nagios/zabbix alerts for security events (≈ alerting policies). Same architecture, different implementation.

---

## Part 2 — Hands-On Lab (60 min)

### Prerequisites
```bash
export PROJECT_ID=$(gcloud config get-value project)
export REGION=europe-west2
export DATASET_ID=audit_logs_dataset
```

### Lab 2.1 — Create Compliant Log Infrastructure

```bash
echo "=== STEP 1: COMPLIANT LOG BUCKET ==="

# Create log bucket with 365-day retention
gcloud logging buckets create compliance-audit-logs \
  --location=$REGION \
  --retention-days=365 \
  --description="Audit logs with 1-year retention for compliance" \
  --project=$PROJECT_ID 2>/dev/null && \
  echo "✓ Compliant log bucket created" || \
  echo "Log bucket already exists or requires permissions"

# Create log sink to route audit logs to compliant bucket
gcloud logging sinks create audit-to-compliant-bucket \
  logging.googleapis.com/projects/$PROJECT_ID/locations/$REGION/buckets/compliance-audit-logs \
  --log-filter='logName:"cloudaudit.googleapis.com"' \
  --project=$PROJECT_ID 2>/dev/null && \
  echo "✓ Audit log sink created" || \
  echo "Sink already exists or requires permissions"

# Verify
echo ""
echo "--- Log Buckets ---"
gcloud logging buckets list --project=$PROJECT_ID \
  --format="table(name, retentionDays, location)" 2>/dev/null

echo ""
echo "--- Log Sinks ---"
gcloud logging sinks list --project=$PROJECT_ID \
  --format="table(name, destination)" 2>/dev/null
```

### Lab 2.2 — Create BigQuery Dataset for Log Analysis

```bash
echo "=== STEP 2: BIGQUERY AUDIT DATASET ==="

# Create BigQuery dataset in europe-west2
bq --location=$REGION mk \
  --dataset \
  --description="Audit log analysis dataset" \
  --default_table_expiration=0 \
  $PROJECT_ID:$DATASET_ID 2>/dev/null && \
  echo "✓ BigQuery dataset created" || \
  echo "Dataset already exists"

# Create log sink to BigQuery
gcloud logging sinks create audit-to-bigquery \
  bigquery.googleapis.com/projects/$PROJECT_ID/datasets/$DATASET_ID \
  --log-filter='logName:"cloudaudit.googleapis.com"' \
  --use-partitioned-tables \
  --project=$PROJECT_ID 2>/dev/null && \
  echo "✓ BigQuery log sink created" || \
  echo "Sink already exists"

# Grant the sink's service account write access to the dataset
SINK_SA=$(gcloud logging sinks describe audit-to-bigquery \
  --project=$PROJECT_ID --format="value(writerIdentity)" 2>/dev/null)
echo "Sink writer identity: $SINK_SA"

if [ -n "$SINK_SA" ]; then
  bq update --source $SINK_SA:WRITER \
    $PROJECT_ID:$DATASET_ID 2>/dev/null || \
    echo "Grant BQ access via Console: BigQuery → Dataset → Share"
fi

echo ""
echo "--- BigQuery Datasets ---"
bq ls --project_id=$PROJECT_ID 2>/dev/null
```

### Lab 2.3 — Create All Log-Based Metrics

```bash
echo "=== STEP 3: LOG-BASED METRICS ==="

# Metric 1: SA key creation
gcloud logging metrics create sa-key-creation \
  --description="SA key creation events" \
  --log-filter='protoPayload.methodName="google.iam.admin.v1.CreateServiceAccountKey"' \
  --project=$PROJECT_ID 2>/dev/null && \
  echo "✓ Metric: sa-key-creation" || echo "Metric already exists"

# Metric 2: Privileged role grants
gcloud logging metrics create privileged-role-grant \
  --description="Owner or Editor role granted" \
  --log-filter='protoPayload.methodName="SetIamPolicy" protoPayload.serviceData.policyDelta.bindingDeltas.role:("roles/owner" OR "roles/editor")' \
  --project=$PROJECT_ID 2>/dev/null && \
  echo "✓ Metric: privileged-role-grant" || echo "Metric already exists"

# Metric 3: Firewall changes
gcloud logging metrics create firewall-changes \
  --description="Firewall rule modifications" \
  --log-filter='resource.type="gce_firewall_rule"' \
  --project=$PROJECT_ID 2>/dev/null && \
  echo "✓ Metric: firewall-changes" || echo "Metric already exists"

# Metric 4: Permission denied spike
gcloud logging metrics create permission-denied \
  --description="Permission denied events" \
  --log-filter='protoPayload.status.code=7' \
  --project=$PROJECT_ID 2>/dev/null && \
  echo "✓ Metric: permission-denied" || echo "Metric already exists"

echo ""
echo "--- All Log-Based Metrics ---"
gcloud logging metrics list --project=$PROJECT_ID \
  --format="table(name, description)" 2>/dev/null
```

### Lab 2.4 — Create Alert Definitions

```bash
echo "=== STEP 4: ALERT POLICY DEFINITIONS ==="
echo ""

# Define alert policies (creation via Console is more practical)
cat << 'ALERTS'
┌───────────────────────────────────────────────────────────────┐
│  ALERT 1: SA Key Creation                                     │
│  Metric: logging.googleapis.com/user/sa-key-creation          │
│  Condition: count > 0 in any 5-minute window                  │
│  Severity: CRITICAL                                           │
│  Response: Verify authorization, check key storage             │
├───────────────────────────────────────────────────────────────┤
│  ALERT 2: Privileged Role Grant                               │
│  Metric: logging.googleapis.com/user/privileged-role-grant    │
│  Condition: count > 0 in any 5-minute window                  │
│  Severity: CRITICAL                                           │
│  Response: Verify if authorized, review grant scope            │
├───────────────────────────────────────────────────────────────┤
│  ALERT 3: Firewall Changes                                    │
│  Metric: logging.googleapis.com/user/firewall-changes         │
│  Condition: count > 0 in any 5-minute window                  │
│  Severity: HIGH                                               │
│  Response: Review rule, check if 0.0.0.0/0 allowed            │
├───────────────────────────────────────────────────────────────┤
│  ALERT 4: Permission Denied Spike                             │
│  Metric: logging.googleapis.com/user/permission-denied        │
│  Condition: count > 50 in any 1-hour window                   │
│  Severity: MEDIUM                                             │
│  Response: Investigate source IP/identity for probing attack   │
└───────────────────────────────────────────────────────────────┘

Create these in Console: Monitoring → Alerting → Create Policy
ALERTS

echo ""
echo "To create via Console:"
echo "  1. Go to Monitoring → Alerting → Create Policy"
echo "  2. Add condition → Metric → logging.googleapis.com/user/<metric>"
echo "  3. Set threshold and duration"
echo "  4. Add notification channel (email)"
echo "  5. Save policy"
```

### Lab 2.5 — BigQuery Investigation Queries

```bash
echo "=== STEP 5: SAVED BIGQUERY QUERIES ==="
echo ""

echo "The following queries can be run once audit logs flow to BigQuery."
echo "Save these in BigQuery Console as 'Saved Queries'."
echo ""

cat << 'QUERIES'
-- QUERY 1: Who created SA keys this week?
SELECT
  timestamp,
  protopayload_auditlog.authenticationInfo.principalEmail AS who,
  protopayload_auditlog.resourceName AS target_sa
FROM `PROJECT_ID.audit_logs_dataset.cloudaudit_googleapis_com_activity`
WHERE protopayload_auditlog.methodName = 'google.iam.admin.v1.CreateServiceAccountKey'
  AND timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
ORDER BY timestamp DESC;

-- QUERY 2: Who got Owner or Editor role?
SELECT
  timestamp,
  protopayload_auditlog.authenticationInfo.principalEmail AS granted_by,
  protopayload_auditlog.serviceData.policyDelta.bindingDeltas.role AS role,
  protopayload_auditlog.serviceData.policyDelta.bindingDeltas.member AS granted_to
FROM `PROJECT_ID.audit_logs_dataset.cloudaudit_googleapis_com_activity`
WHERE protopayload_auditlog.methodName = 'SetIamPolicy'
  AND protopayload_auditlog.serviceData.policyDelta.bindingDeltas.role
      IN ('roles/owner', 'roles/editor')
ORDER BY timestamp DESC;

-- QUERY 3: Firewall changes in last 30 days
SELECT
  timestamp,
  protopayload_auditlog.authenticationInfo.principalEmail AS who,
  protopayload_auditlog.methodName AS action,
  protopayload_auditlog.resourceName AS firewall_rule
FROM `PROJECT_ID.audit_logs_dataset.cloudaudit_googleapis_com_activity`
WHERE resource.type = 'gce_firewall_rule'
  AND timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
ORDER BY timestamp DESC;

-- QUERY 4: Permission denied by identity (top offenders)
SELECT
  protopayload_auditlog.authenticationInfo.principalEmail AS identity,
  COUNT(*) AS denied_count,
  MIN(timestamp) AS first_seen,
  MAX(timestamp) AS last_seen
FROM `PROJECT_ID.audit_logs_dataset.cloudaudit_googleapis_com_activity`
WHERE protopayload_auditlog.status.code = 7
  AND timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
GROUP BY identity
ORDER BY denied_count DESC
LIMIT 20;

-- QUERY 5: Weekly compliance summary
SELECT
  DATE(timestamp) AS day,
  COUNTIF(protopayload_auditlog.methodName = 'SetIamPolicy') AS iam_changes,
  COUNTIF(resource.type = 'gce_firewall_rule') AS firewall_changes,
  COUNTIF(protopayload_auditlog.methodName LIKE '%CreateServiceAccount%') AS sa_created,
  COUNTIF(protopayload_auditlog.status.code = 7) AS permission_denied
FROM `PROJECT_ID.audit_logs_dataset.cloudaudit_googleapis_com_activity`
WHERE timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
GROUP BY day
ORDER BY day DESC;
QUERIES
```

### Lab 2.6 — Compliance Evidence Report Script

```bash
cat << 'SCRIPT'
#!/bin/bash
# compliance-report.sh — Generate compliance evidence report
# Run quarterly before auditor reviews

set -euo pipefail

PROJECT_ID=$(gcloud config get-value project)
REPORT_DATE=$(date +%Y-%m-%d)
REPORT_FILE="/tmp/compliance-report-${REPORT_DATE}.txt"

{
  echo "╔══════════════════════════════════════════════════════╗"
  echo "║   QUARTERLY COMPLIANCE EVIDENCE REPORT              ║"
  echo "║   Project: $PROJECT_ID                              ║"
  echo "║   Date: $REPORT_DATE                                ║"
  echo "║   Region: europe-west2                              ║"
  echo "╚══════════════════════════════════════════════════════╝"
  echo ""

  echo "═══ 1. IAM CONFIGURATION ═══"
  gcloud projects get-iam-policy $PROJECT_ID \
    --flatten="bindings[].members" \
    --format="table(bindings.role, bindings.members)" 2>/dev/null
  echo ""

  echo "═══ 2. SERVICE ACCOUNTS ═══"
  gcloud iam service-accounts list --project=$PROJECT_ID \
    --format="table(email, displayName, disabled)" 2>/dev/null
  echo ""

  echo "═══ 3. LOG RETENTION CONFIGURATION ═══"
  gcloud logging buckets list --project=$PROJECT_ID \
    --format="table(name, retentionDays, locked)" 2>/dev/null
  echo ""

  echo "═══ 4. LOG SINKS ═══"
  gcloud logging sinks list --project=$PROJECT_ID \
    --format="table(name, destination, filter)" 2>/dev/null
  echo ""

  echo "═══ 5. ALERT POLICIES ═══"
  gcloud alpha monitoring policies list --project=$PROJECT_ID \
    --format="table(displayName, enabled)" 2>/dev/null || echo "N/A"
  echo ""

  echo "═══ 6. RESOURCE LOCATIONS ═══"
  gcloud compute instances list --project=$PROJECT_ID \
    --format="table(name, zone)" 2>/dev/null || echo "No instances"
  gcloud storage buckets list --project=$PROJECT_ID \
    --format="table(name, location)" 2>/dev/null || echo "No buckets"
  echo ""

  echo "═══ END OF REPORT ═══"
} > "$REPORT_FILE"

echo "Report saved to: $REPORT_FILE"
cat "$REPORT_FILE"
SCRIPT

echo ""
echo "Save the script above as compliance-report.sh"
echo "Run it quarterly to generate evidence for auditors."
```

### 🧹 Cleanup

```bash
echo "=== CLEANUP ==="

# Delete log sinks
gcloud logging sinks delete audit-to-compliant-bucket --project=$PROJECT_ID --quiet 2>/dev/null
gcloud logging sinks delete audit-to-bigquery --project=$PROJECT_ID --quiet 2>/dev/null

# Delete log bucket
gcloud logging buckets delete compliance-audit-logs \
  --location=$REGION --project=$PROJECT_ID --quiet 2>/dev/null

# Delete BigQuery dataset
bq rm -r -f $PROJECT_ID:$DATASET_ID 2>/dev/null

# Delete log-based metrics
gcloud logging metrics delete sa-key-creation --project=$PROJECT_ID --quiet 2>/dev/null
gcloud logging metrics delete privileged-role-grant --project=$PROJECT_ID --quiet 2>/dev/null
gcloud logging metrics delete firewall-changes --project=$PROJECT_ID --quiet 2>/dev/null
gcloud logging metrics delete permission-denied --project=$PROJECT_ID --quiet 2>/dev/null

echo "✓ All project resources cleaned up"
```

---

## Part 3 — Revision (15 min)

### Key Concepts
- **Audit monitoring system:** log sinks + BigQuery + log-based metrics + alerting
- **Two storage targets:** compliant log bucket (365d retention) for regulation, BigQuery for analysis
- **Four critical metrics:** SA key creation, privileged role grant, firewall changes, permission denied
- **Alert severity tiers:** Critical (immediate), High (within hours), Medium (hourly batch)
- **BigQuery queries** replace manual log review — pre-built queries for common investigations
- **Compliance report** script automates evidence collection for auditors
- **Architecture** mirrors Linux SIEM: rsyslog → ELK/Splunk → dashboards → alerting

### Essential Commands
```bash
# Full pipeline
gcloud logging buckets create BUCKET --location=REGION --retention-days=365
gcloud logging sinks create SINK DESTINATION --log-filter=FILTER
gcloud logging metrics create METRIC --log-filter=FILTER
bq mk --dataset PROJECT:DATASET

# Investigation
gcloud logging read 'FILTER' --limit=10 --freshness=7d
bq query --use_legacy_sql=false 'SELECT ...'

# Report
gcloud projects get-iam-policy PROJECT
gcloud logging buckets list
gcloud logging sinks list
```

---

## Part 4 — Quiz (15 min)

**Q1.** You're building an audit system for a new production project. What five components do you deploy on day 1?

<details><summary>Answer</summary>

1. **Custom log bucket** with 365-day retention — compliance requires long-term audit trail
2. **BigQuery dataset** in same region — enables SQL analysis of audit events
3. **Log sinks** (×2) — one to compliant bucket for retention, one to BigQuery for analysis
4. **Log-based metrics** (×4) — SA key creation, privileged role grants, firewall changes, permission denied
5. **Alerting policies** — at minimum, immediate alerts for SA key and Owner role events

These go in before any workload is deployed so you have full audit trail from the start.

</details>

**Q2.** BigQuery shows a spike of 500 permission-denied events from one service account in the last hour. What's your investigation process?

<details><summary>Answer</summary>

1. **Identify the SA:** Run the BQ query to get the SA email and the APIs it's trying to access
2. **Check if expected:** Is this a new deployment with wrong permissions? Or a scanning attack?
3. **Review what changed:** Check Admin Activity logs — was a role recently removed from this SA?
4. **Check the source:** Where are the calls coming from? (IP, VM, Kubernetes pod)
5. **Respond:**
   - If misconfiguration: grant the needed specific permissions
   - If attack/probing: disable the SA immediately, investigate the source
   - If role was mistakenly removed: restore the IAM binding
6. **Document:** Record the incident, root cause, and remediation in your ticketing system

</details>

**Q3.** You're asked to export a year of audit logs for legal discovery. What's the most efficient approach?

<details><summary>Answer</summary>

**If BigQuery sink was set up from day 1:**
```sql
-- Export everything for the year
SELECT * FROM `project.dataset.cloudaudit_*`
WHERE timestamp BETWEEN '2024-01-01' AND '2024-12-31'
```
Export results to GCS as JSONL or CSV.

**If only Cloud Logging was used:**
```bash
# Export from compliant log bucket (if 365d retention was configured)
gcloud logging read 'logName:"cloudaudit"' --freshness=365d --format=json > audit_export.json
```

**If neither was set up:**
Logs older than 30 days are gone from default Cloud Logging. This is why the audit system must be deployed on day 1.

**Lesson:** BigQuery is the best option — unlimited retention, fast queries, easy export.

</details>

**Q4.** Compare this audit monitoring system to what you'd build for RHDS log analysis.

<details><summary>Answer</summary>

| Component | GCP (This Project) | RHDS Equivalent |
|-----------|-------------------|-----------------|
| Log source | Cloud Audit Logs (auto-generated) | `access-log`, `audit-log`, `errors-log` (file-based) |
| Long-term storage | Custom log bucket (365d) | Log rotation + archive to NFS/tape |
| Analysis engine | BigQuery (serverless SQL) | ELK Stack / Splunk (self-hosted) |
| Log forwarding | Log sinks (managed) | rsyslog/Filebeat config (manual) |
| Alert on SA key | Log-based metric + alert | `grep "MOD.*nsDS5ReplicaCredentials"` + nagios check |
| Alert on ACL change | SetIamPolicy metric | `grep "MOD.*aci"` in access-log + email script |
| Compliance report | Shell script with gcloud | Shell script with ldapsearch |
| Dashboard | Logs Explorer + BigQuery | Kibana / Grafana |

The GCP system is fully managed and auto-scales. The RHDS equivalent requires significant infrastructure setup and maintenance. Both achieve the same security outcomes.

</details>
