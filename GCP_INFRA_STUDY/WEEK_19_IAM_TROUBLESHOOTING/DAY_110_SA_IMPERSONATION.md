# Week 19, Day 110 (Tue) — Service Account Impersonation

## Today's Objective

Learn why service account impersonation is preferred over key download, how to configure it with `--impersonate-service-account`, use it in Terraform workflows, understand impersonation chains, and audit impersonation activity.

**Source:** [SA Impersonation](https://cloud.google.com/iam/docs/service-account-impersonation) | [Terraform with Impersonation](https://cloud.google.com/docs/terraform/authentication#impersonation)

**Deliverable:** A working impersonation setup where your user account runs Terraform as a service account without downloading keys

---

## Part 1: Concept (30 minutes)

### 1.1 Why Impersonation Over Key Download?

```
Linux analogy:

sudo -u serviceuser command       ──►    --impersonate-service-account=SA
  - Your identity in audit logs          - Your identity in audit logs
  - No shared password needed            - No key file needed
  - sudoers controls who can             - IAM controls who can
  - Revoke sudo, not the user            - Revoke token creator role

vs. su - serviceuser (with password)  ──►  Download SA key file
  - Password can be stolen                 - Key file can be leaked
  - Hard to audit who used it              - Hard to audit (all look like SA)
  - Stored on disk                         - Stored on disk / in CI
  - Must rotate manually                   - Must rotate manually
```

### 1.2 Key Download vs Impersonation

| Aspect | Key Download | Impersonation |
|---|---|---|
| **File on disk** | Yes (JSON key) | No |
| **Rotation** | Manual (must regenerate) | Automatic (token expires ~1h) |
| **Audit trail** | "SA did it" (who?) | "User X as SA" (clear!) |
| **Revocation** | Delete key, re-distribute | Remove `iam.serviceAccountTokenCreator` role |
| **Blast radius** | Anyone with key file | Only authorised impersonators |
| **CI/CD** | Store key in secrets manager | Use Workload Identity Federation |

### 1.3 Impersonation Architecture

```
┌────────────────┐                      ┌──────────────────┐
│  Your Identity │  "I want to act as"  │  Service Account │
│                │ ─────────────────────►│                  │
│  user@org.com  │                      │  tf-sa@proj.iam  │
│                │◄─── short-lived ─────│                  │
│                │     access token     │  Has: Editor     │
│                │     (~1 hour)        │  on project      │
└────────────────┘                      └──────────────────┘

Requires: user@org.com has
  roles/iam.serviceAccountTokenCreator
  on tf-sa@proj.iam.gserviceaccount.com

Audit log entry:
  "principalEmail": "user@org.com"
  "serviceAccountDelegationInfo": ["tf-sa@proj.iam"]
```

### 1.4 Impersonation Chain

```
User A ──► impersonates SA-1 ──► impersonates SA-2
                                  (delegation chain)

Example:
  Developer ──► project-admin-sa ──► bigquery-writer-sa

  Developer has: tokenCreator on project-admin-sa
  project-admin-sa has: tokenCreator on bigquery-writer-sa

  gcloud --impersonate-service-account=project-admin-sa \
    auth print-access-token --scopes=...

Max chain length: 4 (including the original caller)
```

### 1.5 Terraform with Impersonation

```hcl
# Instead of:
provider "google" {
  credentials = file("key.json")    # BAD: key on disk
}

# Use:
provider "google" {
  impersonate_service_account = "tf-sa@project.iam.gserviceaccount.com"
}
# Your user's token is used to get a short-lived SA token
# Audit log shows: "your-user impersonating tf-sa"
```

### 1.6 When to Use What

| Scenario | Approach |
|---|---|
| Developer running Terraform locally | Impersonation |
| CI/CD pipeline in GCP | Workload Identity Federation |
| CI/CD pipeline outside GCP | WIF or impersonation via OIDC |
| VM accessing GCP APIs | Attached service account (no keys) |
| Legacy system, no other option | Key download (last resort) |

---

## Part 2: Hands-On Lab (60 minutes)

### Step 1: Create the Service Accounts (10 min)

```bash
export PROJECT_ID=$(gcloud config get-value project)
export USER_EMAIL=$(gcloud config get-value account)

# Create a Terraform service account
gcloud iam service-accounts create tf-impersonate-sa \
  --display-name="Terraform Impersonation Lab SA" \
  --description="SA to be impersonated for Terraform operations"

TF_SA="tf-impersonate-sa@${PROJECT_ID}.iam.gserviceaccount.com"
echo "TF SA: $TF_SA"

# Grant the SA necessary project roles
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
  --member="serviceAccount:${TF_SA}" \
  --role="roles/compute.instanceAdmin.v1" \
  --condition=None

gcloud projects add-iam-policy-binding ${PROJECT_ID} \
  --member="serviceAccount:${TF_SA}" \
  --role="roles/iam.serviceAccountUser" \
  --condition=None
```

### Step 2: Grant Impersonation Permission (5 min)

```bash
# Allow your user to impersonate the TF SA
gcloud iam service-accounts add-iam-policy-binding ${TF_SA} \
  --member="user:${USER_EMAIL}" \
  --role="roles/iam.serviceAccountTokenCreator"

echo "You can now impersonate: ${TF_SA}"
```

### Step 3: Test Impersonation with gcloud (10 min)

```bash
# Normal command (as yourself)
echo "=== As yourself ==="
gcloud auth list --filter=status:ACTIVE --format="value(account)"

# Impersonated command (as the SA)
echo ""
echo "=== Impersonating SA ==="
gcloud compute instances list \
  --project=${PROJECT_ID} \
  --impersonate-service-account=${TF_SA} \
  --format="table(name, zone, status)" 2>&1

echo ""
echo "=== Generate token (shows short-lived nature) ==="
gcloud auth print-access-token \
  --impersonate-service-account=${TF_SA} \
  --lifetime=300 2>&1 | head -c 50
echo "... (truncated)"
```

### Step 4: Terraform with Impersonation (20 min)

```bash
mkdir -p tf-impersonate-lab && cd tf-impersonate-lab

cat > main.tf <<'EOF'
terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

# Impersonate the SA instead of using a key file
provider "google" {
  project                     = var.project_id
  region                      = "europe-west2"
  impersonate_service_account = var.terraform_sa_email
}

variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "terraform_sa_email" {
  type        = string
  description = "Service account to impersonate"
}

# Create a resource as the impersonated SA
resource "google_compute_instance" "impersonation_test" {
  name         = "impersonation-lab-vm"
  machine_type = "e2-micro"
  zone         = "europe-west2-a"

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 10
    }
  }

  network_interface {
    network = "default"
  }

  labels = {
    env        = "lab"
    created_by = "impersonated-terraform"
    week       = "19"
  }
}

output "vm_name" {
  value = google_compute_instance.impersonation_test.name
}

output "vm_self_link" {
  value = google_compute_instance.impersonation_test.self_link
}
EOF

cat > terraform.tfvars <<EOF
project_id         = "${PROJECT_ID}"
terraform_sa_email = "${TF_SA}"
EOF

# Init and apply
terraform init
terraform plan    # Watch: it shows "Impersonating SA: tf-impersonate-sa@..."
terraform apply -auto-approve
```

### Step 5: Verify Audit Trail (10 min)

```bash
# Check audit logs — should show YOUR email as the caller
# with delegated SA in the chain
gcloud logging read "
  protoPayload.methodName=\"v1.compute.instances.insert\" AND
  protoPayload.resourceName=~\"impersonation-lab-vm\"
" --limit=5 --format="yaml(
  protoPayload.authenticationInfo.principalEmail,
  protoPayload.authenticationInfo.serviceAccountDelegationInfo,
  protoPayload.methodName,
  timestamp
)" --freshness=30m

echo ""
echo "=== Key Audit Points ==="
echo "principalEmail should show: your user email (not the SA)"
echo "serviceAccountDelegationInfo should show: ${TF_SA}"
echo "This proves WHO ran the command THROUGH which SA"
```

### Step 6: Clean Up (5 min)

```bash
cd tf-impersonate-lab
terraform destroy -auto-approve
cd ~
rm -rf tf-impersonate-lab

# Remove IAM bindings
gcloud projects remove-iam-policy-binding ${PROJECT_ID} \
  --member="serviceAccount:${TF_SA}" \
  --role="roles/compute.instanceAdmin.v1"

gcloud projects remove-iam-policy-binding ${PROJECT_ID} \
  --member="serviceAccount:${TF_SA}" \
  --role="roles/iam.serviceAccountUser"

# Delete the SA
gcloud iam service-accounts delete ${TF_SA} --quiet
```

---

## Part 3: Revision (15 minutes)

- **Impersonation > key download** — no keys on disk, short-lived tokens, clear audit trail
- **Required role** — `roles/iam.serviceAccountTokenCreator` on the SA being impersonated
- **gcloud** — `--impersonate-service-account=SA_EMAIL`
- **Terraform** — `impersonate_service_account` in provider block
- **Audit trail** — shows `principalEmail` (who) + `serviceAccountDelegationInfo` (via which SA)
- **Token lifetime** — default ~1 hour, max 12 hours; auto-refreshed
- **Chain limit** — max 4 hops in an impersonation chain

### Key Commands
```bash
gcloud iam service-accounts add-iam-policy-binding SA \
  --member="user:EMAIL" --role="roles/iam.serviceAccountTokenCreator"
gcloud --impersonate-service-account=SA compute instances list
gcloud auth print-access-token --impersonate-service-account=SA
```

---

## Part 4: Quiz (15 minutes)

**Q1:** Why is `--impersonate-service-account` better than downloading a key JSON file?
<details><summary>Answer</summary>Key files are <b>persistent credentials</b> — they never expire until deleted, can be copied/leaked, and audit logs only show "the SA did it" (not who used the key). Impersonation uses <b>short-lived tokens</b> (~1h), requires no file on disk, audit logs show the real user + SA chain, and revoking access means removing one IAM role. Like <code>sudo -u</code> (auditable, revokable) vs sharing a password (persistent, hard to track).</details>

**Q2:** A CI/CD pipeline needs to run Terraform. Should it use impersonation or Workload Identity Federation?
<details><summary>Answer</summary>For CI/CD <b>running on GCP</b> (Cloud Build, GKE), use <b>Workload Identity Federation (WIF)</b> — it maps the CI/CD identity to a GCP SA without any keys. For CI/CD <b>outside GCP</b> (GitHub Actions, GitLab), use <b>WIF with OIDC</b> — the external identity provider's token is exchanged for a GCP token. Impersonation is best for <b>interactive developer</b> use. Never download key files for CI/CD — use WIF.</details>

**Q3:** The audit log shows `principalEmail: tf-sa@project.iam` with no delegation info. What happened?
<details><summary>Answer</summary>Someone used the SA <b>directly</b> — likely via a downloaded key file or from a VM with that SA attached. There's no impersonation chain because the request came directly from the SA, not through a user. This is the <b>audit visibility problem</b> with keys: you can't tell which human initiated the action. Investigate: who has access to the key file? Was it a VM's attached SA? Migrate to impersonation or WIF for better audit trails.</details>

**Q4:** You try to impersonate a SA and get "Permission 'iam.serviceAccounts.getAccessToken' denied". What's missing?
<details><summary>Answer</summary>You're missing <code>roles/iam.serviceAccountTokenCreator</code> on the target service account. This role grants <code>iam.serviceAccounts.getAccessToken</code> which is needed for impersonation. Grant it with: <code>gcloud iam service-accounts add-iam-policy-binding SA_EMAIL --member="user:YOUR_EMAIL" --role="roles/iam.serviceAccountTokenCreator"</code>. Note: the role must be granted <b>on the SA resource</b> (not at project level, though project-level also works but is broader).</details>
