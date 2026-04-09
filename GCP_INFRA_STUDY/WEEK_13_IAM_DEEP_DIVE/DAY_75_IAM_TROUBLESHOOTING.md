# Day 75 — IAM Troubleshooting: Permission Denied & Debugging

> **Week 13 — IAM Deep Dive** | ⏱ 2 hours | Region: `europe-west2`
> Student profile: 6 yrs Linux infra, 3 yrs RHDS LDAP, ACE certified

---

## Part 1 — Concept (30 min)

### 1.1 Why IAM Troubleshooting Matters

Permission errors are the **#1 operational issue** in GCP. Understanding how to debug them quickly is essential for both daily work and the ACE exam.

**Linux analogy:**
| Linux Error | GCP Equivalent |
|-------------|----------------|
| `Permission denied` on file | `403 PERMISSION_DENIED` |
| `Operation not permitted` | Missing IAM role |
| `sudo: user not in sudoers` | No IAM binding for role |
| Checking `/var/log/secure` | Cloud Audit Logs |
| `namei -l /path/to/file` | Policy Troubleshooter |
| `getfacl /path` | `get-iam-policy` |

### 1.2 Common Permission Denied Patterns

```
┌────────────────────────────────────────────────────────────┐
│              COMMON 403 ERROR PATTERNS                      │
├────────────────────────────────────────────────────────────┤
│                                                             │
│  Pattern 1: WRONG PRINCIPAL                                 │
│  ─────────────────────────                                  │
│  You granted to user:alice@company.com                      │
│  But alice is logged in as alice@gmail.com                  │
│                                                             │
│  Pattern 2: WRONG LEVEL                                     │
│  ─────────────────────                                      │
│  Granted storage.admin on project-A                         │
│  But bucket is in project-B                                 │
│                                                             │
│  Pattern 3: WRONG ROLE                                      │
│  ────────────────────                                       │
│  Granted roles/storage.objectViewer                         │
│  But need roles/storage.objectCreator to upload             │
│                                                             │
│  Pattern 4: PROPAGATION DELAY                               │
│  ────────────────────────────                               │
│  Role granted < 60 seconds ago                              │
│  IAM changes can take up to 7 minutes to propagate          │
│                                                             │
│  Pattern 5: DENY POLICY BLOCKING                            │
│  ───────────────────────────────                            │
│  Allow policy exists but a deny policy overrides it         │
│                                                             │
│  Pattern 6: ORG POLICY CONSTRAINT                           │
│  ────────────────────────────────                           │
│  IAM allows it but org policy blocks the action             │
│  (e.g., constraints/compute.vmExternalIpAccess)             │
│                                                             │
│  Pattern 7: API NOT ENABLED                                 │
│  ──────────────────────────                                 │
│  Permission exists but the API service is disabled          │
│  Error: "API not enabled" vs "Permission denied"            │
└────────────────────────────────────────────────────────────┘
```

### 1.3 Debugging Flowchart

```
          ┌───────────────────────┐
          │  403 PERMISSION_DENIED │
          └───────────┬───────────┘
                      │
          ┌───────────▼───────────┐
          │ 1. Is the API enabled? │
          │    gcloud services     │
          │    list --enabled       │
          └───────────┬───────────┘
                      │ YES
          ┌───────────▼───────────┐
          │ 2. Correct principal?  │
          │    gcloud config       │
          │    get-value account   │
          │    (or check SA email) │
          └───────────┬───────────┘
                      │ YES
          ┌───────────▼───────────┐
          │ 3. Has required role?  │
          │    gcloud projects     │
          │    get-iam-policy      │
          │    --filter=member     │
          └───────────┬───────────┘
                      │ YES
          ┌───────────▼───────────┐
          │ 4. Role at right level?│
          │    Check: org, folder, │
          │    project, resource   │
          └───────────┬───────────┘
                      │ YES
          ┌───────────▼───────────┐
          │ 5. Deny policy?        │
          │    Check deny policies │
          │    at all levels       │
          └───────────┬───────────┘
                      │ NO DENY
          ┌───────────▼───────────┐
          │ 6. Org policy          │
          │    constraint?         │
          │    gcloud org-policies │
          │    describe CONSTRAINT │
          └───────────┬───────────┘
                      │ NO CONSTRAINT
          ┌───────────▼───────────┐
          │ 7. Propagation delay?  │
          │    Wait up to 7 min    │
          │    and retry           │
          └───────────┬───────────┘
                      │ STILL FAILS
          ┌───────────▼───────────┐
          │ 8. Use Policy          │
          │    Troubleshooter      │
          │    in Console          │
          └───────────────────────┘
```

### 1.4 Policy Troubleshooter

The **Policy Troubleshooter** (Console tool) lets you ask: "Does principal X have permission Y on resource Z?"

