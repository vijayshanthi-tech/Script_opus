# Day 89 — Compliance Notes: SOC 2, ISO 27001, GDPR on GCP

> **Week 15 — Audit & Compliance** | ⏱ 2 hours | Region: `europe-west2`
> Student profile: 6 yrs Linux infra, 3 yrs RHDS LDAP, ACE certified

---

## Part 1 — Concept (30 min)

### 1.1 The Three Pillars of Cloud Compliance

```
  COMPLIANCE LANDSCAPE FOR GCP ENGINEERS
  ═══════════════════════════════════════

  ┌───────────────────────────────────────────────────────────┐
  │                   YOUR RESPONSIBILITY                      │
  │  ┌─────────────┐  ┌─────────────┐  ┌──────────────────┐  │
  │  │  SOC 2      │  │  ISO 27001  │  │  GDPR            │  │
  │  │  Type II    │  │             │  │  (if UK/EU data) │  │
  │  ├─────────────┤  ├─────────────┤  ├──────────────────┤  │
  │  │ Trust       │  │ ISMS        │  │ Data protection  │  │
  │  │ Services:   │  │ framework:  │  │ regulation:      │  │
  │  │ • Security  │  │ • Risk      │  │ • Consent        │  │
  │  │ • Availab.  │  │ • Controls  │  │ • Right to erase │  │
  │  │ • Confid.   │  │ • Audit     │  │ • Data locality  │  │
  │  │ • Process.  │  │ • Improve   │  │ • Breach notify  │  │
  │  │ • Privacy   │  │             │  │ • DPO required   │  │
  │  └─────────────┘  └─────────────┘  └──────────────────┘  │
  └───────────────────────────────────────────────────────────┘
                           │
                    ┌──────▼──────┐
                    │ SHARED      │
                    │ RESPONSIBILITY│
                    │ MODEL       │
                    └─────────────┘
           ┌───────────────┴────────────────┐
           ▼                                ▼
  ┌──────────────────┐            ┌──────────────────┐
  │  GOOGLE's PART   │            │  YOUR PART       │
  │  • Physical DC   │            │  • IAM config    │
  │  • Network       │            │  • Data handling │
  │  • Hardware      │            │  • Access control│
  │  • Base software │            │  • Logging       │
  │  • Certifications│            │  • Encryption    │
  │    (SOC2, ISO)   │            │  • Compliance    │
  └──────────────────┘            └──────────────────┘
```

### 1.2 SOC 2 Type II on GCP

```
  SOC 2 TYPE II — WHAT GCP ENGINEERS MUST DO
  ═══════════════════════════════════════════

  Trust Service Criteria → GCP Control

  ┌──────────────┬─────────────────────────────────────┐
  │ SECURITY     │ IAM least privilege                  │
  │  (CC6.x)     │ Firewall rules (deny by default)    │
  │              │ VPC Service Controls                 │
  │              │ Encryption (at rest + in transit)    │
  ├──────────────┼─────────────────────────────────────┤
  │ AVAILABILITY │ Multi-zone / multi-region deployment│
  │  (A1.x)      │ Load balancing + auto-scaling       │
  │              │ Backup + DR procedures               │
  ├──────────────┼─────────────────────────────────────┤
  │ CONFID.      │ CMEK (Customer-Managed Encryption)  │
  │  (C1.x)      │ DLP (Data Loss Prevention)          │
  │              │ VPC-SC (data exfiltration guard)     │
  ├──────────────┼─────────────────────────────────────┤
  │ PROCESSING   │ Data pipeline validation             │
  │  (PI1.x)     │ Input validation                    │
  │              │ Monitoring + alerting                │
  ├──────────────┼─────────────────────────────────────┤
  │ PRIVACY      │ Data lifecycle management            │
  │  (P1.x)      │ Retention policies                  │
  │              │ Data subject access requests         │
  └──────────────┴─────────────────────────────────────┘
```

### 1.3 ISO 27001 Control Mapping

| ISO 27001 Control | GCP Implementation | Linux Parallel |
|---|---|---|
| A.9.1 Access control policy | IAM policy + org constraints | PAM + `/etc/security/` |
| A.9.2 User access management | IAM bindings + groups | `useradd`, `sudoers` |
| A.9.4 System access control | OS Login + 2FA | SSH keys + PAM MFA |
| A.10.1 Cryptographic controls | CMEK / Cloud KMS | LUKS, GPG |
| A.12.4 Logging and monitoring | Cloud Logging + Monitoring | rsyslog, auditd |
| A.12.6 Vulnerability mgmt | Security Command Center | OpenSCAP, CVE scanning |
| A.13.1 Network security | VPC, firewall rules, VPC-SC | iptables, SELinux |
| A.17.1 Business continuity | Multi-region, snapshots, backups | DRBD, rsync, tape |
| A.18.1 Legal compliance | Data residency (regions) | Local storage compliance |

