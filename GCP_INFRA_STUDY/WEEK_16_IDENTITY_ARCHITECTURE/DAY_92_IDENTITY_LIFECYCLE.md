# Day 92 — Identity Lifecycle: Joiners, Movers, Leavers

> **Week 16 — Identity Architecture** | ⏱ 2 hours | Region: `europe-west2`
> Student profile: 6 yrs Linux infra, 3 yrs RHDS LDAP, ACE certified

---

## Part 1 — Concept (30 min)

### 1.1 The JML Framework

```
  JOINERS → MOVERS → LEAVERS (JML) LIFECYCLE
  ═══════════════════════════════════════════

  ┌──────────────┐     ┌──────────────┐     ┌──────────────┐
  │   JOINER     │────▶│   MOVER      │────▶│   LEAVER     │
  │   (Day 1)    │     │  (Transfer)  │     │  (Last Day)  │
  ├──────────────┤     ├──────────────┤     ├──────────────┤
  │ • Create     │     │ • Remove old │     │ • Suspend    │
  │   account    │     │   group/roles│     │   account    │
  │ • Add to     │     │ • Add new    │     │ • Revoke     │
  │   groups     │     │   group/roles│     │   sessions   │
  │ • Assign     │     │ • Transfer   │     │ • Remove     │
  │   roles      │     │   ownership  │     │   all roles  │
  │ • Set up     │     │ • Update     │     │ • Disable    │
  │   MFA/2FA    │     │   metadata   │     │   SAs owned  │
  │ • Device     │     │              │     │ • Transfer   │
  │   enrollment │     │              │     │   resources  │
  └──────────────┘     └──────────────┘     └──────────────┘
        │                    │                     │
        └────────────────────┼─────────────────────┘
                             ▼
                     ┌──────────────┐
                     │  AUDIT TRAIL │
                     │  Log every   │
                     │  change      │
                     └──────────────┘
```

### 1.2 RHDS vs GCP Identity Lifecycle

| Stage | RHDS Action | GCP Action |
|-------|-------------|------------|
| **Joiner** | `ldapadd` entry under `ou=People` | Create user in Cloud Identity / Google Workspace |
| | Add to `groupOfNames` | Add to Google Group |
| | Set ACI for the user's OU | Add IAM binding at folder/project level |
| | Set `passwordPolicy` subentry | Configure MFA, password policy in Admin |
| **Mover** | `ldapmodify` to change `ou` | Move to new Google Group, update IAM bindings |
| | Remove from old group | `gcloud identity groups memberships delete` |
| | Add to new group | `gcloud identity groups memberships add` |
| | Update `manager` attribute | Update in Cloud Identity directory |
| **Leaver** | `nsAccountLock: true` | Suspend user in Cloud Identity |
| | Remove from all groups | Remove all group memberships |
| | Delete entry after 30 days | Delete account after retention period |
| | Archive mailbox | Google Vault / Takeout transfer |

### 1.3 Automation Architecture

```
  AUTOMATED JML PIPELINE
  ══════════════════════

  ┌──────────────┐     ┌───────────────┐     ┌───────────────┐
  │  HR SYSTEM   │────▶│  EVENT QUEUE  │────▶│  AUTOMATION   │
  │  (source of  │     │  (Pub/Sub or  │     │  (Cloud       │
  │   truth)     │     │   webhook)    │     │   Function)   │
  └──────────────┘     └───────────────┘     └───────┬───────┘
                                                     │
                        ┌────────────────────────────┼┐
                        ▼                            ▼
                ┌──────────────┐          ┌──────────────────┐
                │ Cloud        │          │ IAM              │
                │ Identity     │          │ (roles, groups,  │
                │ (create/     │          │  project access) │
                │  suspend)    │          │                  │
                └──────────────┘          └──────────────────┘
                                                     │
                                              ┌──────▼──────┐
                                              │ AUDIT LOG   │
                                              │ (every      │
                                              │  action)    │
                                              └─────────────┘

  RHDS EQUIVALENT:
  ┌──────────────┐     ┌───────────────┐     ┌───────────────┐
  │  HR SYSTEM   │────▶│  CSV/LDIF     │────▶│  CRON SCRIPT  │
  │              │     │  export       │     │  (ldapmodify)  │
  └──────────────┘     └───────────────┘     └───────────────┘
```

