# Day 63 — Least Privilege Exercise

> **Week 11 · Security Posture**
> Estimated time: 2 hours | Region: `europe-west2` (London)
> Prerequisites: Day 62 IAM Intro completed

---

## Part 1 — Concept (30 min)

### Principle of Least Privilege

```
Linux Analogy
─────────────
  Bad:   chmod 777 /data/app.conf     ← everyone can read/write/execute
  Good:  chmod 640 /data/app.conf     ← owner=rw, group=r, other=none

  Bad:   Running nginx as root        ← if hacked, attacker is root
  Good:  Running nginx as www-data    ← if hacked, attacker is limited

GCP Equivalent:
  Bad:   VM with default SA (roles/editor)   ← access to everything
  Good:  VM with custom SA (roles/logging.logWriter only)
```

### Access Matrix Approach

```
┌────────────────────────────────────────────────────┐
│            ACCESS MATRIX                            │
│                                                     │
│  Role ↓ / Resource →  │ VMs │ Storage │ IAM │ Logs │
│  ──────────────────────┼─────┼─────────┼─────┼──────│
│  SRE Team              │ RW  │  R      │ R   │ RW   │
│  Developers            │ R   │  RW     │ ─   │ R    │
│  Security Team         │ R   │  R      │ RW  │ RW   │
│  CI/CD Service Acct    │ RW  │  RW     │ ─   │ W    │
│  Monitoring SA         │ R   │  ─      │ ─   │ RW   │
│  App VM SA             │ ─   │  R      │ ─   │ W    │
│                                                     │
│  R = Read, W = Write, RW = Read+Write, ─ = None    │
└────────────────────────────────────────────────────┘
```

### Custom Roles — Build Your Own

```
Predefined Role: roles/compute.instanceAdmin.v1
  Contains 50+ permissions including:
  ✓ compute.instances.create
  ✓ compute.instances.delete       ← Too much for an operator!
  ✓ compute.instances.get
  ✓ compute.instances.list
  ✓ compute.instances.start
  ✓ compute.instances.stop
  ✓ compute.instances.setMetadata  ← Could inject SSH keys!
  ✓ compute.instances.setTags
  ✓ ... many more

Custom Role: vmOperator
  Contains only what's needed:
  ✓ compute.instances.get
  ✓ compute.instances.list
  ✓ compute.instances.start
  ✓ compute.instances.stop
  ✗ No create/delete/setMetadata
```

### IAM Recommender

```
┌────────────────────────────────────────────────────┐
│              IAM RECOMMENDER                        │
│                                                     │
│  Analyzes 90 days of IAM usage patterns:            │
│                                                     │
│  user:alice@company.com                             │
│    Current role: roles/editor                       │
│    Actually used: 12 out of 3,000+ permissions     │
│                                                     │
│  Recommendation:                                    │
│    REPLACE roles/editor                             │
│    WITH roles/compute.viewer + roles/logging.viewer │
│                                                     │
│  Confidence: HIGH (based on 90-day activity)        │
│  Savings: Removed 2,988 unused permissions          │
└────────────────────────────────────────────────────┘
```

### Permission Testing Strategy

```
Test Matrix:
┌───────────────────────────────────────────────────┐
│ Action               │ Expected │ SA: app │ SA: op│
│──────────────────────┼──────────┼─────────┼───────│
│ List VMs             │ app:✗ op:✓│  Test  │  Test │
│ Start VM             │ app:✗ op:✓│  Test  │  Test │
│ Stop VM              │ app:✗ op:✓│  Test  │  Test │
│ Create VM            │ app:✗ op:✗│  Test  │  Test │
│ Delete VM            │ app:✗ op:✗│  Test  │  Test │
│ Write logs           │ app:✓ op:✗│  Test  │  Test │
│ Read storage object  │ app:✓ op:✗│  Test  │  Test │
└───────────────────────────────────────────────────┘
```

---

## Part 2 — Hands-On Lab (60 min)

### Lab Objective

Create custom roles, assign them to service accounts, test the access matrix, and use IAM Recommender to audit excessive permissions.

### Step 1 — Set Variables

```bash
export PROJECT_ID=$(gcloud config get-value project)
export REGION=europe-west2
export ZONE=europe-west2-a
```

### Step 2 — Create Custom Role: VM Operator

