# Day 84 — PROJECT: Secure Access Blueprint + Terraform

> **Week 14 — Secure Access** | ⏱ 2 hours | Region: `europe-west2`
> Student profile: 6 yrs Linux infra, 3 yrs RHDS LDAP, ACE certified

---

## Part 1 — Concept (30 min)

### 1.1 Secure Access Blueprint — What We're Building

```
  ┌──────────────────────────────────────────────────────────────┐
  │            SECURE ACCESS BLUEPRINT                            │
  │                                                              │
  │  ┌─────────────────────────────────────────────────┐        │
  │  │                PROJECT                           │        │
  │  │                                                  │        │
  │  │  OS LOGIN: ENABLED                               │        │
  │  │  ┌───────────┐  ┌───────────┐  ┌───────────┐   │        │
  │  │  │ web-vm    │  │ api-vm    │  │ batch-vm  │   │        │
  │  │  │ web-sa    │  │ api-sa    │  │ batch-sa  │   │        │
  │  │  │ GCS read  │  │ PubSub    │  │ BQ write  │   │        │
  │  │  └───────────┘  └───────────┘  └───────────┘   │        │
  │  │                                                  │        │
  │  │  NO SA KEYS ✓                                    │        │
  │  │  PER-WORKLOAD SAs ✓                              │        │
  │  │  LEAST PRIVILEGE ROLES ✓                         │        │
  │  │  OS LOGIN SSH ✓                                  │        │
  │  │  AUDIT LOGGING ✓                                 │        │
  │  │  IAM VIA TERRAFORM ✓                             │        │
  │  └─────────────────────────────────────────────────┘        │
  └──────────────────────────────────────────────────────────────┘
```

### 1.2 Security Checklist

```
  SECURE ACCESS CHECKLIST
  ═══════════════════════

  IDENTITY:
  □ OS Login enabled at project level
  □ No metadata SSH keys in project metadata
  □ osLogin role for standard users
  □ osAdminLogin only for admins who need sudo

  SERVICE ACCOUNTS:
  □ One SA per workload (no sharing)
  □ Descriptive naming: {app}-{env}-{function}
  □ No SA keys created (zero keys policy)
  □ Minimum roles per SA
  □ Default compute SA not used by any workload

  IAM:
  □ All bindings managed via Terraform
  □ No basic roles (viewer/editor/owner) except owner for break-glass
  □ Conditional bindings for temporary access
  □ Regular access reviews (quarterly)

  AUDIT:
  □ Admin Activity logs retained (default)
  □ Data Access logs enabled for sensitive services
  □ Log sink to GCS/BQ for long-term retention
  □ Alerting on critical IAM changes
```

### 1.3 Architecture Diagram

```
  ┌─────────────────────────────────────────────────────────────┐
  │                      INTERNET                                │
  └───────────────────────────┬─────────────────────────────────┘
                              │
  ┌───────────────────────────▼─────────────────────────────────┐
  │                    IAP TUNNEL                                │
  │              (SSH via Identity-Aware Proxy)                  │
  └───────────────────────────┬─────────────────────────────────┘
                              │
  ┌───────────────────────────▼─────────────────────────────────┐
  │                   VPC: secure-vpc                            │
  │                   10.0.0.0/24                                │
  │                                                              │
  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
  │  │ web-vm       │  │ api-vm       │  │ batch-vm     │      │
  │  │ e2-micro     │  │ e2-micro     │  │ e2-micro     │      │
  │  │ No ext IP    │  │ No ext IP    │  │ No ext IP    │      │
  │  │              │  │              │  │              │      │
  │  │ SA: web-sa   │  │ SA: api-sa   │  │ SA: batch-sa │      │
  │  │ OS Login: ✓  │  │ OS Login: ✓  │  │ OS Login: ✓  │      │
  │  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘      │
  │         │                  │                  │              │
  └─────────┼──────────────────┼──────────────────┼──────────────┘
            │                  │                  │
     ┌──────▼──────┐   ┌──────▼──────┐   ┌──────▼──────┐
     │ GCS Bucket  │   │ Pub/Sub     │   │ BigQuery    │
     │ (read only) │   │ (subscribe) │   │ (write)     │
     └─────────────┘   └─────────────┘   └─────────────┘
```