```
  INPUT:
  ┌─────────────────────────────────────┐
  │ Principal: user:alice@company.com    │
  │ Resource:  projects/my-proj/...     │
  │ Permission: compute.instances.start │
  └───────────────────┬─────────────────┘
                      │
  OUTPUT:
  ┌───────────────────▼─────────────────┐
  │ ✅ ACCESS GRANTED                    │
  │   via: roles/compute.instanceAdmin  │
  │   at:  project level                │
  │   binding: direct                   │
  ├─────────────────────────────────────┤
  │ OR                                   │
  │ ❌ ACCESS DENIED                     │
  │   Nearest matching role:             │
  │   roles/compute.instanceAdmin        │
  │   Missing permission:                │
  │   compute.instances.start            │
  │   Suggestion: grant the above role   │
  └─────────────────────────────────────┘
```

### 1.5 testIamPermissions API

Programmatic way to check permissions — does not require admin access:

```
  testIamPermissions( resource, [permissions] )
  ──────────────────────────────────────────────
  Returns: subset of permissions that the caller has

  Example: check if SA can read + write storage
  Input:   ["storage.objects.get", "storage.objects.create"]
  Output:  ["storage.objects.get"]  ← can read but not write
```

> **RHDS parallel:** This is like `ldapsearch -x -D "uid=app,..." -w password` to test if a bind DN has read access to a subtree. The `testIamPermissions` API is a non-destructive way to verify access without attempting the actual operation.

---

## Part 2 — Hands-On Lab (60 min)

### Prerequisites
```bash
export PROJECT_ID=$(gcloud config get-value project)
export REGION=europe-west2
export ZONE=europe-west2-a
```

### Lab 2.1 — Create a Restricted SA and Observe Failures

```bash
# Create a SA with NO roles
gcloud iam service-accounts create debug-sa \
  --display-name="Debug SA" \
  --project=$PROJECT_ID

export DEBUG_SA=debug-sa@${PROJECT_ID}.iam.gserviceaccount.com

# Allow yourself to impersonate it
gcloud iam service-accounts add-iam-policy-binding $DEBUG_SA \
  --member="user:$(gcloud config get-value account)" \
  --role="roles/iam.serviceAccountTokenCreator"

# Try to list VMs as the SA — should fail
echo "--- Attempting to list instances as debug-sa (expect failure) ---"
gcloud compute instances list \
  --impersonate-service-account=$DEBUG_SA 2>&1 || true
```

### Lab 2.2 — Diagnose and Fix Step by Step

```bash
# Step 1: Check what roles the SA has
echo "--- Step 1: Check roles ---"
gcloud projects get-iam-policy $PROJECT_ID \
  --flatten="bindings[].members" \
  --filter="bindings.members:$DEBUG_SA" \
  --format="table(bindings.role)"
# Result: empty — no roles granted!

# Step 2: Identify needed permission
echo "--- Step 2: Permission needed = compute.instances.list ---"
echo "Which role provides it?"
gcloud iam roles describe roles/compute.viewer \
  --format="value(includedPermissions)" | tr ';' '\n' | grep instances.list

# Step 3: Grant the minimum role
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$DEBUG_SA" \
  --role="roles/compute.viewer"

# Step 4: Wait briefly and retry
echo "--- Waiting 10 seconds for propagation ---"
sleep 10

echo "--- Retrying list instances ---"
gcloud compute instances list \
  --impersonate-service-account=$DEBUG_SA 2>&1
echo "--- Success! ---"
```

### Lab 2.3 — Use testIamPermissions

```bash
# Create a test bucket
gsutil mb -l $REGION gs://${PROJECT_ID}-debug-test/ 2>/dev/null || true

# Test which permissions the SA has on the bucket
echo "--- Testing SA permissions on bucket ---"
curl -s -X POST \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" \
  "https://storage.googleapis.com/storage/v1/b/${PROJECT_ID}-debug-test/iam/testPermissions?permissions=storage.objects.get&permissions=storage.objects.create&permissions=storage.objects.delete" | python3 -m json.tool 2>/dev/null || \
gcloud storage buckets describe gs://${PROJECT_ID}-debug-test/ --format=json 2>&1 | head -20

# Grant storage viewer and re-test
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$DEBUG_SA" \
  --role="roles/storage.objectViewer"

sleep 10

echo "--- Re-testing after granting objectViewer ---"
# The SA should now have storage.objects.get but NOT create/delete
```

### Lab 2.4 — Check Audit Logs for Denied Requests

```bash
# Query recent permission denied errors from audit logs
gcloud logging read '
  severity="ERROR"
  protoPayload.status.code=7
  timestamp>="2026-04-08T00:00:00Z"
' --limit=5 --format="table(
  timestamp,
  protoPayload.authenticationInfo.principalEmail,
  protoPayload.methodName,
  protoPayload.status.message
)" --project=$PROJECT_ID 2>/dev/null || echo "No recent denied logs found"

# Query for specific SA denials
gcloud logging read "
  protoPayload.authenticationInfo.principalEmail=\"$DEBUG_SA\"
  severity>=WARNING
" --limit=5 --format=json --project=$PROJECT_ID 2>/dev/null | head -30
```

### Lab 2.5 — Simulate Role Mismatch

