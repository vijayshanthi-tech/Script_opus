# Day 88 — Access Review: Quarterly IAM Audit

> **Week 15 — Audit & Compliance** | ⏱ 2 hours | Region: `europe-west2`
> Student profile: 6 yrs Linux infra, 3 yrs RHDS LDAP, ACE certified

---

## Part 1 — Concept (30 min)

### 1.1 Why Access Reviews Matter

```
  THE ACCESS REVIEW LIFECYCLE
  ═══════════════════════════

  ┌─────────────┐    ┌──────────────┐    ┌──────────────┐
  │  ONBOARDING │───▶│  IN-SERVICE  │───▶│  OFFBOARDING │
  │  (Day 1)    │    │  (Ongoing)   │    │  (Last Day)  │
  ├─────────────┤    ├──────────────┤    ├──────────────┤
  │ Grant roles │    │ DRIFT!       │    │ Revoke all   │
  │ per job     │    │ • Extra roles│    │ (if done     │
  │ function    │    │ • Unused SAs │    │  correctly)  │
  └─────────────┘    │ • Stale keys │    └──────────────┘
                     │ • Role creep │
                     └──────────────┘
                            │
                     ┌──────▼──────┐
                     │  QUARTERLY  │
                     │  ACCESS     │
                     │  REVIEW     │
                     └─────────────┘
                            │
     ┌──────────────────────┼─────────────────────┐
     ▼                      ▼                     ▼
  ┌─────────┐     ┌──────────────┐     ┌──────────────┐
  │ Review  │     │ Remove       │     │ Document     │
  │ bindings│     │ unused       │     │ exceptions   │
  └─────────┘     └──────────────┘     └──────────────┘
```

### 1.2 Common Access Drift Problems

| Problem | Example | Risk | Linux Parallel |
|---------|---------|------|---------------|
| Role creep | User got Editor for one task, never removed | Over-privilege | User added to `wheel` for one reboot |
| Stale accounts | Left company, IAM binding remains | Unauthorized access | `/etc/passwd` entry not removed |
| Unused SAs | Created for test, forgotten | Attack surface | Leftover daemon user with SSH key |
| Over-scoped SAs | App SA has Editor, only needs Storage | Blast radius | Service running as root |
| Stale keys | SA key not rotated in 6 months | Credential leak | SSH key without passphrase, never rotated |

### 1.3 IAM Recommender

```
  IAM RECOMMENDER: HOW IT WORKS
  ══════════════════════════════

  ┌──────────────────────────────────────────────────┐
  │  Over 90 days, IAM Recommender:                  │
  │                                                  │
  │  1. Observes actual API calls per member          │
  │  2. Compares granted roles vs used permissions    │
  │  3. Generates recommendations:                   │
  │     "Remove Editor, grant Storage Object Viewer"  │
  │                                                  │
  │  Example:                                        │
  │  ┌─────────────────────────────────────────────┐ │
  │  │ Member: deploy-sa@project.iam.gserviceaccount│ │
  │  │ Current: roles/editor (3,000+ permissions)   │ │
  │  │ Used:    storage.objects.get, .list (2 perms)│ │
  │  │ Suggest: roles/storage.objectViewer (5 perms)│ │
  │  │ Impact:  MEDIUM (removes 2,995 permissions)  │ │
  │  └─────────────────────────────────────────────┘ │
  └──────────────────────────────────────────────────┘
```

### 1.4 Access Review Checklist

```
  QUARTERLY ACCESS REVIEW — 8-STEP CHECKLIST
  ═══════════════════════════════════════════

  □ Step 1: List all IAM bindings (project + org level)
  □ Step 2: Identify external members (non-organization emails)
  □ Step 3: Review IAM recommendations (right-size roles)
  □ Step 4: List all service accounts
  □ Step 5: Find unused SAs (no API calls in 90 days)
  □ Step 6: Find SAs with keys (especially old keys)
  □ Step 7: Review custom roles (still needed? permissions accurate?)
  □ Step 8: Document findings + remediation timeline
```

> **RHDS parallel:** In RHDS, quarterly access reviews mean: dump all ACI entries (`ldapsearch -b "dc=example,dc=com" "(aci=*)"`), check group memberships (`nsGroupDN`), review password policy exceptions, check replication agreements. You'd export to CSV and have managers approve. Same process, different tools.

---

## Part 2 — Hands-On Lab (60 min)

### Prerequisites
```bash
export PROJECT_ID=$(gcloud config get-value project)
export REGION=europe-west2
```

### Lab 2.1 — Full IAM Binding Audit