### 1.4 GDPR — What GCP Engineers Must Know

```
  GDPR KEY REQUIREMENTS FOR UK/EU DATA ON GCP
  ═════════════════════════════════════════════

  ┌───────────────────────────────────────────────────────┐
  │  REQUIREMENT 1: DATA RESIDENCY                        │
  │  Store UK/EU data in europe-west2 (London)            │
  │  Use org policy: gcp.resourceLocations                │
  │  Restrict allowed: ["europe-west2"]                   │
  ├───────────────────────────────────────────────────────┤
  │  REQUIREMENT 2: ENCRYPTION                            │
  │  At rest: default (Google-managed) or CMEK            │
  │  In transit: TLS 1.2+ (default on GCP)                │
  │  CMEK for sensitive data: Cloud KMS in europe-west2   │
  ├───────────────────────────────────────────────────────┤
  │  REQUIREMENT 3: ACCESS LOGGING                        │
  │  Enable Data Access audit logs for all services       │
  │  Retain logs: 1 year minimum for compliance           │
  │  Export to BigQuery for long-term analysis             │
  ├───────────────────────────────────────────────────────┤
  │  REQUIREMENT 4: RIGHT TO ERASURE                      │
  │  Ability to delete all data for a specific user       │
  │  Requires: data inventory + labeling + delete APIs    │
  ├───────────────────────────────────────────────────────┤
  │  REQUIREMENT 5: BREACH NOTIFICATION                   │
  │  Detect within hours, notify within 72 hours           │
  │  Requires: robust monitoring + alerting pipeline       │
  │  GCP: Security Command Center premium tier            │
  └───────────────────────────────────────────────────────┘
```

> **RHDS parallel:** RHDS was often the identity backbone for compliance: ACI entries enforced access control (ISO A.9), replication logs provided audit trails (ISO A.12.4), TLS for LDAPS met encryption requirements (ISO A.10), and password policies met complexity requirements. GDPR data residency was easier — the server was physically in your DC.

---

## Part 2 — Hands-On Lab (60 min)

### Prerequisites
```bash
export PROJECT_ID=$(gcloud config get-value project)
export REGION=europe-west2
```

### Lab 2.1 — Verify Data Residency Controls

```bash
echo "=== DATA RESIDENCY VERIFICATION ==="
echo ""

# Check org policy for resource locations (if you have org access)
echo "--- Resource Location Policy ---"
gcloud resource-manager org-policies describe \
  gcp.resourceLocations \
  --project=$PROJECT_ID 2>/dev/null || \
  echo "Org policy not set (requires org-level access)"

# List all resources and their locations
echo ""
echo "--- GCE Instances and Locations ---"
gcloud compute instances list --project=$PROJECT_ID \
  --format="table(name, zone, status)" 2>/dev/null || echo "No instances"

echo ""
echo "--- GCS Buckets and Locations ---"
gcloud storage buckets list --project=$PROJECT_ID \
  --format="table(name, location, locationType)" 2>/dev/null || echo "No buckets"

echo ""
echo "--- Cloud SQL Instances ---"
gcloud sql instances list --project=$PROJECT_ID \
  --format="table(name, region, state)" 2>/dev/null || echo "No SQL instances"

# Flag any non-EU resources
echo ""
echo "--- COMPLIANCE CHECK ---"
echo "All resources should be in europe-west* regions for UK/EU data"
```

### Lab 2.2 — Audit Log Configuration Check

```bash
echo "=== AUDIT LOG CONFIGURATION ==="
echo ""

# Get audit config from IAM policy
echo "--- Current Audit Config ---"
gcloud projects get-iam-policy $PROJECT_ID \
  --format=json 2>/dev/null | \
  python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    configs = data.get('auditConfigs', [])
    if not configs:
        print('No audit configs set (using defaults)')
    for cfg in configs:
        svc = cfg.get('service', 'unknown')
        for lc in cfg.get('auditLogConfigs', []):
            print(f'Service: {svc} | LogType: {lc.get(\"logType\", \"?\")}')
except:
    print('Could not parse audit config')
" 2>/dev/null || echo "Check Console: IAM → Audit Logs"

# Verify Cloud Logging retention
echo ""
echo "--- Log Bucket Retention ---"
gcloud logging buckets list --project=$PROJECT_ID \
  --format="table(name, retentionDays, locked)" 2>/dev/null

echo ""
echo "Compliance requirement: Minimum 365 days for audit logs"
echo "Default _Default bucket: 30 days (NOT compliant!)"
echo "Action: Create custom bucket with 365+ day retention"
```

