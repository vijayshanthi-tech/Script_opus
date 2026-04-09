# Day 77 — IAM Troubleshooting Steps: Systematic Approach

> **Week 13 — IAM Deep Dive** | ⏱ 2 hours | Region: `europe-west2`
> Student profile: 6 yrs Linux infra, 3 yrs RHDS LDAP, ACE certified

---

## Part 1 — Concept (30 min)

### 1.1 The Systematic IAM Troubleshooting Framework

A repeatable, documented approach to diagnosing IAM issues — treat it like a runbook.

**Linux analogy:** Just as you follow a systematic approach to debug access issues (`ls -la` → `getfacl` → `namei -l` → SELinux → audit log), GCP IAM needs the same structured methodology.

### 1.2 The 6-Step IAM Diagnostic Checklist

```
  ┌──────────────────────────────────────────────────────┐
  │       IAM DIAGNOSTIC CHECKLIST (6 STEPS)              │
  ├──────────────────────────────────────────────────────┤
  │                                                       │
  │  STEP 1: CHECK THE ROLE                               │
  │  ──────────────────────                               │
  │  □ What role does the principal have?                  │
  │  □ Does that role include the needed permission?       │
  │  □ Is it a basic, predefined, or custom role?          │
  │  □ Could the role have been recently modified?         │
  │                                                       │
  │  STEP 2: CHECK THE LEVEL                              │
  │  ──────────────────────                               │
  │  □ At which level is the role granted?                 │
  │  □ Is the resource in the same project/folder/org?     │
  │  □ Does inheritance apply?                             │
  │  □ Is the resource in a different project?             │
  │                                                       │
  │  STEP 3: CHECK CONDITIONS                             │
  │  ────────────────────────                             │
  │  □ Is the binding conditional?                         │
  │  □ Has the condition expired (time-based)?             │
  │  □ Does the resource match tag conditions?             │
  │  □ Is the request from an allowed IP/network?          │
  │                                                       │
  │  STEP 4: CHECK DENY POLICIES                          │
  │  ──────────────────────────                           │
  │  □ Are deny policies attached at any level?            │
  │  □ Does a deny rule match the permission + principal?  │
  │  □ Check org → folder → project for deny policies      │
  │                                                       │
  │  STEP 5: CHECK ORG POLICIES                           │
  │  ──────────────────────────                           │
  │  □ Is an org policy constraint restricting actions?    │
  │  □ Common: vmExternalIpAccess, storagePublicAccess     │
  │  □ Org policies override IAM (different system)        │
  │                                                       │
  │  STEP 6: CHECK CONTEXT                                │
  │  ────────────────────                                 │
  │  □ Is the API enabled?                                 │
  │  □ Has the quota been exceeded?                        │
  │  □ Is there a VPC Service Controls perimeter?          │
  │  □ Propagation delay (< 7 minutes)?                    │
  └──────────────────────────────────────────────────────┘
```

### 1.3 Decision Tree for Common Errors

```
  ERROR: "Permission 'X' denied on resource 'Y'"
  ═══════════════════════════════════════════════

  ┌─ Does principal have ANY role on the project?
  │  ├─ NO → Grant appropriate role
  │  └─ YES
  │     ├─ Does the role include permission X?
  │     │  ├─ NO → Wrong role, find correct one:
  │     │  │       gcloud iam roles list --filter="includedPermissions:X"
  │     │  └─ YES
  │     │     ├─ Is role at the right level?
  │     │     │  ├─ NO → Re-bind at correct level
  │     │     │  └─ YES
  │     │     │     ├─ Is binding conditional?
  │     │     │     │  ├─ YES → Check condition still valid
  │     │     │     │  └─ NO
  │     │     │     │     ├─ Deny policy?
  │     │     │     │     │  ├─ YES → Remove deny or add exception
  │     │     │     │     │  └─ NO
  │     │     │     │     │     ├─ Org policy?
  │     │     │     │     │     │  ├─ YES → Contact org admin
  │     │     │     │     │     │  └─ NO → Check VPC-SC / propagation
  │     │     │     │     │     └─────────────────────────────────────
  └──────────────────────────────────────────────────────────────────
```

### 1.4 Common Error Patterns and Solutions

