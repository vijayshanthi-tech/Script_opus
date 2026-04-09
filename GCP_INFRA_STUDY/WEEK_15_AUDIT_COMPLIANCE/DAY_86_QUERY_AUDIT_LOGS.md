# Day 86 — Query Audit Logs: Logs Explorer & BigQuery Analysis

> **Week 15 — Audit & Compliance** | ⏱ 2 hours | Region: `europe-west2`
> Student profile: 6 yrs Linux infra, 3 yrs RHDS LDAP, ACE certified

---

## Part 1 — Concept (30 min)

### 1.1 Logs Explorer Query Syntax

```
  LOGS EXPLORER FILTER SYNTAX
  ═══════════════════════════

  BASIC STRUCTURE:
    field = "value"              Exact match
    field != "value"             Not equal
    field =~ "regex"             Regex match
    field : "substring"          Contains (partial match)
    field > value                Greater than (timestamps, numbers)

  COMBINING:
    filter1 AND filter2          Both must match (default)
    filter1 OR filter2           Either matches
    NOT filter                   Negation

  COMMON FIELDS:
  ┌────────────────────────────────────────────────────────┐
  │ resource.type                 │ "gce_instance"         │
  │ protoPayload.methodName       │ "v1.compute.instances" │
  │ protoPayload.authenticationInfo│                       │
  │   .principalEmail             │ "user@company.com"     │
  │ protoPayload.status.code      │ 0 (ok) / 7 (denied)   │
  │ protoPayload.serviceName      │ "compute.googleapis.." │
  │ severity                      │ "ERROR", "WARNING"     │
  │ timestamp                     │ >= "2026-04-01..."     │
  │ logName                       │ "...cloudaudit..."     │
  └────────────────────────────────────────────────────────┘
```

### 1.2 Query Cookbook — Essential Audit Queries

```
  QUERY COOKBOOK
  ═════════════

  1. WHO CREATED VMs?
  resource.type="gce_instance"
  protoPayload.methodName="v1.compute.instances.insert"

  2. WHO DELETED VMs?
  resource.type="gce_instance"
  protoPayload.methodName="v1.compute.instances.delete"

  3. WHO CHANGED IAM?
  protoPayload.methodName="SetIamPolicy"

  4. WHO MODIFIED FIREWALL RULES?
  resource.type="gce_firewall_rule"

  5. WHO CREATED SA KEYS?
  protoPayload.methodName="google.iam.admin.v1.CreateServiceAccountKey"

  6. PERMISSION DENIED EVENTS
  protoPayload.status.code=7

  7. SPECIFIC USER'S ACTIONS
  protoPayload.authenticationInfo.principalEmail="user@company.com"

  8. ALL CHANGES TO SPECIFIC VM
  resource.type="gce_instance"
  resource.labels.instance_id="1234567890"
```

### 1.3 BigQuery Analysis Pattern

```
  LOGS → BigQuery → SQL Analysis
  ═══════════════════════════════

  ┌──────────────┐    ┌───────────┐    ┌───────────────┐
  │ Cloud Logging │───▶│ Log Sink  │───▶│ BigQuery      │
  │              │    │ (filter)  │    │ Dataset       │
  └──────────────┘    └───────────┘    └───────┬───────┘
                                               │
                                        ┌──────▼──────┐
                                        │ SQL Queries │
                                        │ for analysis│
                                        └─────────────┘

  BQ TABLE STRUCTURE (auto-created by sink):
  ┌──────────────────────────────────────────────┐
  │ cloudaudit_googleapis_com_activity_YYYYMMDD  │
  │                                               │
  │ Columns:                                      │
  │ ├── timestamp                                 │
  │ ├── protopayload_auditlog                     │
  │ │   ├── authenticationInfo.principalEmail      │
  │ │   ├── methodName                             │
  │ │   ├── resourceName                           │
  │ │   ├── serviceName                            │
  │ │   └── status.code                            │
  │ ├── resource                                   │
  │ │   ├── type                                   │
  │ │   └── labels                                 │
  │ └── severity                                   │
  └──────────────────────────────────────────────┘
```

