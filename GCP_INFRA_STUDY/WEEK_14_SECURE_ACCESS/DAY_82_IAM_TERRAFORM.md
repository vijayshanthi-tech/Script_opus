# Day 82 — IAM Bindings with Terraform: Authoritative vs Additive

> **Week 14 — Secure Access** | ⏱ 2 hours | Region: `europe-west2`
> Student profile: 6 yrs Linux infra, 3 yrs RHDS LDAP, ACE certified

---

## Part 1 — Concept (30 min)

### 1.1 Three Terraform IAM Resources — Critical Differences

```
  ┌────────────────────────────────────────────────────────────────┐
  │        TERRAFORM IAM RESOURCES — KNOW THE DIFFERENCE          │
  ├──────────────────────┬─────────────────┬──────────────────────┤
  │ google_project_iam_  │ google_project_ │ google_project_iam_  │
  │ policy               │ iam_binding     │ member               │
  │ (AUTHORITATIVE-ALL)  │ (AUTHORITATIVE  │ (ADDITIVE)           │
  │                      │  PER ROLE)      │                      │
  ├──────────────────────┼─────────────────┼──────────────────────┤
  │ Manages ENTIRE       │ Manages ALL     │ Manages ONE          │
  │ IAM policy           │ members for     │ member for           │
  │                      │ ONE role        │ ONE role             │
  │                      │                 │                      │
  │ ⚠ REMOVES all        │ ⚠ REMOVES       │ ✅ ONLY adds/removes │
  │ bindings not in TF   │ members not in  │ the specified        │
  │                      │ TF for that role│ member-role pair     │
  │                      │                 │                      │
  │ DANGER: Can lock     │ RISK: Can remove│ SAFE: Won't affect   │
  │ you out of project   │ manually added  │ other bindings       │
  │                      │ members         │                      │
  │                      │                 │                      │
  │ Use: full IaC control│ Use: team owns  │ Use: adding single   │
  │ of project IAM       │ entire role     │ bindings alongside   │
  │                      │                 │ manual management    │
  └──────────────────────┴─────────────────┴──────────────────────┘
```

**Linux analogy:**
| Terraform Resource | Linux Equivalent |
|-------------------|------------------|
| `iam_policy` | Overwriting entire `/etc/sudoers` |
| `iam_binding` | Replacing all entries for one sudo group |
| `iam_member` | Adding one line to `/etc/sudoers` |

### 1.2 Visual: How Each Resource Behaves

```
  BEFORE TERRAFORM APPLY:
  ─────────────────────────
  Project has these bindings:
  ├── roles/viewer:    [alice, bob]       (manual)
  ├── roles/editor:    [charlie]          (manual)
  └── roles/owner:     [admin]            (manual)

  ═══════════════════════════════════════════════════

  AFTER google_project_iam_policy { ... only viewer for dave }:
  ├── roles/viewer:    [dave]             ← ONLY this remains
  ├── roles/editor:    REMOVED            ← ⚠ GONE
  └── roles/owner:     REMOVED            ← ⚠ GONE (LOCKED OUT!)

  AFTER google_project_iam_binding { role=viewer, members=[dave] }:
  ├── roles/viewer:    [dave]             ← alice, bob REMOVED
  ├── roles/editor:    [charlie]          ← untouched
  └── roles/owner:     [admin]            ← untouched

  AFTER google_project_iam_member { role=viewer, member=dave }:
  ├── roles/viewer:    [alice, bob, dave] ← dave ADDED
  ├── roles/editor:    [charlie]          ← untouched
  └── roles/owner:     [admin]            ← untouched
```

### 1.3 When to Use Each

```
  DECISION MATRIX
  ═══════════════

  ┌─────────────────────────────────────────────────┐
  │ Question                           │ Resource    │
  ├────────────────────────────────────┼─────────────┤
  │ "I want TF to own ALL IAM"        │ iam_policy  │
  │ "I want TF to own one role"       │ iam_binding │
  │ "I want to add one binding"       │ iam_member  │
  │ "Mixed TF + Console management"   │ iam_member  │
  │ "Full compliance — TF is truth"    │ iam_policy  │
  │ "Team-managed role membership"     │ iam_binding │
  │ "One-off access grants"           │ iam_member  │
  └─────────────────────────────────────────────────┘

  RECOMMENDATION: Start with iam_member (safest)
  Graduate to iam_binding when team is comfortable
  Use iam_policy only with strong process controls
```

### 1.4 SA Creation in Terraform

```hcl
  # Create a service account
  resource "google_service_account" "web_app" {
    account_id   = "web-prod-reader"
    display_name = "Web Frontend - Production Reader"
    description  = "Reads static assets from GCS"
    project      = var.project_id
  }

  # Grant role using iam_member (safe)
  resource "google_project_iam_member" "web_storage" {
    project = var.project_id
    role    = "roles/storage.objectViewer"
    member  = "serviceAccount:${google_service_account.web_app.email}"
  }

  # Output the SA email
  output "web_sa_email" {
    value = google_service_account.web_app.email
  }
```

