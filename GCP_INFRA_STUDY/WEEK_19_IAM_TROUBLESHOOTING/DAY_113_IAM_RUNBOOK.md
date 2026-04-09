# Week 19, Day 113 (Fri) — IAM Runbook

## Today's Objective

Create operational runbooks for common IAM procedures: granting/revoking access, emergency access, service account key rotation, access reviews, and escalation paths. These are living documents for on-call engineers.

**Source:** [IAM Best Practices](https://cloud.google.com/iam/docs/using-iam-securely) | [SA Key Rotation](https://cloud.google.com/iam/docs/key-rotation)

**Deliverable:** A complete IAM operations runbook with copy-paste procedures for each scenario

---

## Part 1: Concept (30 minutes)

### 1.1 Why IAM Runbooks?

```
Linux analogy:

/usr/share/doc/sshd/README         ──►    IAM Runbook
"How to add a user to sudoers"      ──►    "How to grant project access"
"Emergency root password reset"     ──►    "Emergency access procedure"
"SSH key rotation procedure"        ──►    "SA key rotation procedure"
"Quarterly access review process"   ──►    "IAM access review process"
```

### 1.2 Runbook Coverage Map

```
┌──────────────────────────────────────────────────────────┐
│                    IAM RUNBOOK                             │
│                                                           │
│  ┌─────────────┐  ┌─────────────┐  ┌──────────────────┐  │
│  │  Routine    │  │  Emergency  │  │  Periodic        │  │
│  │             │  │             │  │                  │  │
│  │ Grant access│  │ Break-glass │  │ Access review    │  │
│  │ Revoke      │  │ Incident    │  │ Key rotation     │  │
│  │ New SA      │  │ Compromised │  │ Cleanup unused   │  │
│  │ Modify role │  │ SA key      │  │ Audit report     │  │
│  └─────────────┘  └─────────────┘  └──────────────────┘  │
│                                                           │
│  ┌─────────────────────────────────────────────────────┐  │
│  │  Escalation Paths                                    │  │
│  │  L1: Platform team → L2: Security → L3: Management  │  │
│  └─────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────┘
```

### 1.3 Access Request Workflow

```
┌──────────┐     Request      ┌──────────┐     Review     ┌──────────┐
│ Requester│ ───────────────► │  Ticket  │ ─────────────► │ Approver │
│          │  (ServiceNow/    │  System  │  (manager +    │          │
│          │   Jira/etc.)     │          │   data owner)  │          │
└──────────┘                  └──────────┘                └──────┬───┘
                                                                │
                                                         Approved?
                                                          │     │
                                                         Yes    No
                                                          │     │
                                                          ▼     ▼
                                                    ┌──────┐  Denied
                                                    │ Apply │  (feedback)
                                                    │ via TF│
                                                    │ or CLI│
                                                    └──────┘
```

### 1.4 Emergency Access Tiers

| Tier | Scenario | Response | Approval |
|---|---|---|---|
| **Level 1** | Normal access request | TF PR + review | Manager |
| **Level 2** | Urgent (blocking deployment) | CLI grant + retrospective ticket | Tech lead |
| **Level 3** | Incident (production down) | Break-glass SA | Security team (post-hoc) |

### 1.5 Key Rotation Schedule

| Key Type | Rotation Frequency | Method |
|---|---|---|
| SA key (if unavoidable) | Every 90 days | Create new → update consumers → delete old |
| User SSH keys | Every 180 days | OS Login handles automatically |
| API keys | Every 90 days | Regenerate + update secrets |
| Certificates | Before expiry (~30d) | Let's Encrypt / CA |

---

## Part 2: Hands-On Lab (60 minutes)

### Step 1: Build the Operational Runbook (30 min)

```bash
export PROJECT_ID=$(gcloud config get-value project)
mkdir -p iam-runbook && cd iam-runbook

cat > IAM_OPERATIONS_RUNBOOK.md <<'RUNBOOK'
# IAM Operations Runbook

**Version:** 1.0 | **Last Updated:** $(date +%Y-%m-%d) | **Owner:** Platform Team

---

## 1. Grant Access to a Project

### Scenario
A team member needs access to a GCP project.

### Prerequisites
- [ ] Approved access request ticket
- [ ] Verified the minimum required role (not "just give Editor")

### Procedure

```bash
# Step 1: Identify the correct predefined role
# Search available roles:
gcloud iam roles list --filter="name:roles/storage" --format="table(name, title)"

# Step 2: Grant the role (additive — won't affect other bindings)
gcloud projects add-iam-policy-binding PROJECT_ID \
  --member="user:EMAIL@DOMAIN.COM" \
  --role="roles/ROLE_NAME"

# Step 3: Verify
gcloud projects get-iam-policy PROJECT_ID \
  --flatten="bindings[].members" \
  --filter="bindings.members:EMAIL@DOMAIN.COM" \
  --format="table(bindings.role)"

# Step 4: Notify the requester
# Step 5: Update the access request ticket
```

### Common Role Mappings
| Request | Role | Notes |
|---|---|---|
| "I need to view logs" | `roles/logging.viewer` | Read-only |
| "I need to deploy VMs" | `roles/compute.instanceAdmin.v1` | + `roles/iam.serviceAccountUser` |
| "I need to read GCS" | `roles/storage.objectViewer` | Bucket-level is better |
| "I need to query BQ" | `roles/bigquery.dataViewer` + `roles/bigquery.jobUser` | jobUser for running queries |

---

## 2. Revoke Access

### Scenario
A team member has left or no longer needs access.

### Procedure

```bash
# Step 1: Find all roles for the user
gcloud projects get-iam-policy PROJECT_ID \
  --flatten="bindings[].members" \
  --filter="bindings.members:EMAIL@DOMAIN.COM" \
  --format="table(bindings.role, bindings.condition.title)"

# Step 2: Remove each binding
gcloud projects remove-iam-policy-binding PROJECT_ID \
  --member="user:EMAIL@DOMAIN.COM" \
  --role="roles/ROLE_NAME"

# Repeat for each role found in Step 1

# Step 3: Check for bucket/resource-level bindings
gcloud storage buckets get-iam-policy gs://BUCKET_NAME \
  --flatten="bindings[].members" \
  --filter="bindings.members:EMAIL@DOMAIN.COM"

# Step 4: Remove resource-level bindings too
gcloud storage buckets remove-iam-policy-binding gs://BUCKET_NAME \
  --member="user:EMAIL@DOMAIN.COM" \
  --role="roles/ROLE_NAME"

# Step 5: Verify no bindings remain
gcloud asset search-all-iam-policies \
  --query="policy:EMAIL@DOMAIN.COM" \
  --scope="projects/PROJECT_ID" \
  --format="table(resource, policy.bindings.role)"

# Step 6: Update the ticket
```

---

## 3. Service Account Key Rotation

### Scenario
Scheduled rotation of a service account key (if key download is unavoidable).

### Procedure

```bash
SA_EMAIL="SERVICE_ACCOUNT@PROJECT.iam.gserviceaccount.com"

# Step 1: List existing keys
gcloud iam service-accounts keys list \
  --iam-account=${SA_EMAIL} \
  --format="table(name.basename(), validAfterTime, validBeforeTime, keyType)"

# Step 2: Create a new key
gcloud iam service-accounts keys create new-key.json \
  --iam-account=${SA_EMAIL}

echo "New key ID: $(jq -r '.private_key_id' new-key.json)"

# Step 3: Update all consumers
# - Update Secret Manager secret version
# - Update CI/CD pipeline credentials
# - Update any applications using the key
# VERIFY: consumers are working with the new key

# Step 4: Delete the old key (ONLY after verifying new key works!)
OLD_KEY_ID="OLD_KEY_ID_HERE"
gcloud iam service-accounts keys delete ${OLD_KEY_ID} \
  --iam-account=${SA_EMAIL}

# Step 5: Securely delete the new-key.json from your workstation
shred -u new-key.json  # Linux
# Or: Remove-Item new-key.json -Force  # Windows

# Step 6: Update the rotation tracker
```

### Post-Rotation Checklist
- [ ] New key created and distributed
- [ ] All consumers updated and verified
- [ ] Old key deleted from GCP
- [ ] Key file deleted from local machine
- [ ] Rotation logged in tracker

---

## 4. Emergency / Break-Glass Access

### Scenario
Production incident — normal access procedures are too slow.

### Procedure

```bash
# ⚠️  THIS IS AN EMERGENCY PROCEDURE — USE ONLY DURING INCIDENTS

# Step 1: Record the incident ID and reason
INCIDENT_ID="INC-XXXX"
REASON="Production compute instance unreachable, need admin access"

# Step 2: Grant temporary access
gcloud projects add-iam-policy-binding PROJECT_ID \
  --member="user:ENGINEER@DOMAIN.COM" \
  --role="roles/compute.admin" \
  --condition="title=emergency-${INCIDENT_ID},expression=request.time < timestamp(\"$(date -u -d '+4 hours' +%Y-%m-%dT%H:%M:%SZ)\")"

echo "Emergency access granted until: $(date -u -d '+4 hours')"
echo "INCIDENT: $INCIDENT_ID"
echo "REASON: $REASON"

# Step 3: Notify security team
# Step 4: Resolve the incident
# Step 5: Revoke access (or let condition expire)
# Step 6: File retrospective justification within 24h
```

---

## 5. Quarterly Access Review

### Procedure

```bash
# Step 1: Export all IAM bindings
gcloud projects get-iam-policy PROJECT_ID \
  --format=json > iam-policy-$(date +%Y%m%d).json

# Step 2: List all members with broad roles
echo "=== Owners ==="
gcloud projects get-iam-policy PROJECT_ID \
  --flatten="bindings[].members" \
  --filter="bindings.role:roles/owner" \
  --format="value(bindings.members)"

echo "=== Editors ==="
gcloud projects get-iam-policy PROJECT_ID \
  --flatten="bindings[].members" \
  --filter="bindings.role:roles/editor" \
  --format="value(bindings.members)"

# Step 3: List all service accounts
gcloud iam service-accounts list \
  --format="table(email, displayName, disabled)"

# Step 4: Check for SA keys
for sa in $(gcloud iam service-accounts list --format="value(email)"); do
  KEYS=$(gcloud iam service-accounts keys list --iam-account=$sa \
    --filter="keyType=USER_MANAGED" --format="value(name)" 2>/dev/null | wc -l)
  if [ "$KEYS" -gt "0" ]; then
    echo "WARNING: $sa has $KEYS user-managed keys"
  fi
done

# Step 5: Generate review report
# Step 6: Schedule removal of unused access
```

---

## 6. Escalation Paths

| Situation | First Contact | Escalation | Final |
|---|---|---|---|
| Standard access request | Platform team | — | — |
| Urgent access (blocking work) | Tech lead | Platform team | — |
| Production incident | On-call engineer | Security team | Management |
| Suspected compromise | Security team | CISO | Legal |
| Compliance audit request | Platform team | Security team | Compliance |
RUNBOOK
```

### Step 2: Practice the Procedures (25 min)

```bash
# --- Practice: Grant and Revoke ---

# Create a test SA
gcloud iam service-accounts create runbook-test-sa \
  --display-name="Runbook Test SA"

TEST_SA="runbook-test-sa@${PROJECT_ID}.iam.gserviceaccount.com"

# Grant access (following runbook Step 1)
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
  --member="serviceAccount:${TEST_SA}" \
  --role="roles/storage.objectViewer"

# Verify
gcloud projects get-iam-policy ${PROJECT_ID} \
  --flatten="bindings[].members" \
  --filter="bindings.members:${TEST_SA}" \
  --format="table(bindings.role)"

# Grant with time-based condition (following emergency procedure)
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
  --member="serviceAccount:${TEST_SA}" \
  --role="roles/compute.viewer" \
  --condition="title=temp-lab-access,expression=request.time < timestamp(\"2026-04-09T00:00:00Z\")"

# Verify conditional binding
gcloud projects get-iam-policy ${PROJECT_ID} \
  --flatten="bindings[].members" \
  --filter="bindings.members:${TEST_SA}" \
  --format="table(bindings.role, bindings.condition.title)"

# Revoke all (following runbook Step 2)
gcloud projects remove-iam-policy-binding ${PROJECT_ID} \
  --member="serviceAccount:${TEST_SA}" \
  --role="roles/storage.objectViewer"

gcloud projects remove-iam-policy-binding ${PROJECT_ID} \
  --member="serviceAccount:${TEST_SA}" \
  --role="roles/compute.viewer" \
  --condition="title=temp-lab-access,expression=request.time < timestamp(\"2026-04-09T00:00:00Z\")"

# Verify clean
echo "Remaining bindings (should be empty):"
gcloud projects get-iam-policy ${PROJECT_ID} \
  --flatten="bindings[].members" \
  --filter="bindings.members:${TEST_SA}" \
  --format="table(bindings.role)"
```

### Step 3: Clean Up (5 min)

```bash
gcloud iam service-accounts delete ${TEST_SA} --quiet
cd ~
rm -rf iam-runbook
```

---

## Part 3: Revision (15 minutes)

- **Runbooks are living documents** — update after every incident that reveals a gap
- **Grant access** — always use additive `add-iam-policy-binding`, verify with `get-iam-policy`
- **Revoke access** — check ALL levels (project, folder, bucket, resource), use `search-all-iam-policies`
- **Key rotation** — create new → update consumers → verify → delete old → shred local key
- **Emergency access** — time-bound conditions, mandatory retrospective ticket
- **Quarterly review** — export policy, flag `roles/editor` / `roles/owner`, check SA keys

### Key Commands
```bash
gcloud projects add-iam-policy-binding PROJECT --member=M --role=R
gcloud projects remove-iam-policy-binding PROJECT --member=M --role=R
gcloud projects get-iam-policy PROJECT --flatten="bindings[].members"
gcloud asset search-all-iam-policies --query="policy:USER"
gcloud iam service-accounts keys list --iam-account=SA
```

---

## Part 4: Quiz (15 minutes)

**Q1:** A developer asks for "Editor access to the project." What should you do before granting?
<details><summary>Answer</summary><b>Do NOT grant Editor.</b> Ask: "What specific tasks do you need to perform?" Then map to the minimum predefined roles. Editor includes write access to <b>everything</b> — storage, compute, networking, IAM. If they need to deploy VMs, grant <code>roles/compute.instanceAdmin.v1</code> + <code>roles/iam.serviceAccountUser</code>. If they need to read logs, grant <code>roles/logging.viewer</code>. Document the approved roles in the ticket. Like giving someone <code>sudo ALL</code> when they only need <code>sudo systemctl restart nginx</code>.</details>

**Q2:** During an incident, you need to grant emergency admin access. What safeguards should be in place?
<details><summary>Answer</summary>
1. <b>Time-bound condition</b> — auto-expire in 4h: <code>--condition="expression=request.time < timestamp(\"...\")"</code><br>
2. <b>Record incident ID</b> — link the access to a tracked incident<br>
3. <b>Notify security team</b> — they should know about emergency grants<br>
4. <b>Retrospective justification</b> — file within 24h, reviewed by security<br>
5. <b>Explicit revocation</b> — don't rely only on condition expiry; revoke when incident resolved<br>
Emergency access should be auditable, temporary, and justified.
</details>

**Q3:** It's quarterly access review time. What are the top 3 things to check?
<details><summary>Answer</summary>
1. <b>Broad roles</b>: Who has <code>roles/owner</code> or <code>roles/editor</code>? Can these be narrowed?<br>
2. <b>Stale access</b>: Are there members who haven't used their access in 90+ days? (Use IAM Recommender)<br>
3. <b>Service account keys</b>: Do any SAs have user-managed keys? Can these be replaced with WIF/impersonation?<br>
Also check: disabled SAs still bound, contractor access past contract end dates, groups with overly broad membership.
</details>

**Q4:** You need to revoke access for an ex-employee. How do you ensure they have NO remaining access?
<details><summary>Answer</summary>
1. Remove project-level bindings: <code>gcloud projects get-iam-policy</code> and remove each role<br>
2. Check resource-level bindings: <code>gcloud asset search-all-iam-policies --query="policy:EMAIL"</code> across all projects<br>
3. Check group memberships: remove from all Google Groups that have GCP access<br>
4. Check folder/org-level bindings: inherited roles from above the project<br>
5. Revoke OAuth tokens: <code>gcloud auth revoke EMAIL</code> (if you have admin access)<br>
6. Check external identity providers: remove from IdP if using SSO<br>
One project-level check is NOT sufficient — access can be inherited or bound at resource level.
</details>