### 1.4 Leaver Checklist: Critical Steps

```
  LEAVER PROCESS — WHAT TO REVOKE
  ═══════════════════════════════

  IMMEDIATE (Same day):
  ┌────────────────────────────────────────────────┐
  │ □ Suspend Cloud Identity account               │
  │ □ Revoke all active sessions (OAuth tokens)    │
  │ □ Remove from all Google Groups                │
  │ □ Reset Google Workspace app passwords          │
  │ □ Wipe enrolled mobile devices                 │
  └────────────────────────────────────────────────┘

  WITHIN 24 HOURS:
  ┌────────────────────────────────────────────────┐
  │ □ Remove all IAM bindings (all projects)       │
  │ □ Disable any SAs the user owned               │
  │ □ Transfer Drive/Docs ownership                │
  │ □ Transfer resource ownership (GCE, GCS, etc.) │
  │ □ Rotate any shared credentials user knew       │
  └────────────────────────────────────────────────┘

  WITHIN 30 DAYS:
  ┌────────────────────────────────────────────────┐
  │ □ Delete Cloud Identity account                │
  │ □ Archive mailbox data (Google Vault)          │
  │ □ Delete user-owned SAs (after workload check) │
  │ □ Final audit log review                       │
  └────────────────────────────────────────────────┘
```

> **RHDS parallel:** In RHDS leavers, you'd: set `nsAccountLock: true`, remove from all `groupOfNames`, delete any `userCertificate` attributes, run `ldapdelete` after 30 days, and archive the entry in LDIF format. The GCP process is the same workflow, just different APIs.

---

## Part 2 — Hands-On Lab (60 min)

### Prerequisites
```bash
export PROJECT_ID=$(gcloud config get-value project)
export REGION=europe-west2
```

### Lab 2.1 — Simulate Joiner Process

```bash
echo "=== JOINER SIMULATION ==="
echo ""
echo "In production, users are created in Cloud Identity or Google Workspace."
echo "We'll simulate with a service account (same lifecycle concepts)."
echo ""

# Step 1: Create identity (≈ ldapadd)
echo "--- Step 1: Create identity ---"
gcloud iam service-accounts create joiner-alice-sa \
  --display-name="Alice Thompson (Joiner - SRE Team)" \
  --project=$PROJECT_ID

export ALICE_SA=joiner-alice-sa@${PROJECT_ID}.iam.gserviceaccount.com
echo "Created: $ALICE_SA"

# Step 2: Assign role (≈ add ACI allowing access)
echo ""
echo "--- Step 2: Assign initial role (SRE needs Monitoring Viewer) ---"
gcloud projects add-iam-binding $PROJECT_ID \
  --role="roles/monitoring.viewer" \
  --member="serviceAccount:$ALICE_SA" \
  --condition=None 2>/dev/null | tail -3

# Step 3: Assign additional role
echo ""
echo "--- Step 3: Assign Compute Viewer (view VMs) ---"
gcloud projects add-iam-binding $PROJECT_ID \
  --role="roles/compute.viewer" \
  --member="serviceAccount:$ALICE_SA" \
  --condition=None 2>/dev/null | tail -3

# Verify all bindings (≈ ldapsearch for user's effective ACIs)
echo ""
echo "--- Verify Alice's access (≈ ldapsearch effective rights) ---"
gcloud projects get-iam-policy $PROJECT_ID \
  --flatten="bindings[].members" \
  --filter="bindings.members:$ALICE_SA" \
  --format="table(bindings.role, bindings.members)" 2>/dev/null
```

### Lab 2.2 — Simulate Mover Process

