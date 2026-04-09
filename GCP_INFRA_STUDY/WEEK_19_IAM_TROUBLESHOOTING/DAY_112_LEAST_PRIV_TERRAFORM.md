# Week 19, Day 112 (Thu) — Least Privilege in Terraform

## Today's Objective

Implement IAM least privilege through Terraform: module patterns for IAM bindings, `for_each` for multi-role assignment, conditional bindings, CI/CD-driven IAM, and preventing privilege escalation in Terraform configurations.

**Source:** [Terraform google_project_iam](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/google_project_iam) | [IAM Best Practices](https://cloud.google.com/iam/docs/using-iam-securely)

**Deliverable:** A Terraform IAM module with least-privilege patterns, conditional bindings, and escalation prevention

---

## Part 1: Concept (30 minutes)

### 1.1 IAM Resource Types in Terraform

```
Linux analogy:

chmod 644 /etc/hosts              ──►    google_project_iam_policy (authoritative)
  (sets exact permissions)                 (replaces ALL bindings)

setfacl -m u:bob:r-- /etc/hosts   ──►    google_project_iam_binding (authoritative per role)
  (set for specific user+perm)             (replaces members for ONE role)

setfacl -m u:bob:r-- /etc/hosts   ──►    google_project_iam_member (additive)
  (add without removing others)            (adds one member to one role)
```

### 1.2 The Three IAM Resource Types

| Resource | Behaviour | Risk | Use When |
|---|---|---|---|
| `google_project_iam_policy` | **Authoritative** — replaces ALL bindings | EXTREME: removes bindings from other tools/console | Almost never in practice |
| `google_project_iam_binding` | **Authoritative per role** — replaces all members of a role | HIGH: removes manually-added members | When TF owns a specific role entirely |
| `google_project_iam_member` | **Additive** — adds one member-role pair | LOW: doesn't affect others | Most common, safest for mixed management |

```
DANGER ZONES:

google_project_iam_policy {       ← Replaces EVERYTHING
  policy_data = data.google_iam_policy.admin.policy_data
}
Result: Every binding not in your TF code is DELETED
Including service agents, default bindings, console changes

google_project_iam_binding "editors" {   ← Replaces all editors
  role    = "roles/editor"
  members = ["user:alice@corp.com"]
}
Result: Bob (added via console) loses his Editor role

google_project_iam_member "alice_editor" {  ← Adds one binding
  role    = "roles/editor"
  member  = "user:alice@corp.com"
}
Result: Bob keeps his Editor role, Alice is added. SAFE.
```

### 1.3 Least Privilege IAM Module Pattern

```hcl
# modules/iam/variables.tf
variable "project_id" { type = string }

variable "iam_members" {
  type = map(object({
    roles  = list(string)
    member = string
  }))
  description = "Map of member descriptions to roles"
}

# modules/iam/main.tf — uses for_each for safe, additive bindings
locals {
  # Flatten: {key="alice-viewer", role="roles/viewer", member="user:alice@..."}
  member_role_pairs = flatten([
    for key, val in var.iam_members : [
      for role in val.roles : {
        key    = "${key}-${replace(role, "roles/", "")}"
        role   = role
        member = val.member
      }
    ]
  ])
}

resource "google_project_iam_member" "bindings" {
  for_each = { for pair in local.member_role_pairs : pair.key => pair }
  
  project = var.project_id
  role    = each.value.role
  member  = each.value.member
}
```

### 1.4 Conditional IAM Bindings

```hcl
resource "google_project_iam_member" "temp_access" {
  project = var.project_id
  role    = "roles/viewer"
  member  = "user:contractor@external.com"

  condition {
    title       = "expires_2026_06_30"
    description = "Temporary access until end of Q2 2026"
    expression  = "request.time < timestamp(\"2026-06-30T00:00:00Z\")"
  }
}
```

| Condition Type | Expression | Use Case |
|---|---|---|
| **Time-based** | `request.time < timestamp("2026-06-30T...")` | Temporary access |
| **Resource-based** | `resource.name.startsWith("projects/p/...")` | Limit to specific resources |
| **IP-based** | `request.origin.ip.startsWith("10.0.")` | On-premise only |

### 1.5 Preventing Privilege Escalation

```
Escalation Risk:
  A user with roles/iam.admin can grant THEMSELVES roles/owner
  A user with roles/editor can create SA keys

Prevention in Terraform:

1. Never grant Editor/Owner via Terraform
   ──► Use predefined fine-grained roles

2. Restrict who can modify IAM
   ──► Only CI/CD SA has iam.admin

3. Review all IAM changes in PRs
   ──► Policy-as-code

4. Use org policies to restrict role grants
   ──► iam.allowedPolicyMemberDomains
```

### 1.6 CI/CD-Driven IAM

```
┌────────────┐     PR with IAM      ┌──────────────┐
│ Developer  │ ──────────────────►   │   Git Repo   │
│            │  changes in .tf       │              │
└────────────┘                       └──────┬───────┘
                                            │
                                            ▼
                                    ┌──────────────┐
                                    │   CI Pipeline │
                                    │              │
                                    │ 1. tf plan   │
                                    │ 2. Show diff │
                                    │ 3. Wait for  │
                                    │    approval  │
                                    └──────┬───────┘
                                            │ approved
                                            ▼
                                    ┌──────────────┐
                                    │  tf apply    │
                                    │ (via SA with │
                                    │  iam roles)  │
                                    └──────────────┘
```

---

## Part 2: Hands-On Lab (60 minutes)

### Step 1: Set Up Lab (5 min)

```bash
export PROJECT_ID=$(gcloud config get-value project)
mkdir -p tf-iam-lab && cd tf-iam-lab
```

### Step 2: Create IAM Module (15 min)

```bash
mkdir -p modules/iam

cat > modules/iam/variables.tf <<'EOF'
variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "iam_members" {
  type = map(object({
    roles  = list(string)
    member = string
  }))
  description = "Map of IAM bindings (additive)"
  default     = {}
}

variable "service_accounts" {
  type = map(object({
    display_name = string
    description  = string
    roles        = list(string)
  }))
  description = "Service accounts to create with their roles"
  default     = {}
}
EOF

cat > modules/iam/main.tf <<'EOF'
# --- Service Account Creation ---
resource "google_service_account" "sa" {
  for_each = var.service_accounts

  account_id   = each.key
  display_name = each.value.display_name
  description  = each.value.description
  project      = var.project_id
}

# Flatten SA role bindings
locals {
  sa_role_pairs = flatten([
    for sa_key, sa_val in var.service_accounts : [
      for role in sa_val.roles : {
        key    = "${sa_key}-${replace(role, "roles/", "")}"
        role   = role
        member = "serviceAccount:${google_service_account.sa[sa_key].email}"
      }
    ]
  ])

  member_role_pairs = flatten([
    for key, val in var.iam_members : [
      for role in val.roles : {
        key    = "${key}-${replace(role, "roles/", "")}"
        role   = role
        member = val.member
      }
    ]
  ])

  all_bindings = concat(local.sa_role_pairs, local.member_role_pairs)
}

# --- Additive IAM Bindings (safe) ---
resource "google_project_iam_member" "bindings" {
  for_each = { for pair in local.all_bindings : pair.key => pair }

  project = var.project_id
  role    = each.value.role
  member  = each.value.member
}
EOF

cat > modules/iam/outputs.tf <<'EOF'
output "service_account_emails" {
  description = "Created service account emails"
  value       = { for k, v in google_service_account.sa : k => v.email }
}

output "binding_count" {
  description = "Number of IAM bindings created"
  value       = length(google_project_iam_member.bindings)
}
EOF
```

### Step 3: Use the Module for Least-Privilege Setup (15 min)

```bash
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

provider "google" {
  project = var.project_id
  region  = "europe-west2"
}

variable "project_id" {
  type = string
}

module "iam" {
  source     = "./modules/iam"
  project_id = var.project_id

  # Service accounts with least-privilege roles
  service_accounts = {
    "tf-deployer" = {
      display_name = "Terraform Deployer"
      description  = "Deploys infrastructure via CI/CD"
      roles = [
        "roles/compute.instanceAdmin.v1",
        "roles/iam.serviceAccountUser",
        "roles/storage.admin",
      ]
    }

    "app-runner" = {
      display_name = "Application Runner"
      description  = "Runs application workloads"
      roles = [
        "roles/storage.objectViewer",
        "roles/logging.logWriter",
        "roles/monitoring.metricWriter",
      ]
    }

    "monitoring-reader" = {
      display_name = "Monitoring Reader"
      description  = "Read-only monitoring access"
      roles = [
        "roles/monitoring.viewer",
        "roles/logging.viewer",
      ]
    }
  }
}

# --- Conditional binding example ---
resource "google_project_iam_member" "temp_viewer" {
  project = var.project_id
  role    = "roles/viewer"
  member  = "serviceAccount:${module.iam.service_account_emails["monitoring-reader"]}"

  condition {
    title       = "temp_access_q2_2026"
    description = "Temporary expanded access until end of Q2 2026"
    expression  = "request.time < timestamp(\"2026-06-30T23:59:59Z\")"
  }
}

output "service_accounts" {
  value = module.iam.service_account_emails
}

output "binding_count" {
  value = module.iam.binding_count
}
EOF

echo "project_id = \"${PROJECT_ID}\"" > terraform.tfvars

terraform init
terraform plan
```

### Step 4: Review the Plan (10 min)

```bash
# Generate a detailed plan
terraform plan -out=plan.tfplan

# Show the plan in detail
terraform show plan.tfplan

echo ""
echo "=== Review Checklist ==="
echo "[ ] No roles/editor or roles/owner granted?"
echo "[ ] All bindings use google_project_iam_member (additive)?"
echo "[ ] Service accounts have minimum required roles?"
echo "[ ] Conditional bindings have correct expiry dates?"
echo "[ ] No service account keys being created?"
```

### Step 5: Apply and Verify (10 min)

```bash
terraform apply plan.tfplan

# Verify the bindings
echo ""
echo "=== Terraform Deployer Roles ==="
gcloud projects get-iam-policy ${PROJECT_ID} \
  --flatten="bindings[].members" \
  --filter="bindings.members:tf-deployer@${PROJECT_ID}" \
  --format="table(bindings.role)"

echo ""
echo "=== App Runner Roles ==="
gcloud projects get-iam-policy ${PROJECT_ID} \
  --flatten="bindings[].members" \
  --filter="bindings.members:app-runner@${PROJECT_ID}" \
  --format="table(bindings.role)"
```

### Step 6: Clean Up (5 min)

```bash
terraform destroy -auto-approve
cd ~
rm -rf tf-iam-lab
```

---

## Part 3: Revision (15 minutes)

- **Use `google_project_iam_member`** (additive) — safest; doesn't remove other bindings
- **Avoid `google_project_iam_policy`** — replaces ALL project IAM; can lock you out
- **`for_each` with flattened maps** — scales cleanly for multiple members × multiple roles
- **Conditional bindings** — time-based expiry for temporary access
- **Never grant `roles/editor` or `roles/owner`** in TF — use fine-grained predefined roles
- **No SA key creation** in TF — use impersonation or Workload Identity Federation
- **CI/CD-driven IAM** — all changes via PRs with plan review before apply

### Key Commands
```bash
# Check effective roles for a member
gcloud projects get-iam-policy PROJECT --flatten="bindings[].members" \
  --filter="bindings.members:MEMBER" --format="table(bindings.role)"

# Test permissions
gcloud policy-troubleshoot iam RESOURCE --permission=PERM --principal-email=EMAIL
```

---

## Part 4: Quiz (15 minutes)

**Q1:** What's the danger of using `google_project_iam_policy` vs `google_project_iam_member`?
<details><summary>Answer</summary><code>google_project_iam_policy</code> is <b>fully authoritative</b> — it replaces ALL IAM bindings on the project with what's in your Terraform code. Any binding not in your <code>.tf</code> file is <b>deleted</b>, including Google-managed service agent roles, Console-added bindings, and other team's Terraform bindings. This can break service agents and lock out admins. <code>google_project_iam_member</code> is <b>additive</b> — it only adds one member-role pair without touching anything else. Like <code>chmod 644</code> (replaces all) vs <code>setfacl -m</code> (adds one).</details>

**Q2:** How does `for_each` with flattened maps help manage IAM at scale?
<details><summary>Answer</summary>You define each member's roles as a list in a map variable. The <code>flatten</code> function creates one binding per member-role pair. Adding a new role for a member means adding one string to a list — Terraform creates the new binding without affecting others. Removing a role removes one binding cleanly. Without <code>for_each</code>, you'd need separate resource blocks for each member-role combination, leading to code duplication. It also means renaming a member or role only affects the changed bindings.</details>

**Q3:** A contractor needs temporary BigQuery access for 30 days. How do you implement this in Terraform?
<details><summary>Answer</summary>Use a <b>conditional IAM binding</b> with a time-based expression:<br>
<code>condition { expression = "request.time < timestamp(\"2026-05-08T00:00:00Z\")" }</code><br>
After the timestamp, GCP automatically denies access even though the binding still exists. Set a reminder to clean up the Terraform code after expiry. The condition is enforced server-side, so there's no risk of forgetting. This is better than manually granting/revoking because it's automated, auditable, and version-controlled.</details>

**Q4:** How do you prevent Terraform from being used to escalate privileges?
<details><summary>Answer</summary>
1. <b>Restrict the TF service account's IAM roles</b> — only grant the minimum roles it needs to deploy, never <code>roles/owner</code><br>
2. <b>PR review for IAM changes</b> — require human approval before any IAM modification merges<br>
3. <b>Policy validation in CI</b> — use tools like <code>checkov</code> or OPA to flag overly broad roles<br>
4. <b>Org policy constraints</b> — restrict which roles can be granted<br>
5. <b>Never create SA keys in TF</b> — use impersonation or WIF<br>
6. <b>Separate IAM state</b> — use a dedicated, restricted TF workspace for IAM changes
</details>
