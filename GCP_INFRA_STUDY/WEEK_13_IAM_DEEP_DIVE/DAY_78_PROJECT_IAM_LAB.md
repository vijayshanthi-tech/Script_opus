# Day 78 — PROJECT: IAM Lab Pack — Multi-Scenario Grant/Test/Revoke

> **Week 13 — IAM Deep Dive** | ⏱ 2 hours | Region: `europe-west2`
> Student profile: 6 yrs Linux infra, 3 yrs RHDS LDAP, ACE certified

---

## Part 1 — Concept (30 min)

### 1.1 Project Overview

This is a comprehensive lab that combines everything from Week 13 into 5 real-world IAM scenarios. Each scenario follows the **Grant → Test → Revoke** workflow.

### 1.2 Architecture Diagram

```
  ┌──────────────────────────────────────────────────────────────┐
  │                    PROJECT: $PROJECT_ID                       │
  │                                                              │
  │  SERVICE ACCOUNTS                     RESOURCES              │
  │  ────────────────                     ─────────              │
  │  ┌──────────────┐                    ┌──────────────┐       │
  │  │ scenario1-sa │──── viewer ────────│ GCE VMs      │       │
  │  └──────────────┘                    └──────────────┘       │
  │  ┌──────────────┐                    ┌──────────────┐       │
  │  │ scenario2-sa │──── editor ────────│ GCS Buckets  │       │
  │  └──────────────┘                    └──────────────┘       │
  │  ┌──────────────┐                    ┌──────────────┐       │
  │  │ scenario3-sa │──── custom ────────│ Specific API │       │
  │  └──────────────┘                    └──────────────┘       │
  │  ┌──────────────┐                    ┌──────────────┐       │
  │  │ scenario4-sa │──── attached ──────│ VM Instance  │       │
  │  └──────────────┘                    └──────────────┘       │
  │  ┌──────────────┐                    ┌──────────────┐       │
  │  │ scenario5-sa │──── conditional ───│ Time-limited │       │
  │  └──────────────┘                    └──────────────┘       │
  └──────────────────────────────────────────────────────────────┘
```

### 1.3 Completion Checklist

```
  ┌──────────────────────────────────────────────────┐
  │          IAM LAB PACK CHECKLIST                   │
  ├──────────────────────────────────────────────────┤
  │                                                   │
  │  Scenario 1: Viewer Role                          │
  │  □ Create SA                                      │
  │  □ Grant roles/compute.viewer                     │
  │  □ Test: list instances (should work)             │
  │  □ Test: create instance (should fail)            │
  │  □ Revoke role                                    │
  │  □ Verify revocation                              │
  │                                                   │
  │  Scenario 2: Editor (Observe & Narrow)            │
  │  □ Create SA                                      │
  │  □ Grant roles/editor                             │
  │  □ Test: broad access works                       │
  │  □ Narrow to predefined roles                     │
  │  □ Verify narrowing works                         │
  │  □ Revoke editor                                  │
  │                                                   │
  │  Scenario 3: Custom Role                          │
  │  □ Create custom role                             │
  │  □ Create SA and bind custom role                 │
  │  □ Test: allowed operations work                  │
  │  □ Test: disallowed operations fail               │
  │  □ Revoke and delete custom role                  │
  │                                                   │
  │  Scenario 4: SA Attached to VM                    │
  │  □ Create SA with specific roles                  │
  │  □ Create VM with SA attached                     │
  │  □ Test from within VM: metadata server           │
  │  □ Test: API access matches SA roles              │
  │  □ Delete VM and SA                               │
  │                                                   │
  │  Scenario 5: Conditional Binding                  │
  │  □ Create SA                                      │
  │  □ Add time-limited conditional binding           │
  │  □ Test: access works within condition            │
  │  □ Simulate expired condition                     │
  │  □ Revoke conditional binding                     │
  └──────────────────────────────────────────────────┘
```

---

## Part 2 — Hands-On Lab (60 min)

### Prerequisites
```bash
export PROJECT_ID=$(gcloud config get-value project)
export REGION=europe-west2
export ZONE=europe-west2-a
export MY_ACCOUNT=$(gcloud config get-value account)
```

---