```
┌────────────────────────────────────────────────────────────────────┐
│ ERROR MESSAGE                    │ LIKELY CAUSE         │ FIX      │
├──────────────────────────────────┼──────────────────────┼──────────┤
│ "Permission compute.instances.   │ Missing role         │ Grant    │
│  create denied"                  │                      │ compute  │
│                                  │                      │ .admin   │
├──────────────────────────────────┼──────────────────────┼──────────┤
│ "The caller does not have        │ SA has no role       │ Bind     │
│  permission"                     │ on this resource     │ role at  │
│                                  │                      │ right    │
│                                  │                      │ level    │
├──────────────────────────────────┼──────────────────────┼──────────┤
│ "Request had insufficient        │ OAuth scope too      │ Use      │
│  authentication scopes"          │ narrow               │ --scopes │
│                                  │                      │ cloud-   │
│                                  │                      │ platform │
├──────────────────────────────────┼──────────────────────┼──────────┤
│ "Constraint 'X' violated"        │ Org policy blocks    │ Contact  │
│                                  │ the action           │ org admin│
├──────────────────────────────────┼──────────────────────┼──────────┤
│ "API not enabled"                │ Service not active   │ gcloud   │
│                                  │                      │ services │
│                                  │                      │ enable   │
├──────────────────────────────────┼──────────────────────┼──────────┤
│ "Request is prohibited by        │ VPC Service Controls │ Check    │
│  organization's policy"          │ perimeter            │ VPC-SC   │
└──────────────────────────────────┴──────────────────────┴──────────┘
```

### 1.5 Documenting IAM Decisions

```
  IAM DECISION LOG (Template)
  ════════════════════════════

  Date:        2026-04-08
  Requester:   alice@company.com
  Resource:    project/prod-web
  Action:      Grant access to manage VMs
  
  Decision:
  ┌─────────────────────────────────────────────┐
  │ Role granted:  roles/compute.instanceAdmin  │
  │ Level:         project (prod-web)           │
  │ Condition:     None                         │
  │ Justification: Alice needs to restart VMs   │
  │                for deployment pipeline       │
  │ Approved by:   bob@company.com (team lead)  │
  │ Review date:   2026-07-08 (90 days)         │
  │ Ticket:        OPS-1234                     │
  └─────────────────────────────────────────────┘
  
  Rejected alternatives:
  - roles/editor: too broad (5000+ permissions)
  - roles/compute.admin: includes network/firewall (not needed)
```

> **RHDS parallel:** This is like the ACI documentation you'd maintain for RHDS — every access control decision should be traceable to a request, an approval, and a review date. In LDAP, you document who has bind access and why. Same principle in cloud.

### 1.6 Tracking Error Patterns Over Time

```
  INCIDENT TRACKING TABLE
  ═══════════════════════
  
  Week │ 403 Count │ Root Cause           │ Resolution
  ─────┼───────────┼──────────────────────┼─────────────────
  W1   │ 12        │ Dev using wrong SA   │ Documented SA usage
  W2   │ 8         │ Role at wrong level  │ Re-bound at project
  W3   │ 3         │ Expired condition    │ Updated expiry
  W4   │ 1         │ New API not enabled  │ Enabled API
  W5   │ 0         │ —                    │ Stable ✓
  
  TREND: Declining → IAM hygiene improving
```

---

## Part 2 — Hands-On Lab (60 min)

### Prerequisites
```bash
export PROJECT_ID=$(gcloud config get-value project)
export REGION=europe-west2
export ZONE=europe-west2-a
```

### Lab 2.1 — Build the Diagnostic Script

```bash
# Create an IAM diagnostic script
cat > /tmp/iam-diagnose.sh << 'SCRIPT'
#!/bin/bash
# IAM Diagnostic Tool
# Usage: ./iam-diagnose.sh <principal> <project>

PRINCIPAL=$1
PROJECT=$2

if [ -z "$PRINCIPAL" ] || [ -z "$PROJECT" ]; then
  echo "Usage: $0 <principal-email> <project-id>"
  echo "Example: $0 user:alice@example.com my-project"
  exit 1
fi

echo "========================================"
echo "IAM DIAGNOSTIC REPORT"
echo "Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "Principal: $PRINCIPAL"
echo "Project: $PROJECT"
echo "========================================"

# Step 1: Check roles
echo ""
echo "--- STEP 1: ROLES FOR PRINCIPAL ---"
gcloud projects get-iam-policy $PROJECT \
  --flatten="bindings[].members" \
  --filter="bindings.members:$PRINCIPAL" \
  --format="table(bindings.role, bindings.condition.title)" 2>&1

# Step 2: Check if principal is a SA — verify it exists
if [[ "$PRINCIPAL" == serviceAccount:* ]]; then
  SA_EMAIL=$(echo $PRINCIPAL | cut -d: -f2)
  echo ""
  echo "--- STEP 2: SA EXISTS? ---"
  gcloud iam service-accounts describe $SA_EMAIL --project=$PROJECT 2>&1
fi

# Step 3: Check enabled APIs
echo ""
echo "--- STEP 3: ENABLED APIS (compute, storage, logging) ---"
gcloud services list --enabled --filter="NAME:(compute OR storage OR logging)" \
  --format="table(NAME, TITLE)" --project=$PROJECT 2>&1

# Step 4: Check for deny policies
echo ""
echo "--- STEP 4: DENY POLICIES ---"
gcloud iam policies list --kind=denypolicies \
  --attachment-point="cloudresourcemanager.googleapis.com/projects/$PROJECT" \
  --format=yaml 2>&1 || echo "No deny policies found (or API not available)"

# Step 5: Recent denied requests in audit logs
echo ""
echo "--- STEP 5: RECENT DENIED REQUESTS (last 24h) ---"
gcloud logging read "
  protoPayload.authenticationInfo.principalEmail:\"$(echo $PRINCIPAL | cut -d: -f2)\"
  protoPayload.status.code=7
  timestamp>=\"$(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)\"
" --limit=5 --format="table(
  timestamp,
  protoPayload.methodName,
  protoPayload.status.message
)" --project=$PROJECT 2>&1 || echo "No recent denied requests found"

echo ""
echo "========================================"
echo "DIAGNOSTIC COMPLETE"
echo "========================================"
SCRIPT

chmod +x /tmp/iam-diagnose.sh
echo "Diagnostic script created at /tmp/iam-diagnose.sh"
```