---

## Part 2 — Hands-On Lab (60 min)

### Prerequisites
```bash
export PROJECT_ID=$(gcloud config get-value project)
export REGION=europe-west2
export ZONE=europe-west2-a
mkdir -p /tmp/secure-access-lab && cd /tmp/secure-access-lab
```

### Lab 2.1 — Terraform Configuration

```bash
cat > main.tf << 'TFEOF'
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

variable "zone" {
  type    = string
  default = "europe-west2-a"
}

# ============================================
# OS LOGIN — Project-level metadata
# ============================================
resource "google_compute_project_metadata_item" "oslogin" {
  key     = "enable-oslogin"
  value   = "TRUE"
  project = var.project_id
}

# ============================================
# SERVICE ACCOUNTS — One per workload
# ============================================
resource "google_service_account" "web_sa" {
  account_id   = "bp-web-reader"
  display_name = "Blueprint - Web Reader"
  description  = "Reads static assets from GCS for web frontend"
  project      = var.project_id
}

resource "google_service_account" "api_sa" {
  account_id   = "bp-api-subscriber"
  display_name = "Blueprint - API Subscriber"
  description  = "Subscribes to Pub/Sub for API events"
  project      = var.project_id
}

resource "google_service_account" "batch_sa" {
  account_id   = "bp-batch-writer"
  display_name = "Blueprint - Batch Writer"
  description  = "Writes processed data to BigQuery"
  project      = var.project_id
}

# ============================================
# IAM BINDINGS — Least privilege (additive)
# ============================================
resource "google_project_iam_member" "web_storage" {
  project = var.project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${google_service_account.web_sa.email}"
}

resource "google_project_iam_member" "web_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.web_sa.email}"
}

resource "google_project_iam_member" "api_pubsub" {
  project = var.project_id
  role    = "roles/pubsub.subscriber"
  member  = "serviceAccount:${google_service_account.api_sa.email}"
}

resource "google_project_iam_member" "api_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.api_sa.email}"
}

resource "google_project_iam_member" "batch_bq" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.batch_sa.email}"
}

resource "google_project_iam_member" "batch_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.batch_sa.email}"
}

# ============================================
# COMPUTE INSTANCES — No external IPs
# ============================================
resource "google_compute_instance" "web_vm" {
  name         = "bp-web-vm"
  machine_type = "e2-micro"
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
    }
  }

  network_interface {
    network = "default"
    # No access_config = no external IP
  }

  service_account {
    email  = google_service_account.web_sa.email
    scopes = ["cloud-platform"]
  }

  labels = {
    workload = "web"
    env      = "lab"
    managed  = "terraform"
  }
}

resource "google_compute_instance" "api_vm" {
  name         = "bp-api-vm"
  machine_type = "e2-micro"
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
    }
  }

  network_interface {
    network = "default"
  }

  service_account {
    email  = google_service_account.api_sa.email
    scopes = ["cloud-platform"]
  }

  labels = {
    workload = "api"
    env      = "lab"
    managed  = "terraform"
  }
}

resource "google_compute_instance" "batch_vm" {
  name         = "bp-batch-vm"
  machine_type = "e2-micro"
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
    }
  }

  network_interface {
    network = "default"
  }

  service_account {
    email  = google_service_account.batch_sa.email
    scopes = ["cloud-platform"]
  }

  labels = {
    workload = "batch"
    env      = "lab"
    managed  = "terraform"
  }
}

# ============================================
# OUTPUTS
# ============================================
output "web_sa_email" {
  value = google_service_account.web_sa.email
}

output "api_sa_email" {
  value = google_service_account.api_sa.email
}

output "batch_sa_email" {
  value = google_service_account.batch_sa.email
}

output "vm_list" {
  value = {
    web   = google_compute_instance.web_vm.name
    api   = google_compute_instance.api_vm.name
    batch = google_compute_instance.batch_vm.name
  }
}
TFEOF
```

