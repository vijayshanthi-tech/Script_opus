# Week 19, Day 114 (Sat) — PROJECT: 5 IAM Troubleshooting Cases

## Today's Objective

Work through five realistic IAM troubleshooting scenarios end-to-end: diagnose the problem, identify the root cause, apply the fix, and verify. Each case builds on the techniques learned this week.

**Source:** [IAM Troubleshooting](https://cloud.google.com/iam/docs/troubleshooting-access) | [Policy Troubleshooter](https://cloud.google.com/policy-intelligence/docs/troubleshoot-access)

**Deliverable:** Five solved troubleshooting cases with documented diagnosis steps and permanent fixes

---

## Part 1: Concept (30 minutes)

### 1.1 The Five Cases

```
┌─────────────────────────────────────────────────────────┐
│                  5 IAM CASES                              │
│                                                          │
│  CASE 1: User can't access a GCS bucket                  │
│  ────── Missing role at the correct level                │
│                                                          │
│  CASE 2: Service account can't write to BigQuery          │
│  ────── Wrong OAuth scope on VM                          │
│                                                          │
│  CASE 3: VM can't pull images from Artifact Registry      │
│  ────── Missing scope + wrong SA                         │
│                                                          │
│  CASE 4: terraform apply fails on IAM                     │
│  ────── Missing iam.admin + authoritative conflict       │
│                                                          │
│  CASE 5: Cross-project access denied                      │
│  ────── Missing binding in target project                │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

### 1.2 Diagnostic Framework

```
For every 403 error:

1. IDENTIFY  ──► Who? What? When? Where? (from error + audit logs)
2. REPRODUCE ──► Can you trigger it yourself?
3. DIAGNOSE  ──► Policy Troubleshooter + IAM policy inspection
4. ROOT CAUSE──► Missing role? Wrong scope? Deny rule? Org policy?
5. FIX       ──► Minimum change to resolve
6. VERIFY    ──► Confirm the fix works
7. PREVENT   ──► How to prevent recurrence (TF, automation)
```

---

## Part 2: Hands-On Lab (60 minutes)

### Case Setup (5 min)

```bash
export PROJECT_ID=$(gcloud config get-value project)

# Create service accounts for the cases
gcloud iam service-accounts create case-app-sa \
  --display-name="Case Lab - App SA"
gcloud iam service-accounts create case-bq-sa \
  --display-name="Case Lab - BQ Writer SA"
gcloud iam service-accounts create case-gcr-sa \
  --display-name="Case Lab - GCR Puller SA"

APP_SA="case-app-sa@${PROJECT_ID}.iam.gserviceaccount.com"
BQ_SA="case-bq-sa@${PROJECT_ID}.iam.gserviceaccount.com"
GCR_SA="case-gcr-sa@${PROJECT_ID}.iam.gserviceaccount.com"
```

---

### CASE 1: User Can't Access a GCS Bucket (10 min)

**Scenario:** A developer reports: "I get 403 when trying to read files from `gs://team-data-bucket`. I was told I have access."

```bash
# Setup: Create bucket with no public access
gcloud storage buckets create gs://${PROJECT_ID}-case1-data \
  --location=europe-west2 \
  --uniform-bucket-level-access
echo "test data" | gcloud storage cp - gs://${PROJECT_ID}-case1-data/report.csv

# Symptom: SA (simulating user) has no role on the bucket
```

**Diagnosis:**

```bash
echo "=== CASE 1: Diagnosis ==="

# Step 1: Check project-level roles
echo "Project-level roles for app SA:"
gcloud projects get-iam-policy ${PROJECT_ID} \
  --flatten="bindings[].members" \
  --filter="bindings.members:${APP_SA}" \
  --format="table(bindings.role)"

# Step 2: Check bucket-level roles
echo ""
echo "Bucket-level roles:"
gcloud storage buckets get-iam-policy gs://${PROJECT_ID}-case1-data \
  --flatten="bindings[].members" \
  --filter="bindings.members:${APP_SA}" \
  --format="table(bindings.role)"

# Step 3: Use Policy Troubleshooter
echo ""
echo "Policy Troubleshooter:"
gcloud policy-troubleshoot iam \
  "//storage.googleapis.com/projects/_/buckets/${PROJECT_ID}-case1-data" \
  --permission="storage.objects.get" \
  --principal-email="${APP_SA}" 2>&1 | head -20
```

**Root Cause:** No IAM binding grants storage read access to the SA.

**Fix:**

```bash
# Grant bucket-level access (not project-level — least privilege)
gcloud storage buckets add-iam-policy-binding \
  gs://${PROJECT_ID}-case1-data \
  --member="serviceAccount:${APP_SA}" \
  --role="roles/storage.objectViewer"

# Verify
gcloud policy-troubleshoot iam \
  "//storage.googleapis.com/projects/_/buckets/${PROJECT_ID}-case1-data" \
  --permission="storage.objects.get" \
  --principal-email="${APP_SA}" 2>&1 | grep "GRANTED\|NOT_GRANTED"
```

**Prevention:** Manage bucket IAM in Terraform; include access as part of service onboarding.

---

### CASE 2: Service Account Can't Write to BigQuery (10 min)

**Scenario:** A VM's application writes data to BigQuery. It suddenly gets 403. The SA has `roles/bigquery.dataEditor`.

```bash
echo "=== CASE 2: Diagnosis ==="

# Setup: Grant the BQ role
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
  --member="serviceAccount:${BQ_SA}" \
  --role="roles/bigquery.dataEditor"

# Step 1: Verify the role exists
gcloud projects get-iam-policy ${PROJECT_ID} \
  --flatten="bindings[].members" \
  --filter="bindings.members:${BQ_SA}" \
  --format="table(bindings.role)"

echo "Result: YES, the SA has bigquery.dataEditor"

# Step 2: Create a VM with WRONG scopes (simulating the problem)
echo ""
echo "Creating VM with restricted scopes (compute-ro only)..."
gcloud compute instances create case2-bq-vm \
  --zone=europe-west2-a \
  --machine-type=e2-micro \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --service-account=${BQ_SA} \
  --scopes=compute-ro \
  --quiet

# Step 3: Check scopes
echo ""
echo "VM Scopes:"
gcloud compute instances describe case2-bq-vm \
  --zone=europe-west2-a \
  --format="yaml(serviceAccounts[].scopes)"
```

**Root Cause:** VM OAuth scopes are restricted to `compute-ro`. BigQuery APIs are not accessible despite the IAM role.

**Fix:**

```bash
# Must stop, change scopes, restart (or recreate)
gcloud compute instances stop case2-bq-vm --zone=europe-west2-a --quiet
gcloud compute instances set-service-account case2-bq-vm \
  --zone=europe-west2-a \
  --service-account=${BQ_SA} \
  --scopes=cloud-platform
gcloud compute instances start case2-bq-vm --zone=europe-west2-a --quiet

# Verify new scopes
echo "Fixed scopes:"
gcloud compute instances describe case2-bq-vm \
  --zone=europe-west2-a \
  --format="yaml(serviceAccounts[].scopes)"
```

**Prevention:** Always use `--scopes=cloud-platform` and control access via IAM roles only.

---

### CASE 3: VM Can't Pull Images from Artifact Registry (10 min)

**Scenario:** A VM fails to pull Docker images from Artifact Registry. Error: "denied: Permission denied."

```bash
echo "=== CASE 3: Diagnosis ==="

# Step 1: Check current SA and roles
echo "SA on the conceptual VM: ${GCR_SA}"
gcloud projects get-iam-policy ${PROJECT_ID} \
  --flatten="bindings[].members" \
  --filter="bindings.members:${GCR_SA}" \
  --format="table(bindings.role)"

echo "Result: No roles — SA was just created"

# Step 2: What role is needed?
echo ""
echo "Required: roles/artifactregistry.reader"
echo "  Grants: artifactregistry.repositories.downloadArtifacts"

# Step 3: Check if Artifact Registry API is enabled
gcloud services list --enabled --filter="name:artifactregistry" \
  --format="value(name)" || echo "API NOT ENABLED"
```

**Root Cause:** SA lacks `roles/artifactregistry.reader` AND the API may not be enabled.

**Fix:**

```bash
# Enable API if needed
gcloud services enable artifactregistry.googleapis.com

# Grant the minimum role
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
  --member="serviceAccount:${GCR_SA}" \
  --role="roles/artifactregistry.reader"

# Verify
echo "After fix:"
gcloud projects get-iam-policy ${PROJECT_ID} \
  --flatten="bindings[].members" \
  --filter="bindings.members:${GCR_SA}" \
  --format="table(bindings.role)"
```

**Prevention:** Include AR reader role in VM module defaults; check API enablement in CI.

---

### CASE 4: terraform apply Fails on IAM (10 min)

**Scenario:** `terraform apply` fails with "googleapi: Error 403: The caller does not have permission, forbidden" when managing IAM.

```bash
echo "=== CASE 4: Diagnosis ==="

# The TF SA needs:
# 1. roles/resourcemanager.projectIamAdmin (to manage project IAM)
# 2. roles/iam.serviceAccountAdmin (to manage SAs)

echo "Common missing roles for TF IAM management:"
echo "  roles/resourcemanager.projectIamAdmin  - manage project IAM bindings"
echo "  roles/iam.serviceAccountAdmin          - create/delete service accounts"
echo "  roles/iam.serviceAccountUser            - attach SAs to resources"
echo ""

# Check what the TF SA has
echo "Current TF SA roles (simulated with APP_SA):"
gcloud projects get-iam-policy ${PROJECT_ID} \
  --flatten="bindings[].members" \
  --filter="bindings.members:${APP_SA}" \
  --format="table(bindings.role)"

echo ""
echo "=== Another common issue: authoritative vs additive conflict ==="
echo "If someone uses google_project_iam_binding (authoritative per role)"
echo "and someone else uses google_project_iam_member (additive) for the"
echo "same role, they'll fight each other on every apply."
echo ""
echo "Solution: Standardise on google_project_iam_member (additive) everywhere."
```

**Root Cause:** TF service account missing `roles/resourcemanager.projectIamAdmin`.

**Fix:**

```bash
# Grant IAM management roles to the TF SA
# (In practice, this would be done by a project admin)
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
  --member="serviceAccount:${APP_SA}" \
  --role="roles/resourcemanager.projectIamAdmin"

echo "After fix:"
gcloud projects get-iam-policy ${PROJECT_ID} \
  --flatten="bindings[].members" \
  --filter="bindings.members:${APP_SA}" \
  --format="table(bindings.role)"
```

**Prevention:** Document required TF SA roles; use a bootstrap module to set up the TF SA.

---

### CASE 5: Cross-Project Access Denied (10 min)

**Scenario:** Project A's service account needs to read from a GCS bucket in Project B. Error: 403.

```bash
echo "=== CASE 5: Cross-Project Access ==="

echo "Architecture:"
echo ""
echo "  Project A                     Project B"
echo "  ┌──────────────┐             ┌──────────────┐"
echo "  │ SA: app-sa   │────403────►│ gs://proj-b   │"
echo "  │              │             │   /data/      │"
echo "  └──────────────┘             └──────────────┘"
echo ""
echo "Problem: SA exists in Project A, but the bucket is in Project B."
echo "Project A's IAM has no effect on Project B's resources."
echo ""
echo "Solution: Grant the SA access IN Project B (on the bucket or project)."
echo ""

# Simulate the fix (using same project for lab)
gcloud storage buckets create gs://${PROJECT_ID}-case5-cross \
  --location=europe-west2 \
  --uniform-bucket-level-access
echo "cross project data" | gcloud storage cp - gs://${PROJECT_ID}-case5-cross/data.txt

# Grant access to app-sa (from "Project A") on the bucket (in "Project B")
gcloud storage buckets add-iam-policy-binding \
  gs://${PROJECT_ID}-case5-cross \
  --member="serviceAccount:${APP_SA}" \
  --role="roles/storage.objectViewer"

echo "Fix applied: SA from Project A now has objectViewer on Project B's bucket"
```

**Root Cause:** IAM bindings are resource-scoped. Project A's bindings don't grant access to Project B's resources.

**Prevention:** Document cross-project access in Terraform; use shared VPC or resource-level bindings.

---

### Clean Up All Cases (5 min)

```bash
gcloud compute instances delete case2-bq-vm --zone=europe-west2-a --quiet
gcloud storage rm -r gs://${PROJECT_ID}-case1-data
gcloud storage rm -r gs://${PROJECT_ID}-case5-cross

# Remove IAM bindings
gcloud projects remove-iam-policy-binding ${PROJECT_ID} \
  --member="serviceAccount:${BQ_SA}" --role="roles/bigquery.dataEditor"
gcloud projects remove-iam-policy-binding ${PROJECT_ID} \
  --member="serviceAccount:${GCR_SA}" --role="roles/artifactregistry.reader"
gcloud projects remove-iam-policy-binding ${PROJECT_ID} \
  --member="serviceAccount:${APP_SA}" --role="roles/resourcemanager.projectIamAdmin"

# Delete SAs
gcloud iam service-accounts delete ${APP_SA} --quiet
gcloud iam service-accounts delete ${BQ_SA} --quiet
gcloud iam service-accounts delete ${GCR_SA} --quiet
```

---

## Part 3: Revision (15 minutes)

- **Case 1 (Bucket 403)** — grant access at the bucket level, not project level (least privilege)
- **Case 2 (BQ scope)** — always use `--scopes=cloud-platform`; control via IAM roles only
- **Case 3 (AR image pull)** — need `roles/artifactregistry.reader` + API enabled
- **Case 4 (TF IAM fail)** — TF SA needs `roles/resourcemanager.projectIamAdmin`; standardise on additive bindings
- **Case 5 (Cross-project)** — grant access IN the target project/resource; source project bindings don't help
- **Diagnostic framework** — identify → reproduce → diagnose → root cause → fix → verify → prevent

### Key Commands
```bash
gcloud policy-troubleshoot iam RESOURCE --permission=P --principal-email=E
gcloud projects get-iam-policy P --flatten="bindings[].members" --filter="bindings.members:M"
gcloud compute instances describe VM --format="yaml(serviceAccounts[].scopes)"
gcloud asset search-all-iam-policies --query="policy:SA_EMAIL" --scope="projects/P"
```

---

## Part 4: Quiz (15 minutes)

**Q1:** A VM with `roles/storage.admin` via IAM still can't access GCS. The VM was created with `--scopes=compute-ro`. What's wrong?
<details><summary>Answer</summary>OAuth <b>scopes restrict API access</b> at the VM level. Even though IAM grants full storage admin, the <code>compute-ro</code> scope means the VM can only call Compute Engine APIs. <b>Fix:</b> Stop the VM, change scopes to <code>cloud-platform</code>, restart. <b>Prevention:</b> Always use <code>--scopes=cloud-platform</code> and control access purely through IAM roles.</details>

**Q2:** A SA in Project A can't access a bucket in Project B. Where do you add the IAM binding?
<details><summary>Answer</summary>On the <b>bucket in Project B</b> (or at Project B's project level). IAM bindings in Project A have no effect on Project B's resources. The SA's identity (email) is global, but access is granted where the resource lives. <code>gcloud storage buckets add-iam-policy-binding gs://BUCKET_IN_B --member="serviceAccount:SA_FROM_A" --role="roles/storage.objectViewer"</code>.</details>

**Q3:** `terraform apply` alternates between adding and removing members from a role. What's the likely cause?
<details><summary>Answer</summary>Two Terraform configurations (or TF + Console) are fighting over the same role using <b>authoritative resources</b>. If one config uses <code>google_project_iam_binding</code> for <code>roles/viewer</code> with members [A,B], and another adds member C, the authoritative binding removes C on every apply, and the other process re-adds it. <b>Fix:</b> Standardise on <code>google_project_iam_member</code> (additive) everywhere. Never mix authoritative and additive for the same role.</details>

**Q4:** For each case, what's the 1-line permanent prevention?
<details><summary>Answer</summary>
<b>Case 1:</b> Include bucket IAM in the Terraform module that creates the bucket<br>
<b>Case 2:</b> Default all VM modules to <code>scopes = ["cloud-platform"]</code><br>
<b>Case 3:</b> Include AR reader role in the VM module's SA configuration<br>
<b>Case 4:</b> Bootstrap the TF SA with documented required roles via a separate admin module<br>
<b>Case 5:</b> Document and code cross-project bindings in the consuming project's Terraform
</details>
