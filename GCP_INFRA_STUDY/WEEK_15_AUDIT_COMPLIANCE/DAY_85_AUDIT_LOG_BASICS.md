# Day 85 — Audit Log Basics: Types, Retention & Log Sinks

> **Week 15 — Audit & Compliance** | ⏱ 2 hours | Region: `europe-west2`
> Student profile: 6 yrs Linux infra, 3 yrs RHDS LDAP, ACE certified

---

## Part 1 — Concept (30 min)

### 1.1 The Four Audit Log Types — Deep Dive

```
  ┌────────────────────────────────────────────────────────────────────┐
  │  ADMIN ACTIVITY                                                    │
  │  ══════════════                                                    │
  │  What: API calls that MODIFY resources or config                   │
  │  Examples: create VM, delete bucket, change IAM, modify firewall   │
  │  Default: ALWAYS ON — cannot be disabled                           │
  │  Retention: 400 days                                               │
  │  Cost: FREE (included in base pricing)                             │
  │  Log name: cloudaudit.googleapis.com/activity                      │
  ├────────────────────────────────────────────────────────────────────┤
  │  DATA ACCESS                                                       │
  │  ═══════════                                                       │
  │  What: API calls that READ data or resource metadata               │
  │  Sub-types:                                                        │
  │    ADMIN_READ:  list resources, get resource config                │
  │    DATA_READ:   read data (GCS objects, BQ rows)                   │
  │    DATA_WRITE:  write data (upload object, insert row)             │
  │  Default: OFF (opt-in per service)                                 │
  │  Retention: 30 days (default), configurable up to 3650 days        │
  │  Cost: CHARGED based on volume (can be significant!)               │
  │  Log name: cloudaudit.googleapis.com/data_access                   │
  ├────────────────────────────────────────────────────────────────────┤
  │  SYSTEM EVENT                                                      │
  │  ═══════════                                                       │
  │  What: Actions performed by Google systems (not humans)            │
  │  Examples: live migration, preemption, auto-scaling                │
  │  Default: ALWAYS ON                                                │
  │  Retention: 400 days                                               │
  │  Cost: FREE                                                        │
  │  Log name: cloudaudit.googleapis.com/system_event                  │
  ├────────────────────────────────────────────────────────────────────┤
  │  POLICY DENIED                                                     │
  │  ═════════════                                                     │
  │  What: Access blocked by security policies (VPC-SC, org policy)    │
  │  Default: ALWAYS ON                                                │
  │  Retention: 400 days                                               │
  │  Cost: FREE                                                        │
  │  Log name: cloudaudit.googleapis.com/policy                        │
  └────────────────────────────────────────────────────────────────────┘
```

**Linux analogy:**
| GCP Audit Log | Linux / RHDS |
|---------------|-------------|
| Admin Activity | `/var/log/secure` + `auditd` SYSCALL rules |
| Data Access | `auditd -w /data -p rwa` (file access) |
| System Event | `journalctl -k` (kernel events) |
| Policy Denied | SELinux AVC denials / RHDS `errors` log |

### 1.2 Retention Periods

```
  RETENTION TIMELINE
  ══════════════════

  ──────────────────────────────────────────────────────────▶ Time
  │           │                    │                           │
  Day 0       Day 30               Day 400                     Day 3650
  │           │                    │                           │
  │ Data      │ Data Access        │ Admin Activity            │
  │ Access    │ default retention  │ System Event              │
  │ starts    │ ENDS here          │ Policy Denied             │
  │           │                    │ retention ENDS            │
  │           │                    │                           │
  │           │                    │                  Max custom
  │           │                    │                  retention
  │           │                    │                  (10 years)
  │           │                    │                           │

  FOR COMPLIANCE:
  ┌────────────────────────────────────────────────────┐
  │ SOC 2:  1 year minimum → Admin Activity covers it  │
  │ ISO 27001: Defined by org → may need log sinks     │
  │ GDPR: No specific log retention, but need audit    │
  │ PCI-DSS: 1 year online, 1 year archive             │
  │ HIPAA: 6 years → NEED log sinks to GCS/BQ          │
  └────────────────────────────────────────────────────┘
```

### 1.3 Log Sinks for Long-Term Storage