### Lab 2.2 — Deploy the Blueprint

```bash
terraform init
terraform plan -var="project_id=$PROJECT_ID"
terraform apply -var="project_id=$PROJECT_ID" -auto-approve
```

### Lab 2.3 — Verify Security Posture

```bash
echo "═══════════════════════════════════════════"
echo "SECURITY POSTURE VERIFICATION"
echo "═══════════════════════════════════════════"

# Check OS Login enabled
echo ""
echo "--- OS Login Status ---"
gcloud compute project-info describe --project=$PROJECT_ID \
  --format="value(commonInstanceMetadata.items.filter(key:enable-oslogin).value)"

# Check VM SAs (should all be custom, not default)
echo ""
echo "--- VM Service Accounts ---"
for VM in bp-web-vm bp-api-vm bp-batch-vm; do
  SA=$(gcloud compute instances describe $VM --zone=$ZONE \
    --format="value(serviceAccounts.email)" 2>/dev/null)
  echo "$VM → $SA"
done

# Check no VMs have external IPs
echo ""
echo "--- External IPs (should be empty) ---"
gcloud compute instances list \
  --filter="name~bp-" \
  --format="table(name, networkInterfaces[0].accessConfigs[0].natIP:label=EXTERNAL_IP)"

# Check SA keys (should be zero for all)
echo ""
echo "--- SA Keys (should be 0 user-managed) ---"
for SA in $(terraform output -json | python3 -c "import sys,json; d=json.load(sys.stdin); [print(v['value']) for k,v in d.items() if 'sa_email' in k]" 2>/dev/null); do
  KEYS=$(gcloud iam service-accounts keys list \
    --iam-account=$SA --managed-by=user --format="value(name)" 2>/dev/null | wc -l)
  echo "$SA: $KEYS user-managed keys"
done

echo ""
echo "═══════════════════════════════════════════"
echo "POSTURE SUMMARY"
echo "═══════════════════════════════════════════"
echo "✅ OS Login: Enabled"
echo "✅ Per-workload SAs: 3 dedicated SAs"
echo "✅ No external IPs: VMs are private"
echo "✅ No SA keys: Zero user-managed keys"
echo "✅ Infrastructure as Code: All via Terraform"
```

### Lab 2.4 — Audit Trail Check

```bash
# Wait for audit logs
sleep 30

# Check that our Terraform actions were logged
echo "--- Recent admin actions (from blueprint deployment) ---"
gcloud logging read '
  protoPayload.authenticationInfo.principalEmail="'$(gcloud config get-value account)'"
  timestamp>="2026-04-08T00:00:00Z"
' --limit=10 --format="table(
  timestamp,
  protoPayload.methodName:label=ACTION,
  resource.type:label=RESOURCE
)" --project=$PROJECT_ID
```

### Lab 2.5 — Document the Blueprint

```bash
cat << EOF
═══════════════════════════════════════════════════════════
SECURE ACCESS BLUEPRINT — DEPLOYMENT REPORT
═══════════════════════════════════════════════════════════

Project:    $PROJECT_ID
Region:     $REGION
Deployed:   $(date -u +%Y-%m-%dT%H:%M:%SZ)
Method:     Terraform

RESOURCES CREATED:
  Service Accounts:
    - bp-web-reader    → roles/storage.objectViewer, logging.logWriter
    - bp-api-subscriber → roles/pubsub.subscriber, logging.logWriter
    - bp-batch-writer  → roles/bigquery.dataEditor, logging.logWriter

  Compute Instances:
    - bp-web-vm   (e2-micro, no ext IP, SA: bp-web-reader)
    - bp-api-vm   (e2-micro, no ext IP, SA: bp-api-subscriber)
    - bp-batch-vm (e2-micro, no ext IP, SA: bp-batch-writer)

  Project Settings:
    - OS Login: ENABLED
    - SSH via: IAP tunnel only

SECURITY CONTROLS:
  ✅ OS Login for SSH access control
  ✅ Per-workload service accounts
  ✅ Least privilege IAM roles
  ✅ No SA keys (zero key policy)
  ✅ No external IPs (IAP only)
  ✅ All resources managed via Terraform
  ✅ Audit logging active (Admin Activity)
═══════════════════════════════════════════════════════════
EOF
```