### 1.5 Conditional IAM in Terraform

```hcl
  # Time-limited access
  resource "google_project_iam_member" "temp_admin" {
    project = var.project_id
    role    = "roles/compute.instanceAdmin.v1"
    member  = "user:oncall@company.com"

    condition {
      title       = "temp-access-30d"
      description = "Temporary admin during incident window"
      expression  = "request.time < timestamp('2026-05-08T00:00:00Z')"
    }
  }

  # Resource-tag condition
  resource "google_project_iam_member" "prod_only" {
    project = var.project_id
    role    = "roles/compute.viewer"
    member  = "group:prod-team@company.com"

    condition {
      title       = "prod-tagged-only"
      description = "Access only to resources tagged as production"
      expression  = "resource.matchTag('env', 'prod')"
    }
  }
```

> **RHDS parallel:** Terraform IAM is like managing ACIs with Ansible/LDIF scripts. `iam_policy` = replacing all ACIs under a subtree (dangerous). `iam_binding` = replacing all entries for one ACI (risky). `iam_member` = adding one userdn to an existing ACI (safe). In RHDS automation, you'd use `ldapmodify` to add entries — the equivalent of `iam_member`.

---

## Part 2 — Hands-On Lab (60 min)

### Prerequisites
```bash
export PROJECT_ID=$(gcloud config get-value project)
export REGION=europe-west2
export ZONE=europe-west2-a

# Create working directory
mkdir -p /tmp/iam-tf-lab && cd /tmp/iam-tf-lab
```

### Lab 2.1 — Terraform SA Creation + iam_member

```bash
cat > main.tf << 'EOF'
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

variable "project_id" {
  type = string
}

variable "region" {
  type    = string
  default = "europe-west2"
}

# Create Service Account
resource "google_service_account" "app_sa" {
  account_id   = "tf-app-reader"
  display_name = "TF Lab App Reader"
  description  = "Created by Terraform for IAM lab"
  project      = var.project_id
}

# Grant role using iam_member (ADDITIVE — safe)
resource "google_project_iam_member" "app_storage_viewer" {
  project = var.project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${google_service_account.app_sa.email}"
}

resource "google_project_iam_member" "app_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.app_sa.email}"
}

output "service_account_email" {
  value = google_service_account.app_sa.email
}
EOF

# Initialize and plan
terraform init

echo ""
echo "--- Terraform Plan ---"
terraform plan -var="project_id=$PROJECT_ID"
```

### Lab 2.2 — Apply and Verify

```bash
# Apply
terraform apply -var="project_id=$PROJECT_ID" -auto-approve

# Verify in GCP
SA_EMAIL=$(terraform output -raw service_account_email)
echo ""
echo "--- SA created: $SA_EMAIL ---"

echo "--- Roles granted ---"
gcloud projects get-iam-policy $PROJECT_ID \
  --flatten="bindings[].members" \
  --filter="bindings.members:$SA_EMAIL" \
  --format="table(bindings.role)"
```

### Lab 2.3 — Compare iam_binding Behaviour

```bash
# Add a binding file to show iam_binding
cat > binding_example.tf << 'EOF'
# WARNING: This is AUTHORITATIVE for this role
# It will REMOVE any manually added members for this role

# resource "google_project_iam_binding" "viewer_binding" {
#   project = var.project_id
#   role    = "roles/compute.viewer"
#   members = [
#     "serviceAccount:${google_service_account.app_sa.email}",
#   ]
# }

# SAFER ALTERNATIVE: iam_member
resource "google_project_iam_member" "app_compute_viewer" {
  project = var.project_id
  role    = "roles/compute.viewer"
  member  = "serviceAccount:${google_service_account.app_sa.email}"
}
EOF

echo "--- Comparing approaches ---"
echo ""
echo "iam_binding (commented out): Would REPLACE all members for compute.viewer"
echo "iam_member (active):         Would ADD one member for compute.viewer"
echo ""

terraform plan -var="project_id=$PROJECT_ID"
```

### Lab 2.4 — Add Conditional IAM Binding

```bash
cat > conditional.tf << 'EOF'
# Time-limited compute access
resource "google_project_iam_member" "temp_compute" {
  project = var.project_id
  role    = "roles/compute.instanceAdmin.v1"
  member  = "serviceAccount:${google_service_account.app_sa.email}"

  condition {
    title       = "temp-access-lab"
    description = "Temporary access for lab exercise"
    expression  = "request.time < timestamp('2026-05-08T00:00:00Z')"
  }
}
EOF

terraform plan -var="project_id=$PROJECT_ID"
terraform apply -var="project_id=$PROJECT_ID" -auto-approve

# Verify conditional binding
SA_EMAIL=$(terraform output -raw service_account_email)
echo "--- Conditional bindings ---"
gcloud projects get-iam-policy $PROJECT_ID \
  --flatten="bindings[].members" \
  --filter="bindings.members:$SA_EMAIL AND bindings.condition:*" \
  --format="yaml(bindings.role, bindings.condition)"
```