### Scenario 1: Viewer Role — Read-Only Access

```bash
echo "════════════════════════════════════════"
echo "SCENARIO 1: VIEWER ROLE"
echo "════════════════════════════════════════"

# GRANT
gcloud iam service-accounts create s1-viewer-sa \
  --display-name="Scenario 1 Viewer"
export S1_SA=s1-viewer-sa@${PROJECT_ID}.iam.gserviceaccount.com

gcloud iam service-accounts add-iam-policy-binding $S1_SA \
  --member="user:$MY_ACCOUNT" \
  --role="roles/iam.serviceAccountTokenCreator"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$S1_SA" \
  --role="roles/compute.viewer"

sleep 10

# TEST — should succeed (list)
echo "--- Test 1a: List instances (expect SUCCESS) ---"
gcloud compute instances list \
  --impersonate-service-account=$S1_SA 2>&1 | head -5
echo "Result: ✅ Can list"

# TEST — should fail (create)
echo "--- Test 1b: Create instance (expect FAILURE) ---"
gcloud compute instances create s1-test-vm \
  --zone=$ZONE --machine-type=e2-micro \
  --image-family=debian-12 --image-project=debian-cloud \
  --impersonate-service-account=$S1_SA 2>&1 | tail -3
echo "Result: ❌ Cannot create (correct!)"

# REVOKE
gcloud projects remove-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$S1_SA" \
  --role="roles/compute.viewer"

# VERIFY
echo "--- Verify: No roles remaining ---"
gcloud projects get-iam-policy $PROJECT_ID \
  --flatten="bindings[].members" \
  --filter="bindings.members:$S1_SA" \
  --format="value(bindings.role)" | wc -l

echo "✅ Scenario 1 complete"
```

---

### Scenario 2: Editor → Narrow to Predefined Roles

```bash
echo "════════════════════════════════════════"
echo "SCENARIO 2: EDITOR → NARROW"
echo "════════════════════════════════════════"

# GRANT (broad)
gcloud iam service-accounts create s2-editor-sa \
  --display-name="Scenario 2 Editor"
export S2_SA=s2-editor-sa@${PROJECT_ID}.iam.gserviceaccount.com

gcloud iam service-accounts add-iam-policy-binding $S2_SA \
  --member="user:$MY_ACCOUNT" \
  --role="roles/iam.serviceAccountTokenCreator"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$S2_SA" \
  --role="roles/editor"

sleep 10

# TEST — broad access works
echo "--- Test 2a: Editor can list + create ---"
gcloud compute instances list \
  --impersonate-service-account=$S2_SA 2>&1 | head -3
echo "Result: ✅ Editor works (but too broad)"

# NARROW — add specific roles first
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$S2_SA" \
  --role="roles/storage.objectViewer"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$S2_SA" \
  --role="roles/logging.logWriter"

# REMOVE editor
gcloud projects remove-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$S2_SA" \
  --role="roles/editor"

# VERIFY narrowing
echo "--- Test 2b: Roles after narrowing ---"
gcloud projects get-iam-policy $PROJECT_ID \
  --flatten="bindings[].members" \
  --filter="bindings.members:$S2_SA" \
  --format="table(bindings.role)"

echo "✅ Scenario 2 complete"
```

---

### Scenario 3: Custom Role

```bash
echo "════════════════════════════════════════"
echo "SCENARIO 3: CUSTOM ROLE"
echo "════════════════════════════════════════"

# CREATE custom role
gcloud iam roles create labPackReader \
  --project=$PROJECT_ID \
  --title="Lab Pack Reader" \
  --description="Read compute instances and storage objects" \
  --permissions="compute.instances.get,compute.instances.list,storage.objects.get,storage.objects.list"

# GRANT
gcloud iam service-accounts create s3-custom-sa \
  --display-name="Scenario 3 Custom"
export S3_SA=s3-custom-sa@${PROJECT_ID}.iam.gserviceaccount.com

gcloud iam service-accounts add-iam-policy-binding $S3_SA \
  --member="user:$MY_ACCOUNT" \
  --role="roles/iam.serviceAccountTokenCreator"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$S3_SA" \
  --role="projects/$PROJECT_ID/roles/labPackReader"

sleep 10

# TEST — allowed operations
echo "--- Test 3a: List instances (expect SUCCESS) ---"
gcloud compute instances list \
  --impersonate-service-account=$S3_SA 2>&1 | head -3
echo "Result: ✅ Custom role grants list access"

# TEST — disallowed operations
echo "--- Test 3b: Delete instance (expect FAILURE) ---"
gcloud compute instances delete nonexistent-vm --zone=$ZONE \
  --impersonate-service-account=$S3_SA --quiet 2>&1 | tail -2
echo "Result: ❌ Cannot delete (correct!)"

# REVOKE
gcloud projects remove-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$S3_SA" \
  --role="projects/$PROJECT_ID/roles/labPackReader"

gcloud iam roles delete labPackReader --project=$PROJECT_ID --quiet

echo "✅ Scenario 3 complete"
```