**Linux analogy:** This is like shipping `auditd` logs to an ELK stack. `gcloud logging read` = `grep` on log files. BigQuery export = Elasticsearch queries on structured audit data. Both transform raw logs into queryable, analysable data.

### 1.4 Key Investigation Patterns

```
  INVESTIGATION PATTERNS
  ═════════════════════

  Pattern 1: TIMELINE RECONSTRUCTION
  ──────────────────────────────────
  "What happened to resource X in the past 24 hours?"
  → Filter by resource + time range → sort by timestamp

  Pattern 2: ACTOR ANALYSIS
  ─────────────────────────
  "What has user Y done this week?"
  → Filter by principalEmail + time range

  Pattern 3: CHANGE VERIFICATION
  ──────────────────────────────
  "Did anyone modify firewall rules recently?"
  → Filter by resource.type="gce_firewall_rule"

  Pattern 4: SECURITY INCIDENT
  ────────────────────────────
  "Is the compromised SA being used?"
  → Filter by SA email → check callerIp, methodName

  Pattern 5: COMPLIANCE EVIDENCE
  ──────────────────────────────
  "Show all IAM changes in Q1 2026"
  → Filter by SetIamPolicy + date range → export
```

---

## Part 2 — Hands-On Lab (60 min)

### Prerequisites
```bash
export PROJECT_ID=$(gcloud config get-value project)
export REGION=europe-west2
export ZONE=europe-west2-a
```

### Lab 2.1 — Generate Events for Querying

```bash
# Create various resources to populate audit logs
gcloud compute instances create query-test-vm \
  --zone=$ZONE --machine-type=e2-micro \
  --image-family=debian-12 --image-project=debian-cloud \
  --no-address

gcloud iam service-accounts create query-test-sa \
  --display-name="Query Test SA"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:query-test-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/compute.viewer"

gsutil mb -l $REGION gs://${PROJECT_ID}-query-test/ 2>/dev/null || true

echo "Waiting 60 seconds for logs..."
sleep 60
```

### Lab 2.2 — Essential Audit Queries

```bash
# Query 1: Who created VMs?
echo "═══ QUERY 1: VM CREATION EVENTS ═══"
gcloud logging read '
  resource.type="gce_instance"
  protoPayload.methodName="v1.compute.instances.insert"
' --limit=5 --format="table(
  timestamp,
  protoPayload.authenticationInfo.principalEmail:label=CREATED_BY,
  resource.labels.instance_id:label=INSTANCE_ID
)" --project=$PROJECT_ID

# Query 2: Who changed IAM?
echo ""
echo "═══ QUERY 2: IAM CHANGES ═══"
gcloud logging read '
  protoPayload.methodName="SetIamPolicy"
' --limit=5 --format="table(
  timestamp,
  protoPayload.authenticationInfo.principalEmail:label=CHANGED_BY,
  protoPayload.serviceName:label=SERVICE
)" --project=$PROJECT_ID

# Query 3: Who created service accounts?
echo ""
echo "═══ QUERY 3: SA CREATION ═══"
gcloud logging read '
  protoPayload.methodName="google.iam.admin.v1.CreateServiceAccount"
' --limit=5 --format="table(
  timestamp,
  protoPayload.authenticationInfo.principalEmail:label=CREATED_BY,
  protoPayload.request.serviceAccount.displayName:label=SA_NAME
)" --project=$PROJECT_ID
```

### Lab 2.3 — Investigate a Specific User

```bash
MY_EMAIL=$(gcloud config get-value account)

echo "═══ ALL ACTIONS BY $MY_EMAIL (today) ═══"
gcloud logging read "
  protoPayload.authenticationInfo.principalEmail=\"$MY_EMAIL\"
  logName:\"cloudaudit.googleapis.com/activity\"
" --limit=15 --format="table(
  timestamp,
  protoPayload.methodName:label=ACTION,
  resource.type:label=RESOURCE_TYPE,
  protoPayload.resourceName:label=RESOURCE_NAME
)" --project=$PROJECT_ID
```

### Lab 2.4 — Export to BigQuery for Analysis

