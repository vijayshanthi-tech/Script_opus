# Day 76 — Least Privilege in Practice: Narrowing Roles & IAM Recommender

> **Week 13 — IAM Deep Dive** | ⏱ 2 hours | Region: `europe-west2`
> Student profile: 6 yrs Linux infra, 3 yrs RHDS LDAP, ACE certified

---

## Part 1 — Concept (30 min)

### 1.1 Principle of Least Privilege

Grant **only the permissions needed** for a specific task — nothing more.

**Linux analogy:**
| Bad Practice | Good Practice |
|-------------|---------------|
| `chmod 777 /var/www` | `chmod 750 /var/www` + correct owner |
| Adding user to `wheel` group | Specific `sudoers` command entries |
| RHDS: `aci: (targetattr="*")(allow all)` | RHDS: `aci: (targetattr="cn||sn")(allow read)` |
| GCP: `roles/editor` on project | GCP: `roles/compute.viewer` + `roles/storage.objectViewer` |

### 1.2 The Problem with Broad Roles

```
  roles/editor — THE DANGEROUS DEFAULT
  ═══════════════════════════════════════
  
  Permissions included: ~5,000+
  ├── compute.instances.create    ← deploy VMs
  ├── compute.instances.delete    ← DELETE VMs
  ├── storage.objects.delete      ← DELETE data
  ├── pubsub.topics.create        ← create resources
  ├── bigquery.datasets.create    ← create datasets
  ├── cloudfunctions.functions.*  ← deploy code
  └── ... thousands more
  
  What the app actually needs:
  ├── storage.objects.get         ← read files
  └── storage.objects.list        ← list files
  
  BLAST RADIUS if compromised:
  ┌─────────────────────────────────────┐
  │ roles/editor:  ENTIRE PROJECT       │
  │ roles/storage.objectViewer: STORAGE │  ← 99.9% smaller
  └─────────────────────────────────────┘
```

### 1.3 IAM Recommender

```
  ┌───────────────────────────────────────────────┐
  │              IAM RECOMMENDER                    │
  ├───────────────────────────────────────────────┤
  │                                                │
  │  Analyzes: 90 days of permission usage         │
  │                                                │
  │  Input:                                        │
  │  ┌─────────────────────────────────┐           │
  │  │ SA: app@project.iam...         │           │
  │  │ Current role: roles/editor      │           │
  │  │ Permissions used:               │           │
  │  │   - storage.objects.get         │           │
  │  │   - storage.objects.list        │           │
  │  │   - logging.logEntries.create   │           │
  │  └─────────────────────────────────┘           │
  │                                                │
  │  Output (Recommendation):                      │
  │  ┌─────────────────────────────────┐           │
  │  │ REPLACE roles/editor WITH:      │           │
  │  │   roles/storage.objectViewer    │           │
  │  │   roles/logging.logWriter       │           │
  │  │                                  │           │
  │  │ Permissions removed: 4,997      │           │
  │  │ Permissions kept:    3          │           │
  │  │ Risk reduction:      99.9%      │           │
  │  └─────────────────────────────────┘           │
  └───────────────────────────────────────────────┘
```

### 1.4 Custom Roles

When no predefined role matches exactly, create a **custom role**:

```
  CUSTOM ROLE CREATION APPROACHES
  ════════════════════════════════

  Approach 1: Start from predefined, remove permissions
  ┌─────────────────────────────────┐
  │ roles/storage.admin             │
  │  - storage.buckets.create       │ ← REMOVE
  │  - storage.buckets.delete       │ ← REMOVE
  │  + storage.objects.get          │ ← KEEP
  │  + storage.objects.list         │ ← KEEP
  │  + storage.objects.create       │ ← KEEP
  └─────────────────────────────────┘

  Approach 2: Build from scratch with exact permissions
  ┌─────────────────────────────────┐
  │ projects/my-proj/roles/appRole  │
  │  + storage.objects.get          │
  │  + storage.objects.list         │
  │  + logging.logEntries.create    │
  └─────────────────────────────────┘

  Approach 3: IAM Recommender suggestion
  ┌─────────────────────────────────┐
  │ Auto-generated from 90 days of  │
  │ actual usage data               │
  └─────────────────────────────────┘
```

> **RHDS parallel:** Custom roles are like writing specific ACIs in RHDS instead of granting `Directory Manager` access. In RHDS, you'd write `aci: (targetattr="mail||telephonenumber")(version 3.0; acl "app-read-contact"; allow (read,search) userdn="ldap:///uid=app,...";)` — only the exact attributes needed.

### 1.5 Role Narrowing Strategy