---

### Scenario 4: SA Attached to VM

```bash
echo "════════════════════════════════════════"
echo "SCENARIO 4: SA ATTACHED TO VM"
echo "════════════════════════════════════════"

# CREATE SA with specific roles
gcloud iam service-accounts create s4-vm-sa \
  --display-name="Scenario 4 VM SA"
export S4_SA=s4-vm-sa@${PROJECT_ID}.iam.gserviceaccount.com

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$S4_SA" \
  --role="roles/storage.objectViewer"

# CREATE VM with SA
gcloud compute instances create s4-vm \
  --zone=$ZONE \
  --machine-type=e2-micro \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --service-account=$S4_SA \
  --scopes=cloud-platform \
  --no-address

sleep 15

# TEST from within VM
echo "--- Test 4a: Check SA from VM metadata ---"
gcloud compute ssh s4-vm --zone=$ZONE --tunnel-through-iap --command="
  echo 'SA on this VM:'
  curl -s -H 'Metadata-Flavor: Google' \
    http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/email
  echo ''
  echo 'Scopes:'
  curl -s -H 'Metadata-Flavor: Google' \
    http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/scopes
" 2>&1 || echo "(SSH may need IAP tunnel firewall rule)"

echo "✅ Scenario 4 complete"
```

---

### Scenario 5: Conditional Binding

```bash
echo "════════════════════════════════════════"
echo "SCENARIO 5: CONDITIONAL BINDING"
echo "════════════════════════════════════════"

# GRANT with future expiry
gcloud iam service-accounts create s5-cond-sa \
  --display-name="Scenario 5 Conditional"
export S5_SA=s5-cond-sa@${PROJECT_ID}.iam.gserviceaccount.com

gcloud iam service-accounts add-iam-policy-binding $S5_SA \
  --member="user:$MY_ACCOUNT" \
  --role="roles/iam.serviceAccountTokenCreator"

# Conditional binding — valid for 30 days
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$S5_SA" \
  --role="roles/compute.viewer" \
  --condition="expression=request.time < timestamp('2026-05-08T00:00:00Z'),title=temp-30d,description=Temporary viewer access for 30 days"

sleep 10

# TEST — should work (condition is current)
echo "--- Test 5a: Access within condition window ---"
gcloud compute instances list \
  --impersonate-service-account=$S5_SA 2>&1 | head -3
echo "Result: ✅ Conditional access works"

# SHOW the condition
echo "--- Condition details ---"
gcloud projects get-iam-policy $PROJECT_ID \
  --flatten="bindings[].members" \
  --filter="bindings.members:$S5_SA" \
  --format="yaml(bindings.role, bindings.condition)"

echo "✅ Scenario 5 complete"
```

---

### 🧹 Full Cleanup