```bash
# Create dataset
bq mk --dataset --location=$REGION \
  --description="Audit log analysis" \
  ${PROJECT_ID}:audit_analysis 2>/dev/null || true

# Create sink for admin activity to BigQuery
gcloud logging sinks create audit-analysis-sink \
  bigquery.googleapis.com/projects/${PROJECT_ID}/datasets/audit_analysis \
  --log-filter='logName="projects/'$PROJECT_ID'/logs/cloudaudit.googleapis.com%2Factivity"' \
  --project=$PROJECT_ID 2>/dev/null || echo "Sink may exist"

# Grant sink writer access
SINK_SA=$(gcloud logging sinks describe audit-analysis-sink \
  --project=$PROJECT_ID --format="value(writerIdentity)" 2>/dev/null)

if [ -n "$SINK_SA" ]; then
  gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="$SINK_SA" \
    --role="roles/bigquery.dataEditor" 2>/dev/null
fi

echo "Sink created. Logs will flow to BigQuery dataset: audit_analysis"
echo ""
echo "Sample BQ queries you can run once data arrives:"
cat << 'EOF'

-- Most active users today
SELECT
  protopayload_auditlog.authenticationInfo.principalEmail AS user,
  COUNT(*) AS action_count
FROM `audit_analysis.cloudaudit_googleapis_com_activity_*`
WHERE _TABLE_SUFFIX = FORMAT_DATE('%Y%m%d', CURRENT_DATE())
GROUP BY user
ORDER BY action_count DESC
LIMIT 10;

-- IAM changes this week
SELECT
  timestamp,
  protopayload_auditlog.authenticationInfo.principalEmail AS changed_by,
  protopayload_auditlog.methodName AS method,
  protopayload_auditlog.resourceName AS resource
FROM `audit_analysis.cloudaudit_googleapis_com_activity_*`
WHERE protopayload_auditlog.methodName = 'SetIamPolicy'
  AND timestamp > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
ORDER BY timestamp DESC;

-- Failed access attempts
SELECT
  timestamp,
  protopayload_auditlog.authenticationInfo.principalEmail AS user,
  protopayload_auditlog.methodName AS attempted_action,
  protopayload_auditlog.status.message AS error
FROM `audit_analysis.cloudaudit_googleapis_com_activity_*`
WHERE protopayload_auditlog.status.code = 7
ORDER BY timestamp DESC
LIMIT 20;

EOF
```

### Lab 2.5 — Advanced Query: Firewall Rule Tracking

```bash
echo "═══ FIREWALL RULE CHANGES ═══"
gcloud logging read '
  resource.type="gce_firewall_rule"
' --limit=10 --format="table(
  timestamp,
  protoPayload.authenticationInfo.principalEmail:label=WHO,
  protoPayload.methodName:label=METHOD,
  protoPayload.resourceName:label=RULE
)" --project=$PROJECT_ID

echo ""
echo "═══ BUCKET OPERATIONS ═══"
gcloud logging read '
  resource.type="gcs_bucket"
  protoPayload.methodName=~"storage.buckets"
' --limit=10 --format="table(
  timestamp,
  protoPayload.authenticationInfo.principalEmail:label=WHO,
  protoPayload.methodName:label=METHOD,
  protoPayload.resourceName:label=BUCKET
)" --project=$PROJECT_ID
```

### 🧹 Cleanup

```bash
# Delete test resources
gcloud compute instances delete query-test-vm --zone=$ZONE --quiet 2>/dev/null
gcloud projects remove-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:query-test-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/compute.viewer" 2>/dev/null
gcloud iam service-accounts delete query-test-sa@${PROJECT_ID}.iam.gserviceaccount.com --quiet 2>/dev/null
gsutil rm -r gs://${PROJECT_ID}-query-test/ 2>/dev/null

# Delete log sink and BQ dataset
gcloud logging sinks delete audit-analysis-sink --project=$PROJECT_ID --quiet 2>/dev/null
bq rm -r -f ${PROJECT_ID}:audit_analysis 2>/dev/null
```

---

## Part 3 — Revision (15 min)