### Lab 2.5 — View the Terraform State

```bash
# Show the state — what TF is tracking
echo "--- Terraform state resources ---"
terraform state list

echo ""
echo "--- Detail of SA resource ---"
terraform state show google_service_account.app_sa

echo ""
echo "--- Detail of IAM member ---"
terraform state show google_project_iam_member.app_storage_viewer
```

### 🧹 Cleanup

```bash
# Destroy all resources created by Terraform
terraform destroy -var="project_id=$PROJECT_ID" -auto-approve

# Verify cleanup
echo "--- Verify SA deleted ---"
gcloud iam service-accounts list --filter="email:tf-app-reader" --format="value(email)"

# Remove working directory
cd ~
rm -rf /tmp/iam-tf-lab
```

---

## Part 3 — Revision (15 min)

### Key Concepts
- **3 IAM resources:** `iam_policy` (all bindings), `iam_binding` (all members per role), `iam_member` (one member-role pair)
- `iam_policy` is **authoritative** — removes ALL bindings not in TF (can lock you out!)
- `iam_binding` is **authoritative per role** — removes members not listed for that role
- `iam_member` is **additive** — only adds/removes the specified pair (safest)
- **Start with `iam_member`**, graduate to `iam_binding` when mature
- SA creation in TF: `google_service_account` resource
- Conditional IAM: add `condition` block with CEL expression
- Never mix `iam_binding` and `iam_member` for the same role — they'll fight

### Essential Terraform Blocks
```hcl
# SA creation
resource "google_service_account" "sa" {
  account_id   = "name"
  display_name = "Display Name"
}

# Additive binding (safe)
resource "google_project_iam_member" "binding" {
  project = var.project_id
  role    = "roles/ROLE"
  member  = "serviceAccount:${google_service_account.sa.email}"
}

# Conditional binding
resource "google_project_iam_member" "conditional" {
  project = var.project_id
  role    = "roles/ROLE"
  member  = "TYPE:EMAIL"
  condition {
    title      = "condition-name"
    expression = "CEL_EXPRESSION"
  }
}
```

---

## Part 4 — Quiz (15 min)

**Q1.** You have 3 team members manually added as `roles/compute.viewer` via Console. You write a Terraform `google_project_iam_binding` for `roles/compute.viewer` with only 2 SAs. What happens on `terraform apply`?

<details><summary>Answer</summary>

The 3 manually added team members will be **removed** from `roles/compute.viewer`. `iam_binding` is authoritative per role — it sets the complete member list for that role. After apply, only the 2 SAs will have the viewer role. Use `iam_member` instead if you want to coexist with manually managed bindings.

</details>

**Q2.** Your organization uses Terraform for all IAM. A colleague runs `gcloud projects add-iam-policy-binding` to add a quick fix. What happens on the next `terraform apply`?

<details><summary>Answer</summary>

It depends on which TF resource type is used:
- **`iam_policy`**: The manually added binding gets **removed** — TF overwrites the entire policy.
- **`iam_binding`**: If the manual binding is for a role managed by TF, it gets **removed**. If it's for a different role, it **stays**.
- **`iam_member`**: The manual binding **stays** — TF only manages the specific member-role pairs it knows about.

This is why process discipline is critical — if using `iam_policy/binding`, ALL changes must go through TF.

</details>

**Q3.** Why should you never use `google_project_iam_policy` without extreme caution?

<details><summary>Answer</summary>

`google_project_iam_policy` replaces the **entire project IAM policy**. If you forget to include your own owner role, you **lock yourself out** of the project. It removes Google-managed service agent bindings needed for GCP services to function. It's a "nuclear option" that requires listing every single binding for the project. Only use it in mature teams with thorough review processes and the `lifecycle { prevent_destroy = true }` safeguard.

</details>

**Q4.** How does managing IAM with Terraform compare to managing RHDS ACIs with LDIF scripts?

<details><summary>Answer</summary>

| Terraform IAM | RHDS ACI Management |
|--------------|---------------------|
| `iam_policy` = `ldapmodify -x -D ... -f replace-all-acis.ldif` | Replaces all ACIs on a subtree |
| `iam_binding` = `ldapmodify` replace one ACI entry | Replaces one ACI (all entries within it) |
| `iam_member` = `ldapmodify` add one userdn to an ACI | Adds one entry — safest |
| `terraform plan` = diff check | `ldapcompare` or manual diff |
| State file tracks current config | LDAP directory IS the state |
| `terraform destroy` = remove managed ACIs | `ldapdelete` of ACI entries |

The key difference: Terraform has a state file that tracks what it manages. RHDS/LDAP is its own state — the directory itself. This means LDAP has no "drift" problem (you always read live state), while Terraform can have drift between state file and actual GCP IAM.

</details>