```bash
echo "=== MOVER SIMULATION ==="
echo "Alice transfers from SRE to Security team."
echo ""

# Step 1: Remove old role (≈ remove from old group)
echo "--- Step 1: Remove Compute Viewer (no longer SRE) ---"
gcloud projects remove-iam-binding $PROJECT_ID \
  --role="roles/compute.viewer" \
  --member="serviceAccount:$ALICE_SA" 2>/dev/null | tail -3

# Step 2: Add new role (≈ add to new group)
echo ""
echo "--- Step 2: Add Security Reviewer (new team role) ---"
gcloud projects add-iam-binding $PROJECT_ID \
  --role="roles/iam.securityReviewer" \
  --member="serviceAccount:$ALICE_SA" \
  --condition=None 2>/dev/null | tail -3

# Step 3: Keep shared role (monitoring is used by both teams)
echo ""
echo "--- Monitoring Viewer stays (shared across teams) ---"

# Verify updated bindings
echo ""
echo "--- Alice's updated access after team transfer ---"
gcloud projects get-iam-policy $PROJECT_ID \
  --flatten="bindings[].members" \
  --filter="bindings.members:$ALICE_SA" \
  --format="table(bindings.role:label=ROLE, bindings.members:label=IDENTITY)" 2>/dev/null
```

### Lab 2.3 — Simulate Leaver Process

```bash
echo "=== LEAVER SIMULATION ==="
echo "Alice is leaving the company."
echo ""

# Step 1: IMMEDIATE — Disable the account (≈ nsAccountLock: true)
echo "--- Step 1: Disable account (IMMEDIATE) ---"
gcloud iam service-accounts disable $ALICE_SA
echo "✓ Account disabled (can no longer authenticate)"

# Step 2: Remove ALL IAM bindings (≈ remove from all groups)
echo ""
echo "--- Step 2: Remove all IAM bindings ---"
for ROLE in $(gcloud projects get-iam-policy $PROJECT_ID \
  --flatten="bindings[].members" \
  --filter="bindings.members:$ALICE_SA" \
  --format="value(bindings.role)" 2>/dev/null); do
  echo "Removing: $ROLE"
  gcloud projects remove-iam-binding $PROJECT_ID \
    --role="$ROLE" \
    --member="serviceAccount:$ALICE_SA" 2>/dev/null
done
echo "✓ All roles removed"

# Step 3: Verify no access remains
echo ""
echo "--- Step 3: Verify no access remains ---"
REMAINING=$(gcloud projects get-iam-policy $PROJECT_ID \
  --flatten="bindings[].members" \
  --filter="bindings.members:$ALICE_SA" \
  --format="value(bindings.role)" 2>/dev/null | wc -l)
echo "Remaining bindings: $REMAINING (should be 0)"

# Step 4: Check audit trail
echo ""
echo "--- Step 4: Audit trail of leaver process ---"
gcloud logging read "
  protoPayload.methodName=(\"SetIamPolicy\" OR \"DisableServiceAccount\")
  protoPayload.request.resource:\"joiner-alice-sa\"
" --limit=5 --freshness=1h --project=$PROJECT_ID \
  --format="table(timestamp, protoPayload.methodName:label=ACTION)" 2>/dev/null || \
  echo "Audit entries may take a few minutes to appear"
```

### Lab 2.4 — Leaver: Final Deletion (After Retention Period)

```bash
echo "=== LEAVER FINAL STEP: DELETE AFTER 30 DAYS ==="
echo ""
echo "In production, wait 30 days before deletion."
echo "This allows rollback if the departure is reversed."
echo ""

# Final deletion (≈ ldapdelete)
echo "--- Deleting service account (≈ ldapdelete uid=alice,...) ---"
gcloud iam service-accounts delete $ALICE_SA --quiet 2>/dev/null && \
  echo "✓ Account permanently deleted" || \
  echo "Account already deleted or doesn't exist"

# Verify
echo ""
echo "--- Final verification ---"
gcloud iam service-accounts describe $ALICE_SA 2>&1 || true
echo ""
echo "Account no longer exists. Leaver process complete."
```