### Key Concepts
- **Logs Explorer** = real-time query tool for recent logs (up to retention period)
- **BigQuery** = SQL analysis for historical logs (exported via log sinks)
- Filter syntax: `field="value"`, `field:"substring"`, `field=~"regex"`
- Key fields: `principalEmail` (who), `methodName` (what), `resourceName` (where)
- **8 essential queries:** VM create/delete, IAM changes, firewall changes, SA key creation, permission denied, user activity, resource history, bucket operations
- BigQuery tables auto-created by log sinks: `cloudaudit_googleapis_com_activity_YYYYMMDD`
- Combine Logs Explorer for live investigation, BigQuery for historical analysis

### Essential Query Patterns
```bash
# VM creation
gcloud logging read 'resource.type="gce_instance" protoPayload.methodName="v1.compute.instances.insert"'

# IAM changes
gcloud logging read 'protoPayload.methodName="SetIamPolicy"'

# Specific user
gcloud logging read 'protoPayload.authenticationInfo.principalEmail="EMAIL"'

# Permission denied
gcloud logging read 'protoPayload.status.code=7'

# Firewall changes
gcloud logging read 'resource.type="gce_firewall_rule"'

# Time-bounded
gcloud logging read 'FILTER timestamp>="2026-04-01T00:00:00Z"'
```

---

## Part 4 — Quiz (15 min)

**Q1.** An incident response team needs to know everything a potentially compromised SA did in the last 72 hours. Write the query.

<details><summary>Answer</summary>

```bash
gcloud logging read '
  protoPayload.authenticationInfo.principalEmail="compromised-sa@project.iam.gserviceaccount.com"
  timestamp>="2026-04-05T00:00:00Z"
' --limit=1000 --format="table(
  timestamp,
  protoPayload.methodName,
  protoPayload.resourceName,
  protoPayload.requestMetadata.callerIp,
  protoPayload.status.code
)" --project=PROJECT_ID
```
Look for: unusual callerIp addresses, resource access outside normal patterns, any data exfiltration operations (storage.objects.get in bulk), IAM changes, key creation.

</details>

**Q2.** You need a weekly report of all IAM changes. Should you use Logs Explorer or BigQuery?

<details><summary>Answer</summary>

**BigQuery.** Logs Explorer is for interactive investigation — it doesn't support scheduled queries or aggregation. Export audit logs to BigQuery via a log sink, then create a scheduled query:
```sql
SELECT DATE(timestamp) as date,
  protopayload_auditlog.authenticationInfo.principalEmail,
  COUNT(*) as change_count
FROM `audit_logs.cloudaudit_googleapis_com_activity_*`
WHERE protopayload_auditlog.methodName = 'SetIamPolicy'
  AND timestamp > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
GROUP BY date, principalEmail
ORDER BY date DESC;
```
Schedule this to run weekly and export to a results table or send via email.

</details>

**Q3.** What's the difference between `field="value"` and `field:"value"` in Logs Explorer?

<details><summary>Answer</summary>

- `field="value"` — **exact match**. The field must equal the value exactly.
- `field:"value"` — **contains/has**. The field value must contain the substring. For repeated fields (like lists), it checks if any element matches.

Example: `protoPayload.methodName="SetIamPolicy"` matches only `SetIamPolicy`. But `protoPayload.methodName:"SetIam"` would match `SetIamPolicy`, `TestIamPermissions`, etc.

</details>

**Q4.** Compare querying GCP audit logs to querying RHDS access logs.

<details><summary>Answer</summary>

| GCP Audit Logs | RHDS Access Logs |
|---------------|-----------------|
| `gcloud logging read 'FILTER'` | `grep PATTERN /var/log/dirsrv/slapd-instance/access` |
| Logs Explorer (GUI) | `logconv.pl` (RHDS log analysis tool) |
| BigQuery (SQL analysis) | ELK/Splunk (shipped via rsyslog) |
| Structured JSON | Semi-structured text (conn=X op=Y) |
| `principalEmail` filter | grep for bind DN |
| `methodName` filter | grep for operation type (ADD, MOD, SRCH) |
| `timestamp` filter | grep for date pattern `[DD/Mon/YYYY:HH:MM:SS]` |
| `protoPayload.status.code=7` | grep for `err=50` (insufficient access) |

GCP's advantage: structured logs with a query language. RHDS logs require parsing scripts. The investigative approach is identical.

</details>
