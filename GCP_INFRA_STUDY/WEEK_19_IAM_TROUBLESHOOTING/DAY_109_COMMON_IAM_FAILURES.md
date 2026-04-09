# Week 19, Day 109 (Mon) — Common IAM Failures

## Today's Objective

Learn to systematically diagnose 403 Forbidden errors in GCP, understand missing roles, wrong scopes, org policy blocks, deny rules, propagation delays, and build a repeatable debugging methodology.

**Source:** [IAM Troubleshooting](https://cloud.google.com/iam/docs/troubleshooting-access) | [Policy Troubleshooter](https://cloud.google.com/policy-intelligence/docs/troubleshoot-access)

**Deliverable:** A diagnostic flowchart for 403 errors with gcloud commands for each investigation step

---

## Part 1: Concept (30 minutes)

### 1.1 The 403 Landscape

```
Linux analogy:

Permission denied on /etc/shadow     ──►    403 Forbidden on GCS bucket
ls -la /etc/shadow (check perms)      ──►    gcloud projects get-iam-policy
id (check user groups)                ──►    gcloud auth list (check identity)
SELinux denying access                ──►    Org policy / deny rule blocking
chmod 644 /etc/shadow (fix)           ──►    gcloud projects add-iam-policy-binding
```

### 1.2 IAM Evaluation Flow

```
REQUEST: "Can user@example.com read gs://my-bucket/file.txt?"
                    │
                    ▼
┌─────────────────────────────────────────────────┐
│  Step 1: IDENTITY CHECK                          │
│  Who is making the request?                      │
│  - User account? Service account? Group?         │
│  - Is auth token valid and not expired?          │
│  ──► If invalid identity ──► 401 Unauthorized    │
└──────────────────────┬──────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────┐
│  Step 2: DENY RULES (evaluated first!)           │
│  Is there an explicit deny rule?                 │
│  - Org-level deny?                               │
│  - Folder-level deny?                            │
│  - Project-level deny?                           │
│  ──► If denied ──► 403 (deny rule)               │
└──────────────────────┬──────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────┐
│  Step 3: ORG POLICIES                            │
│  Does an org policy restrict this action?        │
│  - Domain restriction?                           │
│  - Resource location restriction?                │
│  ──► If blocked ──► 403 (org policy)             │
└──────────────────────┬──────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────┐
│  Step 4: ALLOW POLICIES (IAM bindings)           │
│  Check hierarchy: Org → Folder → Project → Res   │
│  Does user have required role?                   │
│  - Direct binding?                               │
│  - Via group membership?                         │
│  - Inherited from parent?                        │
│  ──► If no matching allow ──► 403 (missing role) │
│  ──► If allowed ──► ACCESS GRANTED               │
└─────────────────────────────────────────────────┘
```

### 1.3 Top 403 Causes

| Cause | Symptom | Diagnosis | Fix |
|---|---|---|---|
| **Missing role** | 403 on specific API call | Policy Troubleshooter | Add IAM binding |
| **Wrong scope** | SA has role but still 403 | Check VM scopes | Recreate with correct scopes |
| **Org policy** | 403 despite correct role | Check org policies | Request exception / change policy |
| **Deny rule** | 403 despite correct role | Check deny policies | Remove deny rule or exception |
| **Propagation delay** | 403 right after granting role | Wait up to 7 minutes | Wait, then retry |
| **Wrong project** | 403 on resource | Verify project context | Switch project |
| **Expired token** | Intermittent 403 | Check token expiry | Re-authenticate |
| **Conditional binding** | 403 at certain times/IPs | Check IAM conditions | Verify conditions match |

### 1.4 Propagation Delays

| Change | Typical Propagation | Max Propagation |
|---|---|---|
| Add IAM role | < 60 seconds | Up to 7 minutes |
| Remove IAM role | < 60 seconds | Up to 7 minutes |
| Change org policy | 1-2 minutes | Up to 15 minutes |
| Enable/disable API | Near-instant | Up to 5 minutes |

### 1.5 Scope vs Role Confusion

```
SERVICE ACCOUNT on a VM:

Role (IAM level):
  roles/storage.objectViewer   ──► "You're ALLOWED to read"
  
Scope (VM level):  
  --scopes=storage-ro          ──► "The VM CAN request read"

Both must be correct:
  ┌─────────┐     ┌─────────┐     ┌─────────┐
  │ IAM Role│ AND │ VM Scope│  =  │ ACCESS  │
  │    ✅   │     │    ✅   │     │   ✅    │
  │         │     │         │     │         │
  │    ✅   │ AND │    ❌   │  =  │   ❌    │
  │    ❌   │ AND │    ✅   │  =  │   ❌    │
  └─────────┘     └─────────┘     └─────────┘
  
Best practice: Use --scopes=cloud-platform (full access)
               and control everything via IAM roles.
```

### 1.6 Debugging Flowchart

```
403 Forbidden
     │
     ├── Check: Am I authenticated?
     │   gcloud auth list
     │   └── No? → gcloud auth login
     │
     ├── Check: Right project?
     │   gcloud config get-value project
     │   └── Wrong? → gcloud config set project PROJECT
     │
     ├── Check: API enabled?
     │   gcloud services list --enabled | grep SERVICE
     │   └── No? → gcloud services enable SERVICE
     │
     ├── Check: Do I have the role?
     │   gcloud projects get-iam-policy PROJECT --flatten=bindings
     │   └── No? → Add role binding
     │
     ├── Check: Is there a deny rule?
     │   gcloud iam policies list --kind=denypolicies
     │   └── Yes? → Remove deny or add exception
     │
     ├── Check: Org policy blocking?
     │   gcloud org-policies describe CONSTRAINT --project=PROJECT
     │   └── Yes? → Request exception
     │
     └── Check: Propagation delay?
         └── Recently changed? → Wait 7 min, retry
```

---

## Part 2: Hands-On Lab (60 minutes)

### Step 1: Set Up Lab Environment (10 min)

```bash
export PROJECT_ID=$(gcloud config get-value project)

# Create a test service account
gcloud iam service-accounts create iam-debug-lab-sa \
  --display-name="IAM Debug Lab SA" \
  --description="Service account for IAM troubleshooting lab"

SA_EMAIL="iam-debug-lab-sa@${PROJECT_ID}.iam.gserviceaccount.com"
echo "SA: $SA_EMAIL"

# Create a test bucket
gcloud storage buckets create gs://${PROJECT_ID}-iam-debug-lab \
  --location=europe-west2 \
  --uniform-bucket-level-access

# Upload a test file
echo "Secret lab data" | gcloud storage cp - gs://${PROJECT_ID}-iam-debug-lab/test-file.txt
```

### Step 2: Simulate Missing Role (10 min)

```bash
# Try to read the bucket AS the service account (no roles granted yet)
# First, check what roles the SA has
gcloud projects get-iam-policy ${PROJECT_ID} \
  --flatten="bindings[].members" \
  --filter="bindings.members:${SA_EMAIL}" \
  --format="table(bindings.role)"

# Should show NO roles — the SA can't access anything

# Use Policy Troubleshooter
gcloud policy-troubleshoot iam \
  "//storage.googleapis.com/projects/_/buckets/${PROJECT_ID}-iam-debug-lab" \
  --permission="storage.objects.get" \
  --principal-email="${SA_EMAIL}"

# Should show: NOT_GRANTED
```

### Step 3: Fix the Missing Role (5 min)

```bash
# Grant storage.objectViewer
gcloud storage buckets add-iam-policy-binding \
  gs://${PROJECT_ID}-iam-debug-lab \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/storage.objectViewer"

# Verify the fix
gcloud policy-troubleshoot iam \
  "//storage.googleapis.com/projects/_/buckets/${PROJECT_ID}-iam-debug-lab" \
  --permission="storage.objects.get" \
  --principal-email="${SA_EMAIL}"

# Should show: GRANTED
```

### Step 4: Check IAM Policy Hierarchy (10 min)

```bash
# View project-level IAM
gcloud projects get-iam-policy ${PROJECT_ID} \
  --format="table(bindings.role, bindings.members)" \
  --flatten="bindings[].members" | head -30

# View bucket-level IAM
gcloud storage buckets get-iam-policy gs://${PROJECT_ID}-iam-debug-lab

# Check effective permissions for the SA
echo ""
echo "=== SA Effective Permissions ==="
gcloud projects get-iam-policy ${PROJECT_ID} \
  --flatten="bindings[].members" \
  --filter="bindings.members:${SA_EMAIL}" \
  --format="table(bindings.role)"

gcloud storage buckets get-iam-policy gs://${PROJECT_ID}-iam-debug-lab \
  --flatten="bindings[].members" \
  --filter="bindings.members:serviceAccount:${SA_EMAIL}" \
  --format="table(bindings.role)"
```

### Step 5: Investigate VM Scopes (10 min)

```bash
# Create a VM with restricted scopes
gcloud compute instances create iam-scope-test \
  --zone=europe-west2-a \
  --machine-type=e2-micro \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --scopes=compute-ro \
  --service-account=${SA_EMAIL}

# Check the scopes
gcloud compute instances describe iam-scope-test \
  --zone=europe-west2-a \
  --format="yaml(serviceAccounts[].scopes)"

# The VM has compute-ro scope but the SA has storage roles
# This means storage access will fail despite IAM permissions!

echo ""
echo "=== Diagnosis ==="
echo "SA has: roles/storage.objectViewer (IAM)"
echo "VM has: compute-ro scope (restricted)"
echo "Result: Storage access will FAIL (scope doesn't allow storage)"
echo ""
echo "Fix: Recreate VM with --scopes=cloud-platform"
```

### Step 6: Check Audit Logs for 403s (10 min)

```bash
# Query recent permission denied events
gcloud logging read '
  protoPayload.status.code=7 OR
  protoPayload.status.message=~"PERMISSION_DENIED" OR
  protoPayload.authorizationInfo.granted=false
' --limit=10 --format="table(
  timestamp,
  protoPayload.authenticationInfo.principalEmail,
  protoPayload.methodName,
  protoPayload.authorizationInfo.permission,
  protoPayload.status.message
)" --freshness=1h

# Query specifically for our SA
gcloud logging read "
  protoPayload.authenticationInfo.principalEmail=\"${SA_EMAIL}\"
" --limit=10 --format="table(
  timestamp,
  protoPayload.methodName,
  protoPayload.authorizationInfo.granted
)" --freshness=1h
```

### Step 7: Clean Up (5 min)

```bash
gcloud compute instances delete iam-scope-test --zone=europe-west2-a --quiet
gcloud storage rm -r gs://${PROJECT_ID}-iam-debug-lab
gcloud iam service-accounts delete ${SA_EMAIL} --quiet
```

---

## Part 3: Revision (15 minutes)

- **403 debugging order** — identity → deny rules → org policies → allow policies → propagation
- **Policy Troubleshooter** — `gcloud policy-troubleshoot iam` shows exactly why access is granted/denied
- **Scope vs Role** — both must allow the action; use `--scopes=cloud-platform` and control via IAM
- **Propagation delays** — up to 7 min for IAM, 15 min for org policies; wait before escalating
- **Audit logs** — query for `PERMISSION_DENIED` to find who failed and why
- **Deny rules** are evaluated BEFORE allow policies — they override everything

### Key Commands
```bash
gcloud policy-troubleshoot iam RESOURCE --permission=PERM --principal-email=EMAIL
gcloud projects get-iam-policy PROJECT --flatten="bindings[].members"
gcloud compute instances describe VM --format="yaml(serviceAccounts[].scopes)"
gcloud logging read 'protoPayload.status.code=7' --limit=10
gcloud iam policies list --kind=denypolicies --attachment-point=...
```

---

## Part 4: Quiz (15 minutes)

**Q1:** A service account has `roles/storage.objectViewer` on a bucket, but a VM using that SA gets 403 on storage reads. What's the likely cause?
<details><summary>Answer</summary>The VM was created with <b>restricted scopes</b> that don't include storage (e.g., <code>--scopes=compute-ro</code>). The IAM role grants permission, but the OAuth scope limits what APIs the VM can call. <b>Fix:</b> Delete and recreate the VM with <code>--scopes=cloud-platform</code>. Scopes are set at creation time and can't be changed on a running VM (must stop first). Best practice: always use <code>cloud-platform</code> scope and control access entirely through IAM.</details>

**Q2:** You granted a role 30 seconds ago and the user still gets 403. Should you troubleshoot further?
<details><summary>Answer</summary><b>Wait.</b> IAM propagation can take up to 7 minutes. Before investigating further: 1) Confirm the binding was actually applied: <code>gcloud projects get-iam-policy PROJECT | grep USER</code>. 2) If the binding exists, wait 5-7 minutes and retry. 3) If still failing after 7 minutes, THEN investigate deeper (deny rules, org policies, wrong resource path). Like DNS propagation — verify the record exists, then wait for caches to update.</details>