### Lab 2.3 — Create Compliant Log Bucket

```bash
# Create a log bucket with 1-year retention
echo "--- Creating Compliant Log Bucket ---"
gcloud logging buckets create compliance-audit-logs \
  --location=$REGION \
  --retention-days=365 \
  --description="Compliant audit log bucket (1yr retention)" \
  --project=$PROJECT_ID 2>/dev/null && \
  echo "Created compliance log bucket" || \
  echo "Log bucket creation requires permissions or already exists"

# Create a log sink to route audit logs to the compliant bucket
gcloud logging sinks create audit-compliance-sink \
  logging.googleapis.com/projects/$PROJECT_ID/locations/$REGION/buckets/compliance-audit-logs \
  --log-filter='logName:"cloudaudit.googleapis.com"' \
  --project=$PROJECT_ID 2>/dev/null && \
  echo "Created audit log sink" || \
  echo "Sink creation requires permissions or already exists"

# Verify
echo ""
echo "--- Log Sinks ---"
gcloud logging sinks list --project=$PROJECT_ID \
  --format="table(name, destination, filter)" 2>/dev/null
```

### Lab 2.4 — Encryption Verification

```bash
echo "=== ENCRYPTION STATUS ==="
echo ""

# Check default encryption for GCS buckets
echo "--- GCS Bucket Encryption ---"
for BUCKET in $(gcloud storage buckets list --project=$PROJECT_ID \
  --format="value(name)" 2>/dev/null); do
  ENC=$(gcloud storage buckets describe gs://$BUCKET \
    --format="value(default_kms_key)" 2>/dev/null)
  if [ -z "$ENC" ]; then
    echo "$BUCKET: Google-managed encryption (default)"
  else
    echo "$BUCKET: CMEK ($ENC)"
  fi
done

# Check KMS key rings in the region
echo ""
echo "--- KMS Key Rings in $REGION ---"
gcloud kms keyrings list --location=$REGION --project=$PROJECT_ID \
  --format="table(name.basename(), createTime)" 2>/dev/null || \
  echo "No KMS key rings in $REGION"

echo ""
echo "All GCP data is encrypted at rest by default."
echo "CMEK adds customer control over the encryption key."
echo "For GDPR sensitive data, consider CMEK with Cloud KMS."
```

### Lab 2.5 — Compliance Evidence Report

```bash
echo "╔════════════════════════════════════════════════╗"
echo "║   COMPLIANCE EVIDENCE REPORT                   ║"
echo "║   Project: $PROJECT_ID                         ║"
echo "║   Date: $(date +%Y-%m-%d)                      ║"
echo "║   Region: $REGION                              ║"
echo "╚════════════════════════════════════════════════╝"
echo ""

echo "1. DATA RESIDENCY"
echo "   Required: europe-west2 for UK/EU data"
NON_EU=$(gcloud compute instances list --project=$PROJECT_ID \
  --filter="NOT zone:europe-west*" --format="value(name)" 2>/dev/null | wc -l)
echo "   Non-EU instances: $NON_EU"
echo ""

echo "2. ACCESS CONTROL"
echo "   IAM members: $(gcloud projects get-iam-policy $PROJECT_ID \
  --flatten='bindings[].members' --format='value(bindings.members)' 2>/dev/null | sort -u | wc -l)"
echo ""

echo "3. LOGGING"
echo "   Log buckets:"
gcloud logging buckets list --project=$PROJECT_ID \
  --format="csv[no-heading](name, retentionDays)" 2>/dev/null | \
  while IFS=, read -r NAME DAYS; do
    echo "   - $NAME: ${DAYS}d retention"
  done
echo ""

echo "4. ENCRYPTION"
echo "   All GCP storage: encrypted at rest (AES-256)"
echo ""

echo "5. MONITORING"
ALERT_COUNT=$(gcloud alpha monitoring policies list --project=$PROJECT_ID \
  --format="value(name)" 2>/dev/null | wc -l)
echo "   Alert policies: $ALERT_COUNT"
```

### 🧹 Cleanup

```bash
# Delete test log sink and bucket
gcloud logging sinks delete audit-compliance-sink --project=$PROJECT_ID --quiet 2>/dev/null
gcloud logging buckets delete compliance-audit-logs \
  --location=$REGION --project=$PROJECT_ID --quiet 2>/dev/null

echo "Cleanup complete."
```

---

## Part 3 — Revision (15 min)

