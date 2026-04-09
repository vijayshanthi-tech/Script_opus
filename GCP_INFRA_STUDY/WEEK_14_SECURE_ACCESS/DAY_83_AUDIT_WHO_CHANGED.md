# Day 83 — Audit: Who Changed What — Cloud Audit Logs

> **Week 14 — Secure Access** | ⏱ 2 hours | Region: `europe-west2`
> Student profile: 6 yrs Linux infra, 3 yrs RHDS LDAP, ACE certified

---

## Part 1 — Concept (30 min)

### 1.1 Four Types of Cloud Audit Logs

```
  ┌──────────────────────────────────────────────────────────────┐
  │                CLOUD AUDIT LOG TYPES                          │
  ├────────────────────┬──────────┬───────────┬─────────────────┤
  │ Type               │ Default  │ Retention │ Cost            │
  ├────────────────────┼──────────┼───────────┼─────────────────┤
  │ 1. Admin Activity  │ Always ON│ 400 days  │ FREE            │
  │    (who changed    │ Cannot   │           │                 │
  │     config)        │ disable  │           │                 │
  ├────────────────────┼──────────┼───────────┼─────────────────┤
  │ 2. Data Access     │ OFF      │ 30 days   │ Can be costly   │
  │    (who read/      │ (opt-in) │ (default) │ (high volume)   │
  │     wrote data)    │          │           │                 │
  ├────────────────────┼──────────┼───────────┼─────────────────┤
  │ 3. System Event    │ Always ON│ 400 days  │ FREE            │
  │    (GCP automated  │ Cannot   │           │                 │
  │     actions)       │ disable  │           │                 │
  ├────────────────────┼──────────┼───────────┼─────────────────┤
  │ 4. Policy Denied   │ Always ON│ 400 days  │ FREE            │
  │    (access denied  │ Cannot   │           │                 │
  │     by VPC-SC/org) │ disable  │           │                 │
  └────────────────────┴──────────┴───────────┴─────────────────┘
```

**Linux analogy:**
| Linux Log | GCP Audit Log |
|-----------|---------------|
| `/var/log/secure` (auth events) | Admin Activity |
| `auditd` rules (file access) | Data Access |
| Kernel/systemd events | System Event |
| SELinux AVC denials | Policy Denied |
| RHDS `access-log` | Data Access (LDAP ops) |
| RHDS `errors-log` | Policy Denied |

### 1.2 What Each Log Type Captures

```
  ADMIN ACTIVITY (always on, free)
  ════════════════════════════════
  Records: Configuration changes
  ├── IAM policy changes (who granted/revoked roles)
  ├── Resource creation/deletion (VMs, buckets, etc.)
  ├── Firewall rule changes
  ├── Metadata changes
  └── Service account operations

  DATA ACCESS (opt-in, can be expensive)
  ═══════════════════════════════════════
  Records: Data read/write operations
  ├── ADMIN_READ: listing resources, reading config
  ├── DATA_READ: reading data (GCS object, BQ query)
  └── DATA_WRITE: writing data (upload, insert)

  SYSTEM EVENT (always on, free)
  ═════════════════════════════
  Records: Google-initiated actions
  ├── Live migration of VMs
  ├── Auto-scaling events
  └── Spot VM preemption

  POLICY DENIED (always on, free)
  ═══════════════════════════════
  Records: Access blocked by security policies
  ├── VPC Service Controls violations
  └── Organization policy violations
```

### 1.3 Audit Log Entry Structure

```
  AUDIT LOG ENTRY (protoPayload)
  ══════════════════════════════

  ┌──────────────────────────────────────────────┐
  │ timestamp: "2026-04-08T10:30:00Z"            │
  │                                               │
  │ protoPayload:                                 │
  │   @type: "type.../AuditLog"                   │
  │                                               │
  │   authenticationInfo:                         │
  │     principalEmail: "alice@company.com"       │ ← WHO
  │                                               │
  │   methodName:                                 │
  │     "compute.instances.delete"                │ ← WHAT
  │                                               │
  │   resourceName:                               │
  │     "projects/prod/zones/eu-w2-a/             │
  │      instances/web-vm"                        │ ← WHERE
  │                                               │
  │   request: { ... parameters ... }             │ ← HOW
  │                                               │
  │   response: { ... result ... }                │ ← RESULT
  │                                               │
  │   status:                                     │
  │     code: 0 (success) / 7 (denied)            │ ← STATUS
  │                                               │
  │ resource:                                     │
  │   type: "gce_instance"                        │
  │   labels:                                     │
  │     project_id: "prod"                        │
  │     zone: "europe-west2-a"                    │
  └──────────────────────────────────────────────┘
```

### 1.4 Correlating Changes — The Investigation Flow