```
  PROGRESSIVE NARROWING
  ═════════════════════

  Day 0 (Quick start):
    roles/editor  ────────────────────▶  Works but too broad

  Week 1 (First narrowing):
    roles/compute.admin  ─────────────▶  Scoped to compute
    roles/storage.admin  ─────────────▶  Scoped to storage

  Week 4 (After observing usage):
    roles/compute.instanceAdmin.v1  ──▶  Only instance ops
    roles/storage.objectViewer  ──────▶  Only read objects

  Week 12 (IAM Recommender):
    custom/appMinimalRole  ───────────▶  Exact permissions used
```

### 1.6 Testing Role Changes Safely

```
  SAFE ROLE CHANGE WORKFLOW
  ═════════════════════════

  1. AUDIT current permissions used
     └── IAM Recommender or audit logs

  2. ADD new narrow role first
     └── gcloud add-iam-policy-binding (new role)

  3. VERIFY application works
     └── Test all features over 24-48 hours

  4. REMOVE old broad role
     └── gcloud remove-iam-policy-binding (old role)

  5. MONITOR for 7 days
     └── Watch for 403 errors in audit logs

  ⚠ NEVER remove the old role before adding the new one!
```

---

## Part 2 — Hands-On Lab (60 min)

### Prerequisites
```bash
export PROJECT_ID=$(gcloud config get-value project)
export REGION=europe-west2
export ZONE=europe-west2-a
```

### Lab 2.1 — Start with Editor, Observe the Problem

```bash
# Create an "over-privileged" SA
gcloud iam service-accounts create overprivileged-sa \
  --display-name="Over-privileged SA"

export OVERPRIV_SA=overprivileged-sa@${PROJECT_ID}.iam.gserviceaccount.com

# Grant Editor (bad practice — we'll fix this)
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$OVERPRIV_SA" \
  --role="roles/editor"

# See how many permissions Editor provides
echo "--- Permissions in roles/editor ---"
gcloud iam roles describe roles/editor \
  --format="value(includedPermissions)" | tr ';' '\n' | wc -l
```

### Lab 2.2 — Check IAM Recommender Insights

```bash
# List IAM recommendations (may be empty for new SAs)
gcloud recommender recommendations list \
  --project=$PROJECT_ID \
  --location="-" \
  --recommender=google.iam.policy.Recommender \
  --format="table(
    name.basename(),
    primaryImpact.category,
    stateInfo.state,
    description
  )" 2>/dev/null || echo "No recommendations yet (need 90 days of usage data)"

# List IAM insights
gcloud recommender insights list \
  --project=$PROJECT_ID \
  --location="-" \
  --insight-type=google.iam.policy.Insight \
  --format="table(
    name.basename(),
    category,
    stateInfo.state,
    description
  )" 2>/dev/null || echo "No insights yet"
```

### Lab 2.3 — Narrow to Specific Predefined Roles

```bash
# Step 1: Remove Editor and add specific narrow roles
# First, ADD the narrow roles
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$OVERPRIV_SA" \
  --role="roles/storage.objectViewer"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$OVERPRIV_SA" \
  --role="roles/logging.logWriter"

# Step 2: Verify narrow roles are in place
echo "--- Roles for SA after adding narrow roles ---"
gcloud projects get-iam-policy $PROJECT_ID \
  --flatten="bindings[].members" \
  --filter="bindings.members:$OVERPRIV_SA" \
  --format="table(bindings.role)"

# Step 3: NOW remove Editor
gcloud projects remove-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$OVERPRIV_SA" \
  --role="roles/editor"

# Step 4: Verify final state
echo "--- Final roles (should be only narrow roles) ---"
gcloud projects get-iam-policy $PROJECT_ID \
  --flatten="bindings[].members" \
  --filter="bindings.members:$OVERPRIV_SA" \
  --format="table(bindings.role)"
```

### Lab 2.4 — Create a Custom Role

```bash
# Create a custom role with exact permissions
gcloud iam roles create appMinimalReader \
  --project=$PROJECT_ID \
  --title="App Minimal Reader" \
  --description="Read storage objects and write logs only" \
  --permissions="storage.objects.get,storage.objects.list,logging.logEntries.create" \
  --stage=GA

# Describe the custom role
gcloud iam roles describe appMinimalReader \
  --project=$PROJECT_ID

# Replace predefined roles with custom role
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$OVERPRIV_SA" \
  --role="projects/$PROJECT_ID/roles/appMinimalReader"

# Remove the predefined roles
gcloud projects remove-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$OVERPRIV_SA" \
  --role="roles/storage.objectViewer"

gcloud projects remove-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$OVERPRIV_SA" \
  --role="roles/logging.logWriter"

# Verify — should only have the custom role
echo "--- Final: only custom role ---"
gcloud projects get-iam-policy $PROJECT_ID \
  --flatten="bindings[].members" \
  --filter="bindings.members:$OVERPRIV_SA" \
  --format="table(bindings.role)"
```

### Lab 2.5 — Update and Manage Custom Role