```bash
echo "=== FULL IAM BINDING AUDIT ==="
echo ""

# Get all project-level IAM bindings
echo "--- Project IAM Bindings ---"
gcloud projects get-iam-policy $PROJECT_ID \
  --format="table(bindings.role, bindings.members.flatten())" 2>/dev/null

# Count bindings per role
echo ""
echo "--- Bindings per Role ---"
gcloud projects get-iam-policy $PROJECT_ID \
  --flatten="bindings[].members" \
  --format="csv(bindings.role)" 2>/dev/null | sort | uniq -c | sort -rn

# Find external members (not in your org domain)
echo ""
echo "--- All IAM Members ---"
gcloud projects get-iam-policy $PROJECT_ID \
  --flatten="bindings[].members" \
  --format="value(bindings.members)" 2>/dev/null | sort -u
```

### Lab 2.2 — Service Account Inventory

```bash
echo "=== SERVICE ACCOUNT INVENTORY ==="
echo ""

# List all SAs in the project
echo "--- All Service Accounts ---"
gcloud iam service-accounts list --project=$PROJECT_ID \
  --format="table(email, displayName, disabled)"

# For each SA, check if it has keys
echo ""
echo "--- SA Key Inventory ---"
for SA in $(gcloud iam service-accounts list --project=$PROJECT_ID \
  --format="value(email)" 2>/dev/null); do
  KEYS=$(gcloud iam service-accounts keys list \
    --iam-account=$SA \
    --managed-by=user \
    --format="value(name)" 2>/dev/null | wc -l)
  if [ "$KEYS" -gt 0 ]; then
    echo "⚠️  $SA has $KEYS user-managed key(s)"
    gcloud iam service-accounts keys list \
      --iam-account=$SA \
      --managed-by=user \
      --format="table(name.basename(), validAfterTime, validBeforeTime)" 2>/dev/null
  fi
done

echo ""
echo "Goal: 0 user-managed keys"
```

### Lab 2.3 — IAM Recommender Review

```bash
echo "=== IAM RECOMMENDER ==="
echo ""

# List IAM recommendations
gcloud recommender recommendations list \
  --recommender=google.iam.policy.Recommender \
  --project=$PROJECT_ID \
  --location=global \
  --format="table(
    name.basename(),
    description,
    stateInfo.state,
    primaryImpact.category
  )" 2>/dev/null || echo "No recommendations available (needs 90 days of data)"

# List IAM insights
echo ""
echo "--- IAM Insights ---"
gcloud recommender insights list \
  --insight-type=google.iam.policy.Insight \
  --project=$PROJECT_ID \
  --location=global \
  --format="table(
    name.basename(),
    description,
    stateInfo.state,
    severity
  )" 2>/dev/null || echo "No insights available"
```

### Lab 2.4 — Find Unused Service Accounts via Audit Logs

```bash
echo "=== UNUSED SA DETECTION ==="
echo ""

# Check each SA for recent activity (last 30 days)
echo "--- SA Activity Check (last 30 days) ---"
for SA in $(gcloud iam service-accounts list --project=$PROJECT_ID \
  --format="value(email)" 2>/dev/null | grep -v "gserviceaccount.com$" | head -10); do
  ACTIVITY=$(gcloud logging read "
    protoPayload.authenticationInfo.principalEmail=\"$SA\"
  " --limit=1 --freshness=30d --project=$PROJECT_ID \
    --format="value(timestamp)" 2>/dev/null)
  
  if [ -z "$ACTIVITY" ]; then
    echo "UNUSED (30d): $SA"
  else
    echo "ACTIVE ($ACTIVITY): $SA"
  fi
done

# Check for SAs with broad roles
echo ""
echo "--- SAs with Broad Roles ---"
gcloud projects get-iam-policy $PROJECT_ID \
  --flatten="bindings[].members" \
  --filter="bindings.members:serviceAccount AND bindings.role:(roles/editor OR roles/owner)" \
  --format="table(bindings.role, bindings.members)" 2>/dev/null
```

### Lab 2.5 — Generate Access Review Report

```bash
echo "╔══════════════════════════════════════╗"
echo "║   QUARTERLY ACCESS REVIEW REPORT     ║"
echo "║   Project: $PROJECT_ID               ║"
echo "║   Date: $(date +%Y-%m-%d)            ║"
echo "╚══════════════════════════════════════╝"
echo ""

echo "1. IAM MEMBER COUNT"
echo "   Total unique members: $(gcloud projects get-iam-policy $PROJECT_ID \
  --flatten='bindings[].members' --format='value(bindings.members)' 2>/dev/null | sort -u | wc -l)"
echo ""

echo "2. SERVICE ACCOUNT COUNT"
echo "   Total SAs: $(gcloud iam service-accounts list --project=$PROJECT_ID \
  --format='value(email)' 2>/dev/null | wc -l)"
echo ""

echo "3. SAs WITH USER-MANAGED KEYS"
KEY_COUNT=0
for SA in $(gcloud iam service-accounts list --project=$PROJECT_ID \
  --format="value(email)" 2>/dev/null); do
  K=$(gcloud iam service-accounts keys list --iam-account=$SA \
    --managed-by=user --format="value(name)" 2>/dev/null | wc -l)
  KEY_COUNT=$((KEY_COUNT + K))
done
echo "   Total user-managed keys: $KEY_COUNT"
echo ""

echo "4. BROAD ROLES IN USE"
gcloud projects get-iam-policy $PROJECT_ID \
  --flatten="bindings[].members" \
  --filter="bindings.role:(roles/editor OR roles/owner)" \
  --format="csv[no-heading](bindings.role, bindings.members)" 2>/dev/null | \
  while IFS=, read -r ROLE MEMBER; do
    echo "   ⚠️  $MEMBER has $ROLE"
  done

echo ""
echo "5. RECOMMENDATIONS"
echo "   Review IAM Recommender in Console:"
echo "   Console → IAM → Recommendations"
```