```bash
gcloud iam roles create vmOperator \
    --project=$PROJECT_ID \
    --title="VM Operator" \
    --description="Can start, stop, and list VMs only" \
    --permissions="compute.instances.get,compute.instances.list,compute.instances.start,compute.instances.stop,compute.instances.reset,compute.zones.list,compute.projects.get"
```

### Step 3 — Create Custom Role: App Runner

```bash
gcloud iam roles create appRunner \
    --project=$PROJECT_ID \
    --title="App Runner" \
    --description="Minimal SA for application VMs" \
    --permissions="logging.logEntries.create,monitoring.metricDescriptors.create,monitoring.metricDescriptors.list,monitoring.timeSeries.create"
```

### Step 4 — Create Service Accounts

```bash
# Operator SA
gcloud iam service-accounts create vm-operator-sa \
    --display-name="VM Operator SA"

# App SA
gcloud iam service-accounts create app-runner-sa \
    --display-name="App Runner SA"

OP_SA="vm-operator-sa@${PROJECT_ID}.iam.gserviceaccount.com"
APP_SA="app-runner-sa@${PROJECT_ID}.iam.gserviceaccount.com"
```

### Step 5 — Assign Custom Roles

```bash
# VM Operator role to operator SA
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$OP_SA" \
    --role="projects/$PROJECT_ID/roles/vmOperator"

# App Runner role to app SA
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$APP_SA" \
    --role="projects/$PROJECT_ID/roles/appRunner"
```

### Step 6 — Create Test VMs with Custom SAs

```bash
# VM with app-runner SA
gcloud compute instances create app-vm \
    --zone=$ZONE \
    --machine-type=e2-micro \
    --image-family=debian-12 \
    --image-project=debian-cloud \
    --service-account=$APP_SA \
    --scopes=cloud-platform \
    --no-address \
    --tags=allow-iap

# Firewall for IAP SSH
gcloud compute firewall-rules create allow-iap-least-priv \
    --network=default --action=allow --direction=ingress \
    --source-ranges=35.235.240.0/20 --rules=tcp:22 \
    --target-tags=allow-iap
```

### Step 7 — Test Access From App VM

```bash
# SSH into the app-vm and test permissions
gcloud compute ssh app-vm --zone=$ZONE --tunnel-through-iap

# Inside the VM:
# Test 1: List VMs — should FAIL (app SA doesn't have compute permissions)
gcloud compute instances list 2>&1

# Test 2: Write a log entry — should SUCCEED
gcloud logging write test-log "Hello from app-vm" --severity=INFO 2>&1

# Test 3: Read a storage bucket — should FAIL
gsutil ls gs://some-bucket 2>&1

# Exit SSH
exit
```

### Step 8 — Check IAM Recommender

```bash
# List role recommendations
gcloud recommender recommendations list \
    --project=$PROJECT_ID \
    --location=global \
    --recommender=google.iam.policy.Recommender \
    --format="table(name.basename(), description, primaryImpact)" \
    --limit=10
```

### Step 9 — Audit Excessive Bindings

```bash
# Find all principals with basic roles (owner/editor/viewer)
echo "=== Principals with Basic Roles ==="
gcloud projects get-iam-policy $PROJECT_ID \
    --flatten="bindings[].members" \
    --filter="bindings.role:(roles/owner OR roles/editor OR roles/viewer)" \
    --format="table(bindings.role, bindings.members)"

# Find all service accounts with their roles
echo "=== Service Account Roles ==="
gcloud projects get-iam-policy $PROJECT_ID \
    --flatten="bindings[].members" \
    --filter="bindings.members:serviceAccount:" \
    --format="table(bindings.members, bindings.role)"
```

### Step 10 — Update Custom Role (Add Permission)

```bash
# Add a permission to the operator role
gcloud iam roles update vmOperator \
    --project=$PROJECT_ID \
    --add-permissions="compute.instances.getSerialPortOutput"

# Verify
gcloud iam roles describe vmOperator --project=$PROJECT_ID \
    --format="yaml(includedPermissions)"
```

### Cleanup

```bash
gcloud compute instances delete app-vm --zone=$ZONE --quiet
gcloud compute firewall-rules delete allow-iap-least-priv --quiet
gcloud projects remove-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$OP_SA" --role="projects/$PROJECT_ID/roles/vmOperator"
gcloud projects remove-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$APP_SA" --role="projects/$PROJECT_ID/roles/appRunner"
gcloud iam service-accounts delete $OP_SA --quiet
gcloud iam service-accounts delete $APP_SA --quiet
gcloud iam roles delete vmOperator --project=$PROJECT_ID --quiet
gcloud iam roles delete appRunner --project=$PROJECT_ID --quiet
```