### Lab 2.5 — Build Leaver Automation Script

```bash
echo "=== LEAVER AUTOMATION SCRIPT ==="
cat << 'SCRIPT'
#!/bin/bash
# leaver-process.sh — Automate account off-boarding
# Usage: ./leaver-process.sh <sa-email-or-user-email> <project-id>

set -euo pipefail

IDENTITY=$1
PROJECT_ID=$2

echo "╔════════════════════════════════════════╗"
echo "║   LEAVER PROCESS: $IDENTITY"
echo "║   Project: $PROJECT_ID"
echo "║   Date: $(date +%Y-%m-%d_%H:%M:%S)"
echo "╚════════════════════════════════════════╝"

# Step 1: Disable
echo ""
echo "Step 1: Disabling account..."
if [[ "$IDENTITY" == *"gserviceaccount.com" ]]; then
  gcloud iam service-accounts disable "$IDENTITY"
else
  echo "For user accounts, suspend via Cloud Identity Admin Console"
fi

# Step 2: Remove all IAM bindings
echo ""
echo "Step 2: Removing IAM bindings..."
MEMBER_TYPE="serviceAccount"
[[ "$IDENTITY" != *"gserviceaccount.com" ]] && MEMBER_TYPE="user"

for ROLE in $(gcloud projects get-iam-policy "$PROJECT_ID" \
  --flatten="bindings[].members" \
  --filter="bindings.members:$IDENTITY" \
  --format="value(bindings.role)" 2>/dev/null); do
  echo "  Removing: $ROLE"
  gcloud projects remove-iam-binding "$PROJECT_ID" \
    --role="$ROLE" \
    --member="${MEMBER_TYPE}:${IDENTITY}" 2>/dev/null
done

# Step 3: List any owned SAs (for users)
echo ""
echo "Step 3: Check for owned service accounts..."
echo "  Review: Any SAs created by this identity should be transferred or disabled."

# Step 4: Summary
echo ""
echo "═══ COMPLETE ═══"
echo "Account disabled, all roles removed."
echo "Schedule account deletion for: $(date -d '+30 days' +%Y-%m-%d 2>/dev/null || echo '30 days from now')"
SCRIPT

echo ""
echo "Save as leaver-process.sh and use for off-boarding."
```

### 🧹 Cleanup

```bash
# The SA was already deleted in Lab 2.4
# Verify cleanup
gcloud iam service-accounts list --project=$PROJECT_ID \
  --filter="email:joiner-alice" --format="value(email)" 2>/dev/null | \
  xargs -I {} gcloud iam service-accounts delete {} --quiet 2>/dev/null

echo "Cleanup complete."
```

---

## Part 3 — Revision (15 min)

### Key Concepts
- **JML (Joiners, Movers, Leavers)** — the three stages of identity lifecycle management
- **Joiner:** Create account → add to groups → assign roles → enable MFA
- **Mover:** Remove old roles → add new roles → transfer ownership → update metadata
- **Leaver:** Disable immediately → remove all roles → wait retention → delete
- **Never delete on day 1** — disable first, delete after 30-day retention
- **Automation:** HR event → Pub/Sub → Cloud Function → Cloud Identity + IAM APIs
- **RHDS equivalent:** `ldapadd` (joiner), `ldapmodify` groups (mover), `nsAccountLock` + `ldapdelete` (leaver)
- **Audit every step** — every JML action generates audit log entries

### Essential Commands
```bash
# Joiner: Create and grant
gcloud iam service-accounts create NAME --display-name="DESC"
gcloud projects add-iam-binding PROJECT --role=ROLE --member=serviceAccount:EMAIL

# Mover: Remove old, add new
gcloud projects remove-iam-binding PROJECT --role=OLD_ROLE --member=MEMBER
gcloud projects add-iam-binding PROJECT --role=NEW_ROLE --member=MEMBER

# Leaver: Disable, remove all, then delete
gcloud iam service-accounts disable SA_EMAIL
# Remove all bindings (loop)
gcloud iam service-accounts delete SA_EMAIL  # After retention period
```