```bash
echo "════════════════════════════════════════"
echo "CLEANUP: ALL SCENARIOS"
echo "════════════════════════════════════════"

# Scenario 4: Delete VM first
gcloud compute instances delete s4-vm --zone=$ZONE --quiet 2>/dev/null

# Remove all IAM bindings
for SA in $S1_SA $S2_SA $S3_SA $S4_SA $S5_SA; do
  echo "Cleaning up $SA..."
  
  # Remove token creator from all
  gcloud iam service-accounts remove-iam-policy-binding $SA \
    --member="user:$MY_ACCOUNT" \
    --role="roles/iam.serviceAccountTokenCreator" 2>/dev/null
  
  # Remove all project-level bindings
  for ROLE in $(gcloud projects get-iam-policy $PROJECT_ID \
    --flatten="bindings[].members" \
    --filter="bindings.members:$SA" \
    --format="value(bindings.role)" 2>/dev/null); do
    gcloud projects remove-iam-policy-binding $PROJECT_ID \
      --member="serviceAccount:$SA" --role="$ROLE" 2>/dev/null
  done
  
  # Delete SA
  gcloud iam service-accounts delete $SA --quiet 2>/dev/null
done

# Conditional binding needs explicit removal
gcloud projects remove-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$S5_SA" \
  --role="roles/compute.viewer" \
  --condition="expression=request.time < timestamp('2026-05-08T00:00:00Z'),title=temp-30d,description=Temporary viewer access for 30 days" 2>/dev/null

echo "✅ All cleanup complete"
```

---

## Part 3 — Revision (15 min)

### Key Concepts
- **Grant → Test → Revoke** is the standard IAM workflow for any access change
- Always test both **positive** (allowed operation works) and **negative** (disallowed operation fails)
- **Viewer** = read-only, **Editor** = read-write (too broad), **Custom** = exact match
- Attaching a SA to a VM = the VM authenticates via metadata server (no keys)
- Conditional bindings add time/resource/IP constraints — automatically expire
- When narrowing roles: add new → test → remove old (never remove first)
- Clean up test SAs and bindings — leftover SAs are a security risk

### Scenario Summary Table
| Scenario | Role Type | Key Learning |
|----------|-----------|-------------|
| 1. Viewer | Predefined | Read-only, cannot modify |
| 2. Editor→Narrow | Basic→Predefined | Safe narrowing workflow |
| 3. Custom Role | Custom | Exact permissions only |
| 4. VM Attached SA | Predefined | Metadata server auth |
| 5. Conditional | Predefined+condition | Time-limited access |

---

## Part 4 — Quiz (15 min)

**Q1.** In Scenario 2, why do we add the narrow roles BEFORE removing Editor?

<details><summary>Answer</summary>

To avoid a **window of no access**. If you remove Editor first, the application loses all permissions immediately and breaks. By adding narrow roles first, you create an overlap period where both roles are active. You then test the application works with the narrow roles, and only then remove Editor. This is the same principle as doing a rolling update — never take down the old before the new is ready.

</details>

**Q2.** In Scenario 4, why use `--scopes=cloud-platform` instead of specific scopes?

<details><summary>Answer</summary>

`--scopes=cloud-platform` grants the widest OAuth scope, which means **IAM becomes the sole access control**. With narrow scopes (e.g., `--scopes=storage-ro`), the scope acts as an additional ceiling on top of IAM — even if IAM grants `storage.objects.create`, the scope blocks it. Best practice is to use `cloud-platform` and control access entirely through IAM roles on the SA. This is cleaner and easier to manage.

</details>

**Q3.** What happens when the conditional binding in Scenario 5 expires?

<details><summary>Answer</summary>

The binding still **exists in the policy** but no longer **grants access**. The condition `request.time < timestamp('2026-05-08T00:00:00Z')` evaluates to `false` after May 8, 2026, so the binding effectively becomes inert. The SA will get 403 errors. The binding should be cleaned up manually — expired conditional bindings don't auto-delete. IAM Recommender may flag them for removal.

</details>

**Q4.** How would you set up these 5 scenarios in an RHDS environment?

<details><summary>Answer</summary>

| GCP Scenario | RHDS Equivalent |
|-------------|----------------|
| Viewer SA | `aci: allow (read,search,compare)` on the subtree |
| Editor → Narrow | Replace `allow (all)` with `allow (read,search)` + `allow (write) targetattr="specific"` |
| Custom Role | Specific ACI with `targetattr` and `targetfilter` for exact attributes |
| VM Attached SA | Bind DN in application config + ACI for that DN |
| Conditional | ACI with `timeofday` or `dayofweek` filter, or `nsTimeLimit` |

In both systems, the pattern is: create identity → grant minimal access → test → revoke when done.

</details>