```
  INCIDENT: "Who deleted the production VM?"
  ═══════════════════════════════════════════

  Step 1: Find the event
  ┌─────────────────────────────────────────┐
  │ Filter:                                  │
  │   resource.type="gce_instance"           │
  │   protoPayload.methodName=               │
  │     "compute.instances.delete"           │
  │   resource.labels.instance_id="12345"    │
  └─────────────────┬───────────────────────┘
                    │
  Step 2: Identify the actor
  ┌─────────────────▼───────────────────────┐
  │ protoPayload.authenticationInfo.         │
  │   principalEmail: "bob@company.com"      │
  │                                          │
  │ protoPayload.requestMetadata.            │
  │   callerIp: "203.0.113.50"              │
  │   callerSuppliedUserAgent: "gcloud/..."  │
  └─────────────────┬───────────────────────┘
                    │
  Step 3: Understand the context
  ┌─────────────────▼───────────────────────┐
  │ When: timestamp                         │
  │ From: callerIp                          │
  │ How: callerSuppliedUserAgent            │
  │ Via: serviceName (compute.googleapis..) │
  └─────────────────────────────────────────┘
```

> **RHDS parallel:** This is like reviewing RHDS `access-log` entries: each entry records the bind DN (who), the operation (add/modify/delete/search), the target DN (what), and the result code. The structure and investigative approach are identical.

---

## Part 2 — Hands-On Lab (60 min)

### Prerequisites
```bash
export PROJECT_ID=$(gcloud config get-value project)
export REGION=europe-west2
export ZONE=europe-west2-a
```

### Lab 2.1 — Generate Auditable Events

```bash
# Create resources to generate audit log entries
echo "--- Creating resources to generate audit logs ---"

# Create a VM
gcloud compute instances create audit-test-vm \
  --zone=$ZONE --machine-type=e2-micro \
  --image-family=debian-12 --image-project=debian-cloud \
  --no-address

# Create a bucket
gsutil mb -l $REGION gs://${PROJECT_ID}-audit-test/ 2>/dev/null || true

# Create a SA
gcloud iam service-accounts create audit-test-sa \
  --display-name="Audit Test SA"

# Add an IAM binding
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:audit-test-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/compute.viewer"

echo "--- Waiting 60 seconds for logs to be available ---"
sleep 60
```

### Lab 2.2 — Query Admin Activity Logs

```bash
# Who created VMs today?
echo "=== VM CREATION EVENTS ==="
gcloud logging read '
  resource.type="gce_instance"
  protoPayload.methodName="v1.compute.instances.insert"
  severity!="ERROR"
' --limit=5 --format="table(
  timestamp,
  protoPayload.authenticationInfo.principalEmail:label=WHO,
  protoPayload.resourceName:label=RESOURCE,
  protoPayload.response.status:label=STATUS
)" --project=$PROJECT_ID

# Who changed IAM policies?
echo ""
echo "=== IAM POLICY CHANGES ==="
gcloud logging read '
  protoPayload.methodName="SetIamPolicy"
' --limit=5 --format="table(
  timestamp,
  protoPayload.authenticationInfo.principalEmail:label=WHO,
  protoPayload.serviceName:label=SERVICE,
  protoPayload.methodName:label=METHOD
)" --project=$PROJECT_ID
```

### Lab 2.3 — Query for Specific Changes

```bash
# SA creation events
echo "=== SERVICE ACCOUNT CREATION ==="
gcloud logging read '
  protoPayload.methodName="google.iam.admin.v1.CreateServiceAccount"
' --limit=5 --format="table(
  timestamp,
  protoPayload.authenticationInfo.principalEmail:label=CREATED_BY,
  protoPayload.request.serviceAccount.displayName:label=SA_NAME
)" --project=$PROJECT_ID

# Firewall rule changes
echo ""
echo "=== FIREWALL CHANGES ==="
gcloud logging read '
  resource.type="gce_firewall_rule"
  protoPayload.methodName=~"firewalls"
' --limit=5 --format="table(
  timestamp,
  protoPayload.authenticationInfo.principalEmail:label=WHO,
  protoPayload.methodName:label=ACTION
)" --project=$PROJECT_ID
```

### Lab 2.4 — Investigate "Who Did This?"

```bash
# Full detail of a specific event
echo "=== DETAILED AUDIT LOG ENTRY ==="
gcloud logging read '
  resource.type="gce_instance"
  protoPayload.methodName="v1.compute.instances.insert"
' --limit=1 --format=json --project=$PROJECT_ID | python3 -m json.tool 2>/dev/null | head -60

echo ""
echo "=== CALLER DETAILS ==="
gcloud logging read '
  protoPayload.methodName="v1.compute.instances.insert"
' --limit=1 --format="yaml(
  protoPayload.authenticationInfo.principalEmail,
  protoPayload.requestMetadata.callerIp,
  protoPayload.requestMetadata.callerSuppliedUserAgent
)" --project=$PROJECT_ID
```

### Lab 2.5 — Export Logs Summary