### Key Concepts
- **Shared Responsibility:** Google secures the infrastructure; you secure your configuration, data, and access
- **SOC 2 Type II:** Trust services — Security, Availability, Confidentiality, Processing, Privacy
- **ISO 27001:** 114 controls across 14 domains — GCP maps to most via services and configurations
- **GDPR (UK/EU):** Data residency (europe-west2), encryption (CMEK for sensitive), logging (365d retention), right to erasure, breach notification (72h)
- **Data residency:** Enforce with org policy `gcp.resourceLocations`
- **Audit log retention:** Default 30 days is NOT compliant — create custom bucket with 365+ days
- **Encryption:** All GCP data encrypted at rest by default; CMEK adds customer control
- **Evidence collection:** Automate compliance reports via gcloud commands

### Essential Commands
```bash
# Check resource locations
gcloud compute instances list --format="table(name, zone)"
gcloud storage buckets list --format="table(name, location)"

# Audit log configuration
gcloud projects get-iam-policy PROJECT_ID --format=json

# Log bucket with long retention
gcloud logging buckets create BUCKET --location=REGION --retention-days=365

# Log sink for audit logs
gcloud logging sinks create SINK DESTINATION --log-filter='logName:"cloudaudit"'

# Resource location org policy
gcloud resource-manager org-policies describe gcp.resourceLocations --project=PROJECT_ID
```

---

## Part 4 — Quiz (15 min)

**Q1.** Your project stores UK customer PII. What three GCP configurations must you verify for GDPR compliance?

<details><summary>Answer</summary>

1. **Data residency:** All storage resources (GCS, Cloud SQL, GCE disks) must be in `europe-west2` (London). Enforce via org policy `gcp.resourceLocations = ["europe-west2"]`.
2. **Audit logging:** Data Access audit logs enabled for all services that touch PII. Retain for 365+ days using a custom log bucket. Export to BigQuery for analysis.
3. **Encryption:** CMEK using Cloud KMS in `europe-west2` for PII data. Enables key rotation control and crypto-shredding (destroy key = data unrecoverable for right-to-erasure).

Bonus: breach notification alerting within 72 hours, data inventory for right-to-erasure requests.

</details>

**Q2.** Default Cloud Logging retention is 30 days. Why is this insufficient for compliance, and how do you fix it?

<details><summary>Answer</summary>

**Why insufficient:**
- SOC 2 requires audit trail for the entire examination period (typically 6-12 months)
- ISO 27001 A.12.4 requires logs "retained for an agreed period"
- GDPR breach investigation may need logs from months ago
- Many regulations require 1-year minimum retention

**How to fix:**
```bash
# Create custom log bucket with 365-day retention
gcloud logging buckets create compliance-logs \
  --location=europe-west2 --retention-days=365

# Route audit logs to it
gcloud logging sinks create compliance-sink \
  logging.googleapis.com/projects/PROJECT/locations/europe-west2/buckets/compliance-logs \
  --log-filter='logName:"cloudaudit.googleapis.com"'
```

Also consider exporting to BigQuery for unlimited retention and SQL analysis.

</details>

**Q3.** An auditor asks you to prove that only authorized users accessed production data in Q3. What evidence do you provide?

<details><summary>Answer</summary>

1. **IAM policy export:** `gcloud projects get-iam-policy` showing who has access and with what roles
2. **Data Access audit logs:** Filtered for the Q3 date range showing every data read/write with `principalEmail`
3. **IAM change history:** Admin Activity logs showing any IAM changes during Q3
4. **IAM Recommender report:** Showing no unused or over-scoped permissions
5. **Access review documentation:** Quarterly review records showing manager sign-off
6. **Org policy evidence:** Resource location constraints, SA key restrictions

Export all to BigQuery, run queries, export as CSV/PDF for the auditor.

</details>

**Q4.** Map three RHDS compliance controls to their GCP equivalents.

<details><summary>Answer</summary>

| RHDS Control | Purpose | GCP Equivalent |
|-------------|---------|---------------|
| `ACI` (Access Control Instructions) | Control who reads/writes directory entries | IAM bindings + conditions |
| `passwordPolicy` objectclass | Enforce password complexity, rotation, lockout | Cloud Identity password policy + 2FA |
| LDAPS (TLS for LDAP) | Encrypt data in transit | Default TLS on all GCP APIs |
| `nsslapd-auditlog` | Track all directory changes | Admin Activity audit logs |
| `nsslapd-accesslog` | Track all read/search operations | Data Access audit logs |
| Replication agreements with TLS | Secure data replication | Multi-region replication (encrypted) |
| `nsDS5ReplicaBindDN` | Control replication credentials | Service account for cross-project access |

The concepts are identical; GCP provides managed equivalents of everything you built manually in RHDS.

</details>