### 🧹 Cleanup

```bash
# No resources created in this audit lab — only read operations performed
echo "Access review lab used read-only commands."
echo "No cleanup needed."
```

---

## Part 3 — Revision (15 min)

### Key Concepts
- **Access drift** happens naturally: roles accumulate, SAs are forgotten, keys age
- **Quarterly reviews** catch what automation misses: role creep, stale accounts, over-scoped SAs
- **IAM Recommender** uses 90 days of API usage data to suggest right-sized roles
- **Unused SA detection:** check audit logs for SAs with no API calls in 30-90 days
- **User-managed keys** should be zero; every key is a liability
- **Report structure:** member count, SA count, key count, broad roles, recommendations
- **RHDS parallel:** same JML lifecycle, same quarterly process, different tools (ldapsearch vs gcloud)

### Essential Commands
```bash
# Full IAM binding list
gcloud projects get-iam-policy PROJECT_ID

# All SAs and their keys
gcloud iam service-accounts list
gcloud iam service-accounts keys list --iam-account=SA_EMAIL --managed-by=user

# IAM Recommender
gcloud recommender recommendations list \
  --recommender=google.iam.policy.Recommender \
  --project=PROJECT_ID --location=global

# SA activity in audit logs
gcloud logging read 'protoPayload.authenticationInfo.principalEmail="SA_EMAIL"' --limit=1 --freshness=30d
```

---

## Part 4 — Quiz (15 min)

**Q1.** A service account has not made any API calls in 90 days but is bound to a production workload. Should you remove it?

<details><summary>Answer</summary>

**Not immediately.** The SA might be used by a workload that runs quarterly (batch processing, annual reports, disaster recovery). Steps: (1) Check audit logs for the SA over the past year, not just 90 days. (2) Check if the SA is referenced in Terraform, Kubernetes manifests, or CI/CD pipelines. (3) Contact the workload owner. (4) If truly unused, **disable** first (don't delete), wait 30 days, then delete. Disabling is reversible; deletion is not.

</details>

**Q2.** Your access review reveals 15 users with `roles/editor` on the production project. What's your remediation plan?

<details><summary>Answer</summary>

1. **Get IAM recommendations** — Recommender will show actual permissions each user needs
2. **Categorize users:** Developers (need specific resource access), Ops (need monitoring + deployment), Managers (need viewer only)
3. **Replace incrementally:** Start with users who only use read operations — switch to `roles/viewer` + specific roles
4. **Test per user:** Switch one user at a time, monitor for permission denied errors over 1-2 weeks
5. **Document exceptions:** If someone must keep Editor (rare), document why and set a review date
6. **Timeline:** 8-12 weeks for 15 users (1-2 per week) to avoid disruption

</details>

**Q3.** How do you detect and remediate stale SA keys?

<details><summary>Answer</summary>

**Detection:**
```bash
# List all user-managed keys with creation dates
gcloud iam service-accounts keys list --iam-account=SA_EMAIL --managed-by=user
# Keys older than 90 days are stale (validAfterTime field)
```

**Remediation options:**
1. **Delete the key** if the workload should use Workload Identity, metadata server, or SA impersonation
2. **Rotate** if a key is truly needed: create new key, update the workload, delete old key
3. **Set org policy** `constraints/iam.disableServiceAccountKeyCreation` to prevent new keys
4. **Alert** on key creation with log-based metrics (Day 87's lab)

</details>

**Q4.** Compare a GCP quarterly access review to an RHDS directory cleanup.

<details><summary>Answer</summary>

| GCP Access Review | RHDS Directory Cleanup |
|-------------------|----------------------|
| `gcloud projects get-iam-policy` | `ldapsearch -b dc=example,dc=com "(objectclass=*)"` |
| IAM Recommender (automated suggestions) | Manual ACI review / custom scripts |
| Check SA key age | Check `passwordExpirationTime` |
| Unused SAs via audit logs | Unused accounts via `lastLoginTime` |
| `roles/editor` → specific roles | `(all)` ACI → targeted ACI |
| Org policies prevent drift | Password/lockout policies prevent drift |
| Console → IAM → Recommendations | RHDS Console → Access Control |
| Export to BigQuery for tracking | Export to LDIF for tracking |

Key difference: GCP IAM Recommender automates what RHDS requires custom scripts for.

</details>