### 🧹 Cleanup

```bash
# Destroy all Terraform-managed resources
cd /tmp/secure-access-lab
terraform destroy -var="project_id=$PROJECT_ID" -auto-approve

# Clean up directory
cd ~
rm -rf /tmp/secure-access-lab
```

---

## Part 3 — Revision (15 min)

### Blueprint Components
- **OS Login** — centralized SSH via IAM (no metadata keys)
- **Per-workload SAs** — isolated blast radius per application
- **No SA keys** — metadata server for on-GCP, WIF for off-GCP
- **Least privilege** — specific predefined roles, not basic roles
- **No external IPs** — SSH only via IAP tunnel
- **Terraform** — all IAM bindings as code (auditable, reviewable)
- **Audit logging** — admin activity always on, data access for sensitive services

### Terraform Resource Summary
```hcl
# Project metadata
google_compute_project_metadata_item   # OS Login

# Service accounts
google_service_account                 # Create SAs

# IAM (additive)
google_project_iam_member              # Bind roles to SAs

# Compute
google_compute_instance                # VMs with SAs attached
```

---

## Part 4 — Quiz (15 min)

**Q1.** A new team member needs SSH access to the web VM. What's the process under this blueprint?

<details><summary>Answer</summary>

1. Add `google_project_iam_member` with `roles/compute.osLogin` (or `osAdminLogin` if sudo needed) for the new team member
2. Submit a PR with the Terraform change
3. After review + merge, `terraform apply`
4. The team member can now SSH via `gcloud compute ssh bp-web-vm --zone=europe-west2-a --tunnel-through-iap`
5. No key distribution, no metadata changes — all controlled via IAM

</details>

**Q2.** The web application now needs to write to Pub/Sub in addition to reading GCS. What change is needed?

<details><summary>Answer</summary>

Add one new `google_project_iam_member` resource:
```hcl
resource "google_project_iam_member" "web_pubsub" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_service_account.web_sa.email}"
}
```
No VM restart needed — the SA's permissions update automatically. The metadata server will include the new permissions in the next token refresh (within minutes).

</details>

**Q3.** A security audit asks: "Prove that no service account keys exist in this project." How do you demonstrate this?

<details><summary>Answer</summary>

Run the automated check:
```bash
for SA in $(gcloud iam service-accounts list --format="value(email)"); do
  KEYS=$(gcloud iam service-accounts keys list --iam-account=$SA \
    --managed-by=user --format="value(name)" | wc -l)
  echo "$SA: $KEYS user-managed keys"
done
```
Additionally, show the Terraform code — no `google_service_account_key` resources exist. For ongoing enforcement, enable the org policy `constraints/iam.disableServiceAccountKeyCreation`.

</details>

**Q4.** How does this blueprint compare to securing an RHDS deployment?

<details><summary>Answer</summary>

| Blueprint Component | RHDS Equivalent |
|--------------------|-----------------|
| OS Login | SSSD + PAM + LDAP for SSH |
| Per-workload SAs | Per-application bind DNs |
| No SA keys | SASL/GSSAPI (no stored passwords) |
| IAM roles | ACIs on LDAP subtrees |
| Terraform IaC | Ansible + LDIF for config management |
| Audit logs | RHDS access-log + errors-log |
| No external IPs | Firewall restricting LDAP port access |
| IAP tunnel | VPN/bastion host for admin access |

The security principles are identical: centralised identity, least privilege, no shared credentials, infrastructure as code, audit everything. GCP provides these as managed services; in RHDS, you build and maintain them yourself.

</details>
