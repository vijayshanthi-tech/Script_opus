# Week 19, Day 111 (Wed) — Audit Who Accessed What

## Today's Objective

Use Cloud Audit Logs (Data Access, Admin Activity) to trace who accessed specific resources, reconstruct incident timelines, and audit storage and BigQuery access patterns.

**Source:** [Cloud Audit Logs](https://cloud.google.com/logging/docs/audit) | [Data Access Logs](https://cloud.google.com/logging/docs/audit/configure-data-access)

**Deliverable:** A set of audit queries for common investigation scenarios — storage access, IAM changes, and timeline reconstruction

---

## Part 1: Concept (30 minutes)

### 1.1 Audit Log Types

```
Linux analogy:

/var/log/auth.log              ──►    Admin Activity logs (always on)
/var/log/secure                ──►    Admin Activity logs
audit.log (auditd)             ──►    Data Access logs (opt-in)
.bash_history per user         ──►    Data Access logs (who read what)
/var/log/wtmp (last)           ──►    Login/Activity logs
```

### 1.2 The Three Audit Log Types

```
┌──────────────────────────────────────────────────────────┐
│                    CLOUD AUDIT LOGS                        │
│                                                           │
│  ┌─────────────────────────────────────────────────────┐  │
│  │  ADMIN ACTIVITY                                      │  │
│  │  • Always enabled (cannot be disabled)               │  │
│  │  • Free (no charge)                                  │  │
│  │  • 400-day retention                                 │  │
│  │  • Write operations: create, delete, update, setIAM  │  │
│  └─────────────────────────────────────────────────────┘  │
│                                                           │
│  ┌─────────────────────────────────────────────────────┐  │
│  │  DATA ACCESS                                         │  │
│  │  • Opt-in (must enable per service)                  │  │
│  │  • Charged (can be high volume)                      │  │
│  │  • 30-day retention (default)                        │  │
│  │  • Read operations: get, list, getData               │  │
│  └─────────────────────────────────────────────────────┘  │
│                                                           │
│  ┌─────────────────────────────────────────────────────┐  │
│  │  SYSTEM EVENT                                        │  │
│  │  • Always enabled                                    │  │
│  │  • Free                                              │  │
│  │  • GCP system actions (migrations, maintenance)      │  │
│  └─────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────┘
```

| Log Type | Enabled By | Cost | Retention | Captures |
|---|---|---|---|---|
| Admin Activity | Always on | Free | 400 days | Creates, deletes, IAM changes |
| Data Access | Opt-in | Per log entry | 30 days | Reads, lists, metadata access |
| System Event | Always on | Free | 400 days | GCP system operations |

### 1.3 What Data Access Logs Capture

| Service | Data Read | Data Write | Admin Read |
|---|---|---|---|
| **Cloud Storage** | Object reads (GET) | Object writes (PUT) | Bucket metadata |
| **BigQuery** | Query results, tabledata.list | Insert/update rows | Dataset.list, tables.list |
| **Cloud SQL** | N/A (use SQL audit) | N/A | Instance metadata |
| **Compute Engine** | Instance metadata | — | Instance.list |

### 1.4 Log Entry Structure

```json
{
  "protoPayload": {
    "authenticationInfo": {
      "principalEmail": "user@example.com",         ← WHO
      "serviceAccountDelegationInfo": [...]          ← Via which SA
    },
    "authorizationInfo": [{
      "permission": "storage.objects.get",           ← WHAT permission
      "granted": true,                               ← ALLOWED?
      "resource": "projects/_/buckets/my-bucket/..." ← ON WHAT resource
    }],
    "methodName": "storage.objects.get",             ← API METHOD
    "resourceName": "projects/_/buckets/b/objects/f",← RESOURCE PATH
    "requestMetadata": {
      "callerIp": "203.0.113.1",                    ← FROM WHERE
      "callerSuppliedUserAgent": "gcloud/..."        ← USING WHAT tool
    }
  },
  "timestamp": "2026-04-08T10:30:00Z",              ← WHEN
  "resource": {
    "type": "gcs_bucket",                            ← RESOURCE TYPE
    "labels": { "bucket_name": "my-bucket" }
  }
}
```

### 1.5 Timeline Reconstruction

```
INCIDENT: Suspicious data access on 8 April 2026

Timeline from audit logs:
┌──────────┬──────────────────────────────────────┐
│ 09:15:00 │ user@corp.com: SetIamPolicy on bucket │
│          │ Added: allUsers with objectViewer     │
│ 09:15:30 │ unknown@gmail.com: objects.list       │
│ 09:15:45 │ unknown@gmail.com: objects.get x47    │
│ 09:20:00 │ admin@corp.com: SetIamPolicy on bucket│
│          │ Removed: allUsers                     │
│ 09:25:00 │ admin@corp.com: Filed incident report │
└──────────┴──────────────────────────────────────┘
```

---

## Part 2: Hands-On Lab (60 minutes)

### Step 1: Enable Data Access Logs (10 min)

```bash
export PROJECT_ID=$(gcloud config get-value project)

# Enable Data Access logs for Storage and Compute
cat > audit-config.yaml <<'EOF'
auditConfigs:
- auditLogConfigs:
  - logType: ADMIN_READ
  - logType: DATA_READ
  - logType: DATA_WRITE
  service: storage.googleapis.com
- auditLogConfigs:
  - logType: ADMIN_READ
  - logType: DATA_READ
  service: compute.googleapis.com
EOF

# Get current policy, merge, and set
gcloud projects get-iam-policy ${PROJECT_ID} --format=yaml > current-policy.yaml

echo ""
echo "=== Current audit config ==="
gcloud projects get-iam-policy ${PROJECT_ID} \
  --format="yaml(auditConfigs)"

# Note: In production, use gcloud projects set-iam-policy with merged config
# For the lab, we'll enable via console or use the API
echo ""
echo "Enable Data Access logs at:"
echo "https://console.cloud.google.com/iam-admin/audit?project=${PROJECT_ID}"
echo "Enable: Cloud Storage (DATA_READ, DATA_WRITE, ADMIN_READ)"
```

### Step 2: Create Auditable Resources (5 min)

```bash
# Create a bucket with some files
gcloud storage buckets create gs://${PROJECT_ID}-audit-lab \
  --location=europe-west2 \
  --uniform-bucket-level-access

echo "Secret file 1" | gcloud storage cp - gs://${PROJECT_ID}-audit-lab/secret-data.txt
echo "Secret file 2" | gcloud storage cp - gs://${PROJECT_ID}-audit-lab/credentials.txt
echo "Public readme"  | gcloud storage cp - gs://${PROJECT_ID}-audit-lab/README.md
```

### Step 3: Generate Audit Trail (10 min)

```bash
# Read operations (generates Data Access logs)
gcloud storage ls gs://${PROJECT_ID}-audit-lab/
gcloud storage cat gs://${PROJECT_ID}-audit-lab/secret-data.txt
gcloud storage cat gs://${PROJECT_ID}-audit-lab/credentials.txt

# Write operation (generates Admin Activity logs)
echo "Updated content" | gcloud storage cp - gs://${PROJECT_ID}-audit-lab/new-file.txt

# IAM change (generates Admin Activity logs)
gcloud storage buckets add-iam-policy-binding \
  gs://${PROJECT_ID}-audit-lab \
  --member="allAuthenticatedUsers" \
  --role="roles/storage.objectViewer"

# Immediately remove (this is just for audit trail)
gcloud storage buckets remove-iam-policy-binding \
  gs://${PROJECT_ID}-audit-lab \
  --member="allAuthenticatedUsers" \
  --role="roles/storage.objectViewer"
```

### Step 4: Query Admin Activity Logs (10 min)

```bash
# Who modified IAM on our bucket?
echo "=== IAM Changes on Audit Lab Bucket ==="
gcloud logging read "
  protoPayload.methodName=\"storage.setIamPermissions\" AND
  resource.labels.bucket_name=\"${PROJECT_ID}-audit-lab\"
" --limit=10 --format="table(
  timestamp,
  protoPayload.authenticationInfo.principalEmail:label=WHO,
  protoPayload.methodName:label=ACTION,
  protoPayload.serviceData.policyDelta.bindingDeltas.action:label=IAM_ACTION,
  protoPayload.serviceData.policyDelta.bindingDeltas.role:label=ROLE,
  protoPayload.serviceData.policyDelta.bindingDeltas.member:label=MEMBER
)" --freshness=1h

# Who created/deleted objects?
echo ""
echo "=== Object Write Operations ==="
gcloud logging read "
  protoPayload.methodName=~\"storage.objects.(create|delete)\" AND
  resource.labels.bucket_name=\"${PROJECT_ID}-audit-lab\"
" --limit=10 --format="table(
  timestamp,
  protoPayload.authenticationInfo.principalEmail:label=WHO,
  protoPayload.methodName:label=ACTION,
  protoPayload.resourceName:label=RESOURCE
)" --freshness=1h
```

### Step 5: Query Data Access Logs (10 min)

```bash
# Who read objects from our bucket? (requires Data Access logs enabled)
echo "=== Object Read Operations ==="
gcloud logging read "
  protoPayload.methodName=\"storage.objects.get\" AND
  resource.labels.bucket_name=\"${PROJECT_ID}-audit-lab\" AND
  logName=~\"data_access\"
" --limit=10 --format="table(
  timestamp,
  protoPayload.authenticationInfo.principalEmail:label=WHO,
  protoPayload.resourceName:label=OBJECT,
  protoPayload.requestMetadata.callerIp:label=SOURCE_IP,
  protoPayload.requestMetadata.callerSuppliedUserAgent:label=USER_AGENT
)" --freshness=1h

# Who listed the bucket contents?
echo ""
echo "=== Bucket List Operations ==="
gcloud logging read "
  protoPayload.methodName=\"storage.objects.list\" AND
  resource.labels.bucket_name=\"${PROJECT_ID}-audit-lab\"
" --limit=10 --format="table(
  timestamp,
  protoPayload.authenticationInfo.principalEmail:label=WHO,
  protoPayload.requestMetadata.callerIp:label=SOURCE_IP
)" --freshness=1h
```

### Step 6: Build a Timeline (10 min)

```bash
# All activity on the bucket, in chronological order
echo "=== Complete Timeline for ${PROJECT_ID}-audit-lab ==="
gcloud logging read "
  resource.labels.bucket_name=\"${PROJECT_ID}-audit-lab\"
" --limit=20 --format="table(
  timestamp,
  protoPayload.authenticationInfo.principalEmail:label=WHO,
  protoPayload.methodName:label=ACTION,
  protoPayload.resourceName:label=RESOURCE
)" --freshness=1h --order=asc
```

### Step 7: Clean Up (5 min)

```bash
gcloud storage rm -r gs://${PROJECT_ID}-audit-lab
rm -f audit-config.yaml current-policy.yaml
```

---

## Part 3: Revision (15 minutes)

- **Admin Activity** — always on, free, 400-day retention; captures write/delete/IAM changes
- **Data Access** — opt-in, charged, 30-day retention; captures reads/lists
- **System Event** — always on, free; captures GCP maintenance events
- **Key fields** — `principalEmail` (who), `methodName` (what), `resourceName` (on what), `callerIp` (from where)
- **Timeline reconstruction** — query by resource + time range, order ascending
- **Data Access logs must be enabled** per service; high-sensitivity buckets should always have them
- **Export to BigQuery** for long-term retention and complex queries

### Key Commands
```bash
# IAM changes
gcloud logging read 'protoPayload.methodName=~"SetIamPolicy"' --limit=10

# Storage reads
gcloud logging read 'protoPayload.methodName="storage.objects.get" AND resource.labels.bucket_name="BUCKET"'

# Permission denied events
gcloud logging read 'protoPayload.status.code=7' --limit=10

# All activity by user
gcloud logging read 'protoPayload.authenticationInfo.principalEmail="USER"' --freshness=24h
```

---

## Part 4: Quiz (15 minutes)

**Q1:** A file was accessed from a production GCS bucket. How do you find who read it and when?
<details><summary>Answer</summary>Query Data Access logs (must be enabled): <code>gcloud logging read 'protoPayload.methodName="storage.objects.get" AND protoPayload.resourceName=~"FILENAME" AND resource.labels.bucket_name="BUCKET"'</code>. The log entry shows <code>principalEmail</code> (who), <code>timestamp</code> (when), <code>callerIp</code> (from where), and <code>callerSuppliedUserAgent</code> (how). If Data Access logs weren't enabled, there's <b>no record of reads</b> — only writes/deletes are in Admin Activity logs.</details>

**Q2:** What's the difference between Admin Activity and Data Access audit logs?
<details><summary>Answer</summary><b>Admin Activity</b>: always on, free, 400-day retention. Captures <b>state changes</b> (create, delete, update, setIAM). <b>Data Access</b>: opt-in, charged, 30-day default retention. Captures <b>read operations</b> (get, list). Analogy: Admin Activity is like <code>/var/log/auth.log</code> (who logged in, who changed configs). Data Access is like <code>auditd</code> with file read rules (who read which files). Both are needed for complete security auditing.</details>

**Q3:** Data Access logs are expensive. How do you minimize cost while maintaining security?
<details><summary>Answer</summary>
1. <b>Enable selectively</b> — only for high-sensitivity services (Secret Manager, critical GCS buckets, BigQuery datasets with PII)<br>
2. <b>Use log exclusion filters</b> — exclude known noisy patterns (health checks, monitoring reads)<br>
3. <b>Export to BigQuery</b> for long-term retention, then reduce Cloud Logging retention<br>
4. <b>Sample non-critical reads</b> — log 10% of low-sensitivity bucket reads<br>
5. <b>Never disable for compliance-required resources</b>
</details>

**Q4:** You suspect a service account key was leaked. What audit queries help assess the damage?
<details><summary>Answer</summary>
1. <b>All activity by the SA</b>: <code>gcloud logging read 'protoPayload.authenticationInfo.principalEmail="SA_EMAIL"' --freshness=7d</code><br>
2. <b>Source IPs</b>: Check <code>callerIp</code> — unexpected IPs indicate unauthorized use<br>
3. <b>Data reads</b>: Query Data Access logs for the SA to see what was read<br>
4. <b>IAM changes</b>: Check if the SA created or modified any IAM policies (privilege escalation)<br>
5. <b>Resource creation</b>: Check if the SA created VMs (crypto mining) or GCS buckets (data exfiltration)<br>
Immediately: rotate/delete the key, review all activity, scope the blast radius.
</details>