```
  LOG SINK ARCHITECTURE
  ═════════════════════

  ┌──────────────┐
  │ Cloud Logging │
  │  (source)    │
  └──────┬───────┘
         │
    ┌────▼────┐
    │ FILTER  │  ─── "Which logs to route?"
    └────┬────┘
         │
    ┌────▼─────────────────────────────────────────┐
    │               DESTINATIONS                    │
    ├──────────────┬───────────────┬────────────────┤
    │ Cloud Storage│  BigQuery     │  Pub/Sub       │
    │              │               │                │
    │ Cheapest for │ Best for      │ Real-time      │
    │ archival     │ querying      │ streaming to   │
    │              │ historical    │ SIEM/Splunk    │
    │ Lifecycle    │ data          │                │
    │ policies     │               │ Alert          │
    │ (Nearline,   │ SQL queries   │ integration    │
    │  Coldline)   │ on logs       │                │
    └──────────────┴───────────────┴────────────────┘

  FILTER EXAMPLES:
  ┌────────────────────────────────────────────────────────┐
  │ All audit logs:                                        │
  │   logName:"cloudaudit.googleapis.com"                  │
  │                                                        │
  │ Admin Activity only:                                   │
  │   logName="projects/X/logs/cloudaudit...%2Factivity"   │
  │                                                        │
  │ IAM changes only:                                      │
  │   protoPayload.methodName="SetIamPolicy"               │
  │                                                        │
  │ Specific service:                                      │
  │   protoPayload.serviceName="compute.googleapis.com"    │
  └────────────────────────────────────────────────────────┘
```

### 1.4 Enabling Data Access Logs

```
  DATA ACCESS LOG CONFIGURATION
  ═════════════════════════════

  Per-service granularity:
  ┌──────────────────────────────────────────┐
  │ Service              │ ADMIN │DATA│DATA  │
  │                      │ READ  │READ│WRITE │
  ├──────────────────────┼───────┼────┼──────┤
  │ Cloud Storage        │  ✓    │ ✓  │  ✓   │ ← full audit
  │ BigQuery             │  ✓    │ ✓  │  ✓   │ ← full audit
  │ Compute Engine       │  ✓    │    │      │ ← config only
  │ Cloud IAM            │  ✓    │    │      │ ← config only
  │ All other services   │       │    │      │ ← disabled
  └──────────────────────┴───────┴────┴──────┘

  ⚠ Enable selectively! Full Data Access on BigQuery
    can generate millions of log entries/day.
```

> **RHDS parallel:** In RHDS, the `access-log` configuration controls which operations are logged. `nsslapd-accesslog-level: 256` logs everything (like enabling all Data Access). `nsslapd-accesslog-level: 0` disables (default for data ops). The principle is the same — log what you need for compliance, not everything.

---

## Part 2 — Hands-On Lab (60 min)

### Prerequisites
```bash
export PROJECT_ID=$(gcloud config get-value project)
export REGION=europe-west2
export ZONE=europe-west2-a
```

### Lab 2.1 — Explore Current Audit Log Configuration

```bash
# Check current audit config
echo "=== CURRENT AUDIT LOG CONFIGURATION ==="
gcloud projects get-iam-policy $PROJECT_ID \
  --format="yaml(auditConfigs)" 2>/dev/null || echo "No custom audit config (defaults apply)"

# List available log types
echo ""
echo "=== AVAILABLE AUDIT LOGS ==="
gcloud logging logs list --project=$PROJECT_ID \
  --filter="name:cloudaudit" \
  --format="table(name)" 2>/dev/null | head -10
```

### Lab 2.2 — Enable Data Access Logs for Storage

```bash
# Enable Data Access logging for Cloud Storage
# This uses the IAM policy audit config
gcloud projects get-iam-policy $PROJECT_ID --format=json > /tmp/policy.json

# Add audit config (using Python for JSON manipulation)
python3 << 'PYEOF'
import json

with open('/tmp/policy.json') as f:
    policy = json.load(f)

# Add audit logging config
audit_configs = policy.get('auditConfigs', [])

# Check if storage config already exists
storage_exists = any(c.get('service') == 'storage.googleapis.com' for c in audit_configs)

if not storage_exists:
    audit_configs.append({
        'service': 'storage.googleapis.com',
        'auditLogConfigs': [
            {'logType': 'ADMIN_READ'},
            {'logType': 'DATA_READ'},
            {'logType': 'DATA_WRITE'}
        ]
    })
    policy['auditConfigs'] = audit_configs

    with open('/tmp/policy.json', 'w') as f:
        json.dump(policy, f, indent=2)
    print("Added storage audit logging config")
else:
    print("Storage audit logging already configured")
PYEOF

gcloud projects set-iam-policy $PROJECT_ID /tmp/policy.json --format=json > /dev/null 2>&1

# Verify
echo "=== UPDATED AUDIT CONFIG ==="
gcloud projects get-iam-policy $PROJECT_ID \
  --format="yaml(auditConfigs)"
```