```bash
# SA has compute.viewer — try to START an instance
gcloud compute instances create debug-vm \
  --zone=$ZONE \
  --machine-type=e2-micro \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --no-address 2>/dev/null

# Try to stop the VM as the debug SA (should fail — viewer can't stop)
echo "--- Attempting stop as viewer (expect failure) ---"
gcloud compute instances stop debug-vm --zone=$ZONE \
  --impersonate-service-account=$DEBUG_SA 2>&1 || true

# Diagnose: what permission is needed?
echo "--- compute.instances.stop requires instanceAdmin or compute.admin ---"
```

### 🧹 Cleanup

```bash
# Delete test VM
gcloud compute instances delete debug-vm --zone=$ZONE --quiet 2>/dev/null

# Delete test bucket
gsutil rm -r gs://${PROJECT_ID}-debug-test/ 2>/dev/null

# Remove IAM bindings
gcloud projects remove-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$DEBUG_SA" \
  --role="roles/compute.viewer" 2>/dev/null

gcloud projects remove-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$DEBUG_SA" \
  --role="roles/storage.objectViewer" 2>/dev/null

gcloud iam service-accounts remove-iam-policy-binding $DEBUG_SA \
  --member="user:$(gcloud config get-value account)" \
  --role="roles/iam.serviceAccountTokenCreator" 2>/dev/null

# Delete SA
gcloud iam service-accounts delete $DEBUG_SA --quiet
```

---

## Part 3 — Revision (15 min)

### Key Concepts
- **403 PERMISSION_DENIED** — the most common GCP operational error
- **7 common patterns:** wrong principal, wrong level, wrong role, propagation delay, deny policy, org policy, API not enabled
- **Debugging order:** API enabled → correct principal → has role → right level → deny policy → org policy → propagation → Policy Troubleshooter
- **Policy Troubleshooter** — Console tool that explains why access is granted/denied
- **testIamPermissions** — API to check what permissions a caller has on a resource
- **Audit logs** record denied requests — check `protoPayload.status.code=7`
- IAM changes can take **up to 7 minutes** to propagate
- **Org policies** are separate from IAM — they restrict what actions are possible regardless of IAM

### Essential Commands
```bash
# Check what account you're using
gcloud config get-value account

# Check roles for a principal
gcloud projects get-iam-policy PROJECT \
  --flatten="bindings[].members" \
  --filter="bindings.members:PRINCIPAL"

# List enabled APIs
gcloud services list --enabled --filter="NAME:compute"

# Query audit logs for denied requests
gcloud logging read 'severity="ERROR" protoPayload.status.code=7' --limit=10

# Describe a role to see permissions
gcloud iam roles describe roles/ROLE_NAME

# Search for a permission across roles
gcloud iam roles list --filter="includedPermissions:PERMISSION"
```

---

## Part 4 — Quiz (15 min)

**Q1.** A developer says "I have `roles/compute.viewer` but can't stop a VM." What's the issue and how do you fix it?

<details><summary>Answer</summary>

`roles/compute.viewer` only grants **read** permissions (`compute.instances.get`, `compute.instances.list`). Stopping a VM requires `compute.instances.stop`, which is in `roles/compute.instanceAdmin.v1` or `roles/compute.admin`. Grant the minimum needed: `roles/compute.instanceAdmin.v1` or create a custom role with just `compute.instances.stop` and `compute.instances.start`.

</details>

**Q2.** A user has `roles/storage.admin` at the org level, but gets 403 when accessing a bucket in project-X. What could cause this?

<details><summary>Answer</summary>

Possible causes: (1) A **deny policy** on project-X or the bucket blocking storage permissions. (2) An **org policy constraint** like `constraints/storage.uniformBucketLevelAccess` interfering. (3) The user is authenticated with a **different identity** (e.g., personal Gmail instead of corporate account). (4) **VPC Service Controls** perimeter blocking access from the user's network. Use the Policy Troubleshooter to identify the exact cause.

</details>

**Q3.** You granted a role 2 minutes ago but it's still not working. Is this expected?

<details><summary>Answer</summary>

Yes. IAM changes can take **up to 7 minutes** to propagate across Google's infrastructure. For most changes, propagation happens within 60 seconds, but in some cases (especially for deny policies and conditional bindings), it can take longer. Wait and retry. If it's still failing after 10 minutes, investigate other causes.

</details>

**Q4.** How is debugging GCP IAM similar to debugging Linux file permissions?

<details><summary>Answer</summary>

Both follow a systematic hierarchy check:
- **Linux:** `ls -la` (file perms) → `getfacl` (ACLs) → `namei -l` (path perms) → SELinux context (`ls -Z`) → audit log (`/var/log/audit`)
- **GCP:** `get-iam-policy` (bindings) → check hierarchy level → deny policies → org policies → audit logs

In RHDS, debugging access is similar: check ACI (Access Control Instructions) at each DIT level, check CoS, check resource limits. The layered model is the same — permissions compound from top to bottom.

</details>