---

## Part 3 — Revision (15 min)

### Key Concepts

- **Least privilege**: grant only the permissions actually needed
- **Custom roles**: cherry-pick exact permissions; more secure than predefined
- **IAM Recommender**: analyses 90 days of usage, suggests permission reductions
- **Access matrix**: document WHO needs WHAT on WHICH resources before assigning
- **Test permissions**: actually verify that denied actions are denied
- **Service accounts**: one per application/service, never share
- **Basic roles** (editor/owner): flag for remediation in any security audit
- Custom roles can be updated (add/remove permissions) without recreating

### Essential Commands

```bash
# Create custom role
gcloud iam roles create ROLE_ID --project=PROJECT \
    --title="Title" --permissions="perm1,perm2,perm3"

# Update custom role
gcloud iam roles update ROLE_ID --project=PROJECT --add-permissions="perm4"

# List custom roles
gcloud iam roles list --project=PROJECT

# IAM Recommender
gcloud recommender recommendations list --recommender=google.iam.policy.Recommender

# Test permissions
gcloud projects test-iam-permissions PROJECT --permissions="perm1,perm2"
```

---

## Part 4 — Quiz (15 min)

**Question 1: Your default Compute Engine service account has `roles/editor`. Why is this dangerous and what should you do?**

<details>
<summary>Show Answer</summary>

`roles/editor` grants write access to nearly **every GCP service** in the project. Every VM using the default SA can:
- Read all Cloud Storage data
- Delete Compute Engine resources
- Access BigQuery datasets
- Modify Pub/Sub topics

If **any** VM is compromised, the attacker has broad access to the entire project.

**Fix**:
1. Create a **custom service account** per application with only needed permissions
2. Remove `roles/editor` from the default SA
3. Assign the custom SA when creating VMs: `--service-account=my-sa@...`
4. Use `--scopes=cloud-platform` with the custom SA (scopes limit the SA's API access scope)

</details>

**Question 2: You created a custom role with `compute.instances.start` but the SA still can't start VMs. What might be wrong?**

<details>
<summary>Show Answer</summary>

Common causes:

1. **Missing dependent permissions**: `compute.instances.start` may also need `compute.instances.get` and `compute.zones.list` and `compute.projects.get`
2. **Role not bound**: Created the role but forgot to bind it to the SA
3. **Wrong project**: Role created in project A, bound in project B
4. **Org policy**: An organizational policy might restrict the action
5. **Scope limitation**: If using service account scopes, `cloud-platform` scope is needed

Fix: Add dependent permissions:
```bash
gcloud iam roles update ROLE --add-permissions="compute.instances.get,compute.zones.list,compute.projects.get"
```

</details>

**Question 3: IAM Recommender suggests removing `roles/editor` from a user and replacing with `roles/compute.viewer` + `roles/storage.objectViewer`. Should you blindly apply this?**

<details>
<summary>Show Answer</summary>

**No.** While the Recommender analyses 90 days of activity, consider:

1. **Seasonal tasks**: The user may need permissions they haven't used recently (e.g., quarterly reports, annual audits)
2. **Emergency access**: They may need broader access during incidents
3. **New projects**: They may be starting new work requiring different permissions
4. **Team changes**: Their role in the team may be expanding

**Best practice**: Review the recommendation with the user/manager, apply the change, and have a process to quickly grant additional permissions if needed (break-glass procedure). Never apply IAM recommendations without review.

</details>

**Question 4: How would you implement "break-glass" emergency access in GCP?**

<details>
<summary>Show Answer</summary>

A break-glass procedure grants temporary elevated access during incidents:

1. **Create an emergency group**: `group:break-glass@company.com` with `roles/owner`
2. **Keep the group empty** normally
3. During an incident, add the responder to the group
4. After resolution, **remove** them from the group
5. **Audit**: Set an alert on group membership changes

Alternative with IAM conditions:
```bash
gcloud projects add-iam-policy-binding PROJECT \
    --member="user:oncall@company.com" \
    --role="roles/editor" \
    --condition='expression=request.time < timestamp("2026-04-09T00:00:00Z"),title=Emergency access expires'
```

This auto-expires the elevated access.

</details>

---

*Next: [Day 64 — No Public IP Approach](DAY_64_NO_PUBLIC_IP.md)*