### Lab 2.3 — Create a Log Sink to Cloud Storage

```bash
# Create a bucket for log storage
gsutil mb -l $REGION gs://${PROJECT_ID}-audit-archive/ 2>/dev/null || true

# Set lifecycle policy (move to Coldline after 90 days)
cat > /tmp/lifecycle.json << 'EOF'
{
  "lifecycle": {
    "rule": [
      {
        "action": {"type": "SetStorageClass", "storageClass": "COLDLINE"},
        "condition": {"age": 90}
      }
    ]
  }
}
EOF
gsutil lifecycle set /tmp/lifecycle.json gs://${PROJECT_ID}-audit-archive/

# Create log sink
gcloud logging sinks create audit-archive-sink \
  storage.googleapis.com/${PROJECT_ID}-audit-archive \
  --log-filter='logName:"cloudaudit.googleapis.com"' \
  --project=$PROJECT_ID

# Get the sink's service account (needs write access to bucket)
SINK_SA=$(gcloud logging sinks describe audit-archive-sink \
  --project=$PROJECT_ID --format="value(writerIdentity)")
echo "Sink SA: $SINK_SA"

# Grant the sink SA write access to the bucket
gsutil iam ch $SINK_SA:objectCreator gs://${PROJECT_ID}-audit-archive/

echo ""
echo "✅ Log sink created: all audit logs → gs://${PROJECT_ID}-audit-archive/"
```

### Lab 2.4 — Create a Log Sink to BigQuery

```bash
# Create BigQuery dataset for log analysis
bq mk --dataset \
  --location=$REGION \
  --description="Audit logs for analysis" \
  ${PROJECT_ID}:audit_logs 2>/dev/null || echo "Dataset may already exist"

# Create log sink to BigQuery
gcloud logging sinks create audit-bq-sink \
  bigquery.googleapis.com/projects/${PROJECT_ID}/datasets/audit_logs \
  --log-filter='logName:"cloudaudit.googleapis.com/activity"' \
  --project=$PROJECT_ID 2>/dev/null || echo "Sink may already exist"

# Get and configure sink SA
BQ_SINK_SA=$(gcloud logging sinks describe audit-bq-sink \
  --project=$PROJECT_ID --format="value(writerIdentity)" 2>/dev/null)
echo "BQ Sink SA: $BQ_SINK_SA"

# Grant BQ access
if [ -n "$BQ_SINK_SA" ]; then
  bq add-iam-policy-binding \
    --member="$BQ_SINK_SA" \
    --role="roles/bigquery.dataEditor" \
    ${PROJECT_ID}:audit_logs 2>/dev/null || echo "BQ IAM binding may need manual setup"
fi

echo ""
echo "✅ Log sink created: admin activity → BigQuery dataset audit_logs"
```

### Lab 2.5 — List and Verify Sinks

```bash
echo "=== ALL LOG SINKS ==="
gcloud logging sinks list --project=$PROJECT_ID \
  --format="table(name, destination, filter)"

echo ""
echo "=== SINK DETAILS ==="
gcloud logging sinks describe audit-archive-sink \
  --project=$PROJECT_ID --format=yaml 2>/dev/null

echo ""
echo "=== RETENTION SUMMARY ==="
cat << 'EOF'
┌────────────────────┬───────────────┬─────────────────────┐
│ Log Type           │ Platform Ret. │ Sink Destination     │
├────────────────────┼───────────────┼─────────────────────┤
│ Admin Activity     │ 400 days      │ GCS (Coldline @90d)  │
│ Data Access        │ 30 days       │ GCS (Coldline @90d)  │
│ System Event       │ 400 days      │ GCS (Coldline @90d)  │
│ Policy Denied      │ 400 days      │ GCS (Coldline @90d)  │
│ Admin Activity     │ 400 days      │ BigQuery (queryable) │
└────────────────────┴───────────────┴─────────────────────┘
EOF
```

### 🧹 Cleanup