**Q3:** What's the difference between a deny rule and a missing allow policy?
<details><summary>Answer</summary>A <b>missing allow</b> means no IAM binding grants the permission — the default state is "no access". A <b>deny rule</b> is an explicit block that overrides allow policies. Even if the user has the correct role, a deny rule will still 403 them. Deny rules are evaluated <b>before</b> allow policies. Use <code>gcloud iam policies list --kind=denypolicies</code> to check. Like the difference between no <code>iptables</code> rule for a port (default DROP) vs an explicit <code>iptables -j REJECT</code> rule.</details>

**Q4:** You need to diagnose 403 errors for a user you can't impersonate. What tools do you use?
<details><summary>Answer</summary>
1. <b>Policy Troubleshooter:</b> <code>gcloud policy-troubleshoot iam RESOURCE --permission=PERM --principal-email=USER</code> — shows access evaluation without needing to be the user<br>
2. <b>Audit Logs:</b> Query Data Access logs for <code>PERMISSION_DENIED</code> from that user — shows the exact API call and missing permission<br>
3. <b>IAM Analyzer:</b> <code>gcloud asset analyze-iam-policy</code> — shows effective permissions for a principal across the hierarchy<br>
4. <b>Activity Logs:</b> Admin Activity logs show successful access, useful for comparison
</details>