### Lab 2.2 — Create Test Scenarios

```bash
# Create a SA to diagnose
gcloud iam service-accounts create diag-test-sa \
  --display-name="Diagnostic Test SA"

export DIAG_SA=diag-test-sa@${PROJECT_ID}.iam.gserviceaccount.com

# Scenario 1: SA with no roles (should show empty)
echo "=== Scenario 1: No roles ==="
bash /tmp/iam-diagnose.sh "serviceAccount:$DIAG_SA" "$PROJECT_ID"
```

### Lab 2.3 — Scenario: Wrong Role

```bash
# Grant viewer (read-only)
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$DIAG_SA" \
  --role="roles/compute.viewer"

# Allow impersonation for testing
gcloud iam service-accounts add-iam-policy-binding $DIAG_SA \
  --member="user:$(gcloud config get-value account)" \
  --role="roles/iam.serviceAccountTokenCreator"

# Try to create a VM as the SA (will fail — viewer can't create)
echo "=== Scenario 2: Wrong role (viewer trying to create) ==="
gcloud compute instances create scenario-vm \
  --zone=$ZONE --machine-type=e2-micro \
  --image-family=debian-12 --image-project=debian-cloud \
  --impersonate-service-account=$DIAG_SA 2>&1 || true

# Diagnose
echo ""
echo "--- Diagnosis: SA has compute.viewer but needs compute.instanceAdmin ---"
gcloud iam roles describe roles/compute.viewer \
  --format="value(includedPermissions)" | tr ';' '\n' | grep -c "create"
echo "^ Zero create permissions in viewer role"
```

### Lab 2.4 — Scenario: Conditional Binding Expired

```bash
# Add an already-expired conditional binding
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$DIAG_SA" \
  --role="roles/compute.instanceAdmin.v1" \
  --condition="expression=request.time < timestamp('2026-04-01T00:00:00Z'),title=expired-access,description=This condition has expired"

# Check — the binding exists but won't grant access
echo "=== Scenario 3: Expired condition ==="
gcloud projects get-iam-policy $PROJECT_ID \
  --flatten="bindings[].members" \
  --filter="bindings.members:$DIAG_SA" \
  --format="yaml(bindings.role, bindings.condition)"

echo ""
echo "--- Diagnosis: Condition expired on 2026-04-01 ---"
echo "--- Fix: Update or remove the condition ---"
```

### Lab 2.5 — Document an IAM Decision

```bash
# Create a decision log entry
cat << 'EOF'
═══════════════════════════════════════════════════
IAM DECISION LOG ENTRY
═══════════════════════════════════════════════════
Date:          2026-04-08
Requester:     Diagnostic Test SA
Resource:      project/$PROJECT_ID
Change:        Grant compute.viewer for monitoring
Justification: SA needs to list instances for health checks
Approved by:   Lab exercise (self-approved)
Review date:   2026-07-08
Alternatives considered:
  - roles/editor: REJECTED (too broad)
  - roles/compute.admin: REJECTED (includes firewall management)
  - roles/compute.viewer: SELECTED (minimum for listing instances)
Risk assessment: LOW (read-only access)
═══════════════════════════════════════════════════
EOF
```

### 🧹 Cleanup