```bash
# Add a permission to the custom role
gcloud iam roles update appMinimalReader \
  --project=$PROJECT_ID \
  --add-permissions="storage.buckets.list"

# View updated role
gcloud iam roles describe appMinimalReader \
  --project=$PROJECT_ID --format="yaml(includedPermissions)"

# Disable the role (soft delete — can be re-enabled)
gcloud iam roles update appMinimalReader \
  --project=$PROJECT_ID \
  --stage=DISABLED

# Re-enable
gcloud iam roles update appMinimalReader \
  --project=$PROJECT_ID \
  --stage=GA
```

### 🧹 Cleanup

```bash
# Remove custom role binding
gcloud projects remove-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$OVERPRIV_SA" \
  --role="projects/$PROJECT_ID/roles/appMinimalReader" 2>/dev/null

# Delete custom role
gcloud iam roles delete appMinimalReader --project=$PROJECT_ID --quiet

# Delete service account
gcloud iam service-accounts delete $OVERPRIV_SA --quiet
```

---

## Part 3 — Revision (15 min)

### Key Concepts
- **Least privilege** — grant only what's needed, nothing more
- `roles/editor` grants **5,000+ permissions** — almost never appropriate
- **IAM Recommender** analyses 90 days of usage to suggest narrower roles
- **Custom roles** let you define exact permission sets
- **Safe narrowing:** add new role → verify → remove old role → monitor
- Custom roles can be **project-level** or **org-level**
- Custom role stages: **ALPHA → BETA → GA → DISABLED → DELETED**
- Deleted custom roles can be **undeleted within 7 days**
- Maximum **300 custom roles per org**, **300 per project**

### Essential Commands
```bash
# Check IAM Recommender suggestions
gcloud recommender recommendations list \
  --project=PROJECT --location="-" \
  --recommender=google.iam.policy.Recommender

# Create custom role
gcloud iam roles create ROLE_ID --project=PROJECT \
  --title="TITLE" --permissions="perm1,perm2"

# Update custom role
gcloud iam roles update ROLE_ID --project=PROJECT \
  --add-permissions="perm3"

# Disable custom role
gcloud iam roles update ROLE_ID --project=PROJECT --stage=DISABLED

# Delete custom role
gcloud iam roles delete ROLE_ID --project=PROJECT

# List permissions in a predefined role
gcloud iam roles describe roles/ROLE_NAME
```

---

## Part 4 — Quiz (15 min)

**Q1.** Your team's application SA has `roles/editor`. What's the step-by-step process to narrow it safely?

<details><summary>Answer</summary>

1. **Audit** actual usage via IAM Recommender insights or audit logs (90 days ideal)
2. **Identify** the minimum permissions/roles needed
3. **Add** the narrow roles to the SA first
4. **Test** the application thoroughly (24-48 hours minimum)
5. **Remove** `roles/editor` from the SA
6. **Monitor** audit logs for 7+ days for any 403 errors
7. **Adjust** if needed — add missing permissions to the narrow role

Never remove the broad role before the narrow roles are in place and verified.

</details>

**Q2.** What is the difference between project-level and org-level custom roles?

<details><summary>Answer</summary>

- **Project-level** custom roles: scoped to a single project, can only use permissions available to that project's enabled APIs, useful for application-specific roles. Format: `projects/PROJECT_ID/roles/ROLE_ID`
- **Org-level** custom roles: available across all projects in the organisation, can include permissions from any GCP service, useful for standardised roles. Format: `organizations/ORG_ID/roles/ROLE_ID`
- Limit: 300 custom roles per project, 300 per org.

</details>

**Q3.** The IAM Recommender suggests removing `roles/compute.admin` and replacing it with `roles/compute.viewer`. But the SA needs to restart VMs occasionally. What do you do?

<details><summary>Answer</summary>

The Recommender bases suggestions on observed usage — if no VM restarts happened in the observation window, it won't include those permissions. You should:
1. Accept the recommendation partially
2. Create a **custom role** that includes `roles/compute.viewer` permissions plus `compute.instances.start`, `compute.instances.stop`, and `compute.instances.reset`
3. Or use `roles/compute.instanceAdmin.v1` if you need broader instance management

Always validate recommendations against the full operational requirements, not just observed usage.

</details>

**Q4.** In RHDS, how would you implement least privilege for an application that only needs to read `mail` and `telephoneNumber` attributes?

<details><summary>Answer</summary>

In RHDS, you'd write an ACI like:
```
aci: (targetattr="mail||telephoneNumber")
     (version 3.0; acl "app-read-contact";
      allow (read,search,compare)
      userdn="ldap:///uid=appbind,ou=Services,dc=example,dc=com";)
```

The GCP equivalent is a custom role with only `storage.objects.get` (or whatever specific permissions needed). The principle is identical: enumerate exactly what's allowed, deny everything else by default. Both RHDS ACIs and GCP custom roles follow the same least-privilege pattern of explicit allow lists.

</details>