```bash
# Delete log sinks
gcloud logging sinks delete audit-archive-sink --project=$PROJECT_ID --quiet 2>/dev/null
gcloud logging sinks delete audit-bq-sink --project=$PROJECT_ID --quiet 2>/dev/null

# Delete GCS bucket
gsutil rm -r gs://${PROJECT_ID}-audit-archive/ 2>/dev/null

# Delete BigQuery dataset
bq rm -r -f ${PROJECT_ID}:audit_logs 2>/dev/null

# Remove temp files
rm -f /tmp/policy.json /tmp/lifecycle.json
```

---

## Part 3 — Revision (15 min)

### Key Concepts
- **Admin Activity** — always on, free, 400 days — your primary audit trail
- **Data Access** — opt-in, costly, 30 days default — enable selectively
- **System Event** — always on, free — GCP-initiated actions
- **Policy Denied** — always on, free — blocked by VPC-SC/org policy
- **Log sinks** route logs to GCS (cheap archival), BigQuery (queryable), or Pub/Sub (streaming)
- Sinks need a **writer identity** that must be granted access to the destination
- Data Access logs have 3 sub-types: `ADMIN_READ`, `DATA_READ`, `DATA_WRITE`
- Enable Data Access logs per service — not globally (cost control)
- For compliance beyond 400 days → must use log sinks

### Essential Commands
```bash
# View audit config
gcloud projects get-iam-policy PROJECT --format="yaml(auditConfigs)"

# Create log sink to GCS
gcloud logging sinks create SINK_NAME \
  storage.googleapis.com/BUCKET \
  --log-filter='logName:"cloudaudit.googleapis.com"'

# Create log sink to BigQuery
gcloud logging sinks create SINK_NAME \
  bigquery.googleapis.com/projects/PROJECT/datasets/DATASET \
  --log-filter='FILTER'

# List sinks
gcloud logging sinks list

# Get sink writer identity
gcloud logging sinks describe SINK_NAME --format="value(writerIdentity)"
```

---

## Part 4 — Quiz (15 min)

**Q1.** Your compliance team requires 7 years of audit log retention. Admin Activity logs are only retained for 400 days. How do you meet this requirement?

<details><summary>Answer</summary>

Create a **log sink** that exports admin activity logs to Cloud Storage with a **retention policy lock** of 7 years. Use lifecycle rules to transition to Coldline (after 30 days) then Archive (after 365 days) to minimise cost. The bucket's retention policy prevents deletion before 7 years, even by project owners. Additionally, consider exporting to BigQuery for the first 1-2 years for queryability.

</details>

**Q2.** Enabling Data Access logs for BigQuery increased your logging costs significantly. What strategies can reduce this?

<details><summary>Answer</summary>

1. **Exclusion filters** — skip logs for routine/automated queries (e.g., monitoring dashboards)
2. **Enable selectively** — only DATA_READ, not DATA_WRITE if you only need read audit
3. **Exempted members** — exclude service accounts that generate high-volume routine queries from data access logging
4. **Log sink with filter** — export only to cheaper storage instead of keeping in Cloud Logging
5. **Shorter retention** — reduce from 30 days to what compliance actually requires

</details>

**Q3.** A log sink's writer identity is `serviceAccount:p123-456@gcs-project-accounts.iam.gserviceaccount.com`. What happens if you don't grant this SA access to the destination bucket?

<details><summary>Answer</summary>

Logs will be **silently dropped**. The sink exists and the filter matches, but the writer identity can't write to the destination. No error appears in Cloud Logging — logs simply don't arrive at the destination. This is a common misconfiguration. Always verify by checking the destination for recent entries after creating a sink. Monitor the `logging.googleapis.com/exports/byte_count` metric to confirm exports are happening.

</details>

**Q4.** Compare GCP log sinks to RHDS log rotation and archival.

<details><summary>Answer</summary>

| GCP Log Sinks | RHDS Log Management |
|--------------|---------------------|
| Sink filter = which logs | `nsslapd-accesslog-level` = which operations |
| GCS destination | `logrotate` + `rsync` to archive server |
| BigQuery destination | Ship to Splunk/ELK via `rsyslog` |
| Pub/Sub destination | Real-time `rsyslog` stream |
| Writer identity needs access | Archive server needs SSH/NFS access |
| Retention policy lock | Immutable storage / WORM compliance |
| Cost = storage + ingestion | Cost = storage + SIEM licensing |

Both patterns: filter what you log → route to destinations → enforce retention → query when needed.

</details>