---

## Part 4 — Quiz (15 min)

**Q1.** An employee transfers from the Dev team to the Security team on Monday. By Friday, they report "permission denied" when running security scans. What happened and how do you fix it?

<details><summary>Answer</summary>

**What happened:** The mover process likely removed the Dev roles but failed to add the Security roles. Common causes:
1. The mover script/process removed old roles but errored before adding new ones
2. The Security role was added at the wrong scope (project vs folder)
3. The role was added but needs propagation time (rare, usually instant)

**How to fix:**
1. Check current bindings: `gcloud projects get-iam-policy PROJECT --filter="bindings.members:USER"`
2. Check audit logs for the transfer: look for `SetIamPolicy` entries around Monday
3. Grant the Security role: `gcloud projects add-iam-binding PROJECT --role=roles/iam.securityReviewer --member=user:EMAIL`
4. Fix the mover process: add transaction-like logic (verify new roles before removing old ones)

</details>

**Q2.** Why is "disable first, delete after 30 days" better than immediate account deletion?

<details><summary>Answer</summary>

1. **Reversibility:** If the employee return is reversed (rescinded resignation, contract extension), re-enabling is instant. Re-creating is complex.
2. **Resource ownership:** Deleted accounts lose ownership of resources. You need time to transfer GCS buckets, GCE instances, BigQuery datasets.
3. **Investigation:** If the leaver was involved in a security incident, you need the account intact to investigate audit logs tied to it.
4. **Data retention:** Some compliance frameworks require maintaining the account association for audit trail integrity.
5. **Group membership recovery:** Re-adding to all the right groups is error-prone if done from scratch.

**RHDS equivalent:** Same reason you'd `nsAccountLock: true` before `ldapdelete` — you keep the DN intact for replication, referential integrity, and rollback.

</details>

**Q3.** Design a simple automated leaver process using GCP services.

<details><summary>Answer</summary>

```
HR System → Pub/Sub topic (leaver-events)
                    │
                    ▼
           Cloud Function (leaver-handler)
                    │
        ┌───────────┼───────────┐
        ▼           ▼           ▼
   Suspend in    Remove all   Send Slack
   Cloud Identity IAM bindings notification
        │           │           │
        └───────────┼───────────┘
                    ▼
              Audit log entry
              (automatic)
```

Components:
- **Pub/Sub topic:** Receives leaver event JSON from HR
- **Cloud Function:** Python function calling Cloud Identity Admin SDK + IAM API
- **Cloud Scheduler:** 30-day delayed job to trigger final account deletion
- **Monitoring:** Alert if leaver function fails (critical — stale accounts are security risk)

</details>

**Q4.** In RHDS, you used `nsRoleDN` and `nsAccountLock` for lifecycle management. Map these to GCP.

<details><summary>Answer</summary>

| RHDS Attribute | Purpose | GCP Equivalent |
|-------------|---------|---------------|
| `nsRoleDN` | Define managed/filtered role for dynamic groups | Google Group with dynamic membership rules |
| `nsAccountLock: true` | Disable account (cannot bind) | `gcloud iam service-accounts disable` or Cloud Identity suspend |
| `nsAccountLock: false` | Re-enable account | `gcloud iam service-accounts enable` or unsuspend |
| `memberOf` (computed) | Show group memberships | `gcloud identity groups memberships search-transitive-memberships` |
| `passwordExpirationTime` | Force password change | Cloud Identity password policy |
| `nsIdleTimeout` | Session timeout | Session control policies in BeyondCorp |
| `nsLookThroughLimit` | Query limits | IAM quotas + API rate limits |

Key difference: RHDS attributes are per-entry in the DIT. GCP equivalents are API-driven and policy-based.

</details>