```bash
# Remove IAM bindings
gcloud projects remove-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$DIAG_SA" \
  --role="roles/compute.viewer" 2>/dev/null

gcloud projects remove-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$DIAG_SA" \
  --role="roles/compute.instanceAdmin.v1" \
  --condition="expression=request.time < timestamp('2026-04-01T00:00:00Z'),title=expired-access,description=This condition has expired" 2>/dev/null

gcloud iam service-accounts remove-iam-policy-binding $DIAG_SA \
  --member="user:$(gcloud config get-value account)" \
  --role="roles/iam.serviceAccountTokenCreator" 2>/dev/null

# Delete SA
gcloud iam service-accounts delete $DIAG_SA --quiet

# Remove diagnostic script
rm -f /tmp/iam-diagnose.sh
```

---

## Part 3 — Revision (15 min)

### Key Concepts
- **6-step checklist:** role → level → conditions → deny → org policy → context
- **Document every IAM decision** — who requested, what was granted, why, review date
- **Common errors:** wrong principal, wrong level, wrong role, expired condition, deny policy, org policy, API disabled
- **Propagation delay** can be up to 7 minutes — always wait before escalating
- **OAuth scopes** on VMs can restrict access even if IAM allows it — use `--scopes=cloud-platform`
- **VPC Service Controls** can block access even with correct IAM — different system
- Track 403 errors over time — declining trend = improving IAM hygiene
- Build diagnostic scripts for your team — automate the checklist

### Essential Commands
```bash
# Full diagnostic for a principal
gcloud projects get-iam-policy PROJECT \
  --flatten="bindings[].members" \
  --filter="bindings.members:PRINCIPAL" \
  --format="yaml(bindings.role, bindings.condition)"

# Check enabled APIs
gcloud services list --enabled --filter="NAME:SERVICE"

# Check deny policies
gcloud iam policies list --kind=denypolicies \
  --attachment-point="cloudresourcemanager.googleapis.com/projects/PROJECT"

# Query denied requests in audit logs
gcloud logging read 'protoPayload.status.code=7' --limit=10

# Check org policies
gcloud org-policies describe CONSTRAINT --project=PROJECT

# Find which role has a permission
gcloud iam roles list --filter="includedPermissions:PERMISSION"
```

---

## Part 4 — Quiz (15 min)

**Q1.** A SA has `roles/storage.admin` at the org level but gets 403 when creating a bucket in project X. The API is enabled. Walk through the 6-step checklist for this scenario.

<details><summary>Answer</summary>

1. **Role:** `roles/storage.admin` includes `storage.buckets.create` ✓
2. **Level:** Granted at org → inherits to project X ✓
3. **Conditions:** Check if the binding has conditions (time, tag, etc.)
4. **Deny policy:** Check for deny policies at org/folder/project X that block `storage.buckets.create`
5. **Org policy:** Check `constraints/storage.uniformBucketLevelAccess` or `constraints/storage.publicAccessPrevention` or other storage constraints
6. **Context:** Check VPC Service Controls perimeters around project X, check quota, check propagation time

Most likely cause: a deny policy at the project level or a VPC-SC perimeter.

</details>

**Q2.** Why should IAM decisions be documented, and what should the document include?

<details><summary>Answer</summary>

Documentation is essential for: **compliance** (SOC 2, ISO 27001 require access control records), **operational continuity** (team members need to understand why access was granted), **review cycles** (quarterly reviews need a baseline), and **incident response** (trace who had access when).

Include: date, requester, resource, role granted, level, justification, alternatives considered, approver, review date, and ticket/reference number. This creates an audit trail independent of GCP's own audit logs.

</details>

**Q3.** An application on a VM gets "insufficient authentication scopes" despite having the correct IAM role. What's wrong?

<details><summary>Answer</summary>

The VM was created with **restricted OAuth scopes** (e.g., `--scopes=storage-ro` instead of `--scopes=cloud-platform`). OAuth scopes on VMs act as a ceiling — even if the SA has broad IAM roles, the VM's scopes limit which APIs can be called. Fix: recreate the VM with `--scopes=cloud-platform` (which allows IAM to be the sole access control) or add the specific scope needed. You cannot change scopes on a running VM.

</details>

**Q4.** Compare GCP IAM troubleshooting with RHDS LDAP access troubleshooting.

<details><summary>Answer</summary>

| RHDS Troubleshooting | GCP IAM Troubleshooting |
|---------------------|------------------------|
| Check ACI at entry/subtree level | Check IAM binding at resource/project level |
| Check parent ACIs (inheritance) | Check parent policies (org→folder→project) |
| Check `nsRole` / CoS | Check conditions on bindings |
| Check resource limits (`nsLookThroughLimit`) | Check quotas and API enablement |
| `ldapsearch -v` for bind errors | Audit logs for 403 errors |
| `access-log` / `error-log` review | Cloud Logging review |
| `dsconf` to verify ACI | `gcloud get-iam-policy` to verify bindings |

Both follow: check direct grants → check inherited grants → check explicit denies → check system constraints.

</details>