```bash
# Generate a summary of all admin actions today
echo "═══════════════════════════════════════════"
echo "DAILY ADMIN ACTIVITY SUMMARY"
echo "Date: $(date -u +%Y-%m-%d)"
echo "Project: $PROJECT_ID"
echo "═══════════════════════════════════════════"

echo ""
echo "--- All admin actions by user ---"
gcloud logging read '
  logName="projects/'$PROJECT_ID'/logs/cloudaudit.googleapis.com%2Factivity"
' --limit=20 --format="table(
  timestamp,
  protoPayload.authenticationInfo.principalEmail:label=USER,
  protoPayload.methodName:label=ACTION,
  resource.type:label=RESOURCE_TYPE
)" --project=$PROJECT_ID

echo ""
echo "--- Failed requests (permission denied) ---"
gcloud logging read '
  protoPayload.status.code=7
' --limit=5 --format="table(
  timestamp,
  protoPayload.authenticationInfo.principalEmail:label=USER,
  protoPayload.methodName:label=ATTEMPTED_ACTION,
  protoPayload.status.message:label=ERROR
)" --project=$PROJECT_ID 2>/dev/null || echo "No denied requests found"
```

### 🧹 Cleanup

```bash
# Remove IAM binding
gcloud projects remove-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:audit-test-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/compute.viewer" 2>/dev/null

# Delete SA
gcloud iam service-accounts delete \
  audit-test-sa@${PROJECT_ID}.iam.gserviceaccount.com --quiet 2>/dev/null

# Delete VM
gcloud compute instances delete audit-test-vm --zone=$ZONE --quiet 2>/dev/null

# Delete bucket
gsutil rm -r gs://${PROJECT_ID}-audit-test/ 2>/dev/null
```

---

## Part 3 — Revision (15 min)

### Key Concepts
- **4 log types:** Admin Activity, Data Access, System Event, Policy Denied
- Admin Activity = **always on, free, 400-day retention** — your primary audit source
- Data Access = **opt-in, costly, 30-day default** — enable for sensitive data
- Key fields: `principalEmail` (who), `methodName` (what), `resourceName` (where)
- `callerIp` + `callerSuppliedUserAgent` = from where and how
- `status.code=7` = permission denied (useful for troubleshooting)
- Logs can be exported to GCS/BigQuery/Pub/Sub for long-term retention
- Log sinks route logs to destinations based on filters

### Essential Commands
```bash
# Query admin activity logs
gcloud logging read 'logName="projects/PROJECT/logs/cloudaudit.googleapis.com%2Factivity"' --limit=10

# IAM changes
gcloud logging read 'protoPayload.methodName="SetIamPolicy"' --limit=10

# VM operations
gcloud logging read 'resource.type="gce_instance" protoPayload.methodName=~"instances"' --limit=10

# Permission denied events
gcloud logging read 'protoPayload.status.code=7' --limit=10

# Specific user's actions
gcloud logging read 'protoPayload.authenticationInfo.principalEmail="USER"' --limit=10
```

---

## Part 4 — Quiz (15 min)

**Q1.** You need to know who deleted a production VM yesterday. Which audit log type has this information and what filter would you use?

<details><summary>Answer</summary>

**Admin Activity** logs. Filter:
```
resource.type="gce_instance"
protoPayload.methodName="v1.compute.instances.delete"
timestamp>="2026-04-07T00:00:00Z"
timestamp<"2026-04-08T00:00:00Z"
```
The `protoPayload.authenticationInfo.principalEmail` field will show who did it, `requestMetadata.callerIp` shows from where.

</details>

**Q2.** Data Access logs are disabled by default. When should you enable them and what's the trade-off?

<details><summary>Answer</summary>

**Enable for:** Sensitive data stores (Cloud Storage with PII, BigQuery with financial data), compliance requirements (SOC 2, GDPR), regulated industries. **Trade-off:** High volume of logs = significant cost. A busy BigQuery dataset can generate millions of log entries daily. Strategy: enable selectively per service, use exclusion filters to reduce volume, export to BigQuery for cost-effective long-term storage.

</details>

**Q3.** Admin Activity logs are retained for 400 days. If compliance requires 7 years of retention, what do you do?

<details><summary>Answer</summary>

Create a **log sink** that exports audit logs to a long-term storage destination:
1. **Cloud Storage** bucket with lifecycle policy (cheapest for archival)
2. **BigQuery** dataset (best for querying historical logs)

Configure the sink with a filter for admin activity logs. Lock the GCS bucket with a retention policy to prevent deletion. This is the standard pattern for compliance — similar to shipping RHDS access logs to a SIEM for long-term retention.

</details>

**Q4.** Compare GCP Cloud Audit Logs to RHDS access/error logs.

<details><summary>Answer</summary>

| GCP Cloud Audit Logs | RHDS Logs |
|---------------------|-----------|
| Admin Activity (config changes) | `access-log` (bind, add, modify, delete) |
| Data Access (data read/write) | `access-log` (search results returned) |
| System Event (automated actions) | `errors-log` (plugin events, replication) |
| Policy Denied (blocked by policy) | `errors-log` (ACI denials, resource limits) |
| `principalEmail` field | Bind DN in access log |
| `methodName` field | Operation type (ADD, MOD, DEL, SRCH) |
| `resourceName` field | Target DN |
| JSON structured format | LDAP log format (configurable) |

Both systems: always log admin operations, optionally log data operations, structured for programmatic analysis.

</details>
